/*******************************************************************************
 * Copyright (c) 2014, 2024  IBM Corporation, Carnegie Mellon University and others
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *******************************************************************************/

import ChatView
import Combine
import Foundation
import UIKit
import AVFoundation
import Speech
import SwiftUI

@objcMembers
open class AppleSTT: NSObject, STTProtocol, AVCaptureAudioDataOutputSampleBufferDelegate, SFSpeechRecognizerDelegate {

    public var tts: TTSProtocol?
    public var speaking: Bool = false
    public var recognizing: Bool = false
    public var paused: Bool = true
    public var restarting: Bool = true
    public var useRawError = false
    public var state: Binding<ChatStateButtonModel>? = nil

    public init(state: Binding<ChatStateButtonModel>, tts: TTSProtocol? = nil) {
        self.state = state
        self.tts = tts
        self.stopstt = {}
        self.audioDataQueue = DispatchQueue(label: "hulop.conversation", attributes: [])
        super.init()

        speechRecognizer.delegate = self
        SFSpeechRecognizer.requestAuthorization { authStatus in
            print(authStatus);
        }

        // need to set AVAudioSession before
        let audioSession:AVAudioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            NSLog("Audio session error")
        }

        //self.initPWCaptureSession()
    }

    public func listen(
        selfvoice: PassthroughSubject<String, any Error>?,
        speakendaction: ((PassthroughSubject<String, any Error>?)->Void)?,
        action: @escaping (PassthroughSubject<String, any Error>?, UInt64)->Void,
        failure: @escaping (NSError)->Void,
        timeout: @escaping ()->Void
    ) {
        if (speaking) {
            NSLog("TTS is speaking so this listen is eliminated")
            return
        }
        // NSLog("Listen \"\(selfvoice ?? "")\" \(action)")
        self.last_action = action

        self.stoptimer()
        DispatchQueue.main.async {
            self.state?.wrappedValue.chatState = .Speaking
            self.state?.wrappedValue.chatText = " "
        }

        self.tts?.speak(selfvoice) {
            if (!self.speaking) {
                return
            }
            self.speaking = false
            if let selfvoice,
               let speakendaction {
                speakendaction(selfvoice)
            }

            self.tts?.vibrate()
            self.tts?.playVoiceRecoStart()

            DispatchQueue.main.asyncAfter(deadline: .now()+self.waitDelay) {
                self.initPWCaptureSession()
                self.startPWCaptureSession()//alternative
                self.startRecognize(action, failure: failure, timeout: timeout)

                self.state?.wrappedValue.chatText = "SPEAK_NOW"
                self.state?.wrappedValue.chatState = .Listening
            }

        }
        self.speaking = true
    }

    public func disconnect() {
        self.tts?.stop()
        DispatchQueue.main.async {
            self.state?.wrappedValue.chatState = .Inactive
        }
        self.speaking = false
        self.recognizing = false
        self.pwCaptureSession?.stopRunning()
        self.stopstt()
        self.stoptimer()
    }

    public func endRecognize() {
        tts?.stop()
        DispatchQueue.main.async {
            self.state?.wrappedValue.chatText = " "
            self.state?.wrappedValue.chatState = .Inactive
        }
        self.speaking = false
        self.recognizing = false
        self.stopPWCaptureSession()
        self.stopstt()
        self.stoptimer()
    }

    public func restartRecognize() {
        self.paused = false;
        self.restarting = true;
        if let actions = self.last_action {
            self.tts?.vibrate()
            self.tts?.playVoiceRecoStart()

            DispatchQueue.main.asyncAfter(deadline: .now()+self.waitDelay) {
                self.startPWCaptureSession()
                self.startRecognize(actions, failure:self.last_failure, timeout:self.last_timeout)
                self.state?.wrappedValue.chatText = "SPEAK_NOW"
                self.state?.wrappedValue.chatState = .Listening
            }
        }
    }

    // MARK: - private func
    private let speechRecognizer = SFSpeechRecognizer()!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var last_action: ((PassthroughSubject<String, Error>, UInt64)->Void)?
    private var last_failure:(NSError)->Void = {arg in}
    private var last_timeout:()->Void = { () in}
    private var last_text: String?

    private var stopstt:()->()
    private let waitDelay = 0.0

    private var pwCaptureSession:AVCaptureSession? = nil
    private var audioDataQueue:DispatchQueue? = nil

    private var timeoutTimer:Timer? = nil
    private var timeoutDuration:TimeInterval = 20.0

    private var resulttimer:Timer? = nil
    private var resulttimerDuration:TimeInterval = 1.0

    private var unknownErrorCount = 0

    private func createError(_ message:String) -> NSError{
        let domain = "swift.sttHelper"
        let code = -1
        let userInfo = [NSLocalizedDescriptionKey:message]
        return NSError(domain:domain, code: code, userInfo:userInfo)
    }

    private var pwCapturingStarted: Bool = false
    private var pwCapturingIgnore: Bool = false
    private func initPWCaptureSession(){//alternative
        if nil == self.pwCaptureSession{
            self.pwCaptureSession = AVCaptureSession()
            if let captureSession = self.pwCaptureSession{
                captureSession.automaticallyConfiguresApplicationAudioSession = false
                if let microphoneDevice = AVCaptureDevice.default(for: .audio) {
                    let microphoneInput = try? AVCaptureDeviceInput(device: microphoneDevice)
                    if(captureSession.canAddInput(microphoneInput!)){
                        captureSession.addInput(microphoneInput!)

                        let adOutput = AVCaptureAudioDataOutput()
                        adOutput.setSampleBufferDelegate(self, queue: self.audioDataQueue)
                        if captureSession.canAddOutput(adOutput){
                            captureSession.addOutput(adOutput)
                        }
                    }
                }
            }
        }

        if !pwCapturingStarted {
            DispatchQueue.global().async {
                self.pwCaptureSession?.startRunning()
            }
        }
    }

    private func startPWCaptureSession(){//alternative
        pwCapturingIgnore = false
    }

    private func stopPWCaptureSession(){
        pwCapturingIgnore = true
    }

    private var ave: Float = 0
    private var aveCount: Int = 0

    open func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // append buffer to recognition request
        if !pwCapturingIgnore {
            recognitionRequest?.appendAudioSampleBuffer(sampleBuffer)
        }
        if !pwCapturingStarted {
            NSLog("Recording started")
        }
        pwCapturingStarted = true
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        guard let asbd = asbd?.pointee else { return }
        let sampleRate = asbd.mSampleRate
        let updateRate = 30.0
        // get raw data and calcurate the power
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout.stride(ofValue: audioBufferList),
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer)
        guard let data = audioBufferList.mBuffers.mData else {
            return
        }
        let actualSampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let ptr = data.bindMemory(to: Int16.self, capacity: actualSampleCount)
        let buf = UnsafeBufferPointer(start: ptr, count: actualSampleCount)
        let array = Array(buf)
        for a in array {
            self.ave += abs(Float(a))
            self.aveCount += 1
            if Float64(self.aveCount) >= sampleRate / updateRate {
                // max is 110db
                let power = 110 + (log10((ave + 1) / Float(sampleRate / updateRate)) - log10(32768)) * 20
                DispatchQueue.main.async {
                    self.state?.wrappedValue.power = power
                }
                ave = 0
                aveCount = 0
            }
        }
    }

    private func startRecognize(_ action: @escaping (PassthroughSubject<String, Error>, UInt64)->Void, failure: @escaping (NSError)->Void,  timeout: @escaping ()->Void){
        self.paused = false

        self.last_timeout = timeout
        self.last_failure = failure

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest!.shouldReportPartialResults = true
        last_text = nil
        NSLog("Start recognizing")
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!, resultHandler: { [weak self] (result, e) in
            guard let weakself = self else {
                return
            }
            let complete:()->Void = {
                if let last_text = weakself.last_text {
                    let text = PassthroughSubject<String, Error>()
                    action(text, 0)
                    text.send(last_text)
                    text.send(completion: .finished)
                }
            }

            if e != nil {
                weakself.stoptimer()
                guard let error:NSError = e as NSError? else {
                    weakself.endRecognize()
                    timeout()
                    return;
                }

                let code = error.code
                if code == 203 { // Empty recognition
                    weakself.endRecognize();
                    DispatchQueue.main.async {
                        weakself.state?.wrappedValue.chatState = .Recognized
                    }
                    timeout()
                } else if code == 209 || code == 216 || code == 1700 || code == 301 {
                    // noop
                    // 209 : trying to stop while starting
                    // 216 : terminated by manual
                    // 1700: background
                    complete()
                } else if code == 4 {
                    weakself.endRecognize(); // network error
                    //let newError = weakself.createError(NSLocalizedString("checkNetworkConnection", tableName: nil, bundle: Bundle.module, value: "", comment:""))
                    //failure(newError)
                } else {
                    weakself.endRecognize()
                    if weakself.useRawError {
                        failure(error) // unknown error
                    } else {
                        //let newError = weakself.createError(NSLocalizedString("unknownError\(weakself.unknownErrorCount)", tableName: nil, bundle: Bundle.module, value: "", comment:""))
                        //failure(newError)
                        weakself.unknownErrorCount = (weakself.unknownErrorCount + 1) % 2
                    }
                }
                return;
            }

            guard let recognitionTask = weakself.recognitionTask else {
                return;
            }

            guard recognitionTask.isCancelled == false else {
                return;
            }

            guard let result = result else {
                return;
            }
            weakself.stoptimer();

            weakself.last_text = result.bestTranscription.formattedString;

            weakself.resulttimer = Timer.scheduledTimer(withTimeInterval: weakself.resulttimerDuration, repeats: false, block: { (timer) in
                weakself.endRecognize()
            })

            let str = weakself.last_text
            let isFinal:Bool = result.isFinal;
            let length:Int = str?.count ?? 0
            if (length > 0) {
                DispatchQueue.main.async {
                    if let str {
                        NSLog("Result = \(str), Length = \(length), isFinal = \(isFinal)");
                        weakself.state?.wrappedValue.chatText = str
                    }
                }
                if isFinal{
                    complete()
                }
            }else{
                if isFinal{
                    DispatchQueue.main.async {
                        weakself.state?.wrappedValue.chatText = "?"
                    }
                }
            }
        })
        self.stopstt = {
            self.recognitionTask?.cancel()
            if self.resulttimer != nil{
                self.resulttimer?.invalidate()
                self.resulttimer = nil;
            }
            self.stopstt = {}
        }

        self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: self.timeoutDuration, repeats: false, block: { (timer) in
            self.endRecognize()
            timeout()
        })

        self.restarting = false
        self.recognizing = true
    }

    private func stoptimer(){
        if self.resulttimer != nil{
            self.resulttimer?.invalidate()
            self.resulttimer = nil
        }
        if self.timeoutTimer != nil {
            self.timeoutTimer?.invalidate()
            self.timeoutTimer = nil
        }
    }
}

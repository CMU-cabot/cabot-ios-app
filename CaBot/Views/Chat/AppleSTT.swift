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
import PriorityQueueTTS

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

        resetLang()
        SFSpeechRecognizer.requestAuthorization { authStatus in
            print(authStatus);
        }

        SilentAudioPlayer.shared.stop()
        AudioSessionRouteHelper.restorePreferredOutputRoute()
    }

    public func resetLang() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: I18N.shared.langCode))
        speechRecognizer?.delegate = self
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
        self.last_timeout = timeout
        self.last_failure = failure

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

            // Navigation actions schedule their own announcement and close the
            // chat. They must take precedence over the PTT close path.
            if ChatData.shared.viewModel?.navigationAction() == true {
                return
            }

            if PTTManager.shared.closePTTConversationAfterResponseIfNeeded() == true {
                return
            }

            self.restartSTT()
        }
        self.speaking = true
        DispatchQueue.main.async {
            self.monitorSpeechBeforeRecognition(timeout: timeout)
        }
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
        endRecognize(stopTTS: true)
    }

    private func endRecognize(stopTTS: Bool) {
        if stopTTS && self.speaking {
            tts?.stop()
        }
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
        restartRecognize(silently: false)
    }

    private func restartRecognize(silently: Bool, stopTTS: Bool = true) {
        self.paused = false;
        self.restarting = true;
        self.restartSTT(playStartSound: !silently, stopTTS: stopTTS)
    }

    public func resetActions(
        action: @escaping (PassthroughSubject<String, any Error>?, UInt64)->Void,
        failure: @escaping (NSError)->Void,
        timeout: @escaping ()->Void
    ) {
        self.last_action = action
        self.last_timeout = timeout
        self.last_failure = failure
    }

    private func restartSTT(playStartSound: Bool = true, stopTTS: Bool = true) {
        if  PriorityQueueTTS.shared.isSpeaking {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.restartSTT(playStartSound: playStartSound, stopTTS: stopTTS)
            }
            return
        }
        if self.recognizing {
            self.endRecognize(stopTTS: stopTTS)
        }
        if stopTTS {
            self.tts?.stop()
        }
        if let actions = self.last_action {
            if playStartSound {
                self.tts?.vibrate()
                self.tts?.playVoiceRecoStart()
            }
            ContentView.inactive_at = nil

            DispatchQueue.main.asyncAfter(deadline: .now()+self.waitDelay) {
                self.initPWCaptureSession()
                self.startPWCaptureSession()
                self.startRecognize(actions, failure:self.last_failure, timeout:self.last_timeout)
                self.state?.wrappedValue.chatText = CustomLocalizedString("SPEAK_NOW", lang: I18N.shared.lang)
                self.state?.wrappedValue.chatState = .Listening
                self.monitorSpeechWhileRecognition(timeout: self.last_timeout)
            }
        }
    }

    private func monitorSpeechBeforeRecognition(timeout: @escaping ()->Void) {
        var lastSpeakAt = Date()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if self.speaking && !self.recognizing {
                if PriorityQueueTTS.shared.isSpeaking || PriorityQueueTTS.shared.isPaused || PriorityQueueTTSWrapper.shared.isQueuing {
                    lastSpeakAt = Date()
                }
                if -lastSpeakAt.timeIntervalSinceNow < 2.0 {
                    return
                }
                timeout()
                print("monitorSpeechBeforeRecognition: Timeout")
            }
            timer.invalidate()
        }
    }

    private func monitorSpeechWhileRecognition(timeout: @escaping ()->Void) {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if self.recognizing {
                if !PriorityQueueTTS.shared.isSpeaking || PriorityQueueTTS.shared.priority == .Chat {
                    return
                }
                self.stoptimer()
                self.endRecognize()
                timeout()
                print("monitorSpeechWhileRecognition: Timeout")
            }
            timer.invalidate()
        }
    }

    // MARK: - private func
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let pttRecognition = PTTRecognitionState()

    private var last_action: ((PassthroughSubject<String, Error>, UInt64)->Void)?
    private var last_failure:(NSError)->Void = {arg in}
    private var last_timeout:()->Void = { () in}
    private var last_text: String?
    private var last_converted: String?

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
        if pwCapturingStarted, let captureSession = self.pwCaptureSession, !captureSession.isRunning {
            NSLog("AVCaptureSession is not running. Restarting...")
            pwCapturingStarted = false // Rerun AVCaptureSession.startRunning
        }
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
        if !pwCapturingIgnore {
            appendRecognitionSampleBuffer(sampleBuffer)
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
        let sessionID = UUID()
        pttRecognition.sessionID = sessionID
        pttRecognition.didComplete = false

        self.last_timeout = timeout
        self.last_failure = failure

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest!.shouldReportPartialResults = true
        recognitionRequest!.contextualStrings = ContactsUtil.shared.getContextualStrings()
        last_text = nil
        last_converted = nil
        NSLog("Start recognizing")
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!, resultHandler: { [weak self] (result, e) in
            guard let weakself = self else {
                return
            }
            guard weakself.pttRecognition.sessionID == sessionID else {
                return
            }
            let complete:()->Void = {
                weakself.completeRecognition(action)
            }

            if e != nil {
                if weakself.pttRecognition.finishAction != nil {
                    weakself.completePTTRecognition()
                    return
                }
                guard let error:NSError = e as NSError? else {
                    if !weakself.restartRecognizeWhilePTTOn() {
                        weakself.endRecognize()
                        timeout()
                    }
                    return;
                }

                let code = error.code
                if code != 1110 {
                    weakself.stoptimer()
                }
                if code == 203 { // Empty recognition
                    weakself.endRecognize();
                    DispatchQueue.main.async {
                        weakself.state?.wrappedValue.chatState = .Recognized
                    }
                    if !weakself.restartRecognizeWhilePTTOn() {
                        timeout()
                    }
                } else if code == 1110 {
                    // No speech detected. Keep listening while PTT is held.
                    if !weakself.restartRecognizeWhilePTTOn() {
                        complete()
                    }
                } else if code == 209 || code == 216 || code == 1700 || code == 301 {
                    // noop
                    // 209 : trying to stop while starting
                    // 216 : terminated by manual
                    // 1700: background
                    if !PTTManager.shared.isPTTOn {
                        complete()
                    }
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
            weakself.last_converted = ContactsUtil.shared.convert(result.bestTranscription.formattedString)

            if !PTTManager.shared.isPTTOn {
                weakself.resulttimer = Timer.scheduledTimer(withTimeInterval: weakself.resulttimerDuration, repeats: false, block: { (timer) in
                    weakself.endRecognize()
                })
            }

            let str = weakself.last_text
            let isFinal:Bool = result.isFinal;
            let length:Int = str?.count ?? 0
            if (length > 0) {
                DispatchQueue.main.async {
                    if let str, let converted = weakself.last_converted {
                        NSLog("Result = \(str)(\(converted)), Length = \(length), isFinal = \(isFinal)");
                        weakself.state?.wrappedValue.chatText = converted
                    }
                }
                if isFinal{
                    if weakself.completePTTRecognitionIfNeeded() {
                        return
                    }
                    if PTTManager.shared.isPTTOn {
                        complete()
                        _ = weakself.restartRecognizeWhilePTTOn()
                    } else {
                        complete()
                    }
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
            if !self.restartRecognizeWhilePTTOn() {
                self.endRecognize()
                timeout()
            }
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

    private func createRecognitionPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let asbd = asbdPointer.pointee
        guard asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mBitsPerChannel == 16 else {
            return nil
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else {
            return nil
        }

        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout.stride(ofValue: audioBufferList),
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr,
              let sourceData = audioBufferList.mBuffers.mData else {
            return nil
        }

        let sourceChannels = max(Int(asbd.mChannelsPerFrame), 1)
        guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: asbd.mSampleRate, channels: 1, interleaved: false),
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(frameCount)),
              let monoData = pcmBuffer.int16ChannelData?[0] else {
            return nil
        }

        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        let source = sourceData.bindMemory(to: Int16.self, capacity: frameCount * sourceChannels)

        if sourceChannels == 1 {
            monoData.assign(from: source, count: frameCount)
            return pcmBuffer
        }

        for frameIndex in 0..<frameCount {
            var sum = 0
            let baseIndex = frameIndex * sourceChannels
            for channelIndex in 0..<sourceChannels {
                sum += Int(source[baseIndex + channelIndex])
            }
            monoData[frameIndex] = Int16(sum / sourceChannels)
        }

        // NSLog("[AppleSTT] PCM converted input sampleRate=\(asbd.mSampleRate) channels=\(asbd.mChannelsPerFrame) formatID=\(asbd.mFormatID) bits=\(asbd.mBitsPerChannel) bytesPerFrame=\(asbd.mBytesPerFrame) -> output sampleRate=\(pcmBuffer.format.sampleRate) channels=\(pcmBuffer.format.channelCount) commonFormat=\(pcmBuffer.format.commonFormat.rawValue) interleaved=\(pcmBuffer.format.isInterleaved)")

        return pcmBuffer
    }

    private func appendRecognitionSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let recognitionRequest else {
            return
        }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            recognitionRequest.appendAudioSampleBuffer(sampleBuffer)
            return
        }

        let channelCount = Int(asbdPointer.pointee.mChannelsPerFrame)
        if channelCount <= 1 {
            recognitionRequest.appendAudioSampleBuffer(sampleBuffer)
            return
        }

        guard let recognitionBuffer = createRecognitionPCMBuffer(from: sampleBuffer) else {
            return
        }
        recognitionRequest.append(recognitionBuffer)
    }

    public func prepareAudioForChat() {
        self.pwCaptureSession?.stopRunning()
        AudioSessionRouteHelper.restorePreferredOutputRoute()
        self.initPWCaptureSession()
    }

    // MARK: - Push-to-talk

    /// State that exists only to finish and restart Apple Speech requests while
    /// PTT is held. Keeping it together prevents the ordinary STT state from
    /// becoming coupled to the PTT conversation lifecycle.
    private final class PTTRecognitionState {
        var sessionID = UUID()
        var didComplete = false
        var finishAction: ((Bool) -> Void)?
        var finishWorkItem: DispatchWorkItem?
    }

    /// Ends microphone input for PTT and waits for Apple Speech to return its
    /// final result before the caller closes the chat UI.
    public func finishPTTRecognition(completion: @escaping (Bool) -> Void) {
        pttRecognition.finishAction = completion

        guard recognizing, recognitionRequest != nil else {
            completePTTRecognition()
            return
        }

        // Stop feeding buffers before ending the Speech request. Otherwise the
        // capture delegate can keep appending audio to a finished request and
        // cause SpeechFramework to emit errors continuously.
        stopPWCaptureSession()
        recognitionRequest?.endAudio()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.pttRecognition.finishAction != nil else { return }
            self.completePTTRecognition()
        }
        pttRecognition.finishWorkItem?.cancel()
        pttRecognition.finishWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    /// Stops a response being read aloud and starts a fresh PTT recognition.
    public func resumePTTRecognition() {
        pttRecognition.finishAction = nil
        pttRecognition.finishWorkItem?.cancel()
        pttRecognition.finishWorkItem = nil

        if speaking || recognizing {
            // PTTManager has already stopped the shared TTS queue.
            endRecognize(stopTTS: false)
        }
        restartRecognize(silently: false, stopTTS: false)
    }

    /// Starts a fresh recognition request while the PTT button remains held.
    /// Apple Speech requests cannot accept more audio after a final result.
    @discardableResult
    private func restartRecognizeWhilePTTOn() -> Bool {
        guard PTTManager.shared.isPTTOn else { return false }
        restartRecognize(silently: true)
        return true
    }

    private func completeRecognition(_ action: @escaping (PassthroughSubject<String, Error>, UInt64)->Void) {
        guard !pttRecognition.didComplete,
              let lastText = last_converted?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lastText.isEmpty else {
            return
        }

        pttRecognition.didComplete = true
        NSLog("Recognized: \(lastText)")
        let text = PassthroughSubject<String, Error>()
        action(text, 0)
        text.send(lastText)
        text.send(completion: .finished)
    }

    private func completeCurrentRecognition() {
        guard let action = last_action else { return }
        completeRecognition(action)
    }

    @discardableResult
    private func completePTTRecognitionIfNeeded() -> Bool {
        guard pttRecognition.finishAction != nil else { return false }
        completePTTRecognition()
        return true
    }

    private func completePTTRecognition() {
        guard let completion = pttRecognition.finishAction else { return }
        completeCurrentRecognition()
        pttRecognition.finishAction = nil
        pttRecognition.finishWorkItem?.cancel()
        pttRecognition.finishWorkItem = nil
        endRecognize()
        let didSendRecognitionResult = pttRecognition.didComplete
        DispatchQueue.main.async {
            completion(didSendRecognitionResult)
        }
    }
}

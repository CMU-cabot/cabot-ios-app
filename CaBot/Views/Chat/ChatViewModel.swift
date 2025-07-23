/*******************************************************************************
 * Copyright (c) 2024  Carnegie Mellon University
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

import Combine
import Foundation
import UIKit
import ChatView
import SwiftUI
import PriorityQueueTTS

class ChatViewModel: ObservableObject  {
    public var cancellables = Set<AnyCancellable>()
    @Published public var messages: [ChatMessage] = [] {
        didSet {appModel?.shareChatStatus()}
    }
    @Published var chatState = ChatStateButtonModel()

    var stt: AppleSTT?
    var chat: ChatClientOpenAI?
    var config: ChatConfiguration = ChatConfiguration()
    private var map: [String: ChatMessage] = [:]
    private var map2: [String: PassthroughSubject<String, Error>] = [:]
    var appModel: CaBotAppModel?
    let inactive_delay = 20.0
    let welcome_delay = 5 * 60.0

    private let playBGMKey = "playBGMKey"
    @Published var playBGM: Bool = false {
        didSet {
            UserDefaults.standard.setValue(playBGM, forKey: playBGMKey)
            UserDefaults.standard.synchronize()
        }
    }

    init() {
        if let playBGM = UserDefaults.standard.value(forKey: playBGMKey) as? Bool {
            self.playBGM = playBGM
        }
    }

    func toggleChat() {
        if self.stt?.recognizing == true {
            self.stt?.endRecognize()
        }
        else if self.navigationAction() == true {
            self.stt?.tts?.stop()
            self.stt?.speaking = false
        }
        else {
            self.stt?.tts?.stop()
            self.stt?.restartRecognize()
        }
    }
    func send(message: String) {
        NSLog("chat send message: \(message)")
        self.chat?.send(message: message)
    }

    private func sttAction(text: PassthroughSubject<String, any Error>?, code: UInt64)->Void {
        var buffer = ""
        text?.sink(receiveCompletion: { _ in
            if self.appModel?.showingChatView != true {return}
            self.playVoiceRecoSuccess()
            DispatchQueue.main.async {
                self.messages.append(ChatMessage(user: .User, text: buffer))
                self.send(message: buffer)
            }
        }, receiveValue: { chunk in buffer += chunk})
        .store(in: &self.cancellables)
    }

    private func sttFailure(error: NSError)->Void {
        print(error)
    }

    private func sttTimeout()->Void {
        print("timeout")
        if PriorityQueueTTS.shared.isSpeaking {
//                    self.playVoiceRecoSuccess()
        } else {
            self.playTimeoutSound()
        }
        ContentView.inactive_at = Date()
        self.appModel?.showingChatView = false
    }

    func resetSttActions() {
        stt?.resetActions(action: sttAction, failure: sttFailure, timeout: sttTimeout)
    }

    func process(_ identifier: String, _ text: PassthroughSubject<String, Error>) {
        let message = ChatMessage(user: .Agent, text: "")
        DispatchQueue.main.async {
            self.messages.append(message)
        }
        text.sink(receiveCompletion: {_ in
            self.appModel?.shareChatStatus()
        }, receiveValue: { chunk in
            DispatchQueue.main.async {
                message.append(text: chunk)
                self.objectWillChange.send()
            }
        })
        .store(in: &self.cancellables)

        stt?.listen(
            selfvoice: text,
            speakendaction: { text in
                if let text {
                    print("speakend \(text)")
                }
            },
            action: sttAction,
            failure: sttFailure,
            timeout: sttTimeout
        )
    }

    func playVoiceRecoStart() {
//        appModel?.playAudio(file: "/System/Library/Audio/UISounds/nano/3rdParty_Start_Haptic.caf")
        appModel?.playAudio(file: "/System/Library/Audio/UISounds/nano/SiriStart_Haptic.caf")
    }

    func playVoiceRecoSuccess() {
        //        appModel?.playAudio(file: "/System/Library/Audio/UISounds/nano/3rdParty_Stop_Haptic.caf")
        appModel?.playAudio(file: "/System/Library/Audio/UISounds/nano/SiriStopSuccess_Haptic.caf")
    }

    func playTimeoutSound() {
//        appModel?.playAudio(file: "/System/Library/Audio/UISounds/nano/3rdParty_Stop_Haptic.caf")
        appModel?.playAudio(file: "/System/Library/Audio/UISounds/nano/SiriStopFailure_Haptic.caf")
    }

    func navigationAction() -> Bool {
        if let errorMessage = ChatData.shared.errorMessage {
            ChatData.shared.errorMessage = nil
            self.chatState.chatState = .Inactive
            DispatchQueue.main.async {
//                self.messages.append(ChatMessage(user: .User, text: errorMessage))
                self.send(message: errorMessage)
            }
            return true
        }
        if ChatData.shared.startNavigate {
            ChatData.shared.startNavigate = false
            self.chatState.chatState = .Inactive
            self.appModel?.needToStartAnnounce(wait: true)
            self.playTimeoutSound()
            self.appModel?.showingChatView = false
            return true
        }
        return false
    }
}

class ChatData {
    static let shared = ChatData()
    private let locationLogPack = LogPack(title:"<Socket on: location>", threshold:7.0, maxPacking:10)
    private let cameraOrientationLogPack = LogPack(title:"<Socket on: camera_orientation>", threshold:7.0, maxPacking:10)
    private let cabotNameLogPack = LogPack(title:"<Socket on: cabot_name>", threshold:7.0, maxPacking:10)
    var viewModel: ChatViewModel?
    var tourManager: TourManager?
    var errorMessage: String?
    var startNavigate = false

    struct CurrentLocation: Decodable {
        var lat: Double
        var lng: Double
        var floor: Int
        var yaw: Double?
        var rotate: Double?
    }

    struct CameraOrientation: Decodable {
        var roll: Double
        var pitch: Double
        var yaw: Double
        var camera_rotate: Bool
    }

    var lastLocation: CurrentLocation? {
        didSet {
            guard let location = lastLocation else {return}
            locationLogPack.log(text:"\(location)")
        }
    }

    var lastCameraImage: String? {
        didSet {
            guard let image = lastCameraImage else {return}
            NSLog("chat camera_image \(image.count) bytes")
        }
    }

    var lastCameraOrientation: CameraOrientation? {
        didSet {
            guard let orientation = lastCameraOrientation else {return}
            cameraOrientationLogPack.log(text:"\(orientation)")
        }
    }

    var suitcase_id = "unknown" {
        didSet {
            cabotNameLogPack.log(text:"\(suitcase_id)")
        }
    }

    func clear() {
        lastLocation = nil
        lastCameraImage = nil
        lastCameraOrientation = nil
        errorMessage = nil
        startNavigate = false
    }
}

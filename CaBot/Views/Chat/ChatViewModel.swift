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

class ChatViewModel: ObservableObject  {
    public var cancellables = Set<AnyCancellable>()
    @Published public var messages: [ChatMessage] = []
    @Published var chatState = ChatStateButtonModel()

    var stt: AppleSTT?
    var chat: ChatClient?
    private var map: [String: ChatMessage] = [:]
    private var map2: [String: PassthroughSubject<String, Error>] = [:]

    func toggleChat() {
        if self.stt?.recognizing == true {
            self.stt?.endRecognize()
        }
        else {
            self.stt?.restartRecognize()
        }
    }
    func send(message: String) {
        print("send message: \(message)")
        self.chat?.send(message: message)
    }

    func process(_ identifier: String, _ text: PassthroughSubject<String, Error>) {
        let message = ChatMessage(user: .Agent, text: "")
        DispatchQueue.main.async {
            self.messages.append(message)
        }
        text.sink(receiveCompletion: {_ in
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
            action: { text, code in
                var buffer = ""
                text?.sink(receiveCompletion: { _ in
                    DispatchQueue.main.async {
                        self.messages.append(ChatMessage(user: .User, text: buffer))
                        self.send(message: buffer)
                    }
                }, receiveValue: { chunk in buffer += chunk})
                .store(in: &self.cancellables)
            },
            failure: { error in
                print(error)
            },
            timeout: {
                print("timeout")
            }
        )
    }
}

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

import SwiftUI
import ChatView

public struct ContentView: View {
    @EnvironmentObject var appModel: CaBotAppModel
    @StateObject var model: ChatViewModel
    @State var timer: Timer?
    static var inactive_at: Date?
    public var body: some View {
        ChatView(messages: model.messages)
        HStack {
            Spacer()
            ChatStateButton(action: {
                NSLog("Tapped ChatStateButton while \(model.chatState.chatState.rawValue)")
                model.toggleChat()
            }, state: $model.chatState)
            .frame(width: 150)
            .disabled(appModel.sendingChatData)
            Spacer()
        }
        .frame(height: 200)
        .onAppear() {
            appModel.sendingChatData = false
            startChat(true)
        }
        .onDisappear() {
            startChat(false)
        }
    }
    
    func startChat(_ start: Bool) {
        if !start {
            model.stt?.endRecognize()
            timer?.invalidate()
            if ContentView.inactive_at == nil {
                ContentView.inactive_at = Date()
            }
            return
        }
        var count_down = 0
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            if start, let stt: AppleSTT = model.stt {
                if stt.recognizing {
                    count_down = 2
                }
                if count_down > 0 {
                    appModel.requestCameraImage()
                    count_down -= 1
                }
            }
        }
        var welcome_message = false
        if model.stt == nil {
            model.stt = AppleSTT(state: $model.chatState, tts: PriorityQueueTTSWrapper.shared)
            model.chat = ChatClientOpenAI(config:model.config, callback: model.process)
            model.resetSttActions()
            welcome_message = true
        } else {
            model.stt?.resetLang()
            if let inactive_at = ContentView.inactive_at, -inactive_at.timeIntervalSinceNow > model.inactive_delay {
                ChatData.shared.clear()
                model.chat?.restart(config:model.config)
                if -inactive_at.timeIntervalSinceNow > model.welcome_delay {
                    model.messages.removeAll()
                    welcome_message = true
                }
            }
        }
        ContentView.inactive_at = nil
        debugPrintTourData()
        if welcome_message {
            model.send(message: "")
        } else {
//            model.stt?.restartRecognize()
            if let greeting = ["GREETING_1", "GREETING_2", "GREETING_3", "SPEAK_NOW"].randomElement() {
                model.chat?.speakGreeting(CustomLocalizedString(greeting, lang: I18N.shared.lang))
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            ContactsUtil.shared.load()
        }
    }

    func debugPrintTourData() {
        if let result = try? ResourceManager.shared.load() {
            let tours = result.tours
            let destinations =  result.directory.allDestinations()
            NSLog("\(tours.count) chat tours")
            tours.forEach() { tour in
                NSLog("chat tour \(tour.title.text) \(tour.id)")
            }
            NSLog("\(destinations.count) chat destinations")
            destinations.forEach() { dest in
                NSLog("chat destination \(dest.title.text) \(dest._id)")
            }
        }
    }
}

#Preview("ChatView") {
    let model = ChatViewModel()
    model.messages = [
        ChatMessage(user: .User, text: "Hello1\nHello2\nHello3"),
        ChatMessage(user: .Agent, text: "Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2"),
        ChatMessage(user: .User, text: "Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 ")
    ]
    return ContentView(model: model)
}

#Preview("ChatView Dynamic") {
    let model = ChatViewModel()
    DispatchQueue.main.asyncAfter(deadline: .now()+1) {
        model.messages.append(ChatMessage(user: .User, text: "Hello1\nHello2\nHello3"))
    }
    DispatchQueue.main.asyncAfter(deadline: .now()+2) {
        model.messages.append(ChatMessage(user: .Agent, text: "Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2 Hello2"))
    }
    DispatchQueue.main.asyncAfter(deadline: .now()+3) {
        model.messages.append(ChatMessage(user: .User, text: "Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 Hello3 "))
    }
    return ContentView(model: model)
}

#Preview("ChatView Streaming") {
    let model = ChatViewModel()
    let message = ChatMessage(user: .Agent, text: "")
    let long_sample: String = "This is a sample message."
    var count = 0
    Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {timer in
        let text = long_sample
        if count < text.count {
            let index = text.index(text.startIndex, offsetBy: count)
            let character = text[index]
            message.append(text: String(character))
            count += 1
        } else {
            model.chatState.chatState = .Inactive
            timer.invalidate()
        }
    }
    model.messages.append(message)
    model.chatState.chatState = .Speaking
    return ContentView(model: model)
}

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
import ChatView
import OpenAI

extension Model {
    static let ollama_llama3_2 = "ollama/llama3.2"
}

class ChatClientOpenAI: ChatClient {
    var callback: ChatClientCallback?
    var client: OpenAI
    let welcome_text = "Hello"
    var pub: PassthroughSubject<String, Error>?
    var callback_called = Set<String>()
    let model: Model = .ollama_llama3_2
    var history: LimitedArray<ChatItem>
    var queryResultCancellable : AnyCancellable? = nil
    var queryResultCache :String = ""

    init(config:ChatConfiguration, callback: @escaping ChatClientCallback) {
        self.callback = callback
        let url = URL(string: config.host)!
        NSLog("OpenAI Client with \(url)")
        let configuration = OpenAI.Configuration(
            token: "temp-key",
            organizationIdentifier: nil,
            endpoint: url
        )
        self.client = OpenAI(configuration: configuration)
        self.history = LimitedArray<ChatItem>( limit: config.historySize )
    }
    func send(message: String) {
        var query = ChatQuery(
            messages: [
                .init(role: .system, content: "Please give only a response to the user input in 20 words.")!,
                .init(role: .user, content: message, name: "User")!
            ],
            model: model
        )
        if message.isEmpty {
            query = ChatQuery(
                messages: [
                    .init(role: .system, content: "Please greet to the user in 20 words.", name: "System")!
                ],
                model: model,
                metadata: [
                    "request_id": "dummy",
                    "conversation_id": "dummy",
                    "terminal_id": "dummy",
                    "suitcase_id": "dummy",
                ]
            )
        }
        print(query)
        history.append(.query(query))
        self.pub = PassthroughSubject<String, Error>()
        self.prepareSinkForHistory()
        client.chatsStream(query: query) { partialResult in
            print(partialResult);
            guard let pub = self.pub else { return }
            switch partialResult {
            case .success(let result):
                if !self.callback_called.contains(result.id) {
                    self.callback?(result.id, pub)
                    self.callback_called.insert(result.id)
                }
                if let content = result.choices[0].delta.content {
                    pub.send(content)
                }
            case .failure(let error):
                print(error)
                break
            }
        } completion: { error in
            print("chatStream completed \(error)")
            self.pub?.send(completion: .finished)
        }
    }
    
    func prepareSinkForHistory() {
        cleanupForHistory()
        guard let pub else { return }
        
        self.queryResultCancellable = pub.sink { [weak self] completion in
            let response :ChatItem.ChatResponse
            switch completion {
            case .finished:
                response = .success(self?.queryResultCache ?? "")
            case .failure(let error):
                response = .error(error)
            }
            self?.history.append(.responce(response))
            self?.cleanupForHistory()
            
            // print( " -- dump\n" + (self?.history.array.description ?? "") )
        } receiveValue: { [weak self] partial in
            self?.queryResultCache.append(partial)
        }
    }
    
    func cleanupForHistory(){
        queryResultCancellable = nil
        queryResultCache = ""
    }
}

enum ChatItem {
    case query(ChatQuery)
    case responce(ChatResponse)
    
    enum ChatResponse {
        case success(String)
        case error(Error)
    }
}

extension ChatItem : CustomStringConvertible {
    var description: String {
        switch self {
        case .query(let query):
            var desc = "\n query: \n"
            for msg in query.messages {
                desc += " - \(msg.role): \(msg.content?.string ?? "???")\n"
            }
            return desc
        case .responce(let responce):
            switch responce {
            case .success(let result):
                return "\n responce(success): \n - \(result)"
            case .error(let error):
                return "\n responce(error): \n - \(error)"
            }
        }
    }
}

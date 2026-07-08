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
import UIKit

extension Model {
    static let ollama_llama3_2 = "ollama/llama3.2"
}

struct ChatCameraMessagePayload: Codable, Equatable {
    struct Item: Codable, Equatable {
        let label: String
        let imageURL: String

        enum CodingKeys: String, CodingKey {
            case label
            case imageURL = "image_url"
        }
    }

    static let prefix = "cabot:camera_images:"

    let items: [Item]

    var encodedText: String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return items.first?.imageURL ?? ""
        }
        return Self.prefix + json
    }

    static func decode(from text: String) -> ChatCameraMessagePayload? {
        guard text.hasPrefix(prefix) else { return nil }
        let json = String(text.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatCameraMessagePayload.self, from: data)
    }
}

class ChatClientOpenAI: ChatClient {
    typealias VisionContent = ChatQuery.ChatCompletionMessageParam.ChatCompletionUserMessageParam.Content.VisionContent

    var callback: ChatClientCallback?
    var client: OpenAI?
    let welcome_text = "Hello"
    var pub: PassthroughSubject<String, Error>?
    var callback_called = Set<String>()
    let model: Model = .ollama_llama3_2
    var history: LimitedArray<ChatItem>
    var queryResultCancellable : AnyCancellable? = nil
    var queryResultCache :String = ""
    var metadata: [String: Any]
    private var backgroundQueue = DispatchQueue.init(label: "Background Queue")
    private let chatLanguages = ["ja": "JA", "en": "EN", "zh": "CN"]
    private var cameraRequestTimer: Timer?
    private var cameraRequestStartedAt: Date?
    private var pendingCameraRequestCompletion: ((String) -> Void)?
    private var cameraRequestObserver: NSObjectProtocol?
    private let cameraRequestInterval: TimeInterval = 1.0
    private let cameraRequestTimeout: TimeInterval = 5.0

    init(config:ChatConfiguration, callback: @escaping ChatClientCallback) {
        self.callback = callback
        self.history = LimitedArray<ChatItem>( limit: config.historySize )
        self.metadata = [
            "conversation_id": UUID().uuidString,
            "terminal_id": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "tour_recommendation_filter": "all" // TBD
        ]
        self.initClient(config: config)
    }
    func restart(config:ChatConfiguration) {
        self.history = LimitedArray<ChatItem>( limit: config.historySize )
        self.metadata["conversation_id"] = UUID().uuidString
        self.initClient(config: config)
    }
    func initClient(config:ChatConfiguration) {
        if let url = URL(string: config.host) {
            NSLog("OpenAI Client with \(url)")
            let configuration = OpenAI.Configuration(
                token: config.apiKey,
                organizationIdentifier: nil,
                endpoint: url,
                timeoutInterval: 30.0
            )
            self.client = OpenAI(configuration: configuration)
        } else {
            NSLog("Invalid URL \(config.host)")
            self.client = nil
        }
    }
    func speakGreeting(_ message: String) {
        self.pub = PassthroughSubject<String, Error>()
        if let pub = self.pub {
            let result_id = UUID().uuidString
            self.callback?(result_id, pub)
            self.callback_called.insert(result_id)
            pub.send(message)
            pub.send(completion: .finished)
        }
    }
    func send(message: String) {
        guard let appModel = ChatData.shared.viewModel?.appModel, appModel.showingChatView else {return}
        // prepare messages
        let messages = prepareMessages(message: message)
        // prepare metadata
        self.metadata["request_id"] = UUID().uuidString
        self.metadata["lang"] = chatLanguages[I18N.shared.langCode, default: "OTHER"]
        self.metadata["suitcase_id"] = ChatData.shared.suitcase_id
        if let loc = ChatData.shared.lastLocation {
            self.metadata["current_location"] = [
                "lat": loc.lat,
                "lng": loc.lng,
                "floor": loc.floor,
                "rotate": loc.rotate ?? loc.yaw ?? 0.0
            ]
        } else {
            self.metadata.removeValue(forKey: "current_location")
        }
        if let tourManager = ChatData.shared.tourManager {
            if let dest = tourManager.currentDestination {
                self.metadata["current_destination"] = dest._id
            } else {
                self.metadata["current_destination"] = NSNull()
            }
            self.metadata["destinations"] = tourManager.destinations.map{$0._id}
        }
#if USER
        self.metadata["staff_call_available"] =
            appModel.lastSuccessfulZoomJoinParameters != nil &&
            appModel.zoomMeetingStatusText != "in_meeting"
#endif
        // query
        let query = ChatQuery(messages: messages, model: "dummy", metadata: AnyCodable(self.metadata), stream: true)

        if let data = try? JSONEncoder().encode(query) {
            if let str = String(data: data, encoding: .utf8) {
                NSLog("chat send query: \(str.prefix(1000))")
            }
        }

        history.append(.query(query))
        self.pub = PassthroughSubject<String, Error>()
        self.prepareSinkForHistory()
        var error_count = 0, success_count = 0
        var requiresCameraMessage = false
        DispatchQueue.main.async {
            appModel.sendingChatData = true
        }
        appModel.receivingChatContent = false
        if let viewModel = ChatData.shared.viewModel, viewModel.playBGM {
            appModel.startBGM()
        }
        var startDate:Date? = Date()
        client?.chatsStream(query: query) { partialResult in
//            appModel.stopBGM()
            if let start = startDate {
                NSLog("chat response time \(String(format: "%.3f", -start.timeIntervalSinceNow)) sec for \"\(message.prefix(100))\"")
                startDate = nil
            }
            print("chat stream partialResult \(partialResult)")
            guard let pub = self.pub, appModel.showingChatView else { return }
            switch partialResult {
            case .success(let result):
                if !requiresCameraMessage && !self.callback_called.contains(result.id) && result.choices[0].delta.toolCalls == nil {
                    self.callback?(result.id, pub)
                    self.callback_called.insert(result.id)
                }
                if !requiresCameraMessage, let content = result.choices[0].delta.content {
                    success_count += min(content.count, 1)
                    pub.send(content)
                    NSLog("chat stream content \(content)")
                    appModel.receivingChatContent = success_count > 0
                }
                if let toolCalls = result.choices[0].delta.toolCalls {
                    ChatData.shared.startNavigate = false
                    toolCalls.forEach {tool_call in
                        if let fn = tool_call.function, let name = fn.name, let arguments = fn.arguments?.data(using: .utf8) {
                            switch name {
                            case "around_description":
                                if let params = try? JSONDecoder().decode(AroundDescription.self, from: arguments) {
                                    NSLog("chat function \(name): \(params)")
                                    if params.is_image_required {
                                        success_count += 1
                                        requiresCameraMessage = true
                                    }
                                }
                                break
                            case "destination_setting":
                                if let params = try? JSONDecoder().decode(DestinationSetting.self, from: arguments) {
                                    success_count += 1
                                    NSLog("chat function \(name): \(params)")
                                    self.checkDestination(params)
                                    DispatchQueue.main.async {
                                        self.onDestinationSetting(params)
                                    }
                                }
                                break
                            case "tour_setting":
                                if let params = try? JSONDecoder().decode(TourSetting.self, from: arguments) {
                                    success_count += 1
                                    NSLog("chat function \(name): \(params)")
                                    self.checkTour(params)
                                    DispatchQueue.main.async {
                                        self.onTourSetting(params)
                                    }
                                }
                                break
                            case "call_staff":
                                NSLog("chat function \(name)")
                                success_count += 1
                                ChatData.shared.callStaffOnSpeechEnd = true
                                break
                            default:
                                break
                            }
                        }
                    }
                }
            case .failure(let error):
                error_count += 1
                NSLog("chat stream failure \(error)")
                break
            }
        } completion: { error in
            appModel.stopBGM()
            NSLog("chat stream completed \(error), error_count=\(error_count), success_count=\(success_count)")
            guard let pub = self.pub, appModel.showingChatView else {return}
            if success_count == 0 {
                let result_id = UUID().uuidString
                self.callback?(result_id, pub)
                self.callback_called.insert(result_id)
                let msg = error_count > 0 ? "Received an unexpected response" : "An unexpected error has occurred"
                pub.send(CustomLocalizedString(msg, lang: I18N.shared.lang))
            }
            if let msg = ChatData.shared.errorMessage {
                pub.send("\n\n\n\(msg)\n\(CustomLocalizedString("Checking now", lang: I18N.shared.lang))")
            }
            pub.send(completion: .finished)
            if requiresCameraMessage {
                self.requestCameraMessage(appModel: appModel)
                return
            }
            DispatchQueue.main.async {
                appModel.sendingChatData = false
            }
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

    func cancelPendingCameraRequest() {
        DispatchQueue.main.async {
            self.finishCameraRequest(message: nil)
        }
    }

    func requestCameraMessage(appModel: CaBotAppModel) {
        DispatchQueue.main.async {
            self.finishCameraRequest(message: nil)
            guard appModel.showingChatView else {
                appModel.sendingChatData = false
                return
            }

            ChatData.shared.clearCameraCache()
            self.cameraRequestStartedAt = Date()
            self.pendingCameraRequestCompletion = { [weak self] message in
                guard let self else { return }
                guard let viewModel = ChatData.shared.viewModel, appModel.showingChatView else {
                    DispatchQueue.main.async {
                        appModel.sendingChatData = false
                    }
                    return
                }
                self.displayMessageTexts(for: message).forEach { text in
                    viewModel.messages.append(ChatMessage(user: .User, text: text))
                }
                self.backgroundQueue.asyncAfter(deadline: .now() + 0.1) { // FIX heartbeat delay
                    self.send(message: message)
                }
            }

            NSLog("chat start camera request interval")
            self.cameraRequestObserver = NotificationCenter.default.addObserver(forName: .chatCameraCacheDidUpdate, object: nil, queue: .main) { [weak self] _ in
                self?.handleCameraCacheUpdate(appModel: appModel)
            }
            appModel.requestCameraImage()
            self.cameraRequestTimer = Timer.scheduledTimer(withTimeInterval: self.cameraRequestInterval, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                guard appModel.showingChatView else {
                    self.finishCameraRequest(message: nil)
                    appModel.sendingChatData = false
                    return
                }
                if let start = self.cameraRequestStartedAt, -start.timeIntervalSinceNow >= self.cameraRequestTimeout {
                    NSLog("chat camera request timed out after \(String(format: "%.3f", self.cameraRequestElapsedTime)) sec")
                    self.finishCameraRequest(message: self.prepareCameraMessage())
                    return
                }
                appModel.requestCameraImage()
            }
        }
    }

    func handleCameraCacheUpdate(appModel: CaBotAppModel) {
        guard pendingCameraRequestCompletion != nil else { return }
        guard appModel.showingChatView else {
            finishCameraRequest(message: nil)
            appModel.sendingChatData = false
            return
        }
        guard ChatData.shared.hasCompleteCameraCache else { return }
        NSLog("chat complete camera cache received in \(String(format: "%.3f", cameraRequestElapsedTime)) sec")
        finishCameraRequest(message: prepareCameraMessage())
    }

    var cameraRequestElapsedTime: TimeInterval {
        guard let start = cameraRequestStartedAt else { return 0.0 }
        return -start.timeIntervalSinceNow
    }

    func finishCameraRequest(message: String?) {
        cameraRequestTimer?.invalidate()
        cameraRequestTimer = nil
        if let observer = cameraRequestObserver {
            NotificationCenter.default.removeObserver(observer)
            cameraRequestObserver = nil
        }
        cameraRequestStartedAt = nil
        let completion = pendingCameraRequestCompletion
        pendingCameraRequestCompletion = nil
        guard let message, let completion else { return }
        completion(message)
    }

    struct AroundDescription: Decodable {
        var is_image_required: Bool
    }

    struct TourSetting: Decodable {
        var tour_id: String
        var add_idx: Int
    }

    struct DestinationSetting: Decodable {
        struct DestinationManipulation: Decodable {
            struct Manipulation: Decodable {
                var manipulation_add_idx: Int
                var manipulation_type: String
            }
            var manipulation: Manipulation
            var index: Int
            var destination_id: String
        }
        var destination_manipulations: [DestinationManipulation]
        var remove_all_destinations: Bool
    }

    func onDestinationSetting(_ params: DestinationSetting) {
        guard let tourManager = ChatData.shared.tourManager, let destinations = try? ResourceManager.shared.load().directory.allDestinations() else {return}
        if params.remove_all_destinations {
            tourManager.clearAllDestinations()
            NSLog("chat clear destinations")
        }
        params.destination_manipulations.forEach{item in
            guard let dest = destinations.first(where: {$0._id == item.destination_id}) else {return}
            ChatData.shared.errorMessage = nil
            switch item.manipulation.manipulation_type {
            case "add":
                if item.manipulation.manipulation_add_idx == 0 {
                    tourManager.stopCurrent()
                    tourManager.addToFirst(destination: dest)
                    ChatData.shared.startNavigate = true
                } else {
                    tourManager.addToLast(destination: dest)
                    if tourManager.destinationCount == 1 {
                        ChatData.shared.startNavigate = true
                    }
                }
                NSLog("chat add destination \(dest.value)")
                break
            case "remove":
                tourManager.remove(destination: dest)
                NSLog("chat remove destination \(dest.value)")
                break
            default:
                NSLog("chat manipulation_type \(item.manipulation.manipulation_type) not supported")
                break
            }
        }
    }

    func onTourSetting(_ params: TourSetting) {
        guard let tourManager = ChatData.shared.tourManager, let tours = try? ResourceManager.shared.load().tours else {return}
        guard let tour = tours.first(where: {$0.id == params.tour_id}) else {return}
        tourManager.set(tour: tour)
        NSLog("chat set tour: \(tour.id)")
        ChatData.shared.startNavigate = true
    }

    func checkDestination(_ params: DestinationSetting) {
        guard let destinations = try? ResourceManager.shared.load().directory.allDestinations() else {return}
        for item in params.destination_manipulations {
            if destinations.first(where: {$0._id == item.destination_id}) == nil {
                NSLog("chat destination_id \(item.destination_id) not found")
                ChatData.shared.errorMessage = CustomLocalizedString("Could not set destination", lang: I18N.shared.lang)
                ChatData.shared.startNavigate = false
            }
        }
    }

    func checkTour(_ params: TourSetting) {
        guard let tours = try? ResourceManager.shared.load().tours else {return}
        if tours.first(where: {$0.id == params.tour_id}) == nil {
            NSLog("chat tour_id \(params.tour_id) not found")
            ChatData.shared.errorMessage = CustomLocalizedString("Could not set tour", lang: I18N.shared.lang)
        }
    }

    func prepareMessages(message: String) -> [ChatQuery.ChatCompletionMessageParam] {
        var messages: [ChatQuery.ChatCompletionMessageParam] = []

        if let payload = ChatCameraMessagePayload.decode(from: message) {
            let vision = makeVisionContents(from: payload)
            if !vision.isEmpty {
                messages.append(.init(role: .user, content: vision)!)
            }
        } else if message.hasPrefix("data:image") {
            let vision: [VisionContent] = [
                .init(chatCompletionContentPartImageParam: .init(imageUrl: .init(url: message, detail: .auto)))
            ]
            messages.append(.init(role: .user, content: vision)!)
        } else if !message.isEmpty {
            messages.append(.init(role: .user, content: message)!)
        }

        return messages
    }

    func displayMessageTexts(for message: String) -> [String] {
        if let payload = ChatCameraMessagePayload.decode(from: message) {
            let imageURLs = payload.items.map(\.imageURL)
            return imageURLs.isEmpty ? [message] : imageURLs
        }
        return [message]
    }

    func prepareCameraMessage() -> String {
        guard let frontImage = preparedCameraImage(imageUrl: ChatData.shared.lastCameraImage, orientation: ChatData.shared.lastCameraOrientation) else {
            return CustomLocalizedString("Could not send camera image", lang: I18N.shared.lang)
        }

        var items: [ChatCameraMessagePayload.Item] = [.init(label: "front camera", imageURL: frontImage)]
        if let leftImage = preparedCameraImage(imageUrl: ChatData.shared.lastLeftCameraImage, orientation: ChatData.shared.lastLeftCameraOrientation) {
            items.append(.init(label: "left camera", imageURL: leftImage))
        }
        if let rightImage = preparedCameraImage(imageUrl: ChatData.shared.lastRightCameraImage, orientation: ChatData.shared.lastRightCameraOrientation) {
            items.append(.init(label: "right camera", imageURL: rightImage))
        }

        return ChatCameraMessagePayload(items: items).encodedText
    }

    func preparedCameraImage(imageUrl: String?, orientation: ChatData.CameraOrientation?) -> String? {
        guard let imageUrl else { return nil }
        if let orientation, orientation.camera_rotate && orientation.yaw < -Double.pi / 2 {
            return imageUrl
        }
        return rotate(imageUrl)
    }

    func makeVisionContents(from payload: ChatCameraMessagePayload) -> [VisionContent] {
        payload.items.flatMap { item in
            [
                .init(chatCompletionContentPartTextParam: .init(text: item.label)),
                .init(chatCompletionContentPartImageParam: .init(imageUrl: .init(url: item.imageURL, detail: .auto)))
            ]
        }
    }

    func rotate(_ imageUrl: String) -> String {
        let array = imageUrl.components(separatedBy: "base64,")
        if array.count == 0 {return imageUrl}
        guard let data = Data(base64Encoded: array[1]) else { return imageUrl }
        guard let image = UIImage(data: data) else { return imageUrl }
        let newImage = UIImage(cgImage: image.cgImage!, scale: 1.0, orientation: .down)
        guard let imageData = newImage.jpegData(compressionQuality: 0.75) else { return imageUrl }
        return "data:image/jpeg;base64,\(imageData.base64EncodedString())"
    }
}

extension Destination {
    var _id: String {
        get {
            return String(self.value.split(separator: "@")[0])
        }
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

/*******************************************************************************
 * Copyright (c) 2021, 2024  Carnegie Mellon University
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

import Foundation


class ResourceManager {
    public static let shared = ResourceManager()
    public var modeType: ModeType = .Normal

    public func set(addressCandidate: AddressCandidate) {
        self.addressCandidate = addressCandidate
    }
    public func set(modeType: ModeType) {
        self.modeType = modeType
    }

    public enum Resource: String {
        case config
        case directory
        case tourdata
        case features_start
        case features

        var file_name: String {
            "\(self.rawValue).json"
        }
    }

    public struct Result {
        var tours: [Tour]
        var directory: Directory.Sections
    }

    public func initServer() throws -> Bool {
        let configData = try ResourceManager.shared.fetchData(from: .config)
        self.config = try JSONDecoder().decode(Config.self, from: configData)
        let _ = try ResourceManager.shared.fetchData(from: .features_start)
        return true
    }

    public var isServerDataReady: Bool {
        get {
            lastResult != nil
        }
    }

    public func invalidate() {
        loadSemaphore.wait()
        defer {
            loadSemaphore.signal()
        }
        lastResult = nil
    }

    private var lastResult: Result? = nil
    private let loadSemaphore = DispatchSemaphore(value: 1)
    public func load() throws -> Result {
        if let lastResult {
            print("loading cache")
            return lastResult
        }
        loadSemaphore.wait()
        defer {
            loadSemaphore.signal()
        }
        print("loading")
        do {
            // need to load in this order to build structure correctly
            // make suer the server is initialized with the user ID
            let _ = try initServer()
            // features are not depending on other data, so load it first
            let _ = try Features.load()
            // tour data depends on features, it provides messages
            let tourData = try TourData.load()
            // directory depends on features and messages
            let directory = try Directory.load()
            lastResult = Result(tours: tourData.tours, directory: directory)
            if let lastResult {
                return lastResult
            }
        } catch {
            print("Error")
        }
        throw ResourceManagerError.contentLoadError
    }

    public func loadForPreview() throws -> Result {
        let _ = try Features.loadForPreview()
        let tourData = try TourData.loadForPreview()
        let directory = try Directory.loadForPreview()
        return Result(tours: tourData.tours, directory: directory)
    }

    public func getDestination(by ref: String) -> (any Destination)? {
        if let dest = TourData.getTourDestination(by: ref) {
            return dest
        }
        else if let dest = Directory.getDestination(by: ref) {
            return dest
        }
        return nil
    }

    public func contentURL(path: String?) -> URL? {
        guard let path else { return nil }
        guard path.range(of: "^[A-Za-z]", options: .regularExpression) != nil else {
            return nil
        }
        let replacedPath = path.replacingOccurrences(of: "%@", with: I18N.shared.langCode)
        guard let addressCandidate else { return nil }
        guard let url = URL(string: "http://\(addressCandidate.getCurrent()):9090/map/\(replacedPath)") else {
            return nil
        }

        var resultData: Data? = nil
        let semaphore = DispatchSemaphore(value: 0)

        let task = self.session.dataTask(with: url) { data, response, error in
            defer { semaphore.signal() }
            if let data = data,
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                resultData = data
            }
        }
        task.resume()
        semaphore.wait()  // Wait until the network call finishes
        if resultData != nil {
            return url
        }
        NSLog("Could not load content at \(path) -> \(url)")
        return nil
    }

    private var addressCandidate: AddressCandidate?
    private var config: Config?

    private struct Config: Codable {
        struct InitialLocation: Codable {
            let lat: Double
            let lng: Double
            let floor: Int
        }

        let doNotUseSavedCenter: String
        let initialLocation: InitialLocation
        let mapService: String
        let mapServiceUseHttp: String

        enum CodingKeys: String, CodingKey {
            case doNotUseSavedCenter = "DO_NOT_USE_SAVED_CENTER"
            case initialLocation = "INITIAL_LOCATION"
            case mapService = "MAP_SERVICE"
            case mapServiceUseHttp = "MAP_SERVICE_USE_HTTP"
        }
    }

    private let session: URLSession
    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData // Ignore local cache
        config.urlCache = nil // Disable URLCache entirely
        session = URLSession(configuration: config)
    }

    fileprivate func fetchData(from resource: Resource, lat: Double? = nil, lng: Double? = nil, dist: Int = 2000, user: String? = nil) throws -> Data {
        guard let currentAddress = addressCandidate?.getCurrent() else { throw ResourceManagerError.contentLoadError }
        let lat = lat ?? config?.initialLocation.lat ?? 0
        let lng = lng ?? config?.initialLocation.lng ?? 0
        let user = user ?? UIDevice.current.identifierForVendor?.uuidString ?? "default_user_identifier"

        let baseURL: String

        switch resource {
        case .config:
            baseURL = "http://\(currentAddress):9090/map/api/config"
        case .directory:
            baseURL = "http://\(currentAddress):9090/query/directory?user=\(user)&lat=\(lat)&lng=\(lng)&dist=\(dist)&lang=\(I18N.shared.langCode)"
        case .tourdata:
            baseURL = "http://\(currentAddress):9090/map/cabot/tourdata.json"
        case .features_start:
            baseURL = "http://\(currentAddress):9090/map/routesearch?action=start&lat=\(lat)&lng=\(lng)&user=\(user)&dist=\(dist)"
        case .features:
            baseURL = "http://\(currentAddress):9090/map/routesearch?action=features&lat=\(lat)&lng=\(lng)&user=\(user)&dist=\(dist)"
        }

        guard let url = URL(string: baseURL) else {
            throw ResourceManagerError.contentLoadError
        }

        var dataReceived: Data?
        let semaphore = DispatchSemaphore(value: 0)

        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                NSLog("Error fetching data: \(error.localizedDescription)")
                semaphore.signal()
                return
            }
            dataReceived = data
            semaphore.signal()
        }

        task.resume()
        _ = semaphore.wait(timeout: .now() + 3.0)

        guard let data = dataReceived else {
            throw ResourceManagerError.contentLoadError
        }
        try saveData(data, to: resource.file_name)

        return data
    }

    fileprivate func fetchDataPreview(for resource: Resource) throws -> Data {
        let path = Bundle.main.resourceURL!.appendingPathComponent("PreviewResource")
        let fileURL = path.appendingPathComponent(resource.file_name)
        return try Data(contentsOf: fileURL)
    }

    private func saveData(_ data: Data, to fileName: String) throws {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ResourceManagerError.contentLoadError
        }
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL)
    }
}

enum ResourceManagerError: Error {
    case noName
    case contentLoadError
}

class I18N {
    private var lang: String

    var langCode: String {
        get {
            Locale(identifier: self.lang).languageCode ?? "en"
        }
    }

    static let shared:I18N = I18N()

    private init() {
        self.lang = Locale.preferredLanguages[0]
    }

    func set(lang: String?) {
        if let lang = lang {
            self.lang = lang
        }
    }
}

class BufferedInfo {
    private var info:String = ""
    func add(info: String?) {
        guard let info = info else { return }
        if self.info.count > 0 { self.info += "\n" }
        self.info += info
    }
    func summary() -> String? {
        if self.info.count > 0 {
            return self.info
        }
        return nil
    }
}

class KeyedI18NText: Equatable {
    let key: String
    let base: I18NText?

    static func == (lhs: KeyedI18NText, rhs: KeyedI18NText) -> Bool {
        return lhs.key == rhs.key && lhs.base == rhs.base
    }

    init(key: String, base: I18NText?) {
        self.key = key
        self.base = base
    }

    var text: String {
        get {
            if let base = self.base {
                return CustomLocalizedString(key, lang: I18N.shared.langCode, base.text)
            } else {
                return CustomLocalizedString(key, lang: I18N.shared.langCode)
            }
        }
    }

    var pron: String {
        get {
            if let base = self.base {
                return CustomLocalizedString("\(key)-pron", lang: I18N.shared.langCode, base.pron)
            } else {
                return CustomLocalizedString("\(key)-pron", lang: I18N.shared.langCode)
            }
        }
    }
}

class I18NText: Equatable, Hashable {
    private var _text: [String: String] = [:]
    private var _pron: [String: String] = [:]

    static func == (lhs: I18NText, rhs: I18NText) -> Bool {
        return lhs._text == rhs._text && lhs._pron == rhs._pron
    }
    func hash(into hasher: inout Hasher) {
        for item in _text {
            hasher.combine(item.key)
            hasher.combine(item.value)
        }
        for item in _pron {
            hasher.combine(item.key)
            hasher.combine(item.value)
        }
    }

    init(text: [String: String], pron: [String: String]) {
        self._text = text
        self._pron = pron
    }

    static func empty() -> I18NText {
        return I18NText(text: [:], pron: [:])
    }

    var text: String {
        get {
            if let text = self._text[I18N.shared.langCode] {
                return text
            }
            if let text = self._text["Base"] {
                return text
            }
            return "" // CustomLocalizedString("❗️NO Text", lang: I18N.shared.lang)
        }
    }

    var pron: String {
        get {
            if let text = self._pron[I18N.shared.langCode] {
                return text
            }
            return self.text
        }
    }

    var languages: [String] {
        get {
            return self._text.keys.sorted()
        }
    }

    var isEmpty: Bool {
        get {
            return _text.count == 0 || _pron.count == 0
        }
    }

    var warn: String? {
        get {
            let warn = BufferedInfo()
            if self.text.count == 0 {
                warn.add(info: "No text found for launguage \(I18N.shared.langCode)")
            }
            return warn.summary()
        }
    }

    private struct CodingKeys: CodingKey {
        var stringValue: String
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        var intValue: Int?
        init?(intValue: Int) {
            return nil
        }
    }
    static func decode(decoder: Decoder, baseKey: String) -> I18NText {
        var main: [String: String] = [:]
        var pron: [String: String] = [:]

        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            for key in container.allKeys.filter({ key in
                key.stringValue.hasPrefix(baseKey)
            }) {
                let separators = CharacterSet(charactersIn: "-_:")
                let items = key.stringValue.components(separatedBy: separators)
                if items.count == 1 { // title
                    main["Base"] = try container.decode(String.self, forKey: key)
                }
                else if items.count == 2 {
                    if items[1] == "hira" { // special case for Japanese hiragana
                        pron["ja"] = try container.decode(String.self, forKey: key)
                    } else {
                        main[String(items[1])] = try container.decode(String.self, forKey: key)
                    }
                }
                else if items.count == 3 && items[2] == "pron" {
                    pron[String(items[1])] = try container.decode(String.self, forKey: key)
                }
            }
            return I18NText(text: main, pron: pron)
        } catch {
            return I18NText(text: [:], pron: [:])
        }
    }
}

class Messages {
    var arriveMessages: [I18NText] = []
    var startMessage: I18NText?
    var summary: I18NText?

    public func add(_ message: Message) {
        switch(message.type) {
        case .startMessage:
            self.startMessage = message.text
        case .arriveMessage:
            self.arriveMessages.append(message.text)
        case .summary:
            self.summary = message.text
        }
    }
}

struct TourData: Decodable {
    let tours: [Tour]
    let destinations: [DestinationRef]
    let messages: [Message]
    static var refIndex: [String: Messages] = [:]
    static var tourIndex: [String: Tour] = [:]
    static var destRefIndex: [String: DestinationRef] = [:]
    static var destIndex: [String: TourDestination] = [:]

    static func buildIndex(messages: [Message]) {
        TourData.refIndex.removeAll()
        for message in messages {
            if TourData.refIndex[message.parent] == nil{
                TourData.refIndex[message.parent] = Messages()
            }
            TourData.refIndex[message.parent]?.add(message)
        }
    }

    static func getMessage(by ref: NodeRef) -> Messages? {
        return refIndex[ref.description]
    }

    static func buildIndex(destinations: [DestinationRef]) {
        for destination in destinations {
            var key = destination.value
            if let variation = destination.variation {
                key += "#\(variation)"
            }
            destRefIndex[key] = destination
        }
    }

    static func getDestinationRef(by ref: String) -> DestinationRef? {
        return destRefIndex[ref]
    }

    static func buildIndex(tours: [Tour]) {
        for tour in tours {
            tourIndex[tour.id] = tour
            for destination in tour.destinations {
                destIndex[destination.ref.description] = destination
            }
        }
    }

    static func getTour(by id: String) -> Tour? {
        return tourIndex[id]
    }

    static func getTourDestination(by ref: String) -> TourDestination? {
        return destIndex[ref]
    }

    enum CodingKeys: CodingKey {
        case tours
        case destinations
        case messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.messages = try container.decode([Message].self, forKey: .messages)
        TourData.buildIndex(messages: self.messages)
        self.destinations = try container.decode([DestinationRef].self, forKey: .destinations)
        TourData.buildIndex(destinations: self.destinations)
        self.tours = try container.decode([Tour].self, forKey: .tours)
        TourData.buildIndex(tours: self.tours)
    }

    fileprivate static func load() throws -> TourData {
        do {
            let data = try ResourceManager.shared.fetchData(from: .tourdata)
            let tourdata = try JSONDecoder().decode(TourData.self, from: data)
            return tourdata
        } catch {
            throw ResourceManagerError.contentLoadError
        }
    }

    fileprivate static func loadForPreview() throws -> TourData {
        do {
            let data = try ResourceManager.shared.fetchDataPreview(for: .tourdata)
            let root = try JSONDecoder().decode(TourData.self, from: data)
            return root
        } catch {
            throw ResourceManagerError.contentLoadError
        }
    }
}

class Tour: Decodable, Hashable{

    // MARK: - Properties
    let title: I18NText
    let id: String
    var destinations: [TourDestination]
    let defaultVar: String?
    let introduction: I18NText
    let error: String?

    // MARK: - Coding Keys
    enum CodingKeys: String, CodingKey {
        case id = "tour_id"
        case destinations
        case defaultVar = "default_var"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        destinations = try container.decode([TourDestination].self, forKey: .destinations)
        defaultVar = try container.decodeIfPresent(String.self, forKey: .defaultVar)
        title = I18NText.decode(decoder: decoder, baseKey: "title")

        introduction = I18NText(text: [:], pron: [:])
        error = nil
    }

    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.intValue = intValue
            self.stringValue = "title-"
        }
    }
    // MARK: - Hashable Conformance
    static func == (lhs: Tour, rhs: Tour) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct NodeRef: Decodable, Hashable, CustomStringConvertible {
    var node_id: String
    var variation: String?

    var description: String {
        if let variation = variation {
            "\(node_id)#\(variation)"
        } else {
            node_id
        }
    }

    static func == (lhs: NodeRef, rhs: NodeRef) -> Bool {
        return lhs.description == rhs.description
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(description)
    }

    init(node_id: String, variation: String?) {
        self.node_id = node_id
        self.variation = variation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let refStr = try container.decode(String.self)
        (self.node_id, self.variation) = NodeRef.parse(from: refStr)
    }

    static func parse(from input: String) -> (node_id: String, variation: String?) {
        let parts = input.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let node_id = String(parts[0])
        let variation = parts.count > 1 ? String(parts[1]) : nil
        return (node_id, variation)
    }
}

class TourDestination: Destination, Decodable {
    static func == (lhs: TourDestination, rhs: TourDestination) -> Bool {
        lhs.ref == rhs.ref
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(ref)
    }

    var value: String
    var arrivalAngle: Int?
    var content: URL?
    var summaryMessage: I18NText? = nil
    var startMessage: I18NText? = nil
    var arriveMessages: [I18NText]? = nil
    var waitingDestination: (any Destination)? = nil
    var waitingDestinationAngle: Int?
    var subtour: Tour?
    var error: String?
    var warning: String?
    var forDemonstration: Bool = false

    let ref: NodeRef
    let refTitle: String
    var title: I18NText = I18NText.empty()

    enum CodingKeys: String, CodingKey {
        case ref
        case refTitle = "#ref"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ref = try container.decode(NodeRef.self, forKey: .ref)

        // TODO use ref not ref.description
        let destRef = TourData.getDestinationRef(by: ref.description)
        arrivalAngle = destRef?.arrivalAngle
        content = ResourceManager.shared.contentURL(path: destRef?.content)
        if let value = destRef?.waitingDestination {
            waitingDestination = WaitingDestination(value: value, arrivalAngle: destRef?.waitingDestinationAngle)
        }

        refTitle = try container.decode(String.self, forKey: .refTitle)
        value = ref.node_id
        if let arrivalAngle {
            value += "@\(arrivalAngle)"
        }
        if let messages = TourData.getMessage(by: ref) {
            self.startMessage = messages.startMessage
            self.arriveMessages = messages.arriveMessages
            self.summaryMessage = messages.summary
        }
        
        if let feature = Features.getFeature(by: ref) {
            title = feature.properties.name
        }
    }
}

struct DestinationRef: Decodable {
    let floor: Int
    let value: String
    let title: String
    let variation: String?
    let arrivalAngle: Int?
    let content: String?
    let waitingDestination: String?
    let waitingDestinationAngle: Int?
    let subtour: String?

    enum CodingKeys: String, CodingKey {
        case floor, value
        case title = "#title"
        case variation = "var"
        case arrivalAngle
        case content
        case waitingDestination
        case waitingDestinationAngle
        case subtour
    }
}

struct Message: Decodable {
    enum MessageType: String, Decodable {
        case startMessage
        case arriveMessage
        case summary
    }
    let type: MessageType
    let parent: String
    var text: I18NText

    enum CodingKeys: String, CodingKey {
        case type
        case parent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(MessageType.self, forKey: .type)
        parent = try container.decode(String.self, forKey: .parent)
        let allValues = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var textDict: [String: String] = [:]
        self.text = I18NText.decode(decoder: decoder, baseKey: "text")
    }

    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            self.intValue = intValue
            self.stringValue = "\(intValue)"
        }
    }
}

class Features {
    private static var features: [Feature] = []
    private static var refIndex: [String: Feature] = [:]

    static func buildIndex() {
        TourData.refIndex.removeAll()
        for feature in features {
            for entrance in feature.properties.entrances {
                refIndex[entrance] = feature
            }
        }
    }

    static func getFeature(by ref: NodeRef) -> Feature? {
        return refIndex[ref.node_id]
    }

    fileprivate static func load() throws -> [Feature] {
        do {
            let featuresData = try ResourceManager.shared.fetchData(from: .features)
            Features.features = try JSONDecoder().decode([Feature].self, from: featuresData)
            buildIndex()
            return Features.features
        } catch {
            throw ResourceManagerError.contentLoadError
        }
    }

    fileprivate static func loadForPreview() throws -> [Feature] {
        do {
            let data = try ResourceManager.shared.fetchDataPreview(for: .features)
            Features.features = try JSONDecoder().decode([Feature].self, from: data)
            buildIndex()
            return Features.features
        } catch {
            throw ResourceManagerError.contentLoadError
        }
    }
}

class Feature : Decodable,  Hashable {
    let properties: Properties
    let identifier: String
    enum CodingKeys: String, CodingKey {
        case properties
        case identifier = "_id"
    }
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        properties = try container.decode(Properties.self, forKey: .properties)
        identifier = try container.decode(String.self, forKey: .identifier)
    }

    static func == (lhs: Feature, rhs: Feature) -> Bool {
        return lhs.identifier == rhs.identifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
    struct Properties: Decodable {
        var entrances: [String] = []
        var name: I18NText

        private struct CodingKeys: CodingKey {
            var stringValue: String
            init?(stringValue: String) {
                self.stringValue = stringValue
            }
            var intValue: Int?
            init?(intValue: Int) {
                return nil
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            for key in container.allKeys.filter({ key in
                key.stringValue.range(of: "ent.?_node", options: .regularExpression) != nil
            })  {
                let entrance = try container.decode(String.self, forKey: key)
                self.entrances.append(entrance)
            }
            name = I18NText.decode(decoder: decoder, baseKey: "name")
        }
    }
}


class Directory {
    struct Sections: Decodable {
        let sections: [Section]
        let showSectionIndex: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sections = try container.decodeIfPresent([Section].self, forKey: .sections) ?? []
            showSectionIndex = try container.decodeIfPresent(Bool.self, forKey: .showSectionIndex) ?? false
        }

        init() {
            sections = []
            showSectionIndex = false
        }

        private enum CodingKeys: String, CodingKey {
            case sections
            case showSectionIndex
        }

        var itemCount: Int {
            get {
                sections.reduce(0) { r, section in r + section.itemCount }
            }
        }

        var sectionCount: Int {
            get {
                sections.reduce(0) { r, section in r + ((section.itemCount > 0) ? 1 : 0)}
            }
        }

        var showSections: Bool {
            return Double(itemCount) / Double(sectionCount) > 1.5
        }

        func allDestinations() -> [any Destination] {
            sections.flatMap { $0.items.flatMap { $0.allDestinations() } }
        }
    }

    struct Section: Decodable, Hashable {
        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
            for item in items {
                hasher.combine(item)
            }
        }
        let title: I18NText
        let items: [SectionItem]

        var itemCount: Int {
            get {
                items.reduce(0) {r, item in r + (item.hidden ? 0 : 1) }
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = I18NText.decode(decoder: decoder, baseKey: "title")
            items = try container.decodeIfPresent([SectionItem].self, forKey: .items) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case title, items
        }
    }

    struct SectionItem: Destination, Decodable {
        static func == (lhs: Directory.SectionItem, rhs: Directory.SectionItem) -> Bool {
            lhs.title == rhs.title && lhs.nodeID == rhs.nodeID
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
            if let nodeID = nodeID {
                hasher.combine(nodeID)
            }
        }

        public var hidden: Bool {
            (self.forDemonstration && ResourceManager.shared.modeType != .Advanced) || sectionContent?.itemCount ?? 1 == 0
        }

        func allDestinations() -> [any Destination] {
            if let content = sectionContent {
                return content.allDestinations()
            }
            return [self]
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = I18NText.decode(decoder: decoder, baseKey: "title")
            sectionContent = try container.decodeIfPresent(Sections.self, forKey: .content)

            if sectionContent == nil {
                subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? "Unknown"
                titlePron = try container.decodeIfPresent(String.self, forKey: .titlePron) ?? "Unknown"
                subtitlePron = try container.decodeIfPresent(String.self, forKey: .subtitlePron) ?? "Unknown"
                nodeID = try container.decodeIfPresent(String.self, forKey: .nodeID) ?? "No ID"

                if let nodeID = nodeID {
                    if let feature = Features.getFeature(by: NodeRef(node_id: nodeID, variation: nil)) {
                        title = feature.properties.name
                    } else {
                        title = I18NText.decode(decoder: decoder, baseKey: "title")
                    }
                    if let destRef = TourData.getDestinationRef(by: nodeID) {
                        arrivalAngle = destRef.arrivalAngle
                        content = ResourceManager.shared.contentURL(path: destRef.content)
                        if let value = destRef.waitingDestination {
                            waitingDestination = WaitingDestination(value: value, arrivalAngle: destRef.arrivalAngle)
                        }
                        _subtour = destRef.subtour
                    }

                    if let forDemonstrationString = try container.decodeIfPresent(String.self, forKey: .forDemonstration) {
                        forDemonstration = (forDemonstrationString.lowercased() == "true")
                    } else {
                        forDemonstration = false
                    }
                    if let message = TourData.getMessage(by: NodeRef(node_id: nodeID, variation: nil)) {
                        if let startMessage = message.startMessage {
                            self.startMessage = startMessage
                        }
                        self.arriveMessages = message.arriveMessages
                        if let summary = message.summary {
                            self.summaryMessage = summary
                        }
                    }
                }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case content
            case subtitle
            case titlePron
            case subtitlePron
            case title
            case nodeID
            case forDemonstration
        }

        var sectionContent: Sections? = nil
        var subtitle: String? = nil
        var titlePron: String? = nil
        var subtitlePron: String? = nil
        var nodeID: String? = nil

        // Destination protocol
        var value: String {
            get {
                var val = self.nodeID ?? ""
                if let arrivalAngle = self.arrivalAngle {
                    val += "@\(arrivalAngle)"
                }
                return val
            }
        }
        var arrivalAngle: Int?
        var title: I18NText = I18NText.empty()
        var content: URL?
        var summaryMessage: I18NText? = nil
        var startMessage: I18NText? = nil
        var arriveMessages: [I18NText]? = nil
        var waitingDestination: (any Destination)?
        var _subtour: String? = nil
        var subtour: Tour? {
            get {
                if let _subtour = _subtour {
                    TourData.getTour(by: _subtour)
                } else {
                    nil
                }
            }
        }
        var error: String? = nil
        var warning: String? = nil
        var forDemonstration: Bool = false
    }
    
    static var sections: Directory.Sections = Directory.Sections()
    static var valueIndex: [String: any Destination] = [:]

    static func buildIndex() {
        for dest in sections.allDestinations() {
            valueIndex[dest.value] = dest
        }
    }

    static func getDestination(by value: String) -> (any Destination)? {
        valueIndex[value]
    }

    fileprivate static func load() throws -> Sections {
        let directoryData = try ResourceManager.shared.fetchData(from: .directory)
        Directory.sections = try JSONDecoder().decode(Sections.self, from: directoryData)
        Directory.buildIndex()
        return Directory.sections
    }

    static func loadForPreview() throws -> Sections {
        let data = try ResourceManager.shared.fetchDataPreview(for: .directory)
        let directoryDataDecoded = try JSONDecoder().decode(Sections.self, from: data)
        Directory.buildIndex()
        return directoryDataDecoded
    }

    class FloorDestination{
        let floorTitle: I18NText
        let destinations: [any Destination]

        init(floorTitle: I18NText, destinations: [any Destination] = []) {
            self.floorTitle = floorTitle
            self.destinations = destinations
        }
    }
}

/// Destination for the robot waiting position
///
/// ```
/// - title: <String> Display text for the destination
///    - the text can be localizable
/// - value: <String> Navigation node ID
/// - pron: <String> Reading text for the destination if required other wise title is used for reading
///    - the text can be localizable
/// ```
struct WaitingDestination: Destination {
    static func == (lhs: WaitingDestination, rhs: WaitingDestination) -> Bool {
        return lhs.value == rhs.value
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.value)
    }

    init(value: String, arrivalAngle: Int? = nil) {
        self._value = value
        self.arrivalAngle = arrivalAngle
        let feature = Features.getFeature(by: NodeRef(node_id: value, variation: nil))
        self.title = feature?.properties.name ?? I18NText.empty()
        self.content = nil
        self.summaryMessage = nil
        self.startMessage = nil
        self.arriveMessages = nil
        self.waitingDestination = nil
        self.subtour = nil
        self.error = nil
        self.warning = nil
        self.forDemonstration = false
    }

    var title: I18NText
    var _value: String
    var value: String {
        get {
            var val = self._value
            if let arrivalAngle = self.arrivalAngle {
                val += "@\(arrivalAngle)"
            }
            return val
        }
    }
    var arrivalAngle: Int?
    var content: URL?
    var summaryMessage: I18NText?
    var startMessage: I18NText?
    var arriveMessages: [I18NText]?
    var waitingDestination: (any Destination)?
    var subtour: Tour?
    var error: String?
    var warning: String?
    var forDemonstration: Bool
}

/// Destination for the navigation
///
/// ```
/// - title: display text for the destination
/// - pron: reading text for the destination
/// - value: navigation node ID
/// - arrivalAngle: navigation arrival angle
/// - content: relative path to an html file
/// - summaryMessage: display under the title
/// - startMessage: will be read when the navigation started
/// - arriveMessage: will be read when the navigation arrive
/// - waitingDestination: the location where the robot will wait
/// - subtour: subtour
/// - forDemonstration: only shown in Advaned mode if true
/// ```
protocol Destination: Hashable {
    var title: I18NText { get }
    //var pron: I18NText { get }
    var value: String { get }
    var arrivalAngle: Int? { get }
    var content: URL? { get }
    var summaryMessage: I18NText? { get }
    var startMessage: I18NText? { get }
    var arriveMessages: [I18NText]? { get }
    var waitingDestination: (any Destination)? { get }
    var subtour: Tour? { get }
    var error: String? { get }
    var warning: String? { get }
    var forDemonstration: Bool { get }
}

protocol TourProtocol {
    var title: I18NText { get }
    var id: String { get }
    var destinations: [any Destination] { get }
    var currentDestination: (any Destination)? { get }
}

struct TourSaveData: Codable {
    var id: String
    var destinations: [String]
    var currentDestination: String

    init(){
        self.id = ""
        self.destinations = []
        self.currentDestination = ""
    }

    func toJson() -> Data {
        let encoder = JSONEncoder()
        if let jsonData = try? encoder.encode(self) {
            return jsonData
        }
        return Data()
    }

    func toJsonString() -> String {
        let jsonData = toJson()
        if let json = String(data: jsonData, encoding: .utf8) {
            return json
        }
        return ""
    }
}

protocol NavigationSettingProtocol {
    var enableSubtourOnHandle: Bool { get }
    var showContentWhenArrive: Bool { get }
}

class NavigationSetting: Decodable, NavigationSettingProtocol {
    let enableSubtourOnHandle: Bool
    let showContentWhenArrive: Bool

    enum CodingKeys: String, CodingKey {
        case enableSubtourOnHandle
        case showContentWhenArrive
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let flag = try? container.decode(Bool.self, forKey: .enableSubtourOnHandle) {
            self.enableSubtourOnHandle = flag
        } else {
            self.enableSubtourOnHandle = false
        }
        if let flag = try? container.decode(Bool.self, forKey: .showContentWhenArrive) {
            self.showContentWhenArrive = flag
        } else {
            self.showContentWhenArrive = false
        }
    }
}

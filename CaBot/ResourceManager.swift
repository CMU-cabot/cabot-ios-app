/*******************************************************************************
 * Copyright (c) 2021  Carnegie Mellon University
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
import Yams

enum MetadataError: Error {
    case noName
    case yamlParseError(error: YamlError)
    case contentLoadError
    case nestedReferenceError
}

enum SourceType: String, Decodable {
    case local
    case remote
}

extension CodingUserInfoKey {
    static let src = CodingUserInfoKey(rawValue: "src")!
    static let i18n = CodingUserInfoKey(rawValue: "i18n")!
    static let refCount = CodingUserInfoKey(rawValue: "refCount")!
    static let error = CodingUserInfoKey(rawValue: "error")!
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

class I18NText: Equatable {
    private var _text: [String: String] = [:]
    private var _pron: [String: String] = [:]
    
    static func == (lhs: I18NText, rhs: I18NText) -> Bool {
        return lhs._text == rhs._text && lhs._pron == rhs._pron
    }

    init(text: [String: String], pron: [String: String]) {
        self._text = text
        self._pron = pron
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
                let items = key.stringValue.split(separator: "-")
                if items.count == 1 { // title
                    main["Base"] = try container.decode(String.self, forKey: key)
                }
                else if items.count == 2 {
                    main[String(items[1])] = try container.decode(String.self, forKey: key)
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

func yamlPath(_ path: [CodingKey]) -> String{
    var ret:String = ""
    for e in path {
        if let index = e.intValue {
            ret += "[\(index)]"
        } else {
            ret += "/[\(e.stringValue)]"
        }
    }
    return ret
}

struct Source: Decodable, Hashable, CustomStringConvertible {
    static func == (lhs: Source, rhs: Source) -> Bool {
        return lhs.base == rhs.base && lhs.type == rhs.type && lhs.src == rhs.src
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(base)
        hasher.combine(type)
        hasher.combine(src)
    }
    var description: String {
        var exists = "not exists"
        if let content = self.content {
            exists = "content length=\(content.count)"
        }
        return "\(self.src) - (\(exists))"
    }
    
    var warn: String? {
        get {
            let warn = BufferedInfo()
            if let content = self.content {
                if let lang = LanguageDetector(string: content).detect() {
                    if lang != i18n.langCode {
                        warn.add(info: "Different language detected: \(lang) - expected \(i18n.langCode)")
                    }
                }
            }
            return warn.summary()
        }
    }
    
    var error: String? {
        get {
            let error = BufferedInfo()
            if let _ = self.content {
            } else {
                error.add(info: "Content not found")
            }
            return error.summary()
        }
    }
    
    let base: URL?
    let type: SourceType
    let _src: String
    var src: String {
        get {
            return String(format:_src, i18n.langCode)
        }
    }
    let i18n: I18N

    var url: URL? {
        get {
            switch(type) {
            case .local:
                let langSrc = String(format: src, i18n.langCode)
                return base?.appendingPathComponent(langSrc)
            case .remote:
                return URL(string:src)
            }
        }
    }

    var content: String? {
        get {
            guard let url = url  else { return nil }
            guard let text = try? String(contentsOf: url) else { return nil }
            return text.replacingOccurrences(of: "\r\n", with: "\n")
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case src
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        i18n = decoder.userInfo[.i18n] as! I18N
        type = try container.decode(SourceType.self, forKey: .type)
        _src = try container.decode(String.self, forKey: .src)
        base = (decoder.userInfo[.src] as? URL)?.deletingLastPathComponent()
    }

    init(base: URL?, type:SourceType, src:String, i18n:I18N) {
        self.base = base
        self.type = type
        self._src = src
        self.i18n = i18n
    }
}

struct CustomMenu: Decodable, Hashable {
    static func == (lhs: CustomMenu, rhs: CustomMenu) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let title: String
    let id: String
    let script: Source
    let function: String
}

struct Metadata: Decodable{
    let identifier: String
    let name: I18NText
    let i18n: I18N
    let langCode: String
    let conversation: Source?
    let destinationAll: Source?
    let destinations: Source?
    let tours: Source?
    let custom_menus: [CustomMenu]?

    static func load(at url: URL) throws -> Metadata {
        do {
            let str = try String(contentsOf: url)
            var userInfo:[CodingUserInfoKey : Any] = [:]
            userInfo[.src] = url
            userInfo[.i18n] = I18N.shared
            let yamlDecoder = YAMLDecoder()
            return try yamlDecoder.decode(Metadata.self, from: str, userInfo: userInfo)
        } catch let error as YamlError {
            throw MetadataError.yamlParseError(error: error)
        }
    }

    enum CodingKeys: CodingKey {
        case name
        case language
        case i18n
        case conversation
        case destinationAll
        case destinations
        case tours
        case custom_menus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // needs to have I18N instance
        let i18n = decoder.userInfo[.i18n] as! I18N
        self.i18n = i18n
        if let language = try? container.decodeIfPresent(String.self, forKey: .language) {
            i18n.set(lang: language)
        }
        self.langCode = i18n.langCode

        self.name = I18NText.decode(decoder: decoder, baseKey: CodingKeys.name.stringValue)
        self.identifier = self.name.text
        self.conversation = try? container.decodeIfPresent(Source.self, forKey: .conversation)
        self.destinationAll = try? container.decodeIfPresent(Source.self, forKey: .destinationAll)
        self.destinations = try? container.decodeIfPresent(Source.self, forKey: .destinations)
        self.tours = try? container.decodeIfPresent(Source.self, forKey: .tours)
        self.custom_menus = try? container.decodeIfPresent([CustomMenu].self, forKey: .custom_menus)
    }
}

class Resource: Hashable {
    let base: URL
    var langOverride: String?

    init(at url: URL) throws {
        base = url
        metadata = try Metadata.load(at: url.appendingPathComponent(Resource.METADATA_FILE_NAME))
    }

    static func == (lhs: Resource, rhs: Resource) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static let METADATA_FILE_NAME: String = "_metadata.yaml"

    private let metadata: Metadata

    var identifier:String {
        get {
            metadata.identifier
        }
    }

    var name:String {
        get {
            metadata.name.text
        }
    }

    var id:String {
        get {
            base.path
        }
    }

    var lang: String {
        get {
            self.langOverride ?? metadata.langCode
        }
        set {
            self.langOverride = newValue
            I18N.shared.set(lang: newValue)  // TODO unify language model
        }
    }

    var locale: Locale {
        return Locale.init(identifier: self.lang)
    }

    var conversationSource: Source? {
        get {
            if let c = metadata.conversation {
                return c
            }
            return nil
        }
    }
    
    var destinationAllSource: Source? {
        get {
            if let d = metadata.destinationAll {
                return d
            }
            return nil
        }
    }

    var destinationsSource: Source? {
        get {
            if let d = metadata.destinations {
                return d
            }
            return nil
        }
    }

    var toursSource: Source? {
        get {
            if let t = metadata.tours {
                return t
            }
            return nil
        }
    }

    var customeMenus: [CustomMenu] {
        get {
            if let cm = metadata.custom_menus {
                return cm
            }
            return []
        }
    }

    var languages: [String] {
        get {
            var languages:[String] = []
            for lang in metadata.name.languages {
                if lang != "Base" {
                    languages.append(lang)
                }
            }

            if languages.contains(where: {lang in lang == metadata.langCode}) == false {
                languages.append(metadata.langCode)
            }
            return languages
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
struct WaitingDestination: Decodable, Equatable {
    static func == (lhs: WaitingDestination, rhs: WaitingDestination) -> Bool {
        return lhs.title == rhs.title && lhs.value == rhs.value
    }
    
    var parentTitle:I18NText?
    let value:String
    var title:KeyedI18NText {
        get {
            return KeyedI18NText(key: "Robot Waiting Spot (%@)", base: parentTitle)
        }
    }

    enum CodingKeys: String, CodingKey {
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .value) {
            self.value = value
        } else {
            self.value = ""
            //warning.add(info: CustomLocalizedString("file specified by Source(type, src) is deprecated, use just 'src' string instead", lang: i18n.langCode))
        }
    }
}

struct Reference: CustomStringConvertible {
    let file: String
    let value: String

    static func from(ref: String) -> Reference? {
        if let index = ref.firstIndex(of: "/") {
            let file = String(ref[..<index])
            let value = String(ref[ref.index(index, offsetBy: 1)...])
            return Reference(file: file, value:value)
        }
        return nil
    }

    var description: String {
        return "\(file)/\(value)"
    }
}

/// Destination for the navigation
///
/// ```
/// - ref: <String> if ref is specified with the format (<local file>/<value>), it will copy properties from the destination that has <value> in the <local file>
///   - if other properties are specified too, it will override
/// - title: <String> Display text for the destination
///   - the text can be localizable
/// - value: <String> Navigation node ID
/// - pron: <String> Reading text for the destination if required other wise title is used for reading
///    - the text can be localizable
/// - file: <Source> file including a list of destinations
/// - summaryMessage: <Source> file inculding a message text
/// - startMessage: <Source> file including a message text
/// - content: <Source> file including a web content to show in the browser
/// - waitingDestination: <WaitingDestination>
/// ```
struct Root: Decodable {
    let sections: [FloorSection]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decodeIfPresent([FloorSection].self, forKey: .sections) ?? []
    }
    
    private enum CodingKeys: String, CodingKey {
        case sections
    }
}

struct FloorSection: Decodable {
    let title: I18NText
    let items: [Item]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = I18NText.decode(decoder: decoder, baseKey: "title")
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
    }
    
    private enum CodingKeys: String, CodingKey {
        case title, items
    }
}

struct Item: Decodable {
    let title: I18NText
    let content: ItemsContent?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = I18NText.decode(decoder: decoder, baseKey: "title")
        content = try container.decodeIfPresent(ItemsContent.self, forKey: .content)
    }
    
    private enum CodingKeys: String, CodingKey {
        case title, content
    }
}

struct ItemsContent: Decodable {
    let sections: [NestedSection]
    let showSectionIndex: Bool
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decodeIfPresent([NestedSection].self, forKey: .sections) ?? []
        showSectionIndex = try container.decodeIfPresent(Bool.self, forKey: .showSectionIndex) ?? false
    }
    
    private enum CodingKeys: String, CodingKey {
        case sections, showSectionIndex
    }
}

struct NestedSection: Decodable {
    let title: I18NText
    let items: [NestedItem]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = I18NText.decode(decoder: decoder, baseKey: "title")
        items = try container.decodeIfPresent([NestedItem].self, forKey: .items) ?? []
    }
    
    private enum CodingKeys: String, CodingKey {
        case title, items
    }
}

struct NestedItem: Decodable {
    let subtitle: String
    let titlePron: String
    let subtitlePron: String
    let title: I18NText
    let nodeID: String
    let forDemonstration: Bool
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? "Unknown"
        titlePron = try container.decodeIfPresent(String.self, forKey: .titlePron) ?? "Unknown"
        subtitlePron = try container.decodeIfPresent(String.self, forKey: .subtitlePron) ?? "Unknown"
        title = I18NText.decode(decoder: decoder, baseKey: "title")
        nodeID = try container.decodeIfPresent(String.self, forKey: .nodeID) ?? "No ID"
        if let forDemonstrationString = try container.decodeIfPresent(String.self, forKey: .forDemonstration) {
            forDemonstration = (forDemonstrationString.lowercased() == "true")
        } else {
            forDemonstration = false
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case subtitle, titlePron, subtitlePron, title, nodeID, forDemonstration
    }
}

func downloadDirectoryJson() throws -> [FloorDestination] {
    let fileConfigName = "config.json"
    
    guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        throw MetadataError.contentLoadError
    }
    let fileConfigURL = documentsDirectory.appendingPathComponent(fileConfigName)
    
    let configUrlString = "http://localhost:9090/map/api/config"
    guard let url = URL(string: configUrlString) else {
        throw MetadataError.contentLoadError
    }
    var downloadedFloorDestinations: [FloorDestination] = []
    
    let semaphore = DispatchSemaphore(value: 0)
    
    var dataReceived: Data?
    var downloadError: Error?
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        if let error = error {
            downloadError = error
            semaphore.signal()
            return
        }
        dataReceived = data
        semaphore.signal()
    }
    
    task.resume()
    semaphore.wait()
    
    if let error = downloadError {
        throw error
    }
    
    guard let data = dataReceived else {
        throw MetadataError.contentLoadError
    }
    
    do {
        try data.write(to: fileConfigURL)
        let configData = try Data(contentsOf: fileConfigURL)
        
        struct InitialLocation: Codable {
            let lat: Double
            let lng: Double
            let floor: Int
        }
        
        struct Config: Codable {
            let DO_NOT_USE_SAVED_CENTER: String
            let INITIAL_LOCATION: InitialLocation
            let MAP_SERVICE: String
            let MAP_SERVICE_USE_HTTP: String
        }
        
        let config = try JSONDecoder().decode(Config.self, from: configData)
        
        let lat = config.INITIAL_LOCATION.lat
        let lng = config.INITIAL_LOCATION.lng
        let dist = 5000
        let user = "user-id"
        
        let fileDirectoryFileName = "directory.json"
        
        let fileDirectoryURL = documentsDirectory.appendingPathComponent(fileDirectoryFileName)
        let directoryUrlString = "http://localhost:9090/query/directory?user=\(user)&lat=\(lat)&lng=\(lng)&dist=\(dist)"
        guard let directoryUrl = URL(string: directoryUrlString) else {
            throw MetadataError.contentLoadError
        }
        
        var directoryDataReceived: Data?
        var directoryDownloadError: Error?
        let directoryTask = URLSession.shared.dataTask(with: directoryUrl) { data, response, error in
            if let error = error {
                directoryDownloadError = error
                semaphore.signal()
                return
            }
            directoryDataReceived = data
            semaphore.signal()
        }
        
        directoryTask.resume()
        
        semaphore.wait()
        
        if let error = directoryDownloadError {
            throw error
        }
        
        guard let directoryData = directoryDataReceived else {
            throw MetadataError.contentLoadError
        }
        
        try directoryData.write(to: fileDirectoryURL)
        let decoder = JSONDecoder()
        let directoryDataDecoded = try decoder.decode(Root.self, from: directoryData)
        
        let tours = try Tour.load()
        let features = try Feature.loadFeature()
        
        for section in directoryDataDecoded.sections {
            for item in section.items {
                var destinations: [Destination] = []
                if let content = item.content {
                    for subSection in content.sections {
                        for subItem in subSection.items {
                            if let destination = try createDestination(from: subItem, itemTitle: item.title, tours: tours, features: features) {
                                destinations.append(destination)
                            }
                        }
                    }
                }
                
                if !destinations.isEmpty {
                    let floorDestination = FloorDestination(floorTitle: item.title, destinations: destinations)
                    downloadedFloorDestinations.append(floorDestination)
                }
            }
        }


        
    } catch {
        NSLog("Error: \(error.localizedDescription)")
    }
    
    return downloadedFloorDestinations
}

func createDestination(from subItem: NestedItem, itemTitle: I18NText, tours: [Tour], features: [Feature]) throws -> Destination? {
    var destination: Destination?

    for feature in features {
        if feature.properties.ent1Node == subItem.nodeID {
            destination = Destination(
                floorTitle: itemTitle,
                title: I18NText(text: feature.properties.names, pron: [:]),
                value: subItem.nodeID,
                pron: nil,
                file: nil,
                summaryMessage: "",
                startMessage: "",
                arriveMessages: [],
                content: nil,
                waitingDestination: nil,
                subtour: nil,
                forDemonstration: subItem.forDemonstration
            )

            for tour in tours {
                if let tourDestination = tour.destinations.first(where: {
                    $0.matchedDestinationRef?.value ?? $0.ref == subItem.nodeID
                }) {
                    destination?.summaryMessage = tourDestination.summaryMessage?.text.text ?? ""
                    destination?.startMessage = tourDestination.startMessage?.text.text ?? ""
                    destination?.arriveMessages = tourDestination.arriveMessages.map { $0.text.text }
                }
            }
            break
        }
    }

    return destination
}

class FloorDestination{
    let floorTitle: I18NText
    let destinations: [Destination]

    init(floorTitle: I18NText, destinations: [Destination] = []) {
        self.floorTitle = floorTitle
        self.destinations = destinations
    }
}


class Destination:  Hashable {
    static func == (lhs: Destination, rhs: Destination) -> Bool {
        if let lhsfile = lhs.file,
           let rhsfile = rhs.file {
            return lhsfile.type == rhsfile.type && lhsfile.src == rhsfile.src
        }
        if let lhsvalue = lhs.value,
           let rhsvalue = rhs.value {
            return lhsvalue == rhsvalue
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        if let file = file {
            hasher.combine(file.type)
            hasher.combine(file.src)
        }
        if let value = value {
            hasher.combine(value)
        }
    }
    
    let i18n:I18N
    let floorTitle: I18NText
    let title: I18NText
    let value:String?
    let file:Source?
    var summaryMessage: String
    var startMessage:String
    var arriveMessages: [String]?
    let content:Source?
    let waitingDestination:WaitingDestination?
    let subtour:Tour?
    let error:String?
    let warning:String?
    let ref:Reference?
    let refDest:Destination?
    var parent: Tour? = nil
    let debug:Bool
    let forDemonstration:Bool

    enum CodingKeys: String, CodingKey {
        case title
        case ref
        case value
        case pron
        case file
        case summaryMessage
        case startMessage
        case arriveMessages
        case content
        case waitingDestination
        case subtour
        case debug
    }
    init(floorTitle: I18NText,title: I18NText,value: String?, pron: String?, file: Source?, summaryMessage: String, startMessage: String,arriveMessages: [String], content: Source?, waitingDestination: WaitingDestination?, subtour: Tour?,forDemonstration:Bool) {
        self.i18n = I18N.shared
        self.title = title
        self.floorTitle = floorTitle
        self.value = value
        self.file = file
        self.summaryMessage = summaryMessage
        self.startMessage = startMessage
        self.arriveMessages = arriveMessages
        self.content = content
        self.waitingDestination = waitingDestination
        self.subtour = subtour
        self.error = nil
        self.warning = nil
        self.ref = nil
        self.refDest = nil
        self.debug = false
        self.forDemonstration = forDemonstration
    }
}


protocol TourProtocol {
    var title: I18NText { get }
    var id: String { get }
    var destinations: [Destination] { get }
    var currentDestination: Destination? { get }
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
// MARK: - Nested Types
struct DestinationJSON: Decodable {
    let ref: String
    let refTitle: String
    var matchedDestinationRef: DestinationRef?
   // var matchedMessage: Message?
    var summaryMessage: Message?
    var startMessage: Message?
    var arriveMessages: [Message]
    var title: I18NText
    
    enum CodingKeys: String, CodingKey {
        case ref
        case refTitle = "#ref"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ref = try container.decode(String.self, forKey: .ref)
        refTitle = try container.decode(String.self, forKey: .refTitle)
        matchedDestinationRef = nil
        summaryMessage = nil
        startMessage = nil
        arriveMessages = []
        title = I18NText(text: [:], pron: [:])
    }
    
    init(ref: String, refTitle: String, title: I18NText) {
        self.ref = ref
        self.refTitle = refTitle
        self.matchedDestinationRef = nil
        summaryMessage = nil
        startMessage = nil
        arriveMessages = []
        self.title = title
    }
}

struct DestinationRef: Decodable {
    let floor: Int
    let value: String
    let title: String
    let variation: String?
    let arrivalAngle: Int?
    
    enum CodingKeys: String, CodingKey {
        case floor, value
        case title = "#title"
        case variation = "var"
        case arrivalAngle
    }
}

struct Message: Decodable {
    let type: String
    let parent: String
    var text: I18NText
    
    enum CodingKeys: String, CodingKey {
        case type
        case parent
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        parent = try container.decode(String.self, forKey: .parent)
        let allValues = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var textDict: [String: String] = [:]
        for key in allValues.allKeys {
            if key.stringValue.hasPrefix("text:") {
                let newKey = String(key.stringValue.dropFirst(5))
                if let value = try? allValues.decodeIfPresent(String.self, forKey: key) {
                    textDict[newKey] = value
                }
            }
        }
        self.text = I18NText(text: textDict, pron: [:])
    }
    
    init(type: String, parent: String) {
        self.type = type
        self.parent = parent
        self.text = I18NText(text: [:], pron: [:])
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
class Tour: Decodable, Hashable{
    
    // MARK: - Properties
    let title: I18NText
    let id: String
    var destinations: [DestinationJSON]
    let defaultVar: String?
    let introduction: I18NText
    let error: String?
    
    // MARK: - Coding Keys
    enum CodingKeys: String, CodingKey {
        case id = "tour_id"
        case destinations
        case defaultVar = "default_var"
    }
    
    
    // MARK: - Static Properties
    private static var _allDestinationsRef: [DestinationRef] = []
    private static var _allMessages: [Message] = []
    
    static var allDestinationsRef: [DestinationRef] {
        get { return _allDestinationsRef }
        set { _allDestinationsRef = newValue }
    }
    
    static var allMessages: [Message] {
        get { return _allMessages }
        set { _allMessages = newValue }
    }
    
    struct Root: Decodable {
        let tours: [Tour]
        let destinations: [DestinationRef]
        let messages: [Message]
    }
    
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        destinations = try container.decode([DestinationJSON].self, forKey: .destinations)
        defaultVar = try container.decodeIfPresent(String.self, forKey: .defaultVar)
        
        var titleText: [String: String] = [:]
        let additionalKeysContainer = try decoder.container(keyedBy: DynamicCodingKeys.self)
        let allKeys = additionalKeysContainer.allKeys
        
        for key in allKeys {
            if key.stringValue.hasPrefix("title-") {
                do {
                    if let value = try additionalKeysContainer.decodeIfPresent(String.self, forKey: key) {
                        let languageCode = String(key.stringValue.dropFirst(6))
                        titleText[languageCode] = value
                    }
                } catch {
                    NSLog("Error decoding key \(key.stringValue): \(error)")
                }
            }
        }
        title = I18NText(text: titleText, pron: [:])
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
    
    // MARK: - Private Methods
    private func matchDestinationsRef() {

        var destinationsRefIndex: [String: DestinationRef] = [:]
        for ref in Tour.allDestinationsRef {
            destinationsRefIndex[ref.value] = ref
        }

        for index in 0..<destinations.count {
            let destination = destinations[index]
            let refParts = destination.ref.split(separator: "#")
            
            if refParts.count == 2 {
                let value = String(refParts[0])
                let variation = String(refParts[1])

                if let matched = destinationsRefIndex[value], matched.variation == variation || matched.variation == nil {
                    destinations[index].matchedDestinationRef = matched
                }
            } else {

                if let matched = destinationsRefIndex[destination.ref] {
                    destinations[index].matchedDestinationRef = matched
                }
            }
        }
    }
    
    private func matchMessage() {

        var destinationIndex: [String: Int] = [:]
        for (index, destination) in destinations.enumerated() {
            destinationIndex[destination.ref] = index
        }

        for message in Tour.allMessages {
            guard let index = destinationIndex[message.parent], !message.parent.isEmpty else {
                continue
            }
            
            var destination = destinations[index]

            switch message.type {
            case "startMessage":
                destination.startMessage = message
            case "summary":
                destination.summaryMessage = message
            case "arriveMessage":
                destination.arriveMessages = [message]
            default:
                break
            }
                  

            destinations[index] = destination
        }
    }
    
    // MARK: - Static Methods
    static func load() throws -> [Tour] {
        do {
            let fileURL = getTourDataJSON().appendingPathComponent("app-resource/tourdata.json")
            let data = try Data(contentsOf: fileURL)
            let root = try JSONDecoder().decode(Root.self, from: data)
            allDestinationsRef = root.destinations
            allMessages = root.messages
           
        
            for tour in root.tours {
                tour.matchDestinationsRef()
                tour.matchMessage()
            }
            
            let features = try Feature.loadFeature()
            
            for tourIndex in 0..<root.tours.count {
                let tour = root.tours[tourIndex]
                for destIndex in 0..<tour.destinations.count {
                    var destination = tour.destinations[destIndex]
                    if let matchedD = destination.matchedDestinationRef {
                        if let matchedFeature = features.first(where: { $0.properties.ent1Node == matchedD.value }) {
                            _ = I18NText(
                                text: matchedFeature.properties.names,
                                pron: [:]
                            )
                            destination.title = I18NText(text: matchedFeature.properties.names, pron: [:])
                            root.tours[tourIndex].destinations[destIndex] = destination
                        } else {
                            NSLog("No matching Feature found")
                        }
                    } else {
                        NSLog("No matched DestinationD found")
                        let refParts = destination.ref.split(separator: "#")
                        let refToUse = refParts.count > 1 ? String(refParts[0]) : destination.ref
                        if let matchedFeature = features.first(where: { $0.properties.ent1Node == refToUse })
                        {
                            _ = I18NText(
                                text: matchedFeature.properties.names,
                                pron: [:]
                            )
                            destination.title = I18NText(text: matchedFeature.properties.names, pron: [:])
                            root.tours[tourIndex].destinations[destIndex] = destination
                        }
                    }
                }
            }
            return root.tours
        } catch {
            throw MetadataError.contentLoadError
        }
    }
    private static func getTourDataJSON() -> URL {
        guard let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Could not find the document directory.")
        }
        return path
    }
}

class Feature : Decodable,  Hashable {
    let properties: Properties
    enum CodingKeys: String, CodingKey {
        case properties
    }
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        properties = try container.decode(Properties.self, forKey: .properties)
    }
    
    static func == (lhs: Feature, rhs: Feature) -> Bool {
        return lhs.properties == rhs.properties
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(properties)
    }
    struct Properties: Decodable, Hashable {
        let ent1Node: String?
        var names: [String: String]
        
        enum CodingKeys: String, CodingKey {
            case ent1Node = "ent1_node"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ent1Node = try container.decodeIfPresent(String.self, forKey: .ent1Node)
            names = [:]
            let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKeys.self)
            for key in dynamicContainer.allKeys {
                if key.stringValue.hasPrefix("name_") {
                    let languageCode = String(key.stringValue.dropFirst(5))
                    if let nameValue = try dynamicContainer.decodeIfPresent(String.self, forKey: key) {
                        names[languageCode] = nameValue
                    }
                }
            }
        }

        // MARK: - DynamicCodingKeys
        struct DynamicCodingKeys: CodingKey {
            var stringValue: String
            var intValue: Int?

            init?(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue: Int) {
                self.intValue = intValue
                self.stringValue = "name_"
            }
        }

        // MARK: - Hashable
        static func == (lhs: Properties, rhs: Properties) -> Bool {
            return lhs.ent1Node == rhs.ent1Node
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ent1Node)
        }
    }
    
    // MARK: - ReadJSON
    class func loadFeature() throws -> [Feature] {
        do {
            let featureJsonFileName = "app-resource/features.json"
            let fileURL = getFacilityDataJSON().appendingPathComponent(featureJsonFileName)
            
            let data = try Data(contentsOf: fileURL)
            let features = try JSONDecoder().decode([Feature].self, from: data)
            return features
        } catch {
            throw MetadataError.contentLoadError
        }
    }
    private static func getFacilityDataJSON() -> URL {
        guard let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Could not find the document directory.")
        }
        return path
    }
}

class ResourceManager {
    public static let shared: ResourceManager = ResourceManager(preview: false)

    private var _resources: [Resource] = []
    private var _resourceMap: [String: Resource] = [:]
    var resources: [Resource] {
        get {
            return _resources
        }
    }

    let preview: Bool

    init(preview: Bool) {
        self.preview = preview
        updateResources()
    }

    public func resolveContentURL(url: URL) -> URL? {
        let abs = url.absoluteString
        if abs.starts(with: "content://") == false {
            return nil
        }

        let path = abs[abs.index(abs.startIndex, offsetBy: 10)...]
        return getResourceRoot().appendingPathComponent(String(path))
    }

    public func updateResources() {
        _resources = listAllResources()
        _resourceMap = [:]

        for resource in resources {
            _resourceMap[resource.id] = resource
        }
    }

    public func resource(by identifier: String) -> Resource? {
        NSLog("resource by identifier=\(identifier)")
        for resource in resources {
            NSLog("iterating resource.identifier = \(resource.identifier)")
            if resource.identifier == identifier {
                return resource
            }
        }
        return nil
    }

    func getResourceRoot() -> URL {
        if preview {
            let path = Bundle.main.resourceURL
            return path!.appendingPathComponent("PreviewResource")

        } else {
            guard let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                fatalError("Could not find the document directory.")
            }
            return path
        }
    }

    private func listAllResources() -> [Resource] {
        var list: [Resource] = []

        let resourceRoot = getResourceRoot()

        let fm = FileManager.default
        let enumerator: FileManager.DirectoryEnumerator? = fm.enumerator(at: resourceRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: nil)

        while let dir = enumerator?.nextObject() as? URL {
            if fm.fileExists(atPath: dir.appendingPathComponent(Resource.METADATA_FILE_NAME).path) {
                do {
                    let model = try Resource(at: dir)
                    list.append(model)
                } catch (let error) {
                    NSLog(error.localizedDescription)
                }
            }
        }

        return list.sorted { r1, r2 in
            r1.name < r2.name
        }
    }


}

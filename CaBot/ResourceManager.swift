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
class Destination: Decodable, Hashable {
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
    let title: I18NText
    let value:String?
    let file:Source?
    let summaryMessage: String
    let startMessage:String
    let arriveMessages: [String]?
    let content:Source?
    let waitingDestination:WaitingDestination?
    let subtour:Tour?
    let error:String?
    let warning:String?
    let ref:Reference?
    let refDest:Destination?
    var parent: Tour? = nil
    let debug:Bool

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

    static func load(at src: Source, refCount: Int = 0, reference: Reference? = nil) throws -> [Destination] {
        do {
            guard let url = src.url else { throw MetadataError.contentLoadError }
            let str = try String(contentsOf: url)
            var userInfo:[CodingUserInfoKey : Any] = [:]
            userInfo[.src] = url
            userInfo[.i18n] = src.i18n
            userInfo[.refCount] = refCount
            
            let node = try Yams.load(yaml: str)
            guard let yaml = node as? Array<Any> else { throw MetadataError.contentLoadError }
            let yamlDecoder = YAMLDecoder()
            var temp: [Destination] = []
            for node in yaml {
                guard let dict = node as? Dictionary<String, Any> else { continue }
                let value = dict["value"] as? String
                
                if reference == nil || value == reference?.value {
                    let str = try Yams.dump(object: node)
                    let dest = try yamlDecoder.decode(Destination.self, from: str, userInfo: userInfo)
                    temp.append(dest)
                }
            }
            return temp
        } catch let error as YamlError {
            throw MetadataError.yamlParseError(error: error)
        }
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let src = decoder.userInfo[.src] as! URL
        let base = src.deletingLastPathComponent()
        let i18n = decoder.userInfo[.i18n] as! I18N
        let refCount = decoder.userInfo[.refCount] as! Int
        let error = BufferedInfo()
        let warning = BufferedInfo()
        var refDest: Destination?
        
        self.i18n = i18n

        // if 'ref' is specified, try to find a destination
    outer: if let refstr = try? container.decode(String.self, forKey: .ref) {
            guard refCount < 10 else {
                self.ref = nil
                error.add(info: CustomLocalizedString("Too deep nested reference \(refCount) [ref]=\(refstr)", lang: i18n.langCode))
                break outer
            }
            if let ref = Reference.from(ref: refstr) {
                self.ref = ref
                let refSrc = Source(base: base, type: .local, src: ref.file, i18n: i18n)
                if let tempDest = try? Destination.load(at: refSrc, refCount: refCount+1, reference: ref) {
                    if tempDest.count == 1 {
                        refDest = tempDest[0]
                    } else if tempDest.count > 1 {
                        error.add(info: CustomLocalizedString("Found multiple \(ref.file)/\(ref.value)", lang: i18n.langCode))

                    } else {
                        error.add(info: CustomLocalizedString("Cannot find \(ref.file)/\(ref.value)", lang: i18n.langCode))
                    }
                } else {
                    error.add(info: CustomLocalizedString("Parse Error \(ref.file)/\(ref.value)", lang: i18n.langCode))
                }
            } else {
                self.ref = nil
                error.add(info: CustomLocalizedString("Reference error (syntax='file/value')", lang: i18n.langCode))
            }
        } else {
            self.ref = nil
        }
        
        self.refDest = refDest

        let title = I18NText.decode(decoder: decoder, baseKey: CodingKeys.title.stringValue)
        
        if !title.isEmpty {
            self.title = title
        } else {
            if let title = refDest?.title{
                self.title = title
            } else {
                self.title = title
            }
        }
        
        if let debug = try? container.decode(Bool.self, forKey: .debug) {
            self.debug = debug
        } else {
            self.debug = false
        }

        if let value = try? container.decode(String.self, forKey: .value) {
            self.value = value
        } else {
            self.value = refDest?.value
        }
        
        // ToDo: should not refer that has file prop (need to separate)
        if let file = try? container.decode(String.self, forKey: .file) {
            self.file = Source(base: base, type: .local, src: file, i18n: i18n)
        } else {
            self.file = try? container.decode(Source.self, forKey: .file)
            warning.add(info: CustomLocalizedString("file specified by Source(type, src) is deprecated, use just 'src' string instead", lang: i18n.langCode))
        }
        if let summaryMessage = try? container.decode(Source.self, forKey: .summaryMessage) {
            self.summaryMessage = summaryMessage.content ?? "nil"
        } else {
            self.summaryMessage = refDest?.summaryMessage ?? "nil"
        }
        if let startMessage = try? container.decode(Source.self, forKey: .startMessage) {
            self.startMessage = startMessage.content ?? ""
        } else {
            self.startMessage = refDest?.startMessage ??  ""
        }
        if let arriveMessages = try? container.decode([String].self, forKey: .arriveMessages) {
            self.arriveMessages = arriveMessages
        } else {
            self.arriveMessages = refDest?.arriveMessages
        }
        if let content = try? container.decode(Source.self, forKey: .content) {
            self.content = content
        } else {
            self.content = refDest?.content
        }
        
        var tempSubtour: Tour? = nil
    outer: do {
            let subtour = try container.decode(String.self, forKey: .subtour)
            guard refCount < 5 else {
                error.add(info: CustomLocalizedString("Nested reference [ref]=\(subtour)", lang: i18n.langCode))
                tempSubtour = nil
                break outer
            }
            if let ref = Reference.from(ref: subtour) {
                let src = Source(base: base, type: .local, src: ref.file, i18n: i18n)
                if let tempTour = try? Tour.load(){
                    if tempTour.count == 1 {
                        tempSubtour = tempTour[0]
                        error.add(info: tempTour[0].error)
                    } else if tempTour.count > 1 {
                        tempSubtour = nil
                        error.add(info: CustomLocalizedString("Found multiple \(ref.file)/\(ref.value)", lang: i18n.langCode))
                    } else {
                        tempSubtour = nil
                        error.add(info: CustomLocalizedString("Cannot find \(ref.file)/\(ref.value)", lang: i18n.langCode))
                    }
                } else {
                    tempSubtour = nil
                    error.add(info: CustomLocalizedString("Parse Error \(ref.file)/\(ref.value)", lang: i18n.langCode))
                }
            } else {
                tempSubtour = nil
                error.add(info:CustomLocalizedString("Reference error (syntax='file/value')", lang: i18n.langCode))
            }
        } catch DecodingError.typeMismatch {
            error.add(info: CustomLocalizedString("subtour should be speficied in ref format (file/id)", lang: i18n.langCode))
            tempSubtour = nil
        } catch {
            if tempSubtour == nil, let temp = refDest?.subtour {
                tempSubtour = temp
            }
        }
        self.subtour = tempSubtour
        
        if var waitingDestination = try? container.decode(WaitingDestination.self, forKey: .waitingDestination) {
            waitingDestination.parentTitle = self.title
            self.waitingDestination = waitingDestination
        } else {
            self.waitingDestination = refDest?.waitingDestination
        }
        
        if error.summary() != nil {
            error.add(info: CustomLocalizedString("Error at \(src.lastPathComponent)\(yamlPath(decoder.codingPath))", lang: i18n.langCode))
        }
        
        if error.summary() == nil, let refError = refDest?.error {
            error.add(info: refError)
            error.add(info: CustomLocalizedString("Error at \(src.lastPathComponent)\(yamlPath(decoder.codingPath))", lang: i18n.langCode))
        }
        self.error = error.summary()
        self.warning = warning.summary()
    }
    
    init(title: I18NText,value: String?, pron: String?, file: Source?, summaryMessage: String, startMessage: String,arriveMessages: [String], content: Source?, waitingDestination: WaitingDestination?, subtour: Tour?) {
        self.i18n = I18N.shared
        self.title = title
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
    }
}


protocol TourProtocol {
    var title: I18NText { get }
    var id: String { get }
    var destinations: [Destination] { get }
    var currentDestination: Destination? { get }
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

class Tour: Decodable, Hashable, TourProtocol {
    var currentDestination: Destination?
    
    // MARK: - Properties
    let title: I18NText
    let id: String
    var destinationsJSON: [DestinationJSON]
    let defaultVar: String?
    let introduction: I18NText
    var destinations: [Destination]
    let error: String?
    
    
    // MARK: - Static Properties
    private static var _allDestinationsD: [DestinationD] = []
    private static var _allMessages: [Message] = []
    
    static var allDestinationsD: [DestinationD] {
        get { return _allDestinationsD }
        set { _allDestinationsD = newValue }
    }
    
    static var allMessages: [Message] {
        get { return _allMessages }
        set { _allMessages = newValue }
    }
    
    // MARK: - Nested Types
    struct DestinationJSON: Decodable {
        let ref: String
        let refTitle: String
        var matchedDestinationD: DestinationD?
        var matchedMessages: Message?
        var matchedMessage: Message?
        var title: I18NText
        
        enum CodingKeys: String, CodingKey {
            case ref
            case refTitle = "#ref"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ref = try container.decode(String.self, forKey: .ref)
            refTitle = try container.decode(String.self, forKey: .refTitle)
            matchedDestinationD = nil
            matchedMessage = nil
            title = I18NText(text: [:], pron: [:])
        }
        
        init(ref: String, refTitle: String, title: I18NText) {
            self.ref = ref
            self.refTitle = refTitle
            self.matchedDestinationD = nil
            matchedMessage = nil
            self.title = title
        }
    }
    
    struct DestinationD: Decodable {
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
        var summaryMessage: I18NText?
        var startMessage: I18NText?
        var arriveMessages: [I18NText]?
        
        enum CodingKeys: String, CodingKey {
            case type
            case parent
            case textJa = "text:ja"
            case textEn = "text:en"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            parent = try container.decode(String.self, forKey: .parent)
            
            let textJa = try container.decode(String.self, forKey: .textJa)
            let textEn = try container.decode(String.self, forKey: .textEn)
            
            switch type {
            case "summary":
                summaryMessage = I18NText(text: ["ja": textJa, "en": textEn], pron: [:])
            case "startMessage":
                startMessage = I18NText(text: ["ja": textJa, "en": textEn], pron: [:])
            case "arriveMessage":
                arriveMessages = [I18NText(text: ["ja": textJa, "en": textEn], pron: [:])]
            default:
                summaryMessage = nil
                startMessage = nil
                arriveMessages = nil
            }
        }
    }
    
    // MARK: - Initializers
    init(title: I18NText, id: String, destinationsJSON: [DestinationJSON],defaultVar: String?, introduction: I18NText, destinations: [Destination],error:String?) {
        self.title = title
        self.id = id
        self.destinationsJSON = destinationsJSON
        self.defaultVar = defaultVar
        self.introduction = introduction
        self.destinations = []
        self.error = nil
        self.matchDestinationsD()
        self.matchMessage()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        destinationsJSON = try container.decode([DestinationJSON].self, forKey: .destinations)
        defaultVar = try container.decodeIfPresent(String.self, forKey: .defaultVar)
        destinations = []
        
        let titleJa = try container.decodeIfPresent(String.self, forKey: .titleJa) ?? ""
        let titleEn = try container.decodeIfPresent(String.self, forKey: .titleEn) ?? ""
        title = I18NText(text: ["ja": titleJa, "en": titleEn], pron: [:])
        introduction = I18NText(text: [:], pron: [:])
        error = nil
        matchDestinationsD()
        matchMessage()
    }
    
    // MARK: - Hashable Conformance
    static func == (lhs: Tour, rhs: Tour) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - Private Methods
    private func matchDestinationsD() {
        for index in 0..<destinationsJSON.count {
            let destination = destinationsJSON[index]
            let refParts = destination.ref.split(separator: "#")
            if refParts.count == 2 {
                let value = String(refParts[0])
                let variation = String(refParts[1])
                if let matched = Tour.allDestinationsD.first(where: {
                    $0.value == value && ($0.variation == variation || $0.variation == nil)
                }) {
                    destinationsJSON[index].matchedDestinationD = matched
                }
            } else {
                if let matched = Tour.allDestinationsD.first(where: { $0.value == destination.ref }) {
                    destinationsJSON[index].matchedDestinationD = matched
                }
            }
        }
    }
    
    private func matchMessage() {
        for index in 0..<destinationsJSON.count {
            var destination = destinationsJSON[index]
            let matchedMessages = Tour.allMessages.filter { message in
                !destination.ref.isEmpty && message.parent == destination.ref
            }
            if let startMessage = matchedMessages.first(where: { $0.type == "startMessage" }) {
                destination.matchedMessage = startMessage // matchedMessageを設定
            }
            if let summaryMessage = matchedMessages.first(where: { $0.type == "summary" }) {
                destination.matchedMessage?.summaryMessage = summaryMessage.summaryMessage // summaryMessageを設定
            }
            if let arriveMessage = matchedMessages.first(where: { $0.type == "arriveMessage" }) {
                destination.matchedMessage?.arriveMessages = arriveMessage.arriveMessages // arriveMessagesを設定
            }
                  
            destinationsJSON[index] = destination
        }
    }
    
    // MARK: - Static Methods
    static func load() throws -> [Tour] {
        do {
            let fileURL = getTourDataJSON().appendingPathComponent("app-resource/tourdata.json")
            let data = try Data(contentsOf: fileURL)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            
            guard let jsonDict = jsonObject as? [String: Any],
                  let tourDicts = jsonDict["tours"] as? [[String: Any]],
                  let destinationsDArray = jsonDict["destinations"] as? [[String: Any]],
                  let messagesArray = jsonDict["messages"] as? [[String: Any]] else {
                throw MetadataError.contentLoadError
            }
            
            let tours = try parseTours(from: tourDicts)
            
            _allDestinationsD = try destinationsDArray.map { try JSONDecoder().decode(DestinationD.self, from: JSONSerialization.data(withJSONObject: $0)) }
            _allMessages = try messagesArray.map { try JSONDecoder().decode(Message.self, from: JSONSerialization.data(withJSONObject: $0)) }
            for tour in tours {
                tour.matchDestinationsD()
                tour.matchMessage()
            }
            
            let features = try Feature.loadFeature()
            
            for tourIndex in 0..<tours.count {
                let tour = tours[tourIndex]
                for destIndex in 0..<tour.destinationsJSON.count {
                    var destination = tour.destinationsJSON[destIndex]
                    if let matchedD = destination.matchedDestinationD {
                        if let matchedFeature = features.first(where: { $0.ent1Node == matchedD.value }) {
                            let newTitle = I18NText(
                                text: ["ja": matchedFeature.nameJa, "en": matchedFeature.nameEn],
                                pron: [:]
                            )
                            destination.title = newTitle
                            tours[tourIndex].destinationsJSON[destIndex] = destination
                        } else {
                            NSLog("No matching Feature found")
                        }
                    } else {
                        NSLog("No matched DestinationD found")
                    }
                }
            }
            return tours
        } catch {
            throw MetadataError.contentLoadError
        }
    }
    
    // MARK: - Private Static Methods
    private static func parseTours(from tourDicts: [[String: Any]]) throws -> [Tour] {
        return try tourDicts.compactMap { tourDict in
            guard let id = tourDict["tour_id"] as? String else {
                return Tour(
                    title: I18NText(text: [:], pron: [:]),
                    id: "default_id",
                    destinationsJSON: [],
                    defaultVar: "nil",
                    introduction: I18NText(text: [:], pron: [:]),
                    destinations: [],
                    error: "nil"
                )
            }
            
            let titleJa = tourDict["title-ja"] as? String ?? ""
            let titleEn = tourDict["title-en"] as? String ?? ""
            let title = I18NText(text: ["ja": titleJa, "en": titleEn], pron: [:])
            let destinations = parseDestinationsFromTourDict(tourDict)
            let introduction = I18NText(text: ["en": "Introduction for \(id)", "ja": "紹介文 \(id)"], pron: [:])
            let defaultVar = tourDict["default_var"] as? String
            
            return Tour(
                title: title,
                id: id,
                destinationsJSON: destinations,
                defaultVar: defaultVar,
                introduction: introduction,
                destinations: [],
                error: nil
            )
        }
    }
    
    private static func parseDestinationsFromTourDict(_ tourDict: [String: Any]) -> [DestinationJSON] {
        guard let destinationsArray = tourDict["destinations"] as? [[String: Any]] else {
            return []
        }
        
        return destinationsArray.compactMap { dict -> DestinationJSON? in
            guard let ref = dict["ref"] as? String,
                  let refTitle = dict["#ref"] as? String else {
                return nil
            }
            return DestinationJSON(ref: ref, refTitle: refTitle, title: I18NText(text: [:], pron: [:]))
        }
    }
    
    private static func getTourDataJSON() -> URL {
        guard let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Could not find the document directory.")
        }
        return path
    }
    
    // MARK: - Coding Keys
    enum CodingKeys: String, CodingKey {
        case id = "tour_id"
        case destinations
        case defaultVar = "default_var"
        case titleJa = "title-ja"
        case titleEn = "title-en"
    }
}
class Feature: Decodable, Hashable {
    let ent1Node: String
    let nameJa: String
    let nameEn: String
    
    init(ent1Node: String, nameJa: String, nameEn: String) {
        self.ent1Node = ent1Node
        self.nameJa = nameJa
        self.nameEn = nameEn
    }
    
    static func == (lhs: Feature, rhs: Feature) -> Bool {
        return lhs.ent1Node == rhs.ent1Node
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ent1Node)
    }
    
    class func loadFeature() throws -> [Feature] {
        do {
            let featrueJsonFileName = "app-resource/features.json"
            let fileURL = getFacilityDataJSON().appendingPathComponent(featrueJsonFileName)
            
            let data = try Data(contentsOf: fileURL)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            
            guard let jsonArray = jsonObject as? [[String: Any]] else {
                throw MetadataError.contentLoadError
            }
            return try parseFeatures(from: jsonArray)
        } catch {
            throw MetadataError.contentLoadError
        }
    }
    
    private static func parseFeatures(from jsonArray: [[String: Any]]) throws -> [Feature] {
        var features: [Feature] = []
        
        for jsonDict in jsonArray {
            guard let geometry = jsonDict["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String, type == "Point",
                  let properties = jsonDict["properties"] as? [String: Any],
                  let ent1Node = properties["ent1_node"] as? String,
                  let nameJaEscaped = properties["name_ja"] as? String,
                  let nameEn = properties["name_en"] as? String else {
                continue
            }
            
            let nameJa = nameJaEscaped.removingPercentEncoding ?? nameJaEscaped
            let feature = Feature(ent1Node: ent1Node, nameJa: nameJa, nameEn: nameEn)
            features.append(feature)
        }
        
        return features
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

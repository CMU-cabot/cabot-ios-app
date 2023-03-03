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
    case yamlParseError
    case contentLoadError
}

enum SourceType: String, Decodable {
    case local
    case remote
}

extension CodingUserInfoKey {
    static let base = CodingUserInfoKey(rawValue: "base")!
    static let i18n = CodingUserInfoKey(rawValue: "i18n")!
}

struct Source: Decodable {
    let base: URL?
    let type: SourceType
    let src: String
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
            if let url = url {
                return try? String(contentsOf: url)
            }
            return nil
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
        src = try container.decode(String.self, forKey: .src)
        base = decoder.userInfo[.base] as? URL
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

class I18N {
    var lang: String
    var tableName: String?
    var bundle: Foundation.Bundle?

    var langCode: String {
        get {
            Locale(identifier: self.lang).languageCode ?? "en"
        }
    }

    init() {
        self.lang = Locale.preferredLanguages[0]
    }

    func set(tableName: String?, bundle: Foundation.Bundle?, lang: String?) {
        self.tableName = tableName
        self.bundle = bundle
        if let lang = lang {
            self.lang = lang
        }
    }

    func localizedString(key: String) -> String {
        guard let tableName = self.tableName else { return key }
        guard let bundle = self.bundle else { return key }

        let text = CustomLocalizedString(key, lang: self.langCode, tableName: tableName, bundle: bundle)
        // NSLog("key=\(key), tableName=\(tableName), text=\(text), bundle=\(bundle.bundleURL)")
        return text
    }
}

struct Metadata: Decodable{
    let identifier: String
    let name: String
    let i18n: I18N
    let conversation: Source?
    let destinations: Source?
    let tours: Source?
    let custom_menus: [CustomMenu]?

    static func load(at url: URL) throws -> Metadata {
        do {
            let str = try String(contentsOf: url)
            guard let yaml = try Yams.load(yaml: str) as? [String: Any?] else { throw MetadataError.yamlParseError }
            let json = try JSONSerialization.data(withJSONObject: yaml)
            let decoder = JSONDecoder()
            decoder.userInfo[.base] = url.deletingLastPathComponent()
            decoder.userInfo[.i18n] = I18N()
            return try decoder.decode(Metadata.self, from: json)
        } catch is YamlError {
            throw MetadataError.yamlParseError
        }
    }

    enum CodingKeys: CodingKey {
        case name
        case language
        case i18n
        case conversation
        case destinations
        case tours
        case custom_menus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // needs to have I18N instance
        let i18nTableName = try? container.decodeIfPresent(String.self, forKey: .i18n)
        var bundle: Foundation.Bundle?
        if let url = decoder.userInfo[.base] as? URL {
            bundle = Foundation.Bundle(url: url)
        }
        let i18n = decoder.userInfo[.i18n] as! I18N
        self.i18n = i18n
        let language = try? container.decodeIfPresent(String.self, forKey: .language)
        i18n.set(tableName: i18nTableName, bundle: bundle, lang: language)

        self.identifier = try container.decode(String.self, forKey: .name)
        self.name = i18n.localizedString(key: self.identifier)
        self.conversation = try? container.decodeIfPresent(Source.self, forKey: .conversation)
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
            metadata.name
        }
    }

    var id:String {
        get {
            base.path
        }
    }

    var lang: String {
        get {
            self.langOverride ?? metadata.i18n.lang
        }
        set {
            self.langOverride = newValue
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
            if let directoryContents = try? FileManager.default.contentsOfDirectory(
                at: base,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) {
                for directory in directoryContents {
                    if directory.pathExtension == "lproj" {
                        languages.append(directory.deletingPathExtension().lastPathComponent)
                    }
                }
            }
            if languages.contains(where: {lang in lang == metadata.i18n.lang }) == false {
                languages.append(metadata.i18n.lang)
            }
            return languages
        }
    }
}

struct SimpleDestination: Decodable {
    let title:String
    let value:String?
    let pron:String?
}

struct Destination: Decodable, Hashable {
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

    let title:String
    let value:String?
    let pron:String?
    let file:Source?
    let message:Source?
    let content:Source?
    let waitingDestination:SimpleDestination?

    enum CodingKeys: String, CodingKey {
        case title
        case value
        case pron
        case file
        case message
        case content
        case waitingDestination
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let i18n = decoder.userInfo[.i18n] as! I18N
        let title = try container.decode(String.self, forKey: .title)
        self.title = i18n.localizedString(key: title)
        value = try? container.decode(String.self, forKey: .value)
        if let pron = try? container.decode(String.self, forKey: .pron) {
            self.pron = i18n.localizedString(key: pron)
        } else {
            self.pron = nil
        }
        file = try? container.decode(Source.self, forKey: .file)
        message = try? container.decode(Source.self, forKey: .message)
        content = try? container.decode(Source.self, forKey: .content)
        waitingDestination = try? container.decode(SimpleDestination.self, forKey: .waitingDestination)
    }

    init(title: String, value: String?, pron: String?, file: Source?, message: Source?, content: Source?, waitingDestination: SimpleDestination?) {
        self.title = title
        self.value = value
        self.pron = pron
        self.file = file
        self.message = message
        self.content = content
        self.waitingDestination = waitingDestination
    }
}

class Destinations {
    let list: [Destination]

    init(at src: Source) throws {
        do {
            guard let url = src.url else { throw MetadataError.contentLoadError }
            let str = try String(contentsOf: url)
            guard let yaml = try Yams.load(yaml: str) else { throw MetadataError.yamlParseError }
            let json = try JSONSerialization.data(withJSONObject: yaml)
            let decoder = JSONDecoder()
            decoder.userInfo[.base] = url.deletingLastPathComponent()
            decoder.userInfo[.i18n] = src.i18n
            list = try decoder.decode([Destination].self, from: json)
        } catch is YamlError {
            throw MetadataError.yamlParseError
        }
    }
}

protocol TourProtocol {
    var title: String { get }
    var pron: String? { get }
    var id: String { get }
    var destinations: [Destination] { get }
    var currentDestination: Destination? { get }
}

struct Tour: Decodable, Hashable, TourProtocol {
    static func == (lhs: Tour, rhs: Tour) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let title: String
    let pron: String?
    let id: String
    let destinations: [Destination]
    var currentDestination: Destination? = nil
}

class Tours {
    let list: [Tour]

    init(at src: Source) throws {
        do {
            guard let url = src.url else { throw MetadataError.contentLoadError }
            let str = try String(contentsOf: url)
            guard let yaml = try Yams.load(yaml: str) else { throw MetadataError.yamlParseError }
            let json = try JSONSerialization.data(withJSONObject: yaml)
            let decoder = JSONDecoder()
            decoder.userInfo[.base] = url.deletingLastPathComponent()
            decoder.userInfo[.i18n] = src.i18n
            list = try decoder.decode([Tour].self, from: json)
        } catch is YamlError {
            throw MetadataError.yamlParseError
        }
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
        NSLog("identifier=\(identifier)")
        for resource in resources {
            NSLog("resource.identifier = \(resource.identifier)")
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
            let path = Bundle.main.resourceURL
            return path!.appendingPathComponent("Resource")
        }
    }

    private func listAllResources() -> [Resource] {
        var list: [Resource] = []

        let resourceRoot = getResourceRoot()

        let fm = FileManager.default
        do {
            for dir in try fm.contentsOfDirectory(at: resourceRoot,
                                                  includingPropertiesForKeys: [.isDirectoryKey],
                                                  options: []) {
                if fm.fileExists(atPath: dir.appendingPathComponent(Resource.METADATA_FILE_NAME).path) {
                    do {
                        let model = try Resource(at: dir)
                        list.append(model)
                    } catch (let error) {
                        NSLog(error.localizedDescription)
                    }
                }
            }
        } catch {
            NSLog("Could not get file list at \(resourceRoot)")
        }

        return list.sorted { r1, r2 in
            r1.name < r2.name
        }
    }


}

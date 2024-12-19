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
import SwiftUI
import CoreBluetooth

enum ConnectionType:String, CaseIterable{
    case BLE = "ble"
    case TCP = "tcp"
}

struct SharedInfo: Codable {
    enum InfoType: String, Codable {
        case None
        // Normal -> Advanced / Debug
        case Speak
        case SpeakProgress
        case Tour
        // Advanced / Debug -> Normal
        case OverrideTour
        case OverrideDestination
        case Skip
        case RequestUserInfo
        case ClearDestinations
        case ChangeLanguage
        case ChangeUserVoiceRate
        case ChangeUserVoiceType
        case ChangeHandleSide
        case ChangeTouchMode
    }
    init(type: InfoType, value: String, flag1: Bool = false, flag2: Bool = false, location: Int = 0, length: Int = 0) {
        self.info_id = Int64(Date().timeIntervalSince1970*1000000000.0)
        self.type = type
        self.value = value
        self.flag1 = flag1
        self.flag2 = flag2
        self.location = location
        self.length = length
    }
    let info_id: Int64
    let type: InfoType
    let value: String
    let flag1: Bool
    let flag2: Bool
    let location: Int
    let length: Int
}

protocol CaBotServiceProtocol {
    func activityLog(category: String, text: String, memo: String) -> Bool
    func send(destination: String) -> Bool
    func summon(destination: String) -> Bool
    func manage(command: CaBotManageCommand, param: String?) -> Bool
    func log_request(request: Dictionary<String, String>) -> Bool
    func isConnected() -> Bool
    func share(user_info: SharedInfo) -> Bool
}

protocol CaBotTransportProtocol: CaBotServiceProtocol {
    func connectionType() -> ConnectionType
    func startAdvertising()
    func stopAdvertising()
}

protocol CaBotServiceDelegate {
    func caBot(service:any CaBotTransportProtocol, centralConnected:Bool)
    func caBot(service:any CaBotTransportProtocol, versionMatched:Bool, with:String)
    func cabot(service:any CaBotTransportProtocol, openRequest:URL)
    func cabot(service:any CaBotTransportProtocol, soundRequest:String)
    func cabot(service:any CaBotTransportProtocol, notification:NavigationNotification, param:String?)
    func cabot(service:any CaBotTransportProtocol, deviceStatus:DeviceStatus)
    func cabot(service:any CaBotTransportProtocol, systemStatus:SystemStatus)
    func cabot(service:any CaBotTransportProtocol, batteryStatus:BatteryStatus)
    func cabot(service:any CaBotTransportProtocol, touchStatus:TouchStatus)
    func cabot(service:any CaBotTransportProtocol, logList:[LogEntry], status: CaBotLogStatus)
    func cabot(service:any CaBotTransportProtocol, logDetail:LogEntry)
    func cabot(service:any CaBotTransportProtocol, userInfo:SharedInfo)
    func getModeType() -> ModeType
}

enum NavigationNotification:String {
    case next
    case arrived
    case subtour
    case skip
    case getlanguage
    case gethandleside
    case gettouchmode
}

enum CaBotManageCommand:String {
    case reboot
    case poweroff
    case start
    case stop
    case lang
    case reqfeatures
    case handleside
    case touchmode
    case restart_localization
}

struct DeviceStatus: Decodable {
    init(){
        level = .Unknown
        devices = []
    }
    var level: DeviceStatusLevel
    var devices: [DeviceStatusEntry]
}

struct DeviceStatusEntry: Decodable, Hashable {
    var type: String
    var model: String
    var level: DeviceStatusLevel
    var message: String
    var values: [DiagnosticStatusKeyValue]

    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(model)
        hasher.combine(level)
        hasher.combine(message)
    }
}

enum DeviceStatusLevel:String, Decodable {
    case OK
    case Error
    case Unknown

    var icon: String {
        get {
            switch (self) {
            case .OK:
                return "checkmark.circle"
            case .Error:
                return "xmark.circle"
            case .Unknown:
                return "questionmark.circle"
            }
        }
    }
    var color: Color? {
        switch (self) {
        case .OK:
            return Color.blue
        case .Error:
            return Color.red
        case .Unknown:
            return Color.gray
        }
    }
}

struct SystemStatus: Decodable {
    init(){
        level = .Unknown
        diagnostics = []
    }
    var level: CaBotSystemLevel
    var diagnostics: [DiagnosticStatus]
}

enum CaBotSystemLevel:String, Decodable {
    case Unknown
    case Inactive
    case Active
    case Activating
    case Deactivating
    case Error

    var icon: String {
        switch (self) {
        case .Active:
            return "checkmark.circle"
        case .Inactive:
            return "sleep"
        case .Error:
            return "xmark.circle"
        case .Unknown:
            return "questionmark.circle"
        case .Activating:
            return "hourglass"
        case .Deactivating:
            return "hourglass"
        }
    }

    var color: Color? {
        switch (self) {
        case .Active, .Inactive:
            return Color.blue
        case .Activating, .Deactivating:
            return Color.orange
        case .Error:
            return Color.red
        case .Unknown:
            return Color.gray
        }
    }
}

struct DiagnosticStatusKeyValue: Decodable, Equatable, Hashable {
    var key: String
    var value: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(value)
    }
}

struct DiagnosticStatus: Decodable, Hashable {
    var level: DiagnosticLevel
    var name: String
    var hardware_id: String
    var message: String
    var values: [DiagnosticStatusKeyValue]

    init(name: String) {
        self.level = .Stale
        self.name = name
        self.hardware_id = ""
        self.message = ""
        self.values = []
    }

    var componentName: String {
        get {
            if let last = name.split(separator: "/").last {
                return String(last)
            }
            return name
        }
    }
    var rootName: String? {
        get {
            if let first = name.split(separator: "/").first {
                let root = String(first)
                if root == componentName {
                    return nil
                }
                return root
            }
            return name
        }
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(hardware_id)
    }
}

struct BatteryStatus: Decodable {
    init(){
        level = .Stale
        name = "Battery"
        hardware_id = ""
        message = "Unknown"
        values = []
    }
    var level: DiagnosticLevel
    var name: String
    var hardware_id: String
    var message: String
    var values: [DiagnosticStatusKeyValue]
}

enum DiagnosticLevel: Int, Decodable {
    case OK = 0
    case Warning = 1
    case Error = 2
    case Stale = 3

    var text: String {
        switch (self) {
        case .OK:
            return "OK"
        case .Warning:
            return "Warning"
        case .Error:
            return "Error"
        case .Stale:
            return "Stale"
        }
    }

    var icon: String {
        switch (self) {
        case .OK:
            return "checkmark.circle"
        case .Warning:
            return "exclamationmark.triangle"
        case .Error:
            return "xmark.circle"
        case .Stale:
            return "questionmark.circle"
        }
    }

    var color: Color? {
        switch (self) {
        case .OK:
            return Color.blue
        case .Warning:
            return Color.orange
        case .Error:
            return Color.red
        case .Stale:
            return Color.gray
        }
    }
}

struct SpeakRequest: Decodable {
    var request_id: Int64
    var text: String = ""
    var rate: Int8 = 0
    var pitch: Int8 = 0
    var volume: Int8 = 0
    var lang: String = ""
    var voice: String = ""
    var force: Bool = false
    var priority: Int32 = 0
    var timeout: Float32 = 0
    var channels: Int8 = 0
}

enum NavigationEventType:String, Decodable {
    case next
    case arrived
    case content
    case sound
    case subtour
    case skip
    case getlanguage
    case gethandleside
    case gettouchmode
    case unknown
}

struct NavigationEventRequest: Decodable {
    var request_id: Int64
    var type: NavigationEventType = .unknown
    var param: String = ""
}

struct TouchStatus: Decodable {
    init(){
        level = .Stale
    }
    var level: TouchLevel
}

enum TouchLevel: Int, Decodable {
    case Stale = -1
    case NoTouch = 0
    case Touching = 1
    
    var icon: String {
        switch (self) {
        case .Stale:
            return "xmark.circle"
        case .NoTouch:
            return "hand.raised.slash"
        case .Touching:
            return "hand.raised"
        }
    }

    var color: Color? {
        switch (self) {
        case .Stale:
            return Color.red
        case .NoTouch:
            return Color.gray
        case .Touching:
            return Color.green
        }
    }
}

enum CaBotLogStatus:String, Decodable {
    case OK
    case NG
}

enum CaBotLogRequestType:String, Decodable {
    case list
    case detail
    case report
}

struct LogEntry: Decodable, Hashable {
    var name: String
    var nanoseconds: String?
    var title: String?
    var detail: String?
    var is_report_submitted: Bool? = false
    var is_uploaded_to_box: Bool? = false
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    var canSubmit: Bool {
        get {
            if let title = title,
               let detail = detail {
                return title.count > 0 && detail.count > 0
            }
            return false
        }
    }
    
    func logDate(for language: String) -> String {
        if let str_nanoseconds = nanoseconds {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "'cabot_'yyyy'-'MM'-'dd'-'HH'-'mm'-'ss"
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            dateFormatter.locale = Locale(identifier: language)
            
            let timeFormatter = DateIntervalFormatter()
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .short
            timeFormatter.locale = Locale(identifier: language)
            
            guard let date = inputFormatter.date(from: name) else {
                return CustomLocalizedString("INVALID_DATE_STRING", lang: language)
            }
            
            let formattedDate = dateFormatter.string(from: date)
            
            let formattedTime: String
            if let int_nanoseconds = Int(str_nanoseconds) {
                var seconds = Double(int_nanoseconds) / 1_000_000_000
                seconds = max(seconds, 60)
                let endDate = Date(timeInterval: seconds, since: date)
                formattedTime = timeFormatter.string(from: date, to: endDate)
            } else {
                let endDate = Date() // now
                formattedTime = timeFormatter.string(from: date, to: endDate)
            }
            
            return "\(formattedDate)  \(formattedTime)"
        } else {
            return name
        }
    }
}

struct LogResponse: Decodable {
    var status: CaBotLogStatus?
    var response_id: Int64
    var type: CaBotLogRequestType
    var log_list: [LogEntry]?
    var log: LogEntry?
}

class CaBotServiceActions {
    static let shared = CaBotServiceActions()
    private init() {
    }

    private var lastSpeakRequestID: Int64 = 0
    private var lastNavigationEventRequestID: Int64 = 0
    private var lastLogResponseID: Int64 = 0
    private var lastSharedInfo: SharedInfo = SharedInfo(type: .None, value: "")

    func handle(service: CaBotTransportProtocol, delegate: CaBotServiceDelegate, tts: CaBotTTS, request: SpeakRequest) {
        guard delegate.getModeType() == .Normal else { return } // only for Normal mode
        // noop for same request ID from different transport
        guard lastSpeakRequestID < request.request_id else { return }
        lastSpeakRequestID = request.request_id

        DispatchQueue.main.async {
            let line = request.text
            let force = request.force
            let priority = request.priority
            _ = service.activityLog(category: "ble speech request speaking", text: String(line), memo: "force=\(force)")
            tts.speak(String(line), force: force, priority: .parse(priority:priority)) { code, length in
                if code == .Completed {
                    _ = service.activityLog(category: "ble speech request completed", text: String(line), memo: "force=\(force),return_code=\(code),length=(length)")
                } else if code == .Canceled {
                    _ = service.activityLog(category: "ble speech request canceled", text: String(line), memo: "force=\(force),return_code=\(code),length=(length)")
                }
            }
        }
    }

    func handle(service: CaBotTransportProtocol, delegate: CaBotServiceDelegate, request: NavigationEventRequest) {
        guard delegate.getModeType() == .Normal else { return } // only for Normal mode
        // noop for same request ID from different transport
        guard lastNavigationEventRequestID < request.request_id else { return }
        lastNavigationEventRequestID = request.request_id

        DispatchQueue.main.async {
            switch(request.type) {
            case .next, .arrived, .subtour, .skip, .getlanguage, .gethandleside, .gettouchmode:
                if let note = NavigationNotification(rawValue: request.type.rawValue) {
                    delegate.cabot(service: service, notification: note, param: request.param)
                } else {
                    NSLog("Unknown navigation notification type %@", request.type.rawValue)
                }
            case .content:
                guard let url = URL(string: request.param) else {
                    return
                }
                delegate.cabot(service: service, openRequest: url)
            case .sound:
                delegate.cabot(service: service, soundRequest: request.param)
            case .unknown:
                break
            }
        }
    }
    
    func handle(service: CaBotTransportProtocol, delegate: CaBotServiceDelegate, response: LogResponse) {
        // noop for same request ID from different transport
        guard lastLogResponseID < response.response_id else { return }
        lastLogResponseID = response.response_id

        DispatchQueue.main.async {
            switch(response.type) {
            case .list:
                let log_list = response.log_list ?? []
                let status = response.status ?? .OK
                delegate.cabot(service: service, logList: log_list, status: status)
                break
            case .detail:
                if let log_entry = response.log {
                    delegate.cabot(service: service, logDetail: log_entry)
                }
                break
            case .report:
                // never happen
                break
            }
        }
    }

    private let updateSemaphore = DispatchSemaphore(value: 1)
    func handle(service: CaBotTransportProtocol, delegate: CaBotServiceDelegate, user_info: SharedInfo) {
        updateSemaphore.wait()
        defer {
            updateSemaphore.signal()
        }
        guard lastSharedInfo.type != user_info.type || lastSharedInfo.info_id < user_info.info_id else { return }
        lastSharedInfo = user_info
        DispatchQueue.main.async {
            delegate.cabot(service: service, userInfo: user_info)
        }
    }
}

actor LogPack {
    private let title :String
    private let threshold :TimeInterval
    private let maxPacking : Int
    private let isLogWithText : Bool
    private var last :(at:Date,text:String?)? = nil
    private var packingCount : Int = 0
    
    init( title:String, threshold:TimeInterval, isLogWithText:Bool = true, maxPacking:Int = 10 ) {
        self.title = title
        self.threshold = threshold
        self.isLogWithText = isLogWithText
        self.maxPacking = maxPacking
    }
    
    nonisolated func log( text:String? = nil ) {
        Task {
            await _log( text:text )
        }
    }
    
    private func _log( text:String? = nil ) {
        var now = Date()
        
        if let (lastAt,lastText) = self.last {
            if text != lastText {
                _packlog(lastText)
                _log( now, text )
            }
            else {
                packingCount += 1
                if (now.timeIntervalSince(lastAt) >= threshold) {
                    _packlog(lastText)
                } else if packingCount >= maxPacking {
                    _packlog(lastText)
                } else {
                    now = lastAt
                }
            }
        }
        else {
            _log( now, text )
        }
        self.last = (now, text)
    }
    
    private func _log( _ date:Date, _ text:String? ) {
        var output = self.title
        if let text, isLogWithText {
            output = "\(self.title): \(text)"
        }
        NSLog(output)
    }
    
    private func _packlog( _ text:String? ) {
        guard packingCount > 0
            else { return }
        var output = self.title
        if let text, isLogWithText {
            output = "\(self.title): \(text)"
        }
        NSLog("\(output)  x \(packingCount)")
        packingCount = 0
    }
}


struct HeartbeatViewModifier: ViewModifier {
    let label :String
    let period :UInt64
    @State var isAppeare:Bool = true

    func body(content: Content) -> some View {
        return content
            .task {
                isAppeare = true
                NSLog("<[\(label)] appear>")
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds:period)
                    if isAppeare && (UIApplication.shared.applicationState != .background) {
                        NSLog("<[\(label)] showing>")
                    }
                }
            }
            .onDisappear() {
                isAppeare = false
                NSLog("<[\(label)] disappear>")
            }
    }
}

extension View {
    func heartbeat( _ label:String, period sec:Double = 3.0 ) -> some View {
        modifier(HeartbeatViewModifier(label:label, period:UInt64(sec * 1_000_000_000)))
    }
}

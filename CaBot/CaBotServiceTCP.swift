/*******************************************************************************
 * Copyright (c) 2022  Carnegie Mellon University
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
import SocketIO
import Network


class CaBotServiceTCP: NSObject {
    fileprivate var tts:CaBotTTS
    fileprivate let mode: ModeType
    fileprivate var address: String?
    fileprivate var port: String?
    fileprivate var manager: SocketManager?
    fileprivate var socket: SocketIOClient?
    fileprivate let version:String = CaBotServiceBLE.CABOT_BLE_VERSION

    private let actions = CaBotServiceActions.shared
    private var connected: Bool = true
    private var primaryIP = true
    private var connectTimer: Timer?
    private let cabotVersionLogPack = LogPack(title:"<Socket on: cabot_version>", threshold:3.0, maxPacking:20)
    private let deviceStatusLogPack = LogPack(title:"<Socket on: device_status>", threshold:7.0, maxPacking:4)
    private let systemStatusLogPack = LogPack(title:"<Socket on: system_status>", threshold:7.0, maxPacking:4)
    private let batteryStatusLogPack = LogPack(title:"<Socket on: battery_status>", threshold:7.0, maxPacking:4)
    private let touchLogPack = LogPack(title:"<Socket on: touch>", threshold:3.0, maxPacking:80)

    var delegate:CaBotServiceDelegate?

    static func == (lhs: CaBotServiceTCP, rhs: CaBotServiceTCP) -> Bool {
        return lhs === rhs
    }

    init(with tts:CaBotTTS, mode: ModeType) {
        self.tts = tts
        self.mode = mode
    }

    func emit(_ event: String, _ items: SocketData..., timeout: TimeInterval = 1.0, completion: (() -> ())? = nil)  {
        guard let manager = self.manager else { return }
        guard let socket = self.socket else { return }
        guard socket.status == .connected else { return }

        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { (timer) in
            NSLog("emit data \(Unmanaged.passUnretained(timer).toOpaque()) - timeout")
            NSLog("emit \(event) timeout \(timeout)sec")
            self.stopUnlessSendingChunks()
        }

        manager.handleQueue.async {
            socket.emit(event, items) {
                timeoutTimer.invalidate()
                completion?()
            }
        }
    }
    
    private var last_chunk_send_time: TimeInterval = 0

    func stopUnlessSendingChunks(){
        if Date().timeIntervalSince1970 - last_chunk_send_time > 10.0 {
            self.stop()
        } else {
            NSLog("Do not stop socket while sending chunks")
        }
    }

    func stop(){
        if let address = address { NSLog("stopping TCP \(address)") }
        self.connected = false
        DispatchQueue.main.async {
            self.delegate?.caBot(service: self, centralConnected: self.connected)
        }

        guard let manager = self.manager else { return }
        manager.handleQueue.async {
            if let skt = self.socket{
                skt.removeAllHandlers()
                skt.disconnect()
            }
            if let mgr = self.manager{
                if let skt = self.socket{
                    mgr.disconnectSocket(skt)
                }
                mgr.disconnect()
                self.manager = nil
            }
            self.socket = nil
            self.stopHeartBeat()
        }
    }

    func start(addressCandidate: AddressCandidate, port:String) {
        self.address = addressCandidate.getCurrent()
        self.port = port
        DispatchQueue.global(qos: .utility).async {
            _ = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] (timer) in
                guard let weakself = self else { return }
                if weakself.socket == nil {
                    weakself.address = addressCandidate.getNext()
                    weakself.connectToServer()
                }
            }
            RunLoop.current.run()
        }
    }

    var last_data_received_time: TimeInterval = 0
     
    private func connectToServer() {
        guard let address = address else { return }
        guard !address.isEmpty else { return }
        guard let port = port else { return }
        guard !port.isEmpty else { return }

        let socketURL = "ws://" + address + ":" + port + "/cabot"
        guard let url = URL(string: socketURL) else { return }
        NSLog("connecting to TCP \(url)")

        let manager = SocketManager(socketURL: url, config: [.log(false), .compress, .reconnects(true), .reconnectWait(1), .reconnectAttempts(-1)])
        manager.handleQueue = DispatchQueue.global(qos: .userInitiated)
        self.manager = manager
        let socket = manager.defaultSocket
        self.socket = socket
        socket.on(clientEvent: .connect) {[weak self] data, ack in
            guard let weakself = self else { return }
            guard let socket = weakself.socket else { return }
            guard let delegate = weakself.delegate else { return }
            NSLog("<Socket: connected>: \(data)")
            DispatchQueue.main.async {
                weakself.connected = true
                delegate.caBot(service: weakself, centralConnected: weakself.connected)
                weakself.startHeartBeat()
                socket.emit("req_name", true)
            }
            socket.emit("req_version", true)
        }
        socket.on(clientEvent: .error){[weak self] data, ack in
            guard let weakself = self else { return }
            NSLog("<Socket: error>: \(data)")
            DispatchQueue.main.async {
                weakself.stop()
            }
        }
        socket.on(clientEvent: .disconnect){[weak self] data, ack in
            guard let weakself = self else { return }
            NSLog("<Socket on: disconnect>: \(data)")
            DispatchQueue.main.async {
                weakself.stop()
            }
        }
        socket.on("cabot_version"){[weak self] data, ack in
            guard let text = data[0] as? String else { return }
            guard let weakself = self else { return }
            weakself.cabotVersionLogPack.log(text:text)
            guard let delegate = weakself.delegate else { return }
            DispatchQueue.main.async {
                delegate.caBot(service: weakself, versionMatched: text == weakself.version, with: text)
            }
            weakself.last_data_received_time = Date().timeIntervalSince1970
        }
        socket.on("device_status"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            guard let data = String(text).data(using:.utf8) else { return }
            guard let weakself = self else { return }
            weakself.deviceStatusLogPack.log(text:text)
            guard let delegate = weakself.delegate else { return }
            do {
                var status = try JSONDecoder().decode(DeviceStatus.self, from: data)
                let levelOrder: [DeviceStatusLevel] = [.Error, .Unknown, .OK]
                status.devices.sort {
                    let index0 = levelOrder.firstIndex(of: $0.level) ?? levelOrder.count
                    let index1 = levelOrder.firstIndex(of: $1.level) ?? levelOrder.count
                    return index0 < index1
                }
                DispatchQueue.main.async {
                    delegate.cabot(service: weakself, deviceStatus: status)
                }
            } catch {
                print(text)
                NSLog(error.localizedDescription)
            }
        }
        socket.on("system_status"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            guard let data = String(text).data(using:.utf8) else { return }
            guard let weakself = self else { return }
            weakself.systemStatusLogPack.log(text:text)
            guard let delegate = weakself.delegate else { return }
            do {
                let status = try JSONDecoder().decode(SystemStatus.self, from: data)
                DispatchQueue.main.async {
                    delegate.cabot(service: weakself, systemStatus: status)
                }
            } catch {
                print(text)
                NSLog(error.localizedDescription)
            }
        }
        socket.on("battery_status"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            guard let data = String(text).data(using:.utf8) else { return }
            guard let weakself = self else { return }
            weakself.batteryStatusLogPack.log(text:text)
            guard let delegate = weakself.delegate else { return }
            do {
                let status = try JSONDecoder().decode(BatteryStatus.self, from: data)
                DispatchQueue.main.async {
                    delegate.cabot(service: weakself, batteryStatus: status)
                }
            } catch {
                print(text)
                NSLog(error.localizedDescription)
            }
        }
        socket.on("touch"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            guard let data = String(text).data(using:.utf8) else { return }
            guard let weakself = self else { return }
            weakself.touchLogPack.log(text:text)
            guard let delegate = weakself.delegate else { return }
            do {
                let status = try JSONDecoder().decode(TouchStatus.self, from: data)
                DispatchQueue.main.async {
                    delegate.cabot(service: weakself, touchStatus: status)
                }
            } catch {
                print(text)
                NSLog(error.localizedDescription)
            }
        }
        socket.on("speak"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            guard let data = String(text).data(using:.utf8) else { return }
            guard let weakself = self else { return }
            NSLog("<Socket on: speak>")
            guard let delegate = weakself.delegate else { return }
            do {
                let request = try JSONDecoder().decode(SpeakRequest.self, from: data)
                weakself.actions.handle(service: weakself, delegate: delegate, tts: weakself.tts, request: request)
            } catch {
                print(text)
                NSLog(error.localizedDescription)
            }
        }
        socket.on("navigate"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            guard let data = String(text).data(using:.utf8) else { return }
            guard let weakself = self else { return }
            guard let delegate = weakself.delegate else { return }
            do {
                let request = try JSONDecoder().decode(NavigationEventRequest.self, from: data)
                NSLog("<Socket on: navigate> \(request.type)")
                weakself.actions.handle(service: weakself, delegate: delegate, request: request)
            } catch {
                print(text)
                NSLog("<Socket on: navigate> json parse error")
                NSLog(error.localizedDescription)
            }
        }
        socket.on("log_response"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            guard let data = String(text).data(using:.utf8) else { return }
            guard let weakself = self else { return }
            NSLog("<Socket on: log_response>")
            guard let delegate = weakself.delegate else { return }
            do {
                let response = try JSONDecoder().decode(LogResponse.self, from: data)
                weakself.actions.handle(service: weakself, delegate: delegate, response: response)
            } catch {
                print(text)
                NSLog(error.localizedDescription)
            }
        }
        socket.on("share"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            guard let data = String(text).data(using:.utf8) else { return }
            guard let weakself = self else { return }
            guard let delegate = weakself.delegate else { return }
            do {
                let decodedData = try JSONDecoder().decode(SharedInfo.self, from: data)
                NSLog("<Socket on: share> \(decodedData)")
                weakself.actions.handle(service: weakself, delegate: delegate, user_info: decodedData)
            } catch {
                print(text)
                NSLog("<Socket on: share> json parse error")
                NSLog(error.localizedDescription)
            }
        }
        socket.on("location"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            guard let data = String(text).data(using:.utf8) else { return }
            do {
                ChatData.shared.lastLocation = try JSONDecoder().decode(ChatData.CurrentLocation.self, from: data)
            } catch {
                print(text)
                NSLog(error.localizedDescription)
            }
        }
        socket.on("cabot_name"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            ChatData.shared.suitcase_id = text
        }
        socket.on("camera_image"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            ChatData.shared.lastCameraImage = text
        }
        socket.on("camera_orientation"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            guard let data = String(text).data(using:.utf8) else { return }
            do {
                ChatData.shared.lastCameraOrientation = try JSONDecoder().decode(ChatData.CameraOrientation.self, from: data)
            } catch {
                print(text)
                NSLog(error.localizedDescription)
            }
        }
        socket.connect(timeoutAfter: 2.0) { [weak self] in
            guard let weakself = self else { return }
            weakself.stop()
        }
    }

    var heartBeatTimer:Timer? = nil

    private func startHeartBeat() {
        self.heartBeatTimer?.invalidate()
        DispatchQueue.global(qos: .utility).async {
            self.heartBeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] (timer) in
                guard let weakself = self else { return }
                guard let deviceID = UIDevice.current.identifierForVendor else { return }
                weakself.emit("heartbeat", "\(deviceID)/\(weakself.mode.rawValue)")
                weakself.emit("req_version", true)

                let now = Date().timeIntervalSince1970
                if now - weakself.last_data_received_time > 5.0 {
                    NSLog("No heartbeat response since last_data_received_time: \(weakself.last_data_received_time)")
                    weakself.stopUnlessSendingChunks()
                }
            }
            RunLoop.current.run()
        }
    }

    private func stopHeartBeat() {
        self.heartBeatTimer?.invalidate()
    }
}

// MARK: CaBotTransportProtocol

extension CaBotServiceTCP: CaBotTransportProtocol {
    func connectionType() -> ConnectionType {
        return .TCP
    }

    func startAdvertising() {
        //assuming nothing to do
    }

    func stopAdvertising() {
        //assuming nothing to do
    }
}

// MARK: CaBotServiceProtocol

extension CaBotServiceTCP: CaBotServiceProtocol {
    func activityLog(category: String, text: String, memo: String) -> Bool {
        let json: Dictionary<String, String> = [
            "category": category,
            "text": text,
            "memo": memo
        ]
        do {
            NSLog("activityLog \(category), \(text), \(memo)")
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            let text = String(data:data, encoding: .utf8)
            self.emit("log", text!)
            return true
        } catch {
            NSLog("activityLog \(category), \(text), \(memo)")
        }
        return false
    }

    func send(destination: String) -> Bool {
        NSLog("destination \(destination)")
        self.emit("destination", destination)
        return true
    }

    func summon(destination: String) -> Bool {
        NSLog("summons \(destination)")
        self.emit("summon", destination)
        return true
    }

    func manage(command: CaBotManageCommand, param: String?) -> Bool {
        if let param = param {
            NSLog("manage \(command.rawValue)-\(param)")
            self.emit("manage_cabot", "\(command.rawValue)-\(param)")
            return true
        } else {
            NSLog("manage \(command.rawValue)")
            self.emit("manage_cabot", command.rawValue)
            return true
        }
    }

    func log_request(request: LogRequest) -> Bool {
        NSLog("log_request \(request)")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let jsonData = try? encoder.encode(request) {
            self.emit("log_request", jsonData)
            return true
        }
        return false
    }
    
    func send_log(log_info: LogRequest, app_log: [String], urls: [URL]) -> Bool {
        NSLog("send log_info \(log_info)")
        NSLog("app_log_list \(app_log)")
        self.last_chunk_send_time = Date().timeIntervalSince1970
        let zipped = zip(app_log ,urls)
        for (fileName, url) in zipped {
            let chunkSize = 512 * 1024
            guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
                return false
            }

            var chunkIndex = 0
            while true {
                let data = fileHandle.readData(ofLength: chunkSize)
                if data.count == 0 {
                    break
                }
                
                let base64String = data.base64EncodedString()
                let dict: [String: Any] = [
                    "type": "data-chunk",
                    "chunkIndex": chunkIndex,
                    "data": base64String,
                    "appLogName": fileName,
                    "cabotLogName": log_info.log_name
                ]
                
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])

                    let start = Date()
                    self.emit("log_request_chunk", jsonData, timeout: 10.0) {
                        self.last_chunk_send_time = Date().timeIntervalSince1970
                        NSLog("log_request_chunk \(fileName):\(chunkIndex), \(jsonData.count) bytes, \(-start.timeIntervalSinceNow) sec")
                    }
                } catch {
                    NSLog("log_request_chunk fail to serialize JSON: \(error)")
                }
                chunkIndex += 1
            }

            let dict2: [String: Any] = ["type": log_info.type, "cabotLogName": log_info.log_name, "appLogName": fileName, "totalChunks": chunkIndex]

            do {
                let jsonData2 = try JSONSerialization.data(withJSONObject: dict2, options: [])

                let start = Date()
                self.emit("log_request", jsonData2) {
                    NSLog("log_request \(fileName), \(jsonData2.count) bytes, \(-start.timeIntervalSinceNow) sec")
                }
            } catch {
                NSLog("log_request fail to serialize JSON: \(error)")
            }

            NSLog("chunk end \(fileName)")
        }
        return true
    }

    public func isConnected() -> Bool {
        return self.connected
    }

    public func isSocket() -> Bool {
        self.socket != nil
    }

    func share(user_info: SharedInfo) -> Bool {
        do {
            let jsonData = try JSONEncoder().encode(user_info)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                self.emit("share", jsonString)
                return true
            }
        } catch {
        }
        return false
    }

    func camera_image_request() -> Bool {
        NSLog("camera_image_request")
        self.emit("camera_image_request", true)
        return true
    }
}

class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                NSLog("Network connection is available.")
            } else {
                NSLog("Network connection is unavailable.")
            }

            // Check the type of interface being used
            if path.usesInterfaceType(.wifi) {
                NSLog("Connection type: Wi-Fi")
            } else if path.usesInterfaceType(.cellular) {
                NSLog("Connection type: Cellular")
            } else if path.usesInterfaceType(.wiredEthernet) {
                NSLog("Connection type: Wired Ethernet")
            } else if path.usesInterfaceType(.other) {
                NSLog("Connection type: Other")
            }
        }
    }

    func startMonitoring() {
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }
}

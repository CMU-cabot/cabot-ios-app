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


class CaBotServiceTCP: NSObject {
    fileprivate var tts:CaBotTTS
    fileprivate var address: String?
    fileprivate var port: String?
    fileprivate var manager: SocketManager?
    fileprivate var socket: SocketIOClient?
    fileprivate let version:String = CaBotServiceBLE.CABOT_BLE_VERSION

    private let actions = CaBotServiceActions.shared
    private var connected: Bool = true
    private var primaryIP = true
    private var connectTimer: Timer?

    var delegate:CaBotServiceDelegate?

    static func == (lhs: CaBotServiceTCP, rhs: CaBotServiceTCP) -> Bool {
        return lhs === rhs
    }

    init(with tts:CaBotTTS) {
        self.tts = tts
    }

    func emit(_ event: String, _ items: SocketData..., completion: (() -> ())? = nil)  {
        guard let manager = self.manager else { return }
        guard let socket = self.socket else { return }
        guard socket.status == .connected else { return }

        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { (timer) in
            NSLog("emit data \(Unmanaged.passUnretained(timer).toOpaque()) - timeout")
            self.stop()
        }

        manager.handleQueue.async {
            socket.emit(event, items) {
                timeoutTimer.invalidate()
            }
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
            DispatchQueue.main.async {
                weakself.connected = true
                delegate.caBot(service: weakself, centralConnected: weakself.connected)
                weakself.startHeartBeat()
            }
            socket.emit("req_version", true)
        }
        socket.on(clientEvent: .error){[weak self] data, ack in
            guard let weakself = self else { return }
            DispatchQueue.main.async {
                weakself.stop()
            }
        }
        socket.on(clientEvent: .disconnect){[weak self] data, ack in
            guard let weakself = self else { return }
            DispatchQueue.main.async {
                weakself.stop()
            }
        }
        socket.on("cabot_version"){[weak self] data, ack in
            guard let text = data[0] as? String else { return }
            guard let weakself = self else { return }
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
            guard let delegate = weakself.delegate else { return }
            do {
                let status = try JSONDecoder().decode(DeviceStatus.self, from: data)
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
                weakself.actions.handle(service: weakself, delegate: delegate, request: request)
            } catch {
                print(text)
                NSLog(error.localizedDescription)
            }
        }
        socket.on("log_response"){[weak self] dt, ack in
            guard let text = dt[0] as? String else { return }
            guard let data = String(text).data(using:.utf8) else { return }
            guard let weakself = self else { return }
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
                weakself.actions.handle(service: weakself, delegate: delegate, user_info: decodedData)
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
                weakself.emit("heartbeat", "true")
                weakself.emit("req_version", true)

                let now = Date().timeIntervalSince1970
                if now - weakself.last_data_received_time > 5.0 {
                    weakself.stop()
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

    func log_request(request: Dictionary<String, String>) -> Bool {
        NSLog("log_request \(request)")
        if let jsonString = try? JSONEncoder().encode(request) {
            self.emit("log_request", jsonString)
            return true
        }
        return false
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
}

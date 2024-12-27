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


import Collections
import Foundation
import CoreBluetooth
import HLPDialog
import Gzip
import UIKit
import SwiftUI

protocol CaBotServiceDelegateBLE : CaBotServiceDelegate{
    func cabot(service:any CaBotTransportProtocol, bluetoothStateUpdated: CBManagerState)
}

class CaBotServiceBLE: NSObject {
    static let CABOT_BLE_VERSION = "20230222"
    static let UUID_FORMAT = "35CE%04X-5E89-4C0D-A3F6-8A6A507C1BF1"
    static let CABOT_SPEED_CONFIG = "cabot_speed"
    static let SPEECH_SPEED_CONFIG = "speech_speed"
    static let CONTRIAL_MAX = 5

    func generateUUID(handle:Int) -> CBUUID {
        return CBUUID(string: String(format:CaBotServiceBLE.UUID_FORMAT, handle))
    }

    fileprivate let tts:CaBotTTS
    fileprivate let mode: ModeType
    fileprivate let actions: CaBotServiceActions
    var delegate:CaBotServiceDelegateBLE?

    static func == (lhs: CaBotServiceBLE, rhs: CaBotServiceBLE) -> Bool {
        return lhs === rhs
    }

    init(with tts:CaBotTTS, mode: ModeType) {
        self.tts = tts
        self.mode = mode
        self.actions = CaBotServiceActions.shared
    }

    public var teamID:String? = nil
    public var peripheralManager:CBPeripheralManager?

    private let queue = DispatchQueue.global(qos: .utility)
    private let uuid = CBUUID(string: String(format:UUID_FORMAT, 0x0000))
    private var logChar:CaBotNotifyChar!
    private var summonsChar:CaBotNotifyChar!
    private var destinationChar:CaBotNotifyChar!
    private var naviChar:CaBotNaviChar!
    private var heartbeatChar:CaBotNotifyChar!
    private var speechChar:CaBotSpeechChar!
    private var manageChar:CaBotNotifyChar!
    private var logRequestChar:CaBotNotifyChar!
    private var characteristics:[CBCharacteristic] = []
    private var chars:[CaBotChar] = []
    private let peripheralRestoreKey:String = UUID().uuidString
    private var serviceAdded:Bool = false
    private var contrialCount:Int = CONTRIAL_MAX
    private var connected:Bool = false

    func startIfAuthorized() {
        if (CBCentralManager.authorization == .allowedAlways) {
            self.start();
        }
    }

    func start() {
        if self.peripheralManager != nil {return}
        let peripheralManager = CBPeripheralManager(delegate: self, queue: queue,
                                                     options: [CBPeripheralManagerOptionShowPowerAlertKey: true,
                                                               CBPeripheralManagerOptionRestoreIdentifierKey: peripheralRestoreKey])

        self.chars.append(CaBotVersionChar(service: self, handle: 0x0000, version: CaBotServiceBLE.CABOT_BLE_VERSION))
        self.manageChar = CaBotNotifyChar(service: self, handle: 0x0001)
        self.chars.append(self.manageChar)

        self.chars.append(CaBotDeviceStatusChar(service: self, handle: 0x0002))
        self.chars.append(CaBotSystemStatusChar(service: self, handle: 0x0003))
        self.chars.append(CaBotBatteryStatusChar(service: self, handle: 0x0004))
        self.logChar = CaBotNotifyChar(service: self, handle:0x0005)
        self.chars.append(self.logChar)

        self.summonsChar = CaBotNotifyChar(service: self, handle:0x00010)
        self.chars.append(self.summonsChar)

        self.destinationChar = CaBotNotifyChar(service: self, handle:0x0011)
        self.chars.append(self.destinationChar)

        self.speechChar = CaBotSpeechChar(service: self, handle:0x0030)
        self.chars.append(self.speechChar)

        self.naviChar = CaBotNaviChar(service: self, handle:0x0040)
        self.chars.append(self.naviChar)
        self.chars.append(CaBotTouchChar(service: self, handle:0x0041))
        
        self.logRequestChar = CaBotNotifyChar(service: self, handle:0x0050)
        self.chars.append(self.logRequestChar)
        
        self.chars.append(CaBotLogResponseChar(service: self, handle:0x0051))

        self.heartbeatChar = CaBotNotifyChar(service: self, handle:0x9999)
        self.chars.append(self.heartbeatChar)
        self.peripheralManager = peripheralManager
    }

    var heartBeatTimer:Timer? = nil
    
    internal func startHeartBeat() {
        self.heartBeatTimer?.invalidate()
        DispatchQueue.global(qos: .utility).async {
            self.heartBeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { (timer) in
                guard let deviceID = UIDevice.current.identifierForVendor else { return }
                NSLog("heartbeat")
                if self.checkAdvertisement() == false {
                    NSLog("disconnected from the server")
                    timer.invalidate()
                    self.contrialCount = 0
                }
                if (self.heartbeatChar.notify(value: "\(deviceID)/\(self.mode.rawValue)", retry: 0)) {
                    self.contrialCount = CaBotServiceBLE.CONTRIAL_MAX
                    NSLog("BLE heartBeat success")
                } else {
                    self.contrialCount = self.contrialCount - 1
                    NSLog("BLE heartBeat failure")
                }
                if(self.contrialCount > 0){
                    self.connected = true
                    DispatchQueue.main.async {
                        self.delegate?.caBot(service: self, centralConnected: self.connected)
                    }
                }else{
                    self.connected = false
                    DispatchQueue.main.async {
                        self.delegate?.caBot(service: self, centralConnected: self.connected)
                    }
                }
            }
            RunLoop.current.run()
        }
    }

    // MARK: private functions

    internal func add(characteristic:CBCharacteristic) {
        self.characteristics.append(characteristic)
    }
    private func addService()
    {
        if serviceAdded {
            startAdvertising()
            return
        }
        let service:CBMutableService = CBMutableService(type: self.uuid, primary: true)
        service.characteristics = self.characteristics

        NSLog("adding a service")
        peripheralManager?.add(service)
    }
    private var checkCount:Int = 0
    private func checkAdvertisement() -> Bool
    {
        if (self.heartbeatChar.characteristic_read.subscribedCentrals?.count ?? 0 > 0) {
            self.checkCount = 0
            self.stopAdvertising()
            return true
        } else {
            self.checkCount += 1
            if self.checkCount > 15 {
                self.stopAdvertising()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.startAdvertising()
                }
                self.checkCount = 0
            } else {
                self.startAdvertising()
            }
        }
        return false
    }
}

extension CaBotServiceBLE: CaBotServiceProtocol {
    // MARK: CaBotServiceProtocol

    public func activityLog(category: String = "", text: String = "", memo: String = "") -> Bool{
        let json: Dictionary<String, String> = [
            "category": category,
            "text": text,
            "memo": memo
        ]
        do {
            NSLog("activityLog \(category), \(text), \(memo)")
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            let result = logChar.notify(data: data)
            if result == false {
                NSLog("FAIL activityLog \(category), \(text), \(memo)")
            }
        } catch {
            NSLog("activityLog \(category), \(text), \(memo)")
        }
        return false
    }

    public func send(destination: String) -> Bool {
        NSLog("destination \(destination)")
        return (self.destinationChar.notify(value: destination))
    }

    public func summon(destination: String) -> Bool {
        NSLog("summons \(destination)")
        return (self.summonsChar.notify(value: destination))
    }

    public func manage(command: CaBotManageCommand, param: String?) -> Bool {
        if let param = param {
            NSLog("manage \(command.rawValue)-\(param)")
            return self.manageChar.notify(value: "\(command.rawValue)-\(param)")

        } else {
            NSLog("manage \(command.rawValue)")
            return self.manageChar.notify(value: command.rawValue)
        }
    }
    
    public func log_request(request: LogRequest) -> Bool {
        NSLog("log_request \(request)")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let jsonData = try? encoder.encode(request) {
            return self.logRequestChar.notify(data: jsonData)
        }
        return false
    }

    public func isConnected() -> Bool {
        return self.connected
    }

    func share(user_info: SharedInfo) -> Bool {
        NSLog("BLE share is not implemented")
        return false
    }
}


extension CaBotServiceBLE: CaBotTransportProtocol {

    // MARK: CaBotTransportProtocol
    public func connectionType() -> ConnectionType {
        return .BLE
    }

    public func startAdvertising() {
        guard let peripheralManager = self.peripheralManager else {
            return
        }
        let localName = "CaBot" + (self.teamID != nil ? "-" + self.teamID! : "")
        let advertisementData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: localName,
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: self.uuid.uuidString)]
        ]
        if (!peripheralManager.isAdvertising) {
            peripheralManager.startAdvertising(advertisementData)
            NSLog("Start advertising \(localName)")
        }
    }

    public func stopAdvertising() {
        guard let peripheralManager = self.peripheralManager else {
            return
        }
        if (peripheralManager.isAdvertising) {
            peripheralManager.stopAdvertising();
            NSLog("Stop advertising")
        }
    }

}


// MARK: CBPeripheralManagerDelegate
extension CaBotServiceBLE: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager)
    {
        NSLog("state: \(peripheral.state.rawValue)")

        if peripheral.state == .poweredOn {
            DispatchQueue.main.asyncAfter(deadline: .now()+1) {
                self.addService();
            }
        }

        guard let delegate = self.delegate else { return }
        delegate.cabot(service: self, bluetoothStateUpdated: peripheral.state)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            NSLog("error: \(error)")
            return
        }
        
        NSLog("service added")
        for char in service.characteristics! {
            NSLog("\(char.uuid)")
        }
        self.serviceAdded = true
        self.startAdvertising();
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        
        if let error = error {
            NSLog("Failed… error: \(error)")
            return
        }
        NSLog("Start advertising succeeded!")
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        NSLog("didReceiveRead \(request)")
        for char in self.chars {
            if char.canHandle(readRequest: request) {
                break
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        NSLog("didReceiveWrite \(requests)")
        guard let peripheralManager = self.peripheralManager else {return}
        for request in requests
        {
            for char in self.chars {
                if char.canHandle(writeRequest: request) {
                    break
                }
            }
            peripheralManager.respond(to: request, withResult: .success)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        NSLog("subscribed centrals: \(central)")

        if characteristic.uuid == self.heartbeatChar.characteristic_read.uuid {
            self.startHeartBeat()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        NSLog("peripheral willRestore")
        if let _ = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBCentral] {
            NSLog("restored")
        }
    }
}

class CaBotChar: NSObject {
    let service:CaBotServiceBLE

    init(service: CaBotServiceBLE) {
        self.service = service
    }

    func canHandle(readRequest: CBATTRequest) -> Bool {
        return false
    }

    func canHandle(writeRequest: CBATTRequest) -> Bool {
        return false
    }
}

class CaBotNotifyChar: CaBotChar {
    let characteristic_read: CBMutableCharacteristic
    
    init(service:CaBotServiceBLE, handle:Int) {
        self.characteristic_read = CBMutableCharacteristic(
            type: service.generateUUID(handle: handle),
            properties: [.indicate],
            value: nil,
            permissions: [.readable])
        
        service.add(characteristic: self.characteristic_read)
        
        super.init(service: service)
    }
    
    func notify(data:Data, retry:Int = 10) -> Bool {
        guard let peripheralManager = self.service.peripheralManager else {return false}
        if self.characteristic_read.subscribedCentrals?.count == 0 {
            return false
        }

        NSLog("notify to "+self.characteristic_read.uuid.uuidString)
        if peripheralManager.updateValue(data, for: self.characteristic_read, onSubscribedCentrals: nil) == false {
            if retry == 0 {
                return false
            }
            NSLog("FAIL(\(retry)) notify to \(self.characteristic_read.uuid.uuidString)")
            DispatchQueue.main.asyncAfter(deadline: .now()+0.1) {
                _ = self.notify(data: data, retry: retry-1)
            }
        }
        return true
    }
    
    func notify(value:String, retry:Int = 10) -> Bool {
        let data = Data(value.utf8)
        return self.notify(data: data, retry: retry)
    }
}

class CaBotBufferedWriteChar: CaBotChar {
    let uuid:CBUUID
    let characteristic: CBMutableCharacteristic
    var buffer: Data = Data()
    var dataSize: Int = 0
    var packetOffset: Int = 0
    var dataReceived: Int = 0

    init(service: CaBotServiceBLE, handle: Int) {
        self.uuid = service.generateUUID(handle: handle)
        self.characteristic = CBMutableCharacteristic(
            type: self.uuid,
            properties: [.write],
            value: nil,
            permissions: [.writeable])
        service.add(characteristic: self.characteristic)
        super.init(service: service)
    }

    func handleData(_ data:Data) {
        preconditionFailure("handleRequest needs to be implemented")
    }

    override func canHandle(writeRequest: CBATTRequest) -> Bool {
        if writeRequest.characteristic.uuid.isEqual(self.characteristic.uuid) {
            guard let temp = writeRequest.value else {
                return false
            }
            let data = Data(temp)
            guard data.count > 0 else {
                return false
            }


            NSLog("canHandle uuid=\(self.characteristic.uuid) len=\(data.count) dataSize=\(dataSize) dataReceived=\(self.dataReceived) offset=\(writeRequest.offset)")
            if writeRequest.offset == 0 {
                guard data.count >= 4  else {
                    return false
                }
                self.dataSize = Int(data[0]) * 256 + Int(data[1])
                self.packetOffset = Int(data[2]) * 256 + Int(data[3])
                NSLog("canHandle uuid=\(self.characteristic.uuid) dataSize=\(self.dataSize) packetOffset=\(self.packetOffset)")
                if self.packetOffset == 0 {
                    self.dataReceived = 0
                }
                if self.buffer.count == 0 {
                    self.buffer = Data(repeating: 0, count: self.dataSize)
                }
                for i in 4..<data.count {
                    self.buffer[i + self.packetOffset - 4] = data[i]
                    self.dataReceived += 1
                }
            } else {
                for i in 0..<data.count {
                    self.buffer[i + self.packetOffset - 4 + writeRequest.offset] = data[i]
                    self.dataReceived += 1
                }
            }

            if self.dataReceived == self.dataSize {
                NSLog("canHandle uuid=\(self.characteristic.uuid) dataSize=\(dataSize) bufferSize=\(self.buffer.count)")
                if buffer.isGzipped {
                    do {
                        let decompressedData = try buffer.gunzipped()
                        self.handleData(decompressedData)
                    } catch {
                        NSLog("gunzip error")
                    }
                } else {
                    self.handleData(buffer)
                }
                buffer.removeAll()
            }

            return true
        }
        return false
    }
}

class CaBotTextWriteChar: CaBotBufferedWriteChar {
    override func handleData(_ data:Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }
        self.handleText(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func handleText(_ text:String) {
        preconditionFailure("handleText needs to be implemented")
    }
}

class CaBotJSONChar<T:Decodable>: CaBotBufferedWriteChar {
    override func handleData(_ data: Data) {
        do {
            let json = try JSONDecoder().decode(T.self, from: data)
            self.handle(json: json)
        } catch {
            guard let text = String(data: data, encoding: .utf8) else {
                return
            }
            print(text)
            NSLog(error.localizedDescription)
        }
    }

    func handle(json: T) {
        preconditionFailure("handle \(T.self) needs to be implemented")
    }
}

// MARK: Concrete CaBot Chars

class CaBotVersionChar: CaBotTextWriteChar {
    let version:String
    init(service:CaBotServiceBLE, handle:Int, version:String) {
        self.version = version
        super.init(service: service, handle: handle)
    }
    override func handleText(_ text: String) {
        guard let delegate = self.service.delegate else { return }
        DispatchQueue.main.async {
            delegate.caBot(service:self.service, versionMatched:self.version == text, with: text)
        }
    }
}

class CaBotSpeechChar: CaBotJSONChar<SpeakRequest> {
    override func handle(json: SpeakRequest) {
        guard let delegate = self.service.delegate else { return }
        self.service.actions.handle(service: self.service, delegate: delegate, tts: self.service.tts, request: json)
    }
}

class CaBotNaviChar: CaBotJSONChar<NavigationEventRequest> {
    override func handle(json: NavigationEventRequest) {
        guard let delegate = self.service.delegate else { return }
        self.service.actions.handle(service: self.service, delegate: delegate, request: json)
    }
}

class CaBotTouchChar: CaBotJSONChar<TouchStatus> {
    override func handle(json: TouchStatus) {
        guard let delegate = self.service.delegate else { return }
        DispatchQueue.main.async {
            delegate.cabot(service: self.service, touchStatus: json)
        }
    }
}

class CaBotLogResponseChar: CaBotJSONChar<LogResponse> {
    override func handle(json: LogResponse) {
        guard let delegate = self.service.delegate else { return }
        self.service.actions.handle(service: self.service, delegate: delegate, response: json)
    }
}

class CaBotDeviceStatusChar: CaBotJSONChar<DeviceStatus> {
    override func handle(json: DeviceStatus) {
        guard let delegate = self.service.delegate else { return }
        DispatchQueue.main.async {
            delegate.cabot(service: self.service, deviceStatus: json)
        }
    }
}

class CaBotSystemStatusChar: CaBotJSONChar<SystemStatus> {
    override func handle(json: SystemStatus) {
        guard let delegate = self.service.delegate else { return }
        DispatchQueue.main.async {
            delegate.cabot(service: self.service, systemStatus: json)
        }
    }
}

class CaBotBatteryStatusChar: CaBotJSONChar<BatteryStatus> {
    override func handle(json: BatteryStatus) {
        guard let delegate = self.service.delegate else { return }
        DispatchQueue.main.async {
            delegate.cabot(service: self.service, batteryStatus: json)
        }
    }
}

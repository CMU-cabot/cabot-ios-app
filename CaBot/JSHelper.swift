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
import JavaScriptCore
import Yams
import UIKit

// JavaScript custom global objests for extension
//
// Bundle for yaml resource loading
@objc protocol JSBundleExport: JSExport {
    func loadYaml(_ name: String) -> [[String: String]]
    static func getInstance(root: URL) -> JSBundle
}

class JSBundle: NSObject, JSBundleExport {
    let root: URL
    init(root: URL) {
        self.root = root
    }
    func loadYaml(_ name: String) -> [[String: String]] {
        let path = root.appendingPathComponent(name).appendingPathExtension("yaml")

        do {
            let content = try String(contentsOf: path)
            var result: [[String: String]] = []
            if let temp = try Yams.load(yaml: content) as? [[String: Any?]] {
                for entry in temp {
                    var yaml: [String: String] = [:]
                    for (key, value) in entry {
                        if let str = value as? String {
                            yaml[key] = str
                        }
                    }
                    result.append(yaml)
                }
            }
            return result
        } catch {
        }
        NSLog("Cannot load \(name).yaml")
        return []
    }
    class func getInstance(root: URL) -> JSBundle {
        return JSBundle(root: root)
    }
}

// Console for logging
@objc protocol JSConsoleExport: JSExport {
    func log(_ text: String) -> Void
    static func getInstance() -> JSConsole
}

class JSConsole: NSObject, JSConsoleExport {
    func log(_ text: String) {
        NSLog(text)
    }
    class func getInstance() -> JSConsole {
        return JSConsole()
    }
}

// Bluetooth for beacon scanning
@objc protocol JSBluetoothExport: JSExport {
    func scanBeacons(_ uuid: JSValue, _ callback: JSValue)
    static func getInstance() -> JSBluetooth
}

class JSBluetooth: NSObject, JSBluetoothExport {
    var sampler: BeaconSampler?
    var callback: JSValue?
    var duration: Int = 0

    func scanBeacons(_ param: JSValue, _ callback: JSValue) {
        guard let json = param.toDictionary() as? [String: Any?] else { callback.call(withArguments: []); return }
        guard let uuids = json["uuids"] as? [String] else { callback.call(withArguments: []); return }
        guard let duration = json["duration"] as? Int else { callback.call(withArguments: []); return }

        sampler = BeaconSampler(with: uuids.map{ uuid in UUID(uuidString: uuid)! }) { beacons in
            if self.duration == 0 {
                self.sampler?.stop()
                return
            }
            self.duration -= 1
            var json:[String:Any?] = ["data":[]]
            guard let callback = self.callback else { return }
            guard beacons.count > 0 else {
                self.duration = 0
                self.sampler?.stop()
                callback.call(withArguments: [json])
                return
            }
            var data:[Any?] = []
            for beacon in beacons {
                data.append([
                    "uuid": beacon.uuid.uuidString,
                    "major": beacon.major,
                    "minor": beacon.minor,
                    "rssi": beacon.rssi
                ])
            }
            json["data"] = data
            callback.call(withArguments: [json])
        }
        self.callback = callback
        self.duration = duration
        sampler?.start()
    }

    class func getInstance() -> JSBluetooth {
        return JSBluetooth()
    }
}

// HTTPS for postJSON method
@objc protocol JSHTTPSExport: JSExport {
    func postJSON(_ path:JSValue, _ json: JSValue, _ callback: JSValue)
    static func getInstance() -> JSHTTPS
}

class JSHTTPS: NSObject, JSHTTPSExport {
    func postJSON(_ path:JSValue, _ json: JSValue, _ callback: JSValue) {
        guard let pathStr = path.toString(),
              let url = URL(string: "https://\(pathStr)"),
              let json = json.toDictionary() as? [String: Any?],
              let data = try? JSONSerialization.data(withJSONObject: json)  else {
            callback.call(withArguments: [])
            return
        }

        NSLog("%@\n%@", url.absoluteString, String(data: try! JSONSerialization.data(withJSONObject: json, options: .prettyPrinted), encoding: .utf8)!)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = data

        let session = URLSession.shared
        let task = session.dataTask(with: request) { data, response, error in
            if response != nil && error == nil {
                if let data = data {
                    if let json = try? JSONSerialization.jsonObject(with: data) {
                        callback.call(withArguments: [json])
                        return
                    }
                }
            }
            callback.call(withArguments: [])
        }
        task.resume()
    }
    class func getInstance() -> JSHTTPS {
        return JSHTTPS()
    }
}

@objc protocol JSDeviceExport: JSExport {
    var type:String { get }
    var id:String { get }
    static func getInstance() -> JSDevice
}

// Device for device type and id
class JSDevice: NSObject, JSDeviceExport {
    var type:String {
        get {
            UIDevice.current.modelName
        }
    }
    var id:String {
        get {
            UIDevice.current.identifierForVendor?.uuidString ?? ""
        }
    }
    class func getInstance() -> JSDevice {
        return JSDevice()
    }
}

@objc protocol JSViewExport: JSExport {
    func showModalWaitingWithMessage(_ message: String)
    func hideModalWaiting()
    func alert(_ title: String, _ message: String)
    static func getInstance() -> JSView
}

// View for modal wait message and alert
class JSView: NSObject, JSViewExport {

    func showModalWaitingWithMessage(_ message: String) {
        NavUtil.showModalWaiting(withMessage: message)
    }
    func hideModalWaiting() {
        NavUtil.hideModalWaiting()
    }
    func alert(_ title: String, _ message: String) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            let ok = UIAlertAction(title: NSLocalizedString("Okay",
                                                            comment: "Okay"),
                                   style: .default) { (action:UIAlertAction) in
                alertController.dismiss(animated: true, completion: {
                })
            }
            alertController.addAction(ok)


            if let view = NavUtil.keyWindow()?.rootViewController  {
                view.present(alertController, animated: true, completion: nil)
            }
        }
    }
    class func getInstance() -> JSView {
        return JSView()
    }
}

// main class
class JSHelper {
    let ctx: JSContext
    let script: String

    init(withScript jsFile: URL) {
        self.ctx = JSContext()
        NSLog("loading \(jsFile)")

        do {
            script = try String(contentsOf: jsFile, encoding: .utf8)

            // JavaScript syntax check
            ctx.exceptionHandler = { context, value in
                let lineNumber:Int = Int(value!.objectForKeyedSubscript("line")!.toInt32())
                guard lineNumber > 0 else { return }
                let moreInfo = "\(jsFile.path)#L\(lineNumber)"
                NSLog("JS ERROR: \(value!) \(moreInfo)")
                let start = max(lineNumber-2, 0)
                for i in (start)..<lineNumber {
                    NSLog("L%-4d %s", i+1, String(self.script.split(separator: "\n", omittingEmptySubsequences:false)[i]))
                }
                exit(0)
            }
            let parent = jsFile.deletingLastPathComponent()
            // set custom global objects
            ctx.setObject(JSBundle.getInstance(root: parent), forKeyedSubscript: "Bundle" as (NSCopying & NSObjectProtocol))
            ctx.setObject(JSConsole.getInstance(), forKeyedSubscript: "Console" as (NSCopying & NSObjectProtocol))
            ctx.setObject(JSBluetooth.getInstance(), forKeyedSubscript: "Bluetooth" as (NSCopying & NSObjectProtocol))
            ctx.setObject(JSHTTPS.getInstance(), forKeyedSubscript: "HTTPS" as (NSCopying & NSObjectProtocol))
            ctx.setObject(JSView.getInstance(), forKeyedSubscript: "View" as (NSCopying & NSObjectProtocol))
            ctx.setObject(JSDevice.getInstance(), forKeyedSubscript: "Device" as (NSCopying & NSObjectProtocol))
            // load script
            ctx.evaluateScript(script)
        } catch {
            script = ""
            NSLog("Cannot load the script \(jsFile.path)")
            exit(0)
        }
    }

    func call(_ funcName:String, withArguments args: [Any]) -> JSValue! {
        if let funk = ctx.objectForKeyedSubscript(funcName) {
            guard !funk.isUndefined else { NSLog("\(funcName) is not defined"); return funk }
            guard !funk.isNull else { NSLog("\(funcName) is null"); return funk }
            return funk.call(withArguments: args)
        }
        return nil
    }

}

/*******************************************************************************
 * Copyright (c) 2024  IBM Corporation and Carnegie Mellon University
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
import AVFAudio
import Speech



public enum Permission : CaseIterable {
    case microphone
    case speechRecognizer
}


extension Permission {
    public enum Status {
        case ok
        case deny
        case suspend
        case restricted
    }
    
    private var feature : PermissionFeature.Type {
        switch self {
        case .microphone:
            return MicrophonePermission.self
        case .speechRecognizer:
            return SpeechRecognizerPermission.self
        }
    }
    public var status : Status { self.feature.status }
    public var requestLabel : String { self.feature.requestLabel }
    @discardableResult
    public func requestPermission() async -> Status {
        await self.feature.requestPermission()
    }
    
    static var needRequests : Array<Permission> {
        return Permission.allCases.filter { permission in
            permission.status == .suspend
        }
    }
    static var needPermissions : Array<Permission> {
        return Permission.allCases.filter { permission in
            let status = permission.status
            return status == .suspend || status == .deny
        }
    }
}


protocol PermissionFeature : AnyObject {
    static var status : Permission.Status { get }
    static var requestLabel : String { get }
    static func requestPermission() async -> Permission.Status
}



class MicrophonePermission : PermissionFeature {
    static let requestLabel = "Enable access microphone"
    
    static var status: Permission.Status {
        let state = AVAudioApplication.shared.recordPermission
        switch state {
        case .granted:
            return .ok
        case .denied:
            return .deny
        default: // case .undetermined:
            return .suspend
        }
    }
    
    static func requestPermission() async -> Permission.Status {
        if await AVAudioApplication.requestRecordPermission() {
            return .ok
        }
        else {
            return .deny
        }
    }
}



class SpeechRecognizerPermission : PermissionFeature {
    static let requestLabel = "Enable speech recognizer"
    
    static var status: Permission.Status {
        let state = SFSpeechRecognizer.authorizationStatus()
        switch state {
        case .authorized:
            return .ok
        case .denied:
            return .deny
        case .restricted:
            return .restricted
        default: // case .undetermined:
            return .suspend
        }
    }
    
    static func requestPermission() async -> Permission.Status {
        await withUnsafeContinuation{ continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                switch authStatus {
                case .authorized:
                    continuation.resume(returning:.ok)
                case .denied, .restricted:
                    continuation.resume(returning:.deny)
                default: // .notDetermined
                    continuation.resume(returning:.suspend)
                }
            }
        }
    }
}

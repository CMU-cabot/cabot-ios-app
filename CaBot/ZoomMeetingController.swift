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

import AVFoundation
import Foundation
import UIKit

protocol ZoomMeetingControlling {
    @discardableResult
    func join(inviteLink: String, useMic: Bool, useCamera: Bool) -> Bool

    @discardableResult
    func switchCamera() -> Bool

    @discardableResult
    func leave() -> Bool
}

protocol ZoomCredentialProviding {
    func meetingSDKJWTURL() -> URL?
}

private enum ZoomMeetingStatus: String {
    case idle
    case authenticating
    case joining
    case waiting_for_host
    case reconnecting
    case in_meeting
    case leaving
    case error
}

private enum ZoomSDKMeetingState: Int {
    case idle = 0
    case connecting = 1
    case waitingForHost = 2
    case inMeeting = 3
    case disconnecting = 4
    case reconnecting = 5
    case failed = 6
    case ended = 7
    case locked = 8
    case unlocked = 9
    case inWaitingRoom = 10
    case webinarPromote = 11
    case webinarDePromote = 12
    case joinBO = 13
    case leaveBO = 14
}

private struct PendingJoinRequest {
    let inviteLink: String
    let useMic: Bool
    let useCamera: Bool
}

private struct BundleInfoZoomCredentialProvider: ZoomCredentialProviding {
    func meetingSDKJWTURL() -> URL? {
        guard let rawValue = (Bundle.main.object(forInfoDictionaryKey: "ZoomMeetingSDKJWTURL") as? String)?.trimmedNonEmpty else {
            return nil
        }
        return URL(string: rawValue)
    }
}

final class ZoomMeetingController: NSObject, ZoomMeetingControlling {
    static let shared = ZoomMeetingController()

    var onStatusChanged: ((String) -> Void)?

    private let credentialProvider: ZoomCredentialProviding
    private let urlSession: URLSession
    private var status: ZoomMeetingStatus = .idle
    private var pendingJoinRequest: PendingJoinRequest?
    private var credentialTask: URLSessionDataTask?
    private var meetingStatePollTimer: Timer?
    private var sdkInitialized = false
    private var isAuthorized = false
    private var joinStateGraceDeadline: Date?

    private let meetingStatePollingInterval: TimeInterval = 1.0
    private let videoActivationRetryDelay: TimeInterval = 0.8
    private let videoActivationPollingInterval: TimeInterval = 0.5
    private let videoActivationMaxAttempts = 6

    override convenience init() {
        self.init(credentialProvider: BundleInfoZoomCredentialProvider(), urlSession: .shared)
    }

    init(credentialProvider: ZoomCredentialProviding, urlSession: URLSession = .shared) {
        self.credentialProvider = credentialProvider
        self.urlSession = urlSession
        super.init()
    }

    func prepare() {
        onStatusChanged?(status.rawValue)
        _ = ensureSDKInitialized(reportErrors: false)
    }

    func applicationWillResignActive() {
        invokeRTCVoid(selector: "appWillResignActive")
    }

    func applicationDidBecomeActive() {
        invokeRTCVoid(selector: "appDidBecomeActive")
        syncPresentationContext()
    }

    func applicationDidEnterBackground() {
        invokeRTCVoid(selector: "appDidEnterBackground")
    }

    func applicationWillTerminate() {
        invokeRTCVoid(selector: "appWillTerminate")
    }

    @discardableResult
    func join(inviteLink: String, useMic: Bool, useCamera: Bool) -> Bool {
        guard let trimmedLink = inviteLink.trimmedNonEmpty else {
            fail("Zoom join failed: invite link is empty.")
            return false
        }
        guard let url = URL(string: trimmedLink), isSupportedInviteLink(url) else {
            fail("Zoom join failed: invite link is invalid (\(trimmedLink)).")
            return false
        }
        guard status == .idle || status == .error else {
            fail("Zoom join failed: already busy with status \(status.rawValue).")
            return false
        }
        if useCamera && AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
            fail("Zoom join failed: camera permission is not granted.")
            return false
        }

        pendingJoinRequest = PendingJoinRequest(
            inviteLink: url.absoluteString,
            useMic: useMic,
            useCamera: useCamera
        )
        updateStatus(.authenticating)

        guard ensureSDKInitialized(reportErrors: true) else {
            return false
        }

        if isAuthorized {
            return startPendingJoin()
        }

        guard let tokenURL = credentialProvider.meetingSDKJWTURL() else {
            fail("Zoom join failed: Meeting SDK JWT URL is not configured.")
            return false
        }
        fetchMeetingSDKJWT(from: tokenURL)
        return true
    }

    private func fetchMeetingSDKJWT(from tokenURL: URL) {
        credentialTask?.cancel()

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        credentialTask = urlSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.credentialTask = nil

                guard self.pendingJoinRequest != nil else {
                    return
                }

                if let error {
                    self.fail("Zoom join failed: could not fetch Meeting SDK JWT (\(error.localizedDescription)).")
                    return
                }

                guard
                    let httpResponse = response as? HTTPURLResponse,
                    (200...299).contains(httpResponse.statusCode)
                else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    self.fail("Zoom join failed: Meeting SDK JWT endpoint returned HTTP \(statusCode).")
                    return
                }

                guard
                    let data,
                    let token = Self.parseMeetingSDKJWT(from: data)
                else {
                    self.fail("Zoom join failed: Meeting SDK JWT endpoint response was invalid.")
                    return
                }

                guard let authService = self.authService() else {
                    self.fail("Zoom join failed: auth service is unavailable.")
                    return
                }

                _ = ZoomObjCRuntime.setValue(token as NSString, forKey: "jwtToken", onTarget: authService)
                ZoomObjCRuntime.invokeVoidSelector("sdkAuth", onTarget: authService)
            }
        }
        credentialTask?.resume()
    }

    @discardableResult
    func leave() -> Bool {
        if status == .authenticating {
            credentialTask?.cancel()
            credentialTask = nil
            pendingJoinRequest = nil
            updateStatus(.idle)
            return true
        }
        let hasActiveMeetingSession = self.hasActiveMeetingSession()
        guard status != .idle || hasActiveMeetingSession else {
            NSLog("Zoom leave ignored: current status is %@ and no active meeting session exists", status.rawValue)
            return false
        }
        guard status != .error || hasActiveMeetingSession else {
            NSLog("Zoom leave ignored: current status is %@", status.rawValue)
            return false
        }
        guard let meetingService = meetingService() else {
            fail("Zoom leave failed: meeting service is unavailable.")
            return false
        }

        pendingJoinRequest = nil
        updateStatus(.leaving)
        ZoomObjCRuntime.invokeVoidSelector("leaveMeetingWithCmd:", onTarget: meetingService, integerArg: 0)
        startMeetingStatePolling()
        return true
    }

    @discardableResult
    func switchCamera() -> Bool {
        guard hasActiveMeetingSession() else {
            NSLog("Zoom switch camera ignored: no active meeting session")
            return false
        }
        guard let meetingService = meetingService() else {
            NSLog("Zoom switch camera failed: meeting service is unavailable")
            return false
        }

        let result = ZoomObjCRuntime.invokeIntegerSelector(
            "switchMyCamera",
            onTarget: meetingService,
            objectArg: nil
        )
        if result == NSNotFound {
            NSLog("Zoom switch camera failed: switchMyCamera is unavailable")
            return false
        }
        if result != 0 {
            NSLog("Zoom switch camera failed with code %@", String(result))
            return false
        }
        return true
    }

    @objc func onMobileRTCAuthReturn(_ returnValue: Int) {
        DispatchQueue.main.async {
            if returnValue == 0 {
                self.isAuthorized = true
                NSLog("Zoom auth succeeded")
                if self.pendingJoinRequest != nil {
                    _ = self.startPendingJoin()
                } else {
                    self.updateStatus(.idle)
                }
            } else {
                self.isAuthorized = false
                if self.pendingJoinRequest != nil {
                    self.fail("Zoom auth failed with code \(returnValue).")
                } else {
                    self.updateStatus(.idle)
                }
            }
        }
    }

    @objc func onMobileRTCAuthExpired() {
        DispatchQueue.main.async {
            self.isAuthorized = false
            if self.status != .idle {
                self.fail("Zoom auth expired.")
            }
        }
    }

    @objc func onJoinMeetingConfirmed() {
        handleMeetingReadySignal()
    }

    @objc func onMeetingReady() {
        handleMeetingReadySignal()
    }

    @objc func onJBHWaitingWithCmd(_ cmd: Int) {
        DispatchQueue.main.async {
            switch cmd {
            case 0: // JBHCmd_Show
                self.updateStatus(.waiting_for_host)
            case 1: // JBHCmd_Hide
                if self.status == .waiting_for_host {
                    self.updateStatus(.joining)
                }
            default:
                break
            }
        }
    }

    @objc func onInitMeetingView() {
        handleMeetingReadySignal()
    }

    @objc func onMeetingStateChange(_ state: Int) {
        DispatchQueue.main.async {
            self.handleMeetingStateChange(state)
        }
    }

    @objc func onMeetingError(_ error: Int, message: String?) {
        DispatchQueue.main.async {
            if error == 0 {
                NSLog("Zoom meeting callback reported success.")
                return
            }
            let detail = message?.trimmedNonEmpty ?? "Unknown error"
            self.fail("Zoom meeting error (\(error)): \(detail)")
        }
    }

    @objc func onMeetingEndedReason(_ reason: Int) {
        DispatchQueue.main.async {
            self.finishLeaving()
        }
    }

    @objc func onJoinMeetingNeedUserInfo() {
        DispatchQueue.main.async {
            _ = self.leave()
            self.fail("Zoom join failed: meeting requires additional user info.")
        }
    }

    @objc func onJoinMeetingInfoRequired(_ infoType: Int) {
        DispatchQueue.main.async {
            _ = self.leave()
            self.fail("Zoom join failed: unsupported additional join info type \(infoType).")
        }
    }

    @objc func onCameraNoPrivilege() {
        DispatchQueue.main.async {
            self.fail("Zoom meeting failed: camera permission is missing.")
        }
    }

    @objc func onMicrophoneNoPrivilege() {
        DispatchQueue.main.async {
            self.fail("Zoom meeting failed: microphone permission is missing.")
        }
    }

    private func startPendingJoin() -> Bool {
        guard let request = pendingJoinRequest else {
            fail("Zoom join failed: there is no pending join request.")
            return false
        }
        performJoin(request)
        return true
    }

    private func performJoin(_ request: PendingJoinRequest) {
        guard let meetingService = meetingService() else {
            fail("Zoom join failed: meeting service is unavailable.")
            return
        }
        guard let joinParam = makeJoinParam(
            inviteLink: request.inviteLink,
            useMic: request.useMic,
            useCamera: request.useCamera
        ) else {
            fail("Zoom join failed: invite link could not be parsed for direct join.")
            return
        }

        syncPresentationContext()
        configureMeetingSettings(for: request)
        updateStatus(.joining)

        let joinResult = ZoomObjCRuntime.invokeIntegerSelector(
            "joinMeetingWithJoinParam:",
            onTarget: meetingService,
            objectArg: joinParam
        )
        if joinResult != 0 && joinResult != NSNotFound {
            fail("Zoom join failed immediately with code \(joinResult).")
            return
        }
        joinStateGraceDeadline = Date().addingTimeInterval(3.0)
        startMeetingStatePolling()
    }

    private func markMeetingReady() {
        guard status != .in_meeting else {
            return
        }
        updateStatus(.in_meeting)
        connectAudioIfNeeded()
        applyMediaPreferencesIfNeeded()
    }

    private func handleMeetingReadySignal() {
        DispatchQueue.main.async {
            self.markMeetingReady()
        }
    }

    private func ensureSDKInitialized(reportErrors: Bool) -> Bool {
        if sdkInitialized {
            syncPresentationContext()
            attachDelegates()
            return true
        }
        guard let sharedRTC = sharedRTC() else {
            if reportErrors {
                fail("Zoom Meeting SDK is not available. Run ./setup_zoom_sdk.sh before building CaBot-User.")
            } else {
                NSLog("Zoom Meeting SDK is not available yet.")
            }
            return false
        }

        syncPresentationContext()

        guard let contextClass = NSClassFromString("MobileRTCSDKInitContext") as? NSObject.Type else {
            if reportErrors {
                fail("Zoom Meeting SDK init context is unavailable.")
            } else {
                NSLog("Zoom Meeting SDK init context is unavailable.")
            }
            return false
        }

        let context = contextClass.init()
        let domain = zoomDomain as NSString
        _ = ZoomObjCRuntime.setValue(domain, forKey: "domain", onTarget: context)
        _ = ZoomObjCRuntime.setValue(NSNumber(value: true), forKey: "enableCustomizeMeetingUI", onTarget: context)

        let initialized = ZoomObjCRuntime.invokeBoolSelector("initialize:", onTarget: sharedRTC, objectArg: context)
        if !initialized {
            if reportErrors {
                fail("Zoom Meeting SDK initialization failed.")
            } else {
                NSLog("Zoom Meeting SDK initialization failed.")
            }
            return false
        }

        sdkInitialized = true
        attachDelegates()
        return true
    }

    private func attachDelegates() {
        if let authService = authService() {
            _ = ZoomObjCRuntime.setValue(self, forKey: "delegate", onTarget: authService)
        }
        if let meetingService = meetingService() {
            _ = ZoomObjCRuntime.setValue(self, forKey: "delegate", onTarget: meetingService)
            _ = ZoomObjCRuntime.setValue(self, forKey: "customizedUImeetingDelegate", onTarget: meetingService)
        }
    }

    private func makeJoinParam(inviteLink: String, useMic: Bool, useCamera: Bool) -> NSObject? {
        guard
            let url = URL(string: inviteLink),
            let parsedLink = parseInviteLink(url)
        else {
            return nil
        }
        guard let joinParamClass = NSClassFromString("MobileRTCMeetingJoinParam") as? NSObject.Type else {
            return nil
        }

        let joinParam = joinParamClass.init()
        _ = ZoomObjCRuntime.setValue(parsedLink.meetingNumber as NSString, forKey: "meetingNumber", onTarget: joinParam)
        _ = ZoomObjCRuntime.setValue(zoomDisplayName as NSString, forKey: "userName", onTarget: joinParam)
        _ = ZoomObjCRuntime.setValue(NSNumber(value: false), forKey: "noAudio", onTarget: joinParam)
        _ = ZoomObjCRuntime.setValue(NSNumber(value: !useCamera), forKey: "noVideo", onTarget: joinParam)
        if let password = parsedLink.password {
            _ = ZoomObjCRuntime.setValue(password as NSString, forKey: "password", onTarget: joinParam)
        }
        return joinParam
    }

    private func configureMeetingSettings(for request: PendingJoinRequest) {
        guard let settings = meetingSettings() else { return }
        ZoomObjCRuntime.invokeVoidSelector("disableDriveMode:", onTarget: settings, boolArg: true)
        ZoomObjCRuntime.invokeVoidSelector("disableShowVideoPreviewWhenJoinMeeting:", onTarget: settings, boolArg: true)
        ZoomObjCRuntime.invokeVoidSelector("setAutoConnectInternetAudio:", onTarget: settings, boolArg: true)
        ZoomObjCRuntime.invokeVoidSelector("setMuteAudioWhenJoinMeeting:", onTarget: settings, boolArg: !request.useMic)
        ZoomObjCRuntime.invokeVoidSelector("setMuteVideoWhenJoinMeeting:", onTarget: settings, boolArg: !request.useCamera)
    }

    private func connectAudioIfNeeded() {
        guard let request = pendingJoinRequest, let meetingService = meetingService() else {
            return
        }

        _ = ZoomObjCRuntime.invokeBoolSelector("connectMyAudio:", onTarget: meetingService, boolArg: true)

        let muteAudioResult = ZoomObjCRuntime.invokeIntegerSelector(
            "muteMyAudio:",
            onTarget: meetingService,
            boolArg: !request.useMic
        )
        if muteAudioResult == NSNotFound {
            NSLog("Zoom audio preference could not be applied.")
        }
    }

    private func applyMediaPreferencesIfNeeded() {
        guard let request = pendingJoinRequest, let meetingService = meetingService() else {
            return
        }
        let muteResult = ZoomObjCRuntime.invokeIntegerSelector(
            "muteMyVideo:",
            onTarget: meetingService,
            boolArg: !request.useCamera
        )
        NSLog(
            "Zoom muteMyVideo(%@) returned %@",
            request.useCamera ? "false" : "true",
            muteResult == NSNotFound ? "NSNotFound" : String(muteResult)
        )
        if muteResult == NSNotFound {
            NSLog("Zoom video preference could not be applied.")
        }

        if request.useCamera {
            scheduleVideoActivationCheck(attempt: 1)
        }
    }

    private func scheduleVideoActivationCheck(attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + self.videoActivationPollingInterval) { [weak self] in
            self?.runVideoActivationCheck(attempt: attempt)
        }
    }

    private func runVideoActivationCheck(attempt: Int) {
        guard
            status == .in_meeting,
            let request = pendingJoinRequest,
            request.useCamera,
            let meetingService = meetingService()
        else {
            return
        }

        let isSendingMyVideo = ZoomObjCRuntime.invokeBoolSelector(
            "isSendingMyVideo",
            onTarget: meetingService,
            objectArg: nil
        )
        let canUnmuteMyVideo = ZoomObjCRuntime.invokeBoolSelector(
            "canUnmuteMyVideo",
            onTarget: meetingService,
            objectArg: nil
        )

        NSLog(
            "Zoom video activation check %d/%d: isSendingMyVideo=%@ canUnmuteMyVideo=%@",
            attempt,
            videoActivationMaxAttempts,
            isSendingMyVideo ? "YES" : "NO",
            canUnmuteMyVideo ? "YES" : "NO"
        )

        if isSendingMyVideo {
            return
        }

        if canUnmuteMyVideo {
            let result = ZoomObjCRuntime.invokeIntegerSelector(
                "muteMyVideo:",
                onTarget: meetingService,
                boolArg: false
            )
            NSLog(
                "Zoom muteMyVideo(false) activation check returned %@",
                result == NSNotFound ? "NSNotFound" : String(result)
            )
        }

        guard attempt < videoActivationMaxAttempts else {
            return
        }
        scheduleVideoActivationCheck(attempt: attempt + 1)
    }

    private func startMeetingStatePolling() {
        stopMeetingStatePolling()
        meetingStatePollTimer = Timer.scheduledTimer(withTimeInterval: meetingStatePollingInterval, repeats: true) { [weak self] _ in
            self?.pollMeetingState()
        }
    }

    private func stopMeetingStatePolling() {
        meetingStatePollTimer?.invalidate()
        meetingStatePollTimer = nil
    }

    private func pollMeetingState() {
        guard let state = currentMeetingState() else {
            return
        }
        handleMeetingStateChange(state)
    }

    private func finishLeaving() {
        pendingJoinRequest = nil
        joinStateGraceDeadline = nil
        stopMeetingStatePolling()
        updateStatus(.idle)
    }

    private func finishMeetingSession() {
        pendingJoinRequest = nil
        joinStateGraceDeadline = nil
        stopMeetingStatePolling()
        updateStatus(.idle)
    }

    private func handleMeetingStateChange(_ state: Int) {
        guard let meetingState = ZoomSDKMeetingState(rawValue: state) else {
            NSLog("Zoom meeting state changed to unknown value %@", String(state))
            return
        }

        switch meetingState {
        case .idle:
            if shouldIgnoreTransientIdleState() {
                return
            }
            finishMeetingSession()
        case .ended:
            finishMeetingSession()
        case .connecting:
            updateStatus(.joining)
        case .waitingForHost, .inWaitingRoom:
            joinStateGraceDeadline = nil
            updateStatus(.waiting_for_host)
        case .inMeeting, .joinBO:
            joinStateGraceDeadline = nil
            markMeetingReady()
        case .disconnecting, .leaveBO:
            updateStatus(.leaving)
        case .reconnecting:
            joinStateGraceDeadline = nil
            updateStatus(.reconnecting)
        case .failed:
            pendingJoinRequest = nil
            joinStateGraceDeadline = nil
            stopMeetingStatePolling()
            updateStatus(.error)
        case .locked, .unlocked, .webinarPromote, .webinarDePromote:
            break
        }
    }

    private func shouldIgnoreTransientIdleState() -> Bool {
        guard pendingJoinRequest != nil else {
            return false
        }
        guard status == .authenticating || status == .joining else {
            return false
        }
        guard let joinStateGraceDeadline else {
            return false
        }
        return joinStateGraceDeadline > Date()
    }

    private func syncPresentationContext() {
        guard let sharedRTC = sharedRTC() else { return }
        if let scene = currentWindowScene() {
            ZoomObjCRuntime.invokeVoidSelector("setMobileRTCPresentationScene:", onTarget: sharedRTC, objectArg: scene)
        }
        if let rootViewController = currentRootViewController() {
            ZoomObjCRuntime.invokeVoidSelector("setMobileRTCRootController:", onTarget: sharedRTC, objectArg: rootViewController)
        }
    }

    private func currentWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { !$0.windows.isEmpty })
    }

    private func currentRootViewController() -> UIViewController? {
        let windowScene = currentWindowScene()
        return windowScene?.windows.first(where: \.isKeyWindow)?.rootViewController ?? windowScene?.windows.first?.rootViewController
    }

    private func sharedRTC() -> NSObject? {
        guard let rtcClass = NSClassFromString("MobileRTC") else {
            return nil
        }
        return ZoomObjCRuntime.invokeObjectSelector("sharedRTC", onTarget: rtcClass) as? NSObject
    }

    private func authService() -> NSObject? {
        guard let sharedRTC = sharedRTC() else { return nil }
        return ZoomObjCRuntime.invokeObjectSelector("getAuthService", onTarget: sharedRTC) as? NSObject
    }

    private func meetingService() -> NSObject? {
        guard let sharedRTC = sharedRTC() else { return nil }
        return ZoomObjCRuntime.invokeObjectSelector("getMeetingService", onTarget: sharedRTC) as? NSObject
    }

    private func meetingSettings() -> NSObject? {
        guard let sharedRTC = sharedRTC() else { return nil }
        return ZoomObjCRuntime.invokeObjectSelector("getMeetingSettings", onTarget: sharedRTC) as? NSObject
    }

    private func currentMeetingState() -> Int? {
        guard let meetingService = meetingService() else {
            return nil
        }
        let state = ZoomObjCRuntime.invokeIntegerSelector("getMeetingState", onTarget: meetingService, objectArg: nil)
        return state == NSNotFound ? nil : state
    }

    private func hasActiveMeetingSession() -> Bool {
        guard let state = currentMeetingState() else {
            return false
        }
        return !Self.isMeetingExitState(state)
    }

    private func invokeRTCVoid(selector: String) {
        guard let sharedRTC = sharedRTC() else { return }
        ZoomObjCRuntime.invokeVoidSelector(selector, onTarget: sharedRTC)
    }

    private var zoomDomain: String {
        (Bundle.main.object(forInfoDictionaryKey: "ZoomMeetingSDKDomain") as? String)?.trimmedNonEmpty ?? "zoom.us"
    }

    private var zoomDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "ZoomMeetingDisplayName") as? String)?.trimmedNonEmpty ?? "CaBot User"
    }

    private func isSupportedInviteLink(_ url: URL) -> Bool {
        let lowercased = url.absoluteString.lowercased()
        return lowercased.contains("zoom.us/") || lowercased.contains("zoomgov.com/")
    }

    private func parseInviteLink(_ url: URL) -> ParsedInviteLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let pathComponents = url.pathComponents.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }.filter { !$0.isEmpty }

        let meetingNumber =
            pathComponents.first(where: { $0.isZoomMeetingNumber }) ??
            firstMeetingNumber(in: url.path)

        guard let meetingNumber else {
            return nil
        }

        let password = components.queryItems?
            .first(where: { $0.name == "pwd" || $0.name == "passcode" })?
            .value?
            .trimmedNonEmpty

        return ParsedInviteLink(meetingNumber: meetingNumber, password: password)
    }

    private func firstMeetingNumber(in text: String) -> String? {
        let pattern = #"\b\d{9,13}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), let matchRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[matchRange])
    }

    private func updateStatus(_ next: ZoomMeetingStatus) {
        guard status != next else {
            return
        }
        status = next
        NSLog("Zoom meeting status = %@", next.rawValue)
        onStatusChanged?(next.rawValue)
    }

    private func fail(_ message: String) {
        pendingJoinRequest = nil
        credentialTask?.cancel()
        credentialTask = nil
        stopMeetingStatePolling()
        NSLog("%@", message)
        updateStatus(.error)
    }

    private static func parseMeetingSDKJWT(from data: Data) -> String? {
        if
            let response = try? JSONDecoder().decode(ZoomMeetingSDKJWTEndpointResponse.self, from: data),
            let token = response.tokenValue?.trimmedNonEmpty,
            token.isLikelyJWT
        {
            return token
        }

        guard
            let body = String(data: data, encoding: .utf8)?.trimmedNonEmpty,
            body.isLikelyJWT
        else {
            return nil
        }
        return body
    }

    private static func isMeetingExitState(_ state: Int) -> Bool {
        state == ZoomSDKMeetingState.idle.rawValue || state == ZoomSDKMeetingState.ended.rawValue
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isZoomMeetingNumber: Bool {
        let charset = CharacterSet.decimalDigits.inverted
        return count >= 9 && count <= 13 && rangeOfCharacter(from: charset) == nil
    }

    var isLikelyJWT: Bool {
        split(separator: ".").count == 3 && rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}

private struct ParsedInviteLink {
    let meetingNumber: String
    let password: String?
}

private struct ZoomMeetingSDKJWTEndpointResponse: Decodable {
    let jwt: String?
    let token: String?
    let meetingSDKJWTCamelCase: String?
    let meetingSDKJWT: String?
    let meetingSdkJwt: String?

    enum CodingKeys: String, CodingKey {
        case jwt
        case token
        case meetingSDKJWTCamelCase = "meetingSDKJWT"
        case meetingSDKJWT = "meeting_sdk_jwt"
        case meetingSdkJwt = "meetingSdkJwt"
    }

    var tokenValue: String? {
        jwt ?? token ?? meetingSDKJWTCamelCase ?? meetingSDKJWT ?? meetingSdkJwt
    }
}

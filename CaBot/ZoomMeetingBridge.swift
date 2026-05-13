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

#if USER
import Foundation

extension CaBotAppModel {
    func configureZoomMeetingShareBridge() {
        ZoomMeetingController.shared.onStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                let previousStatus = self?.zoomMeetingStatusText
                let isJoined = ZoomMeetingController.shared.isJoined()
                let statusPayload = "\(status),\(isJoined ? "joined" : "not_joined")"
                self?.zoomMeetingStatusText = status
                self?.share(user_info: SharedInfo(type: .ZoomStatus, value: statusPayload))
                let shouldRestoreFromIdle =
                    status == "idle" &&
                    ["joining", "waiting_for_host", "reconnecting", "in_meeting", "leaving"].contains(previousStatus ?? "")
                if status == "idle" {
                    self?.didSpeakZoomConnectedMessage = false
                }
                if status == "in_meeting" {
                    guard self?.didSpeakZoomConnectedMessage != true else { return }
                    self?.didSpeakZoomConnectedMessage = true
                    self?.speakZoomStatusMessage(connected: true)
                } else if shouldRestoreFromIdle {
                    self?.speakZoomStatusMessage(connected: false)
                }
            }
        }
        ZoomMeetingController.shared.onCameraDirectionChanged = { [weak self] direction in
            DispatchQueue.main.async {
                self?.zoomCameraDirectionText = direction
                self?.share(user_info: SharedInfo(type: .ZoomCameraDirection, value: direction))
            }
        }
        let initialDirection = ZoomMeetingController.shared.currentCameraDirection()
        self.zoomCameraDirectionText = initialDirection
        self.share(user_info: SharedInfo(type: .ZoomCameraDirection, value: initialDirection))
    }

    @discardableResult
    func joinZoomMeeting(inviteLink: String, useMic: Bool, useCamera: Bool) -> Bool {
        ZoomMeetingController.shared.join(inviteLink: inviteLink, useMic: useMic, useCamera: useCamera)
    }

    @discardableResult
    func leaveZoomMeeting() -> Bool {
        ZoomMeetingController.shared.leave()
    }

    @discardableResult
    func switchZoomCamera() -> Bool {
        ZoomMeetingController.shared.switchCamera()
    }

    private func speakZoomStatusMessage(connected: Bool) {
        let zoomAudioRouteLogTag = "[ZOOM_AUDIO_ROUTE]"
        let message = CustomLocalizedString(connected ? "Zoom Connected Message" : "Zoom Disconnected Message", lang: self.resourceLang)
        NSLog("\(zoomAudioRouteLogTag) [ZoomMeetingBridge] speak zoom status message connected=\(connected) text=\(message)")
        self.speak(message, priority: .Chat, timeout: 5) { reason, _ in
            NSLog("\(zoomAudioRouteLogTag) [ZoomMeetingBridge] zoom status message completed connected=\(connected) reason=\(reason)")
            guard reason == .Completed else { return }
            if let stt = ChatData.shared.viewModel?.stt {
                stt.prepareAudioForChat()
            } else {
                AudioSessionRouteHelper.restorePreferredOutputRoute()
            }
        }
    }
}
#endif

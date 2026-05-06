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
                self?.zoomMeetingStatusText = status
                self?.share(user_info: SharedInfo(type: .ZoomStatus, value: status))
                if previousStatus == "leaving", status == "idle" {
                    ChatData.shared.viewModel?.stt?.prepareAudioForChat()
                }
            }
        }
    }

    @discardableResult
    func joinZoomMeeting(inviteLink: String, useVideo: Bool) -> Bool {
        ZoomMeetingController.shared.join(inviteLink: inviteLink, useVideo: useVideo)
    }

    @discardableResult
    func leaveZoomMeeting() -> Bool {
        ZoomMeetingController.shared.leave()
    }
}
#endif

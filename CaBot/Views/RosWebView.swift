/*******************************************************************************
 * Copyright (c) 2023  Carnegie Mellon University and Miraikan
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

import SwiftUI
import WebKit

protocol LocalizationStatusDelegate {
    func updated(status: Int)
    func startIdleTimer()
}

struct RosWebView: View, LocalizationStatusDelegate {
    class LocalizationStatusHandler: NSObject, WKScriptMessageHandlerWithReply {
        var delegate: LocalizationStatusDelegate?
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            if message.name == "LocalizeStatus" {
                if let status = message.body as? Int {
                    NSLog("<RosLib LocalizeStatus topic: \(status)>")
                    delegate?.updated(status: status)
                }
            } else if message.name == "StartIdleTimer" {
                delegate?.startIdleTimer()
            }
        }
    }

    var address: String
    var port: String
    var type: LocalWebView.ViewModeType
    var localization = LocalizationStatusHandler()
    let idleTimeout:TimeInterval = 60
    @State private var localizationStatus = 0
    @State private var shouldRefresh = false
    @State private var isConfirming = false
    @State private var idleTimer: Timer?
    @State private var showingExitAlert = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var modelData: CaBotAppModel

    func updated(status: Int) {
        localizationStatus = status
    }

    var body: some View {
        localization.delegate = self
        return LocalWebView(address: address, port: port, type: type, handler: localization, reload: $shouldRefresh)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button(action: {
                    isConfirming = true
                }, label: {
                    if (localizationStatus == 2) {
                        Image(systemName: "mappin.and.ellipse")
                        Text("Restart Localization")
                    } else if (localizationStatus != 1) {
                        Image(systemName: "mappin.and.ellipse")
                        Text("Localization State Unknown")
                    } else {
                        Image(systemName: "mappin.and.ellipse")
                        Text("Restarting Localization")
                    }
                })
                .disabled(localizationStatus != 2)
                .confirmationDialog(Text("Restart Localization"), isPresented: $isConfirming) {
                    Button {
                        localizationStatus = 0
                        modelData.systemManageCommand(command: .restart_localization)
                    } label: {
                        Text("Restart Localization")
                    }
                    Button {
                        modelData.systemManageCommand(command: .reset_gnss)
                    } label: {
                        Text("Reset GNSS")
                    }
                    Button("Cancel", role: .cancel) {
                    }
                } message: {
                    Text("RESTART_LOCALIZATION_MESSAGE")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                    Text("Reload")
                }
                .accessibilityLabel("Reload")
            }
        }
        .alert("Please close ROS Map", isPresented: $showingExitAlert) {
            Button("Yes") {
                dismiss()
            }
            Button("No") {
                startIdleTimer()
            }
        } message: {
            Text("Leaving ROS Map open increases network load")
        }
    }

    func reload() {
        self.shouldRefresh = true
    }

    func startIdleTimer() {
        if self.type == .rosMap {
            self.idleTimer?.invalidate()
            self.idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) {timer in
                if self.localizationStatus == 2 {
                    self.showingExitAlert = true
                }
            }
        }
    }
}

struct RosWebView_Previews: PreviewProvider {
    static var previews: some View {
        RosWebView(address: "", port: "", type: .rosMap)
    }
}

struct LocalWebView: UIViewRepresentable {
    enum ViewModeType {
        case rosMap
        case directionTest
    }

    var address: String
    var port: String
    var type: ViewModeType
    var handler: WKScriptMessageHandlerWithReply
    @Binding var reload: Bool
    
    fileprivate func loadRequest(in webView: WKWebView) {
        switch type {
        case .rosMap:
            loadRosMap(webView: webView)
            break
        case .directionTest:
            loadDirectionTest(webView: webView)
            break
        }
    }

    fileprivate func loadRosMap(webView: WKWebView) {
        if let htmlPath = Bundle.main.url(forResource: "Resource/localserver/cabot_map", withExtension: "html"),
           let baseUrl = Bundle.main.resourceURL?.appendingPathComponent("Resource/localserver") {
           var components = URLComponents(url: htmlPath, resolvingAgainstBaseURL: false)
            components?.query = "ip=" + address + "&port=" + port + "&map_compression=png-cbor&scan_compression=cbor"
            if let queryURL = components?.url {
                webView.loadFileURL(queryURL, allowingReadAccessTo: baseUrl)
            }
            webView.isOpaque = false
            webView.isHidden = false
        }
    }

    fileprivate func loadDirectionTest(webView: WKWebView) {
        if let htmlPath = Bundle.main.url(forResource: "Resource/localserver/cabot_direction_test", withExtension: "html"),
           let baseUrl = Bundle.main.resourceURL?.appendingPathComponent("Resource/localserver") {
           var components = URLComponents(url: htmlPath, resolvingAgainstBaseURL: false)
            components?.query = "ip=" + address + "&port=" + port
            if let queryURL = components?.url {
                webView.loadFileURL(queryURL, allowingReadAccessTo: baseUrl)
            }
            webView.isOpaque = false
            webView.isHidden = false
        }
    }

    func makeUIView(context: UIViewRepresentableContext<LocalWebView>) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.addScriptMessageHandler(handler, contentWorld: .page, name: "LocalizeStatus")
        userContentController.addScriptMessageHandler(handler, contentWorld: .page, name: "StartIdleTimer")
        configuration.userContentController = userContentController
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 320), configuration: configuration)
//        webView.isInspectable = true
        UIApplication.shared.isIdleTimerDisabled = true
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: "callbackHandler")
        loadRequest(in: webView)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: UIViewRepresentableContext<LocalWebView>) {
        if reload {
            loadRequest(in: uiView)
            DispatchQueue.main.async {
                self.reload = false
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

}

extension LocalWebView {
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: LocalWebView

        init(_ parent: LocalWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "callbackHandler" {
                NSLog("<RosLib on: \(message.body)>")
                if let body = message.body as? String {
                    if body.contains("connection closed") {
                    }
                }
            }
        }
    }
}

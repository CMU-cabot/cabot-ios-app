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

struct RosWebView: View {

    var address: String
    var port: String
    @State private var shouldRefresh = false

    var body: some View {
        VStack {
            LocalWebView(address: address, port: port, reload: $shouldRefresh)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                Text("Reload")
            }
            .accessibilityLabel("Reload")
        }
    }

    func reload() {
        self.shouldRefresh = true
    }
}

struct RosWebView_Previews: PreviewProvider {
    static var previews: some View {
        RosWebView(address: "", port: "")
    }
}

struct LocalWebView: UIViewRepresentable {
    
    var address: String
    var port: String
    @Binding var reload: Bool
    
    fileprivate func loadRequest(in webView: WKWebView) {
        
        if let htmlPath = Bundle.main.url(forResource: "Resource/localserver/cabot_map", withExtension: "html"),
           let baseUrl = Bundle.main.resourceURL?.appendingPathComponent("Resource/localserver") {
            do {
                var components = URLComponents(url: htmlPath, resolvingAgainstBaseURL: false)
                components?.query = "ip=" + address + "&port=" + port
                if let queryURL = components?.url {
                    webView.loadFileURL(queryURL, allowingReadAccessTo: baseUrl)
                }
            } catch {
            }
            webView.isOpaque = false
            webView.isHidden = false
        }
    }
    
    func makeUIView(context: UIViewRepresentableContext<LocalWebView>) -> WKWebView {
        let webView = WKWebView()
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
                NSLog("\(message.body)")
                if let body = message.body as? String {
                    if body.contains("connection closed") {
                    }
                }
            }
        }
    }
}

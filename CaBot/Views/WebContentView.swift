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

import SwiftUI
import WebKit

struct WebContentView: UIViewRepresentable {
    @EnvironmentObject var modelData: CaBotAppModel
    let url: URL
    let handlers: [String: WKScriptMessageHandlerWithReply]
    let uiDelegateHandler = UIDelegateHandler()

    class UIDelegateHandler: NSObject, WKUIDelegate {
        var owner:WebContentView?
        func webViewDidClose(_ webView: WKWebView) {
            owner?.modelData.isContentPresenting = false
        }
    }

    func makeUIView(context: Context) -> WKWebView  {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        for (_, tuple) in handlers.enumerated() {
            userContentController.addScriptMessageHandler(tuple.1, contentWorld: .page, name: tuple.0)
        }
        configuration.userContentController = userContentController
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 320), configuration: configuration)
        uiDelegateHandler.owner = self
        webView.uiDelegate = uiDelegateHandler

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }
}

struct WebView_Previews : PreviewProvider {
    static var previews: some View {
        let modelData = CaBotAppModel()
        
        let contentURL = URL(string: "content://place0/test.html")!  // TODO
        return WebContentView(url: contentURL,
                              handlers: ["Test": TestHandler()])
            .environmentObject(modelData)
    }
}

class TestHandler: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {

        if let body = message.body as? [String: Any?] {
            if let name = body["name"] as? String {

                replyHandler([name:"replied"], nil)
            }
        }
    }
}

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

struct DestinationDetailView: View {
    @EnvironmentObject var modelData: CaBotAppModel
    @State var destination: Destination
    @State private var isConfirming = false
    @State private var targetDestination: Destination?

    var body: some View {
        Form {
            Section(header: Text(destination.title.text)) {
                if destination.startMessage.text != "" {
                    Text(destination.startMessage.text)
                }
                if let arriveMessages = destination.arriveMessages{
                    ForEach(arriveMessages, id: \.text) { arriveMessage in
                        Text(arriveMessage.text)
                    }
                }
                if let url = destination.content?.url {
                    Button("Show more detail") {
                        modelData.contentURL = url
                        modelData.isContentPresenting = true
                    }
                }
                Button(action: {
                    targetDestination = destination
                    isConfirming = true
                }){
                    Text("SEND_DESTINATION")
                }
                .confirmationDialog(Text("SEND_DESTINATION"), isPresented: $isConfirming, presenting: targetDestination) {
                detail in
                    Button {
                        if let destination = targetDestination {
                            modelData.share(destination: destination)
                            NavigationUtil.popToRootView()
                            targetDestination = nil
                        }
                    } label: {
                        Text("CLEAR_AND_ADD_DESTINATION")
                    }
                    Button {
                        if let destination = targetDestination {
                            modelData.share(destination: destination, clear: false)
                            NavigationUtil.popToRootView()
                            targetDestination = nil
                        }
                    } label: {
                        Text("ADD_DESTINATION")
                    }
                    Button("Cancel", role: .cancel) {
                        targetDestination = nil
                    }
                } message: { detail in
                    let message = LocalizedStringKey("SEND_DESTINATION_MESSAGE \(detail.title.text)")
                    Text(message)
                }
            }
        }
    }
}

struct DestinationDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let modelData = CaBotAppModel()
        var floorDestinationsForPreviews: [Directory.FloorDestination] = []
        do {
            floorDestinationsForPreviews = try Directory.downloadDirectoryJsonForPreview(modeType: .Advanced)
        } catch {
            NSLog("Failed to download directory JSON")
        }


        return DestinationDetailView(destination: floorDestinationsForPreviews[0].destinations[0])
            .environmentObject(modelData)
    }
}

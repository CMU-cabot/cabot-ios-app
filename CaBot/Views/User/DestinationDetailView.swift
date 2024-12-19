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
    @State var destination: any Destination
    @State private var isConfirming = false
    @State private var targetDestination: (any Destination)?

    var body: some View {
        let tourManager = modelData.tourManager
        Form {
            Section(header: Text(destination.title.text)) {
                if let startMessage = destination.startMessage {
                    Text(startMessage.text)
                }
                if let arriveMessages = destination.arriveMessages {
                    ForEach(arriveMessages, id: \.text) { arriveMessage in
                        Text(arriveMessage.text)
                    }
                }
                if let url = destination.content {
                    Button("Show more detail") {
                        modelData.contentURL = url
                        modelData.isContentPresenting = true
                    }
                }
                Button("Add to destinations") {
                    if modelData.tourManager.hasDestination {
                        targetDestination = destination
                        isConfirming = true
                    } else {
                        // if there is no destination, start immediately
                        tourManager.addToLast(destination: destination)
                        modelData.needToStartAnnounce(wait: true)
                        NavigationUtil.popToRootView()
                    }
                }
                .confirmationDialog(Text("ADD_A_DESTINATION"), isPresented: $isConfirming, presenting: targetDestination) {
                    detail in
                    Button {
                        if let dest = targetDestination {
                            modelData.clearAll()
                            tourManager.addToLast(destination: dest)
                            targetDestination = nil
                            NavigationUtil.popToRootView()
                        }
                    } label: {
                        Text("CLEAR_ALL_THEN_ADD")
                    }
                    Button {
                        if let dest = targetDestination {
                            tourManager.stopCurrent()
                            tourManager.addToFirst(destination: dest)
                            targetDestination = nil
                            NavigationUtil.popToRootView()
                        }
                    } label: {
                        Text("ADD_TO_FIRST")
                    }
                    Button {
                        if let dest = targetDestination {
                            tourManager.addToLast(destination: dest)
                            targetDestination = nil
                            NavigationUtil.popToRootView()
                        }
                    } label: {
                        Text("ADD_TO_LAST")
                    }
                    Button("Cancel", role: .cancel) {
                        targetDestination = nil
                    }
                } message: { detail in
                    let message = LocalizedStringKey("ADD_A_DESTINATION_MESSAGE \(modelData.tourManager.destinationCount, specifier: "%d")")
                    Text(message)
                }
            }
        }
    }
}

struct DestinationDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let modelData = CaBotAppModel()
        modelData.modeType = .Normal

        var floorDestinationsForPreviews: Directory.Sections
        do {
            floorDestinationsForPreviews = try Directory.loadForPreview()
            return AnyView(DestinationDetailView(destination: floorDestinationsForPreviews.sections[0].items[0])
                .environmentObject(modelData))
        } catch {
            NSLog("Failed to download directory JSON")
        }
        return AnyView(EmptyView())
    }
}

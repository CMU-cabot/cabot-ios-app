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

struct DestinationsView: View {
    @EnvironmentObject var modelData: CaBotAppModel
    @State private var isConfirming = false
    @State private var targetDestination: Destination?

    var src: Source
    var destination: Destination?

    var body: some View {
        let destinations = try! Destination.load(at: src)
        var header: Text?
        if let title = destination?.title {
            header = Text(title.text)
        } else {
            header = Text("SELECT_DESTINATION")
        }

        let filteredDestinations = destinations.filter{
            destination in (modelData.modeType == .Debug || !destination.debug)}

        return Form {
            Section(
                header: header) {
                ForEach(filteredDestinations, id: \.self) { destination in
                    if let error = destination.error {
                        HStack{
                            Text(destination.title.text)
                            Text(error).font(.system(size: 11))
                        }.foregroundColor(Color.red)
                    } else if let src = destination.file {
                        NavigationLink(
                            destination: DestinationsView(src: src, destination: destination)
                                .environmentObject(modelData),
                            label: {
                                Text(destination.title.text)
                                    .accessibilityLabel(destination.title.pron)
                            })
                    } else {
                        HStack {
                            Button(action: {
                                targetDestination = destination
                                isConfirming = true
                            }){
                                VStack(alignment: .leading) {
                                    Text(destination.title.text)
                                        .font(.body)
                                        .accessibilityLabel(destination.title.pron)
                                        .multilineTextAlignment(.leading)
                                        .accessibilityHint(Text("DOUBLETAP_TO_ADD_A_DESTINATION"))
                                    if let summaryMessage = destination.summaryMessage?.content{
                                        Text(summaryMessage)
                                            .font(.caption)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }
                            .buttonStyle(.borderless)
                            .confirmationDialog(Text("ADD_A_DESTINATION"), isPresented: $isConfirming, presenting: targetDestination) {
                            detail in
                                Button {
                                    if let destination = targetDestination {
                                        modelData.share(destination: destination, clear: false)
                                        NavigationUtil.popToRootView()
                                        targetDestination = nil
                                    }
                                } label: {
                                    Text("ADD_DESTINATION")
                                }
                                Button {
                                    if let destination = targetDestination {
                                        modelData.share(destination: destination)
                                        NavigationUtil.popToRootView()
                                        targetDestination = nil
                                    }
                                } label: {
                                    Text("CLEAR_AND_ADD_DESTINATION")
                                }
                                Button("Cancel", role: .cancel) {
                                    targetDestination = nil
                                }
                            } message: { detail in
                                let message = LocalizedStringKey("SEND_DESTINATION_MESSAGE \(detail.title.text)")
                                Text(message)
                            }
                            Spacer()
                            if let _ = destination.startMessage {
                                ZStack{
                                    Image(systemName: "info.circle")
                                        .accessibilityLabel(Text("Details"))
                                        .accessibilityRemoveTraits(.isImage)
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityHint(Text("DOUBLETAP_TO_VIEW_DETAILS"))
                                        .foregroundColor(.blue)
                                    NavigationLink(
                                        destination: DestinationDetailView(destination: destination).environmentObject(modelData)
                                    ){EmptyView()}
                                    .frame(width: 0, height: 0)
                                    .opacity(0)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
    }
}

struct DestinationsView_Previews: PreviewProvider {
    static var previews: some View {
        preview2
        preview1
    }

    static var preview1: some View {
        let modelData = CaBotAppModel()

        let resource = modelData.resourceManager.resource(by: "Test data")!

        return DestinationsView(src: resource.destinationsSource!)
            .environmentObject(modelData)
    }

    static var preview2: some View {
        let modelData = CaBotAppModel()

        let resource = modelData.resourceManager.resource(by: "Test data")!

        let destinations = try! Destination.load(at: resource.destinationsSource!)

        return DestinationsView(src: destinations[0].file!)
            .environmentObject(modelData)
    }
}

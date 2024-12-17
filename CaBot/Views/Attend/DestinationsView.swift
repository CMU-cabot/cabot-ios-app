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
    @State private var targetDestination: (any Destination)?

    var destination: (any Destination)?
    var destinations: [any Destination] = []

    var body: some View {
        var header: Text?
        // TODO
        // header = Text(destinations.first?.floorTitle.text ?? "SELECT_DESTINATION")
        return Form {
            Section(
                header: header) {
                ForEach(destinations, id: \.value) { destination in
                        HStack {
                            Button(action: {
                                if (modelData.userInfo.destinations.count > 0) {
                                    targetDestination = destination
                                    isConfirming = true
                                } else {
                                    // if there is no destination, start immediately
                                    modelData.share(destination: destination, clear: false)
                                    modelData.needToStartAnnounce(wait: true)
                                    NavigationUtil.popToRootView()
                                }
                            }){
                                VStack(alignment: .leading) {
                                    Text(destination.title.text)
                                        .font(.body)
                                        .accessibilityLabel(destination.title.pron)
                                        .multilineTextAlignment(.leading)
                                        .accessibilityHint(Text("DOUBLETAP_TO_ADD_A_DESTINATION"))
                                    if destination.summaryMessage.text != ""{
                                        Text(destination.summaryMessage.text)
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
                                        modelData.share(destination: destination)
                                        NavigationUtil.popToRootView()
                                        targetDestination = nil
                                    }
                                } label: {
                                    Text("CLEAR_ALL_THEN_ADD")
                                }
                                Button {
                                    if let destination = targetDestination {
                                        modelData.share(destination: destination, clear: false, addFirst: true)
                                        NavigationUtil.popToRootView()
                                        targetDestination = nil
                                    }
                                } label: {
                                    Text("ADD_TO_FIRST")
                                }
                                Button {
                                    if let destination = targetDestination {
                                        modelData.share(destination: destination, clear: false)
                                        NavigationUtil.popToRootView()
                                        targetDestination = nil
                                    }
                                } label: {
                                    Text("ADD_TO_LAST")
                                }
                                Button("Cancel", role: .cancel) {
                                    targetDestination = nil
                                }
                            } message: { detail in
                                let message = LocalizedStringKey("ADD_A_DESTINATION_MESSAGE \(modelData.userInfo.destinations.count, specifier: "%d")")
                                Text(message)
                            }
                            Spacer()
                            if destination.startMessage.text != "" {
                                ZStack{
                                    Image(systemName: "info.circle")
                                        .accessibilityLabel(Text("Details"))
                                        .accessibilityRemoveTraits(.isImage)
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityHint(Text("DOUBLETAP_TO_VIEW_DETAILS"))
                                        .foregroundColor(.blue)
                                    NavigationLink(
                                        destination: DestinationDetailView(destination: destination).environmentObject(modelData).heartbeat("DestinationsView(\(destination.title.text))")
                                    ){EmptyView()}
                                    .frame(width: 0, height: 0)
                                    .opacity(0)
                                }
                            }
                        }
                }
            }
        }
        .listStyle(PlainListStyle())
    }
}

struct DestinationsFloorView: View {
    @EnvironmentObject var modelData: CaBotAppModel
    @State private var isConfirming = false
    @State private var targetDestination: (any Destination)?
    @State var floorDestinations: [Directory.FloorDestination] = []

    var destination: (any Destination)?

    var body: some View {
        var header: Text?
        header = Text("SELECT_DESTINATION")
        
        return Form {
            Section(
                header: header
            ) {
                ForEach(floorDestinations, id: \.floorTitle.text) { floorDestination in
                    NavigationLink(
                        destination: DestinationsView(
                            destination: destination,
                            destinations: floorDestination.destinations
                        )
                        .environmentObject(modelData),
                        label: {
                            Text(floorDestination.floorTitle.text)
                                .accessibilityLabel(floorDestination.floorTitle.pron)
                        }
                    )
                }
            }
        }
        .listStyle(PlainListStyle())
        .onAppear {
            if floorDestinations.isEmpty {
                loadFloorDestinations()
            }
        }
    }
    private func loadFloorDestinations() {
        do {
            floorDestinations = try ResourceManager.shared.load().directory
        } catch {
            NSLog("Error loading tours for preview: \(error)")
        }
    }
}

struct DestinationsView_Previews: PreviewProvider {

    static var previews: some View {
        floor_previews
        floor3_item_previews
        floor5_item_previews
    }

    static var floor3_item_previews: some View {
        let modelData = CaBotAppModel()
        modelData.modeType = .Advanced
        var floorDestinationsForPreviews: [Directory.FloorDestination] = []
        do {
            floorDestinationsForPreviews = try Directory.loadForPreview()
        } catch {
            NSLog("Error loading tours for preview: \(error)")
        }

        return DestinationsView(
            destination: floorDestinationsForPreviews.first?.destinations.first,
            destinations: floorDestinationsForPreviews.first?.destinations ?? []
        )
        .environmentObject(modelData)
        .previewDisplayName("Floor 3")
    }

    static var floor5_item_previews: some View {
        let modelData = CaBotAppModel()
        modelData.modeType = .Advanced
        var floorDestinationsForPreviews: [Directory.FloorDestination] = []
        do {
            floorDestinationsForPreviews = try Directory.loadForPreview()
        } catch {
            NSLog("Error loading tours for preview: \(error)")
        }

        return DestinationsView(
            destination: floorDestinationsForPreviews.last?.destinations.first,
            destinations: floorDestinationsForPreviews.last?.destinations ?? []
        )
        .environmentObject(modelData)
        .previewDisplayName("Floor 5")
    }

    static var floor_previews: some View {
        let modelData = CaBotAppModel()
        modelData.modeType = .Advanced
        var floorDestinationsForPreviews: [Directory.FloorDestination] = []
        do {
            floorDestinationsForPreviews = try Directory.loadForPreview()
        } catch {
            NSLog("Error loading tours for preview: \(error)")
        }

        return DestinationsFloorView(
            floorDestinations: floorDestinationsForPreviews
        )
        .environmentObject(modelData)
        .previewDisplayName("Floors")
    }
}

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

struct StaticTourDetailView: View {
    @EnvironmentObject var modelData: CaBotAppModel
    @State private var isConfirming = false
    @State private var targetTour: Tour?

    var tour: Tour

    var body: some View {
        let hasError = tour.destinations.first(where: {d in d.error != nil}) != nil

        Form {
            Section(header: Text("Actions")) {
                Button(action: {
                    targetTour = tour
                    isConfirming = true
                }) {
                    Label{
                        Text("SEND_TOUR")
                    } icon: {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    }
                }
                .disabled(hasError)
                .confirmationDialog(Text("SEND_TOUR"), isPresented: $isConfirming, presenting: targetTour) { detail in
                    Button {
                        modelData.share(tour: targetTour!)
                        NavigationUtil.popToRootView()
                        targetTour = nil
                    } label: {
                        Text("SEND_TOUR")
                    }
                    Button("Cancel", role: .cancel) {
                    }
                } message: { detail in
                    let message = LocalizedStringKey("SEND_TOUR_MESSAGE \(detail.title.text)")
                    Text(message)
                }                
            }
            Section(header: Text(tour.title.text)) {
                if let cd = tour.currentDestination {
                    Label(cd.title.text, systemImage: "arrow.triangle.turn.up.right.diamond")
                }

                ForEach(tour.destinations, id: \.self) { dest in
                    if let error = dest.error {
                        HStack{
                            Text(dest.title.text)
                            Text(error).font(.system(size: 11))
                        }.foregroundColor(Color.red)
                    } else {
                        Label(dest.title.text, systemImage: "mappin.and.ellipse")
                    }
                }
            }
        }
    }
}

struct DynamicTourDetailView: View {
    @EnvironmentObject var modelData: CaBotAppModel
    @State private var isConfirming = false

    var tour: TourProtocol

    var body: some View {
        Form {
            Section(header: Text("Actions")) {
                Button(action: {
                    isConfirming = true
                }) {
                    Label{
                        Text("CANCEL_NAVIGATION")
                    } icon: {
                        Image(systemName: "xmark.circle")
                    }
                }
                .confirmationDialog(Text("CANCEL_NAVIGATION"), isPresented: $isConfirming) {
                    Button {
                        modelData.clearAll()
                        NavigationUtil.popToRootView()
                    } label: {
                        Text("CANCEL_ALL")
                    }
                    Button("Cancel", role: .cancel) {
                    }
                } message: {
                    let message = LocalizedStringKey("CANCEL_NAVIGATION_MESSAGE \(modelData.tourManager.destinationCount, specifier: "%d")")
                    Text(message)
                }
            }
            Section(header: Text(tour.title.text)) {
                if let cd = tour.currentDestination {
                    Label(cd.title.text, systemImage: "arrow.triangle.turn.up.right.diamond")
                }

                ForEach(tour.destinations, id: \.self) { dest in
                    if let error = dest.error {
                        HStack{
                            Text(dest.title.text)
                            Text(error).font(.system(size: 11))
                        }.foregroundColor(Color.red)
                    } else {
                        Label(dest.title.text, systemImage: "mappin.and.ellipse")
                    }
                }
            }
        }
    }
}


struct TourDetailView_Previews: PreviewProvider {
    static var previews: some View {
        preview4
        preview3
        preview2
        preview1
    }
    
    static var preview4: some View {
        let modelData = CaBotAppModel()
        modelData.modeType = .Advanced

        let resource = modelData.resourceManager.resource(by: "Test data")!
        let tours = try! Tour.load(at: resource.toursSource!)

        return DynamicTourDetailView(tour: tours[0])
            .environmentObject(modelData)
            .previewDisplayName("Dynamic Advanced")
    }

    static var preview3: some View {
        let modelData = CaBotAppModel()
        modelData.modeType = .Normal

        let resource = modelData.resourceManager.resource(by: "Test data")!
        let tours = try! Tour.load(at: resource.toursSource!)

        return DynamicTourDetailView(tour: tours[0])
            .environmentObject(modelData)
            .previewDisplayName("Dynamic Normal")
    }

    static var preview2: some View {
        let modelData = CaBotAppModel()
        modelData.modeType = .Advanced

        let resource = modelData.resourceManager.resource(by: "Test data")!
        let tours = try! Tour.load(at: resource.toursSource!)

        return StaticTourDetailView(tour: tours[0])
            .environmentObject(modelData)
            .previewDisplayName("Advanced")
    }

    static var preview1: some View {
        let modelData = CaBotAppModel()
        modelData.modeType = .Normal

        let resource = modelData.resourceManager.resource(by: "Test data")!
        let tours = try! Tour.load(at: resource.toursSource!)

        return StaticTourDetailView(tour: tours[1])
            .environmentObject(modelData)
            .previewDisplayName("Normal")
    }
}

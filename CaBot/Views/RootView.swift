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
import CoreData
import NavigationBackport

struct RootView: View {
    @EnvironmentObject var modelData: CaBotAppModel

    var body: some View {
        return NBNavigationStack {
            VStack {
                switch(modelData.displayedScene) {
                case .Onboard:
                    OnboardGrantAccess()
                        .environmentObject(modelData)
                case .ResourceSelect:
                    ResourceSelectView()
                        .environmentObject(modelData)
                case .App:
                    MainMenuView()
                        .environmentObject(modelData)
                }
                #if ATTEND
                NavigationLink(
                    destination: SystemStatusView().environmentObject(modelData),
                    isActive: $modelData.showingSystemStatusMenu){
                        EmptyView()
                    }
                    .isDetailLink(false)
                NavigationLink(
                    destination: DeviceStatusView().environmentObject(modelData),
                    isActive: $modelData.showingDeviceStatusMenu){
                        EmptyView()
                    }
                    .isDetailLink(false)
                #endif
            }
            .navigationTitle(modelData.displayedScene.text)
            .sheet(isPresented: $modelData.isContentPresenting, content: {
                if let url = modelData.contentURL {
                    VStack {
                        WebContentView(url: url, handlers: [:])
                            .environmentObject(modelData)
                        HStack {
                            Spacer()
                            Button(action: {
                                modelData.isContentPresenting = false
                            }, label: {
                                Image(systemName: "xmark")
                                    .frame(width: 50, height: 50, alignment: .center)
                                    .accessibility(label: Text("Close"))
                            })
                        }
                    }
                }
            })
            .alert(isPresented: $modelData.isConfirmingSummons) {
                let ad = modelData.tourManager.arrivedDestination
                let destination = ad!.waitingDestination!.value
                let title = ad!.waitingDestination!.title
                return Alert(title: Text("Let the suitcase wait"),
                             message: Text(LocalizedStringKey("Let the suitcase wait message \(title.text)")),
                             primaryButton: .default(Text("No")) {
                                // noop
                             },
                             secondaryButton: .destructive(Text("Yes")){
                                _ = modelData.summon(destination: destination)
                             })
            }
        }.environment(\.locale, modelData.resource?.locale ?? .init(identifier: "base"))
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        previewApp
        previewContent
        previewSelect
        previewOnboard
        previewAdvanced
    }

    static var previewApp: some View {
        let modelData = CaBotAppModel()
        modelData.displayedScene = .ResourceSelect
        modelData.suitcaseConnected = false
        modelData.resource = modelData.resourceManager.resource(by: "place0")

        return RootView()
            .environmentObject(modelData)
    }

    static var previewContent: some View {
        let modelData = CaBotAppModel()
        modelData.displayedScene = .App
        modelData.isContentPresenting = true
        modelData.contentURL = URL(string: "content://place0/test.html")!

        return RootView()
            .environmentObject(modelData)

    }

    static var previewSelect: some View {
        let modelData = CaBotAppModel()
        modelData.displayedScene = .ResourceSelect
        modelData.suitcaseConnected = false
        modelData.resource = nil

        return RootView()
            .environmentObject(modelData)
    }

    static var previewOnboard: some View {
        let modelData = CaBotAppModel()
        modelData.suitcaseConnected = false

        return RootView()
            .environmentObject(modelData)
    }

    static var previewAdvanced: some View {
        let modelData = CaBotAppModel()
        modelData.suitcaseConnected = true
        modelData.modeType = .Advanced

        return RootView()
            .environmentObject(modelData)
    }
}

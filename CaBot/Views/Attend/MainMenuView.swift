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

struct MainMenuView: View {
    @EnvironmentObject var modelData: CaBotAppModel

    var body: some View {
        Form {
            ResourceDownloadRetryUIView()
                .environmentObject(modelData)
            UserInfoView()
                .environmentObject(modelData)
            if modelData.noSuitcaseDebug {
                Label("No Suitcase Debug mode", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
            }
            if hasAnyAction() {
                ActionMenus()
                    .environmentObject(modelData)
            }
            //DestinationMenus()
                //.environmentObject(modelData)
            MainMenus()
                .environmentObject(modelData)
                .disabled(!modelData.suitcaseConnected && !modelData.menuDebug)
            StatusMenus()
                .environmentObject(modelData)
            MapMenus()
                .environmentObject(modelData)
            SettingMenus()
                .environmentObject(modelData)
        }
    }

    func hasAnyAction() -> Bool {
        if modelData.tourManager.hasDestination && modelData.menuDebug {
            return true
        }
        if let ad = modelData.tourManager.arrivedDestination {
            if let _ = ad.content?.url {
                return true
            }
            if modelData.tourManager.currentDestination == nil,
               let _ = ad.waitingDestination?.value,
               let _ = ad.waitingDestination?.title {
                return true
            }
        }
        return false
    }
}

struct UserInfoDestinations: View {
    @EnvironmentObject var modelData: CaBotAppModel

    @State private var isConfirming = false
    @State private var targetTour: Tour?
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
                        modelData.share(user_info: SharedInfo(type: .ClearDestinations, value: ""))
                        
                    } label: {
                        Text("CANCEL_ALL")
                    }
                    Button("Cancel", role: .cancel) {
                    }
                } message: {
                    let message = LocalizedStringKey("CANCEL_NAVIGATION_MESSAGE \(modelData.userInfo.destinations.count, specifier: "%d")")
                    Text(message)
                }
            }
            Section(header: Text("Tour")) {
                ForEach(modelData.userInfo.destinations, id: \.self) { destination in
                    Label {
                        Text(destination)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                }
            }
        }
    }
}

struct UserInfoView: View {
    @EnvironmentObject var modelData: CaBotAppModel
    
    var body: some View {
        Section(header: Text("User App Info")) {
            Label {
                if (modelData.userInfo.selectedTour.isEmpty) {
                    if (modelData.userInfo.destinations.count == 0) {
                        Text("PLACEHOLDER_TOUR_TITLE").foregroundColor(.gray)
                    } else {
                        Text("CUSTOMIZED_TOUR")
                    }
                } else {
                    Text(modelData.userInfo.selectedTour)
                }
            } icon: {
                Image(systemName: "list.bullet.rectangle.portrait")
            }
            Label {
                if modelData.userInfo.currentDestination != "" {
                    Text(modelData.userInfo.currentDestination)
                } else if modelData.userInfo.nextDestination != "" {
                    Text(modelData.userInfo.nextDestination)
                } else {
                    Text("PLACEHOLDER_DESTINATION_TITLE").foregroundColor(.gray)
                }
                if modelData.systemStatus.level == .Active{
                    Spacer()
                    HStack {
                        Image(systemName: modelData.touchStatus.level.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                    .foregroundColor(modelData.touchStatus.level.color)
                }
            } icon: {
                if modelData.userInfo.currentDestination != "" {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                } else {
                    Image(systemName: "mappin.and.ellipse")
                }
            }
            if modelData.userInfo.nextDestination != "" {
                Button(action: {
                    modelData.share(user_info: SharedInfo(type: .Skip, value: ""))
                }) {
                    Label{
                        if modelData.userInfo.currentDestination != ""{
                            Text("Skip Label \(modelData.userInfo.currentDestination)")
                        }else{
                            Text("Skip Label \(modelData.userInfo.nextDestination)")
                        }
                    } icon: {
                        Image(systemName: "arrow.right.to.line")
                    }
                }
            }
            if (modelData.userInfo.destinations.count >= 1) {
                NavigationLink(destination: UserInfoDestinations().environmentObject(modelData), label: {
                    HStack {
                        Spacer()
                        Text("See detail")
                    }
                })
            }
            if modelData.userInfo.speakingText.count == 0 {
                Label {
                    Text("PLACEHOLDER_SPEAKING_TEXT").foregroundColor(.gray)
                } icon: {
                    Image(systemName: "text.bubble")
                }
            } else if modelData.userInfo.speakingText.count > 1 {
                ForEach(modelData.userInfo.speakingText[..<2], id: \.self) { text in
                    SpokenTextView.showText(text: text)
                }
                if modelData.userInfo.speakingText.count > 2 {
                    NavigationLink(destination: SpokenTextView().environmentObject(modelData), label: {
                        HStack {
                            Spacer()
                            Text("See history")
                        }
                    })
                }
            } else {
                ForEach(modelData.userInfo.speakingText, id: \.self) { text in
                    SpokenTextView.showText(text: text)
                }
            }
        }
    }
}

struct ActionMenus: View {
    @EnvironmentObject var modelData: CaBotAppModel

    var body: some View {
        Section(header: Text("Actions")) {
            if modelData.tourManager.hasDestination && modelData.menuDebug {
                if let _ = modelData.tourManager.currentDestination {
                    Button(action: {
                        modelData.tourManager.stopCurrent()
                    }) {
                        Text("PAUSE_NAVIGATION")
                    }
                    .disabled(!modelData.suitcaseConnected)
                } else if modelData.tourManager.destinations.count > 0 {
                    Button(action: {
                        _ = modelData.tourManager.proceedToNextDestination()
                    }) {
                        Label{
                            Text("START")
                        } icon: {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        }
                    }
                    .disabled(!modelData.suitcaseConnected)
                }
            }
            
            ArrivedActionMenus()
                .environmentObject(modelData)
        }
    }
}


struct ArrivedActionMenus: View {
    @EnvironmentObject var modelData: CaBotAppModel
    
    var body: some View {
        if let ad = modelData.tourManager.arrivedDestination {
            if let contentURL = ad.content?.url {
                Button(action: {
                    modelData.open(content: contentURL)
                }) {
                    Label(title: {
                        Text("Open Content for \(ad.title.text)")
                    }, icon: {
                        Image(systemName: "newspaper")
                    })
                }
            }
            if modelData.tourManager.currentDestination == nil,
               let _ = ad.waitingDestination?.value,
               let title = ad.waitingDestination?.title {
                Button(action: {
                    modelData.isConfirmingSummons = true
                }) {
                    Label(title: {
                        Text("Let the suitcase wait at \(title.text)")
                    }, icon: {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    })
                }
                .disabled(!modelData.suitcaseConnected && !modelData.menuDebug)
            }
            if let count = ad.arriveMessages?.count {
                if let text = ad.arriveMessages?[count-1] {
                    Button(action: {
                        modelData.speak(text) {}
                    }) {
                        Label{
                            Text("Repeat the message")
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                }
            }
            if let subtour = ad.subtour {
                Button(action: {
                    modelData.addSubTour(tour: subtour)
                }) {
                    Label{
                        Text("Begin Subtour \(subtour.introduction.text)")
                    } icon: {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    }
                }
            }
            if modelData.tourManager.isSubtour {
                Button(action: {
                    modelData.tourManager.clearSubTour()
                }) {
                    Label{
                        Text("End Subtour")
                    } icon: {
                        Image(systemName: "xmark.circle")
                    }
                }
            }
        }

        if modelData.tourManager.currentDestination == nil &&
            modelData.tourManager.hasDestination {
            if let next = modelData.tourManager.nextDestination {
                Button(action: {
                    modelData.skipDestination()
                }) {
                    Label{
                        Text("Skip Label \(next.title.text)")
                    } icon: {
                        Image(systemName: "arrow.right.to.line")
                    }
                }
                .disabled(!modelData.suitcaseConnected)
            }
        }
    }
}

struct DestinationMenus: View {
    @EnvironmentObject var modelData: CaBotAppModel
    @State private var isConfirming = false

    var body: some View {
        let maxDestinationNumber = 2 + (modelData.tourManager.currentDestination==nil ? 1 : 0)

        if modelData.tourManager.hasDestination {
            Section(header: Text("Destinations")) {

                if let cd = modelData.tourManager.currentDestination {
                    HStack {
                        Label(cd.title.text,
                              systemImage: "arrow.triangle.turn.up.right.diamond")
                        .accessibilityLabel(Text("Navigating to \(cd.title.text)"))
                        if modelData.menuDebug {
                            Spacer()
                            Button(action: {
                                isConfirming = true
                            }) {
                                Image(systemName: "checkmark.seal")
                            }
                            .confirmationDialog(Text("Complete Destination"), isPresented: $isConfirming) {
                                Button {
                                    modelData.debugCabotArrived()
                                } label: {
                                    Text("Complete Destination")
                                }
                                Button("Cancel", role: .cancel) {
                                }
                            } message: {
                                Text("Complete Destination Message")
                            }
                        }
                    }
                }
                ForEach(modelData.tourManager.first(n: maxDestinationNumber-1), id: \.self) {dest in
                    Label(dest.title.text, systemImage: "mappin.and.ellipse")
                }
                if modelData.tourManager.destinations.count > 0 {
                    NavigationLink(
                        destination: DynamicTourDetailView(tour: modelData.tourManager),
                        label: {
                            HStack {
                                Spacer()
                                Text("See detail")
                            }
                        })
                }
            }
        }
    }
}

struct MainMenus: View {
    @EnvironmentObject var modelData: CaBotAppModel

    var body: some View {
        if let cm = modelData.resource {
            Section(header: Text("Navigation")) {
                if modelData.modeType == .Debug{
                    if let src = cm.conversationSource{
                        NavigationLink(
                            destination: ConversationView(src: src, dsrc: cm.destinationAllSource)
                                .onDisappear(){
                                    modelData.resetAudioSession()
                                }
                                .environmentObject(modelData),
                            label: {
                                Text("START_CONVERSATION")
                            })
                    }
                }
                if let src = cm.destinationsSource {
                    NavigationLink(
                        destination: DestinationsView(src: src)
                            .environmentObject(modelData),
                        label: {
                            Text("SELECT_DESTINATION")
                        })
                }
                //if modelData.modeType == .Debug{
                    if let src = cm.toursSource {
                        NavigationLink(
                            destination: ToursView()
                                .environmentObject(modelData),
                            label: {
                                Text("SELECT_TOUR")
                            })
                    }
                //}
            }


            if cm.customeMenus.count > 0 {
                Section(header: Text("Others")) {
                    ForEach (cm.customeMenus, id: \.self) {
                        menu in

                        if let url = menu.script.url {
                            Button(menu.title) {
                                let jsHelper = JSHelper(withScript: url)
                                _ = jsHelper.call(menu.function, withArguments: [])
                            }
                        }
                    }
                }
            }
        }
    }
}


struct StatusMenus: View {
    @EnvironmentObject var modelData: CaBotAppModel

    var body: some View {
        Section(header:Text("Status")) {
            if modelData.modeType == .Debug{
                HStack {
                    if modelData.suitcaseConnectedBLE {
                        Label(LocalizedStringKey("BLE Connected"),
                              systemImage: "antenna.radiowaves.left.and.right")
                        if let version = modelData.serverBLEVersion {
                            Text("(\(version))")
                        }
                    } else {
                        Label(LocalizedStringKey("BLE Not Connected"),
                              systemImage: "antenna.radiowaves.left.and.right")
                        .opacity(0.1)
                    }
                }
                HStack {
                    if modelData.suitcaseConnectedTCP {
                        Label(LocalizedStringKey("TCP Connected"),
                              systemImage: "antenna.radiowaves.left.and.right")
                        if let version = modelData.serverTCPVersion {
                            Text("(\(version))")
                        }
                    } else {
                        Label(LocalizedStringKey("TCP Not Connected"),
                              systemImage: "antenna.radiowaves.left.and.right")
                            .opacity(0.1)
                    }
                }
            }else{
                if modelData.suitcaseConnected{
                    Label(LocalizedStringKey("Suitcase Connected"),
                          systemImage: "antenna.radiowaves.left.and.right")
                }else{
                    Label(LocalizedStringKey("Suitcase Not Connected"),
                          systemImage: "antenna.radiowaves.left.and.right")
                    .opacity(0.1)
                }
            }
            if modelData.suitcaseConnected {
                if (modelData.suitcaseConnectedBLE && modelData.versionMatchedBLE == false) ||
                (modelData.suitcaseConnectedTCP && modelData.versionMatchedTCP == false) {
                    Label(LocalizedStringKey("Protocol mismatch \(CaBotServiceBLE.CABOT_BLE_VERSION)"),
                          systemImage: "exclamationmark.triangle")
                        .foregroundColor(Color.red)
                }
                NavigationLink(
                    destination: BatteryStatusView().environmentObject(modelData),
                    label: {
                        HStack {
                            Label(LocalizedStringKey("Battery"),
                                  systemImage: modelData.batteryStatus.level.icon)
                                .labelStyle(StatusLabelStyle(color: modelData.batteryStatus.level.color))
                            Text(":")
                            Text(modelData.batteryStatus.message)
                        }
                    }
                ).isDetailLink(false)
                NavigationLink(
                    destination: DeviceStatusView().environmentObject(modelData),
                    label: {
                        HStack {
                            Label(LocalizedStringKey("Device"),
                                  systemImage: modelData.deviceStatus.level.icon)
                            .labelStyle(StatusLabelStyle(color: modelData.deviceStatus.level.color))
                            Text(":")
                            Text(LocalizedStringKey(modelData.deviceStatus.level.rawValue))
                        }
                    }
                ).isDetailLink(false)
                NavigationLink(
                    destination: SystemStatusView().environmentObject(modelData),
                    label: {
                        HStack {
                            Label(LocalizedStringKey("System"),
                                  systemImage: modelData.systemStatus.summary.icon)
                            .labelStyle(StatusLabelStyle(color: modelData.systemStatus.summary.color))
                            Text(":")
                            Text(LocalizedStringKey(modelData.systemStatus.levelText()))
                            Text("-")
                            Text(LocalizedStringKey(modelData.systemStatus.summary.text))
                        }
                    }
                ).isDetailLink(false)
            }
        }
    }
}

struct MapMenus: View {
    @EnvironmentObject var modelData: CaBotAppModel

    var body: some View {
        if modelData.suitcaseConnected{
            Section(header:Text("Map")) {
                HStack {
                    NavigationLink(
                        destination: RosWebView(address: modelData.getCurrentAddress(), port: modelData.rosPort)
                            .environmentObject(modelData),
                        label: {
                            Text("ROS Map")
                        })
                }
            }
        }
    }
}

struct SettingMenus: View {
    @EnvironmentObject var modelData: CaBotAppModel
    @Environment(\.locale) var locale: Locale
    
    @State var timer:Timer?
    @State var isResourceChanging:Bool = false
    
    var body: some View {
        let versionNo = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
        let buildNo = Bundle.main.infoDictionary!["CFBundleVersion"] as! String
        let commitHash = Bundle.main.infoDictionary!["GitCommitHash"] as! String

        Section(header:Text("System")) {
            if #available(iOS 15.0, *) {
                NavigationLink (destination: LogFilesView(langOverride: modelData.resourceLang)
                    .environmentObject(modelData.logList),
                                label: {
                    Text("REPORT_BUG")
                }).disabled(!modelData.suitcaseConnected && !modelData.menuDebug)
            }
            NavigationLink (destination: SettingView(langOverride: modelData.resourceLang)
                .environmentObject(modelData)
                .onDisappear {
                    modelData.tcpServiceRestart()
                }
            ) {
                HStack {
                    Label(LocalizedStringKey("Settings"), systemImage: "gearshape")
                }
            }
            if (modelData.menuDebug && modelData.noSuitcaseDebug){
                VStack{
                    HStack{
                        Text("System Status")
                        Spacer()
                    }
                    Picker("", selection: $modelData.debugSystemStatusLevel){
                        Text("Okay").tag(CaBotSystemLevel.Active)
                        Text("ERROR").tag(CaBotSystemLevel.Error)
                    }.onChange(of: modelData.debugSystemStatusLevel, perform: { systemStatusLevel in
                        if (systemStatusLevel == .Active){
                            modelData.debugCabotSystemStatus(systemStatusFile: "system_ok.json")
                            modelData.touchStatus.level = .Touching
                        }else{
                            modelData.debugCabotSystemStatus(systemStatusFile: "system_error.json")
                        }
                    }).pickerStyle(SegmentedPickerStyle())
                    HStack{
                        Text("Device Status")
                        Spacer()
                    }
                    Picker("", selection: $modelData.debugDeviceStatusLevel){
                        Text("Okay").tag(DeviceStatusLevel.OK)
                        Text("ERROR").tag(DeviceStatusLevel.Error)
                    }.onChange(of: modelData.debugDeviceStatusLevel, perform: { deviceStatusLevel in
                        if (deviceStatusLevel == .OK){
                            modelData.debugCabotDeviceStatus(systemStatusFile: "device_ok.json")
                            modelData.touchStatus.level = .NoTouch
                        }else{
                            modelData.debugCabotDeviceStatus(systemStatusFile: "device_error.json")
                        }
                    }).pickerStyle(SegmentedPickerStyle())
                }
            }
            Text("Version: \(versionNo) (\(buildNo)) \(commitHash) - \(CaBotServiceBLE.CABOT_BLE_VERSION)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    
    static var previews: some View {
        preview_connected
        preview_advanced_mode_stale
        preview_advanced_mode_touch
        preview_advanced_mode_no_touch
        preview_debug_mode
        //preview_tour
        //preview_tour2
        //preview_tour3
        //preview_tour4
        //preview
        //preview_ja
    }

    static var preview_connected: some View {
        let modelData = CaBotAppModel()
        modelData.suitcaseConnectedBLE = true
        modelData.suitcaseConnectedTCP = true
        modelData.deviceStatus.level = .OK
        modelData.systemStatus.level = .Inactive
        modelData.systemStatus.summary = .Stale
        modelData.versionMatchedBLE = true
        modelData.versionMatchedTCP = true
        modelData.serverBLEVersion = CaBotServiceBLE.CABOT_BLE_VERSION
        modelData.serverTCPVersion = CaBotServiceBLE.CABOT_BLE_VERSION
        modelData.modeType = .Normal

        if let r = modelData.resourceManager.resource(by: "Test data") {
            modelData.resource = r
        }

        return MainMenuView()
            .environmentObject(modelData)
            .environment(\.locale, .init(identifier: "en"))
            .previewDisplayName("suitcase connected")
    }

    static var preview_debug_mode: some View {
        let modelData = CaBotAppModel(preview: true)
        modelData.suitcaseConnected = true
        modelData.suitcaseConnectedBLE = true
        modelData.suitcaseConnectedTCP = true
        modelData.deviceStatus.level = .OK
        modelData.systemStatus.level = .Inactive
        modelData.systemStatus.summary = .Stale
        modelData.versionMatchedBLE = true
        modelData.versionMatchedTCP = true
        modelData.serverBLEVersion = CaBotServiceBLE.CABOT_BLE_VERSION
        modelData.serverTCPVersion = CaBotServiceBLE.CABOT_BLE_VERSION
        modelData.modeType = .Debug
        modelData.menuDebug = true

        let path = Bundle.main.resourceURL!.appendingPathComponent("PreviewResource")
            .appendingPathComponent("system_ok.json")
        let fm = FileManager.default
        let data = fm.contents(atPath: path.path)!
        let status = try! JSONDecoder().decode(SystemStatus.self, from: data)
        modelData.systemStatus.update(with: status)

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("debug mode")

    }

    static var preview_advanced_mode_no_touch: some View {
        let modelData = CaBotAppModel(preview: true)
        modelData.suitcaseConnected = true
        modelData.suitcaseConnectedBLE = true
        modelData.suitcaseConnectedTCP = true
        modelData.deviceStatus.level = .OK
        modelData.systemStatus.level = .Active
        modelData.systemStatus.summary = .Stale
        modelData.versionMatchedBLE = true
        modelData.versionMatchedTCP = true
        modelData.serverBLEVersion = CaBotServiceBLE.CABOT_BLE_VERSION
        modelData.serverTCPVersion = CaBotServiceBLE.CABOT_BLE_VERSION
        modelData.modeType = .Advanced
        modelData.menuDebug = true
        modelData.touchStatus.level = .NoTouch

        let path = Bundle.main.resourceURL!.appendingPathComponent("PreviewResource")
            .appendingPathComponent("system_ok.json")
        let fm = FileManager.default
        let data = fm.contents(atPath: path.path)!
        let status = try! JSONDecoder().decode(SystemStatus.self, from: data)
        modelData.systemStatus.update(with: status)

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("advanced - no touch")

    }

    static var preview_advanced_mode_stale: some View {
        let modelData = CaBotAppModel(preview: true)
        modelData.suitcaseConnected = true
        modelData.suitcaseConnectedBLE = true
        modelData.suitcaseConnectedTCP = true
        modelData.deviceStatus.level = .OK
        modelData.systemStatus.level = .Inactive
        modelData.systemStatus.summary = .Stale
        modelData.versionMatchedBLE = true
        modelData.versionMatchedTCP = true
        modelData.serverBLEVersion = CaBotServiceBLE.CABOT_BLE_VERSION
        modelData.serverTCPVersion = CaBotServiceBLE.CABOT_BLE_VERSION
        modelData.modeType = .Advanced
        modelData.menuDebug = true
        modelData.touchStatus.level = .Stale

        let path = Bundle.main.resourceURL!.appendingPathComponent("PreviewResource")
            .appendingPathComponent("system_ok.json")
        let fm = FileManager.default
        let data = fm.contents(atPath: path.path)!
        let status = try! JSONDecoder().decode(SystemStatus.self, from: data)
        modelData.systemStatus.update(with: status)

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("advanced - stale")

    }

    static var preview_advanced_mode_touch: some View {
        let modelData = CaBotAppModel(preview: true)
        modelData.suitcaseConnected = true
        modelData.suitcaseConnectedBLE = true
        modelData.suitcaseConnectedTCP = true
        modelData.deviceStatus.level = .OK
        modelData.systemStatus.level = .Active
        modelData.systemStatus.summary = .Stale
        modelData.versionMatchedBLE = true
        modelData.versionMatchedTCP = true
        modelData.serverBLEVersion = CaBotServiceBLE.CABOT_BLE_VERSION
        modelData.serverTCPVersion = CaBotServiceBLE.CABOT_BLE_VERSION
        modelData.modeType = .Advanced
        modelData.menuDebug = true
        modelData.touchStatus.level = .Touching

        let path = Bundle.main.resourceURL!.appendingPathComponent("PreviewResource")
            .appendingPathComponent("system_ok.json")
        let fm = FileManager.default
        let data = fm.contents(atPath: path.path)!
        let status = try! JSONDecoder().decode(SystemStatus.self, from: data)
        modelData.systemStatus.update(with: status)

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("advanced - touch")

    }

    static var preview_tour: some View {
        let modelData = CaBotAppModel()
        modelData.menuDebug = true
        modelData.noSuitcaseDebug = true

        if let r = modelData.resourceManager.resource(by: "place0") {
            modelData.resource = r
            if let url = r.toursSource {
                if let tours = try? Tour.load() {
                    modelData.tourManager.set(tour: tours[0])
                    _ = modelData.tourManager.proceedToNextDestination()
                }
            }
        }

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("tour")
    }

    static var preview_tour2: some View {
        let modelData = CaBotAppModel()

        if let r = modelData.resourceManager.resource(by: "place0") {
            modelData.resource = r
            if r.toursSource != nil {
                if let tours = try? Tour.load(){
                    modelData.tourManager.set(tour: tours[0])
                }
            }
        }

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("tour2")
    }

    static var preview_tour3: some View {
        let modelData = CaBotAppModel()

        if let r = modelData.resourceManager.resource(by: "place0") {
            modelData.resource = r
            if let url = r.toursSource {
                if let tours = try? Tour.load() {
                    modelData.tourManager.set(tour: tours[1])
                }
            }
        }

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("tour3")
    }

    static var preview_tour4: some View {
        let modelData = CaBotAppModel()

        if let r = modelData.resourceManager.resource(by: "place0") {
            modelData.resource = r
            if let url = r.toursSource {
                if let tours = try? Tour.load(){
                    modelData.tourManager.set(tour: tours[1])
                }
            }
        }

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("tour4")
    }

    static var preview: some View {
        let modelData = CaBotAppModel()

        modelData.resource = modelData.resourceManager.resource(by: "place0")

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("preview")
    }


    static var preview_ja: some View {
        let modelData = CaBotAppModel()

        modelData.resource = modelData.resourceManager.resource(by: "place0")

        return MainMenuView()
            .environment(\.locale, .init(identifier: "ja"))
            .environmentObject(modelData)
            .previewDisplayName("preview ja")
    }
}

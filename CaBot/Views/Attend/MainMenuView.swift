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
import ChatView
import Translation

struct MainMenuView: View {
    @Environment(\.locale) var locale
    @EnvironmentObject var modelData: CaBotAppModel

    var body: some View {
        Form {
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
            MainMenus()
                .environmentObject(modelData)
                .disabled((!modelData.suitcaseConnected && !modelData.menuDebug) || modelData.serverIsReady != .Ready)
            MapMenus()
                .environmentObject(modelData)
            StatusMenus()
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
            if let _ = ad.content {
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
                ForEach(modelData.userInfo.destinations, id: \.value) { destination in
                    Label {
                        Text(destination.title.text)
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
    @State var translationShown: Bool = false
    @State var translationText: String = ""
    @State private var isConfirmingSkip = false

    var body: some View {
        Section(header: Text("User App Info")) {
            if modelData.userInfo.speakingText.count == 0 {
                Label {
                    Text("PLACEHOLDER_SPEAKING_TEXT").foregroundColor(.gray)
                } icon: {
                    Image(systemName: "text.bubble")
                }
            } else if modelData.userInfo.speakingText.count > 1 {
                ForEach(modelData.userInfo.speakingText[..<2], id: \.self) { text in
                    SpokenTextView.showText(text: text)
                        .onTapGesture {
                            translationText = text.text
                            translationShown = true
                        }
                }
                if modelData.userInfo.speakingText.count > 2 {
                    NavigationLink(destination: SpokenTextView().environmentObject(modelData).heartbeat("SpokenTextView"), label: {
                        HStack {
                            Spacer()
                            Text("See history")
                        }
                    })
                }
            } else {
                ForEach(modelData.userInfo.speakingText, id: \.self) { text in
                    SpokenTextView.showText(text: text)
                        .onTapGesture {
                            translationText = text.text
                            translationShown = true
                        }
                }
            }
            if !modelData.attend_messages.isEmpty && modelData.isUserAppConnected {
                NavigationLink(
                    destination: ChatHistoryView(),
                    label: {
                        HStack {
                            Label(LocalizedStringKey("See chat history"),
                                  systemImage: "bubble.left.and.text.bubble.right")
                        }
                    }
                )
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
            if let contentURL = ad.content {
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
                        modelData.speak(text.text, priority:.Required) { _, _ in }
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
                ForEach(modelData.tourManager.first(n: maxDestinationNumber-1), id: \.value) {dest in
                    Label(dest.title.text, systemImage: "mappin.and.ellipse")
                }
                if modelData.tourManager.destinations.count > 0 {
                    NavigationLink(
                        destination: DynamicTourDetailView(tour: modelData.tourManager).heartbeat("DynamicTourDetailView"),
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
//
struct MainMenus: View {
    @EnvironmentObject var modelData: CaBotAppModel
//
    var body: some View {
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
                              systemImage: "suitcase.rolling")
                        if let version = modelData.serverBLEVersion {
                            Text("(\(version))")
                        }
                    } else {
                        Label {
                            Text(LocalizedStringKey("BLE Not Connected"))
                        } icon: {
                            Image("suitcase.rolling.slash")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.red)
                                .padding(2)
                        }
                    }
                }
                HStack {
                    if modelData.suitcaseConnectedTCP {
                        Label(LocalizedStringKey("TCP Connected"),
                              systemImage: "suitcase.rolling")
                        if let version = modelData.serverTCPVersion {
                            Text("(\(version))")
                        }
                    } else {
                        Label {
                            Text(LocalizedStringKey("Suitcase Not Connected"))
                        } icon: {
                            Image("suitcase.rolling.slash")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.red)
                                .padding(2)
                        }
                    }
                }
            }else{
                if modelData.suitcaseConnected{
                    Label(LocalizedStringKey("Suitcase Connected"),
                          systemImage: "suitcase.rolling")
                }else{
                    Label {
                        Text(LocalizedStringKey("Suitcase Not Connected"))
                    } icon: {
                        Image("suitcase.rolling.slash")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.red)
                            .padding(2)
                    }
                }
                NavigationLink (destination: SettingView(langOverride: modelData.resourceLang)
                    .environmentObject(modelData)
                    .onDisappear {
                        modelData.tcpServiceRestart()
                    }
                    .heartbeat("SettingView")
                ) {
                    Label {
                        HStack {
                            Text(LocalizedStringKey("Handle"))
                            Text(":")
                            Text(LocalizedStringKey(modelData.suitcaseFeatures.selectedHandleSide.text))
                        }
                    } icon: {
                        Image(modelData.suitcaseFeatures.selectedHandleSide.imageName)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(modelData.suitcaseFeatures.selectedHandleSide.color)
                    }
                }
                .disabled(!modelData.isUserAppConnected)
            }
            if modelData.suitcaseConnected {
                if (modelData.suitcaseConnectedBLE && modelData.versionMatchedBLE == false) ||
                (modelData.suitcaseConnectedTCP && modelData.versionMatchedTCP == false) {
                    Label(LocalizedStringKey("Protocol mismatch \(CaBotServiceBLE.CABOT_BLE_VERSION)"),
                          systemImage: "exclamationmark.triangle")
                        .foregroundColor(Color.red)
                }
                NavigationLink(
                    destination: BatteryStatusView().environmentObject(modelData).heartbeat("BatteryStatusView"),
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
                    destination: DeviceStatusView().environmentObject(modelData).heartbeat("DeviceStatusView"),
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
                    destination: SystemStatusView().environmentObject(modelData).heartbeat("SystemStatusView"),
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
                Text("CABOT_NAME: \(ChatData.shared.suitcase_id)")
            }
        }
    }
}

struct MapMenus: View {
    @EnvironmentObject var modelData: CaBotAppModel
    @State private var selectedLang = "English"
    @State private var selectedOption = "Option 1"

    var body: some View {
       
        if (!modelData.isUserAppConnected) {
            Text("User not connected")
        }
        
        Picker("Language", selection: $selectedLang) {
        Text("English").tag("English")
        Text("Japanese").tag("Japanese")
        }
        .pickerStyle(SegmentedPickerStyle())
        .onChange(of: selectedLang) { newLang in
            modelData.promptLanguage = newLang
        }

        var buttonOptions: [String] {
            modelData.promptLanguage == "Japanese"
                ? ["オプション 1", "オプション 2", "オプション 3"]
                : ["The guide is coming", "We are heading to the next destination", "Waiting for other passersby to pass"]
        }
        
        ForEach(buttonOptions, id: \ .self) { option in
            Button(action: {
                modelData.sendAttendResponse(prompt: option)
            }) {
                Text(option)
            }
        }
        
        var options: [String] {
            modelData.promptLanguage == "Japanese"
                ? ["オプション 1", "オプション 2", "オプション 3"]
                : ["Option 1", "Option 2", "Option 3"]
        }
        
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) {
                    selectedOption = option
                    modelData.sendAttendResponse(prompt: option);
                }
            }
        } label: {
            Label("Select an Option", systemImage: "chevron.down")
        }
        Text("Selected: \(selectedOption)")


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
            NavigationLink (destination: CameraView()) {
                Text("Snapshot")
            }.disabled(!modelData.suitcaseConnected)
            if #available(iOS 15.0, *) {
                NavigationLink (destination: LogFilesView(langOverride: modelData.resourceLang)
                    .environmentObject(modelData.logList).heartbeat("LogFilesView"),
                                label: {
                    Text("REPORT_BUG")
                }).disabled(!modelData.suitcaseConnected && !modelData.menuDebug)
            }
            NavigationLink (destination: SettingView(langOverride: modelData.resourceLang)
                .environmentObject(modelData)
                .onDisappear {
                    modelData.tcpServiceRestart()
                }
                .heartbeat("SettingView")
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
        preview_chat_history
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

        do{
            let tours = try ResourceManager.shared.loadForPreview().tours
            if  tours.indices.contains(1){
                modelData.tourManager.set(tour: tours[0])
                _ = modelData.tourManager.proceedToNextDestination()
            }
        }catch {
            NSLog("Error loading tours for preview: \(error)")
        }

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("tour")
    }

    static var preview_tour2: some View {
        let modelData = CaBotAppModel()

        do{
            let tours = try ResourceManager.shared.loadForPreview().tours
            if  tours.indices.contains(1){
                modelData.tourManager.set(tour: tours[0])
            }
        }catch {
            NSLog("Error loading tours for preview: \(error)")
        }

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("tour2")
    }

    static var preview_tour3: some View {
        let modelData = CaBotAppModel()

        do{
            let tours = try ResourceManager.shared.loadForPreview().tours
            if  tours.indices.contains(1){
                modelData.tourManager.set(tour: tours[1])
            }
        }catch {
            NSLog("Error loading tours for preview: \(error)")
        }

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("tour3")
    }

    static var preview_tour4: some View {
        let modelData = CaBotAppModel()

        do{
            let tours = try ResourceManager.shared.loadForPreview().tours
            if  tours.indices.contains(1){
                modelData.tourManager.set(tour: tours[1])
            }
        }catch {
            NSLog("Error loading tours for preview: \(error)")
        }

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("tour4")
    }

    static var preview: some View {
        let modelData = CaBotAppModel()

        return MainMenuView()
            .environmentObject(modelData)
            .previewDisplayName("preview")
    }


    static var preview_ja: some View {
        let modelData = CaBotAppModel()

        return MainMenuView()
            .environment(\.locale, .init(identifier: "ja"))
            .environmentObject(modelData)
            .previewDisplayName("preview ja")
    }

    static var preview_chat_history: some View {
        let modelData = CaBotAppModel()
        func test(_ count: Int = 5) {
            DispatchQueue.main.asyncAfter(deadline: .now()+1) {
                modelData.attend_messages.append(ChatMessage(user: .Agent, text: "Hello1\nHello2\nHello3"))
                DispatchQueue.main.asyncAfter(deadline: .now()+1) {
                    modelData.attend_messages.append(ChatMessage(user: .User, text: "Hello1\nHello2\nHello3"))
                    if count>0 {
                        test(count-1)
                    }
                }
            }
        }
        test()

        return ChatHistoryView()
            .environmentObject(modelData)
            .previewDisplayName("chat history")
    }
}

struct ChatHistoryView: View {
    @EnvironmentObject var modelData: CaBotAppModel

    var body: some View {
        ChatView(messages: modelData.attend_messages, translate: true)
    }
}

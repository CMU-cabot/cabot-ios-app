//
//  DetailSettingView.swift
//  CaBot
//
//  Created by Daisuke Sato on 2023/04/15.
//  Copyright © 2023 Carnegie Mellon University. All rights reserved.
//

import SwiftUI
#if USE_PICS
import CaBotPICSLibrary
#endif

struct DetailSettingView: View {
    @EnvironmentObject var modelData: DetailSettingModel
    @EnvironmentObject var cabotAppModel: CaBotAppModel
    
    @State private var isConfirmingStart = false
    @State private var isConfirmingStop = false
    @State private var isConfirmingReboot = false
    @State private var isConfirmingPoweroff = false
    @State private var isConfirmingReleaseEmergencystop = false

    let startSounds:[String] = [
        "/System/Library/Audio/UISounds/nano/3rdParty_Success_Haptic.caf",
        "/System/Library/Audio/UISounds/nano/3rdParty_Start_Haptic.caf",
        "/System/Library/Audio/UISounds/nano/Alert_SpartanConnecting_Haptic.caf",
        "/System/Library/Audio/UISounds/nano/Warsaw_Haptic.caf",
    ]
    let arrivedSounds:[String] = [
        "/System/Library/Audio/UISounds/nano/HummingbirdNotification_Haptic.caf",
        "/System/Library/Audio/UISounds/nano/Alarm_Nightstand_Haptic.caf",
        "/System/Library/Audio/UISounds/nano/WorkoutStartAutodetect.caf",
        "/System/Library/Audio/UISounds/nano/Alert_MapsDirectionsInApp_Haptic.caf",
        "/System/Library/Audio/UISounds/nano/WorkoutSaved_Haptic.caf",
        "/System/Library/Audio/UISounds/nano/MultiwayInvitation.caf",
        "/System/Library/Audio/UISounds/nano/SiriStopSuccess_Haptic.caf",
        "/System/Library/Audio/UISounds/nano/NavigationGenericManeuver_Haptic.caf",
    ]
    let speedUpSounds:[String] = [
        "/System/Library/Audio/UISounds/nano/WalkieTalkieActiveStart_Haptic.caf",
        "/System/Library/Audio/UISounds/nano/3rdParty_DirectionUp_Haptic.caf",
        "/System/Library/Audio/UISounds/nano/WalkieTalkieReceiveStart_Haptic.caf",
    ]
    let speedDownSounds:[String] = [
        "/System/Library/Audio/UISounds/nano/ET_RemoteTap_Receive_Haptic.caf",
        "/System/Library/Audio/UISounds/nano/3rdParty_DirectionDown_Haptic.caf",
        "/System/Library/Audio/UISounds/nano/WalkieTalkieReceiveEnd_Haptic.caf",
    ]
    
    var body: some View {
        Form {
            Section(header:Text("Actions")) {
                Button(action: {
                    isConfirmingReboot = true
                }) {
                    Text("Reboot")
                        .frame(width: nil, alignment: .topLeading)
                }
                .confirmationDialog(Text("Reboot Computer"), isPresented: $isConfirmingReboot) {
                    Button {
                        cabotAppModel.systemManageCommand(command: .reboot)
                    } label: {
                        Text("Reboot")
                    }
                    Button("Cancel", role: .cancel) {
                    }
                } message: {
                    Text("The app will be disconnected.")
                }
                .disabled(!cabotAppModel.systemStatus.canStart || !cabotAppModel.suitcaseConnected)

            
                Button(action: {
                    isConfirmingPoweroff = true
                }) {
                    Text("Power off")
                        .frame(width: nil, alignment: .topLeading)
                }
                .confirmationDialog(Text("Power off"), isPresented: $isConfirmingPoweroff) {
                    Button {
                        cabotAppModel.systemManageCommand(command: .poweroff)
                    } label: {
                        Text("Power off")
                    }
                    Button("Cancel", role: .cancel) {
                    }
                } message: {
                    Text("The app will be disconnected.")
                }
                .disabled(!cabotAppModel.systemStatus.canStart || !cabotAppModel.suitcaseConnected)

                Button(action: {
                    isConfirmingReleaseEmergencystop = true
                }) {
                    Text("RELEASE_EMERGENCYSTOP")
                        .frame(width: nil, alignment: .topLeading)
                }
                .confirmationDialog(Text("RELEASE_EMERGENCYSTOP"), isPresented: $isConfirmingReleaseEmergencystop) {
                    Button {
                        cabotAppModel.systemManageCommand(command: .release_emergencystop)
                    } label: {
                        Text("RELEASE_EMERGENCYSTOP")
                    }
                    Button("Cancel", role: .cancel) {
                    }
                } message: {
                    Text("CONFIRM_EMERGENCYSTOP")
                }
                .disabled(!cabotAppModel.suitcaseConnected)

                Button(action: {
                    isConfirmingStart = true
                }){
                   Text("Start System")
                        .frame(width: nil, alignment: .topLeading)
                }
                .confirmationDialog(Text("Start System"), isPresented: $isConfirmingStart) {
                    Button {
                        cabotAppModel.systemManageCommand(command: .start)
                    } label: {
                        Text("Start System")
                    }
                    Button("Cancel", role: .cancel) {
                    }
                } message: {
                    Text("Start the suitcase system")
                }
                .disabled(!cabotAppModel.systemStatus.canStart || !cabotAppModel.suitcaseConnected)
                
                Button(action: {
                    isConfirmingStop = true
                }) {
                    Text("Stop System")
                        .frame(width: nil, alignment: .topLeading)
                }
                .confirmationDialog(Text("Stop System"), isPresented: $isConfirmingStop) {
                    Button {
                        cabotAppModel.systemManageCommand(command: .stop)
                    } label: {
                        Text("Stop")
                    }
                    Button("Cancel", role: .cancel) {
                    }
                } message: {
                    Text("Are you sure to stop the suitcase system?")
                }
                .disabled(!cabotAppModel.systemStatus.canStop || !cabotAppModel.suitcaseConnected)

                Toggle(isOn: $cabotAppModel.wifiEnabled) {
                    Text("WiFi")
                }
                .disabled(!cabotAppModel.suitcaseConnected || !cabotAppModel.wifiDetected)
            }
            
            if cabotAppModel.suitcaseConnected {
                Section(header:Text("ROS")) {
                    List {
                        NavigationLink(
                            destination: RosWebView(address: cabotAppModel.getCurrentAddress(), port: cabotAppModel.rosPort, type: .rosMap)
                                .environmentObject(cabotAppModel).heartbeat("RosWebView"),
                            label: {
                                Text("ROS Map")
                            }
                        )
                    }
                }
            }

            Section(header: Text("Tour")) {
                Toggle("Enable subtour on handle", isOn: $modelData.enableSubtourOnHandle)
                Toggle("Show content when arrive", isOn: $modelData.showContentWhenArrive)
            }
            
            Section(header: Text("Audio Effect")) {
                Picker("Start", selection: $modelData.startSound) {
                    ForEach(startSounds, id: \.self) { sound in
                        Text(NSString(string: sound).lastPathComponent).tag(sound)
                    }
                }.onChange(of: modelData.startSound) { value in
                    modelData.playAudio(file: value)
                }
                Picker("Arrived", selection: $modelData.arrivedSound) {
                    ForEach(arrivedSounds, id: \.self) { sound in
                        Text(NSString(string: sound).lastPathComponent).tag(sound)
                    }
                }.onChange(of: modelData.arrivedSound) { value in
                    modelData.playAudio(file: value)
                }
                Picker("SpeedUp", selection: $modelData.speedUpSound) {
                    ForEach(speedUpSounds, id: \.self) { sound in
                        Text(NSString(string: sound).lastPathComponent).tag(sound)
                    }
                }.onChange(of: modelData.speedUpSound) { value in
                    modelData.playAudio(file: value)
                }
                Picker("SpeedDown", selection: $modelData.speedDownSound) {
                    ForEach(speedDownSounds, id: \.self) { sound in
                        Text(NSString(string: sound).lastPathComponent).tag(sound)
                    }
                }.onChange(of: modelData.speedDownSound) { value in
                    modelData.playAudio(file: value)
                }
            }
            
            Section(header: Text("VoiceOver adjustment")) {
                VStack {
                    Text("Delay after closing browser")
                        .accessibility(hidden: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Slider(value: $modelData.browserCloseDelay,
                               in: 1...2,
                               step: 0.1)
                            .accessibility(label: Text("Delay after closing browser"))
                            .accessibility(value: Text(LocalizedStringKey("\(modelData.browserCloseDelay, specifier: "%.1f") seconds")))
                        Text(LocalizedStringKey("\(modelData.browserCloseDelay, specifier: "%.1f") sec"))
                            .accessibility(hidden: true)
                    }
                }
            }
            
            #if USE_PICS
            if let picsModel = cabotAppModel.picsModel {
                @Bindable var viewModel = picsModel
                Section("Traffic Signal Integration") {
                    List {
                        Toggle(isOn: $viewModel.runSimulation) {
                            Text("Simulate Traffic Signal")
                        }
                        NavigationLink("JSON") {
                            CaBotPICSLibrary.TestView(viewModel: viewModel)
                        }
                        NavigationLink("SDK Sample") {
                            CaBotPICSLibrary.ContentView(viewModel: viewModel)
                        }
                    }
                }
            }
            #endif
        }
    }
}

struct NavigationSettingView_Previews: PreviewProvider {
    static var previews: some View {
        let modelData = CaBotAppModel(preview: true)
        
        DetailSettingView()
            .environmentObject(modelData.detailSettingModel)
            .environmentObject(modelData)
    }
}

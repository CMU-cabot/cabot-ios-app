//
//  DetailSettingView.swift
//  CaBot
//
//  Created by Daisuke Sato on 2023/04/15.
//  Copyright © 2023 Carnegie Mellon University. All rights reserved.
//

import SwiftUI

struct DetailSettingView: View {
    @EnvironmentObject var modelData: DetailSettingModel
    @EnvironmentObject var cabotAppModel: CaBotAppModel

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
        return Form {
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

            Section(header: Text("Navigation")) {
                Toggle(isOn: $cabotAppModel.ignorePeopleEnabled) {
                    Text("Ignore People")
                }
                .disabled(!cabotAppModel.suitcaseConnected)
            }
        }
    }
}

struct NavigationSettingView_Previews: PreviewProvider {
    static var previews: some View {
        let modelData = CaBotAppModel()
        DetailSettingView()
            .environmentObject(modelData.detailSettingModel)
            .environmentObject(modelData)
    }
}

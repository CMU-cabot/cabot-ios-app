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
import CoreBluetooth
import UserNotifications


struct OnboardGrantAccess: View {
    @EnvironmentObject var modelData:CaBotAppModel

    @State var userAction: Bool = false

    var body: some View {

        return VStack {
            Text("ONBOARD_MESSAGE")
                .padding()

            Button(action: {
                userAction = true
                modelData.requestLocationAuthorization()
            }) {
                switch(modelData.locationState) {
                case .Init:
                    Label(LocalizedStringKey("Enable Location Update"), systemImage:"circle")
                case .Granted:
                    Label(LocalizedStringKey("Location Update Enabled"), systemImage:"checkmark.circle")
                case .Denied:
                    Label(LocalizedStringKey("Location Update Denied"), systemImage:"multiply.circle")
                case .Off:
                    Label(LocalizedStringKey("ERROR"), systemImage:"multiply.circle")
                }
            }
            .padding()
            .disabled(modelData.locationState != .Init)
            .frame(width:250, alignment: .leading)

            Button(action: {
                userAction = true
                modelData.requestBluetoothAuthorization()
            }) {
                switch(modelData.bluetoothState) {
                case .unknown:
                    Label(LocalizedStringKey("Enable Bluetooth"), systemImage: "circle")
                case .unauthorized:
                    Label(LocalizedStringKey("Bluetooth Denied"), systemImage: "multiply.circle")
                case .poweredOn:
                    Label(LocalizedStringKey("Bluetooth Enabled"), systemImage: "checkmark.circle")
                case .poweredOff:
                    Label(LocalizedStringKey("Bluetooth is Off"), systemImage: "circle")
                case .unsupported:
                    Label(LocalizedStringKey("Running on Simulator?"),
                          systemImage: "multiply.circle")
                default:
                    Text("bluetoothState error")
                }
            }
            .padding()
            .disabled(modelData.bluetoothState != .unknown)
            .frame(width:250, alignment: .leading)

            Button(action: {
                userAction = true
                modelData.requestNotificationAuthorization()
            }) {
                switch(modelData.notificationState) {
                case .Init:
                    Label(LocalizedStringKey("Enable Notification"), systemImage:"circle")
                case .Granted:
                    Label(LocalizedStringKey("Notification Enabled"), systemImage:"checkmark.circle")
                case .Denied:
                    Label(LocalizedStringKey("Notification Denied"), systemImage:"multiply.circle")
                case .Off:
                    Label(LocalizedStringKey("ERROR"), systemImage:"multiply.circle")
                }
            }
            .padding()
            .disabled(modelData.notificationState != .Init)
            .frame(width:250, alignment: .leading)


            Button(action: {
                userAction = true
                modelData.requestMicrophoneAuthorization()
            }) {
                switch(modelData.recordPermission) {
                case .undetermined:
                    Label(LocalizedStringKey("Enable Microphone"), systemImage:"circle")
                case .granted:
                    Label(LocalizedStringKey("Microphone Enabled"), systemImage:"checkmark.circle")
                case .denied:
                    Label(LocalizedStringKey("Microphone Denied"), systemImage:"multiply.circle")
                }
            }
            .padding()
            .disabled(modelData.recordPermission != .undetermined)
            .frame(width:250, alignment: .leading)

            Button(action: {
                userAction = true
                modelData.requestSpeechRecoAuthorization()
            }) {
                switch(modelData.speechRecoState) {
                case .notDetermined:
                    Label(LocalizedStringKey("Enable Speech Reco"), systemImage:"circle")
                case .authorized:
                    Label(LocalizedStringKey("Speech Reco Enabled"), systemImage:"checkmark.circle")
                case .restricted:
                    Label(LocalizedStringKey("Speech Reco Not Available"), systemImage:"multiply.circle")
                case .denied:
                    Label(LocalizedStringKey("Speech Reco Denied"), systemImage:"multiply.circle")
                }
            }
            .padding()
            .disabled(modelData.speechRecoState != .notDetermined)
            .frame(width:250, alignment: .leading)
        }
    }
}

struct OnboardGrantAccess_Previews: PreviewProvider {
    static var previews: some View {
        let modelData = CaBotAppModel()

        OnboardGrantAccess()
            .environmentObject(modelData)
            .previewDevice("iPhone 12 Pro")
            .previewDisplayName("Normal")
    }
}

/*******************************************************************************
 * Copyright (c) 2022  Carnegie Mellon University
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

struct DeviceStatusView: View {
    @EnvironmentObject var modelData: CaBotAppModel
    @State private var isConfirmingReboot = false
    @State private var isConfirmingPoweroff = false
    @State private var isConfirmingReleaseEmergencystop = false
    var body: some View {
        return VStack {
            Form {
                Section(header:Text("Details")) {
                    List {
                        Label(modelData.deviceStatus.level.rawValue, systemImage: modelData.deviceStatus.level.icon)
                            .labelStyle(StatusLabelStyle(color: modelData.deviceStatus.level.color))
                        ForEach (modelData.deviceStatus.devices, id: \.self) {device in
                            VStack(alignment: .leading, spacing: 5) {
                                Label(device.type, systemImage: device.level.icon)
                                    .labelStyle(StatusLabelStyle(color: device.level.color))
                                Label(device.model, systemImage: "gearshape.2")
                                    .labelStyle(StatusLabelStyle(color: .gray))
                                Label(device.message, systemImage: "text.bubble")
                                    .labelStyle(StatusLabelStyle(color: .gray))
                            }
                        }
                    }
                }

                Section(header:Text("Actions")) {
                    if !modelData.suitcaseConnected {
                        Label(LocalizedStringKey("Suitcase Not Connected"),
                              systemImage: "antenna.radiowaves.left.and.right")
                            .opacity(0.3)
                    }
                    Button(action: {
                        isConfirmingReboot = true
                    }) {
                        Text("Reboot")
                            .frame(width: nil, alignment: .topLeading)
                    }
                    .confirmationDialog(Text("Reboot Computer"), isPresented: $isConfirmingReboot) {
                        Button {
                            modelData.systemManageCommand(command: .reboot)
                        } label: {
                            Text("Reboot")
                        }
                        Button("Cancel", role: .cancel) {
                        }
                    } message: {
                        Text("The app will be disconnected.")
                    }
                    .disabled(!modelData.systemStatus.canStart || !modelData.suitcaseConnected)

                    Button(action: {
                        isConfirmingPoweroff = true
                    }) {
                        Text("Power off")
                            .frame(width: nil, alignment: .topLeading)
                    }
                    .confirmationDialog(Text("Power off"), isPresented: $isConfirmingPoweroff) {
                        Button {
                            modelData.systemManageCommand(command: .poweroff)
                        } label: {
                            Text("Power off")
                        }
                        Button("Cancel", role: .cancel) {
                        }
                    } message: {
                        Text("The app will be disconnected.")
                    }
                    .disabled(!modelData.systemStatus.canStart || !modelData.suitcaseConnected)

                    Button(action: {
                        isConfirmingReleaseEmergencystop = true
                    }) {
                        Text("RELEASE_EMERGENCYSTOP")
                            .frame(width: nil, alignment: .topLeading)
                    }
                    .confirmationDialog(Text("RELEASE_EMERGENCYSTOP"), isPresented: $isConfirmingReleaseEmergencystop) {
                        Button {
                            modelData.systemManageCommand(command: .release_emergencystop)
                        } label: {
                            Text("RELEASE_EMERGENCYSTOP")
                        }
                        Button("Cancel", role: .cancel) {
                        }
                    } message: {
                        Text("CONFIRM_EMERGENCYSTOP")
                    }
                    .disabled(!modelData.suitcaseConnected)

                    Toggle(isOn: $modelData.wifiEnabled) {
                        Text("WiFi")
                    }
                    .disabled(!modelData.suitcaseConnected || !modelData.wifiDetected)
                }
            }
            .navigationTitle("Device Status")
        }
    }
}

struct DeviceStatusView_Previews: PreviewProvider {
    static var previews: some View {
        let modelData = CaBotAppModel()
        modelData.suitcaseConnected = true
        let path = Bundle.main.resourceURL!.appendingPathComponent("PreviewResource")
            .appendingPathComponent("device.json")

        let fm = FileManager.default
        let data = fm.contents(atPath: path.path)!
        let text = String(data: data, encoding: .utf8)

        do {
            let status = try JSONDecoder().decode(DeviceStatus.self, from: data)
            modelData.deviceStatus = status
        } catch {
            modelData.deviceStatus.level = .Error
            let entry = DeviceStatusEntry(type: "Error", model: "Error", level: .Error, message: error.localizedDescription, values: [])
            let entry2 = DeviceStatusEntry(type: "Error", model: "Error", level: .Error, message: text!, values: [])
            modelData.deviceStatus.devices = [entry, entry2]
        }

        return DeviceStatusView()
            .environmentObject(modelData)
    }
}

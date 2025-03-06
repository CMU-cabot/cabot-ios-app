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

struct BatteryStatusView: View {
    @EnvironmentObject var modelData: CaBotAppModel
    @State private var showConfirmationDialog = false
    @State private var resetParam: String?

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Details")) {
                    if !modelData.suitcaseConnected {
                        Label(LocalizedStringKey("Suitcase Not Connected"),
                              systemImage: "antenna.radiowaves.left.and.right")
                            .opacity(0.3)
                    }
                    List {
                        ForEach(modelData.batteryStatus.values, id: \.self) { value in
                            HStack {
                                Text(value.key)
                                    .frame(maxWidth: 200, alignment: .topLeading)
                                if value.value.starts(with: "/") {
                                    Button(action: {
                                        resetParam = value.value
                                        showConfirmationDialog = true
                                    }) {
                                        Text("Reset")
                                    }
                                } else {
                                    Text(value.value)
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Battery Status")
            .confirmationDialog("Confirm Reset",
                                isPresented: $showConfirmationDialog,
                                titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    if let param = resetParam {
                        modelData.systemManageCommand(command: .reset_power, param: param)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to reset the battery?")
            }
        }
    }
}

struct BatteryStatusView_Previews: PreviewProvider {
    static var previews: some View {
        let modelData = CaBotAppModel()
        modelData.suitcaseConnected = true
        let path = Bundle.main.resourceURL!.appendingPathComponent("PreviewResource")
            .appendingPathComponent("battery.json")

        let fm = FileManager.default
        let data = fm.contents(atPath: path.path)!
        let status = try! JSONDecoder().decode(BatteryStatus.self, from: data)
        modelData.batteryStatus = status

        return BatteryStatusView()
            .environmentObject(modelData)
    }
}

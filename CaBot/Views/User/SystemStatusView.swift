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

struct SystemStatusView: View {
    @EnvironmentObject var modelData: CaBotAppModel
    @State private var isConfirmingStop = false

    var body: some View {
        return VStack {
            Form {
                Section(header:Text("Details")) {
                    List {
                        HStack {
                            Label(modelData.systemStatus.levelText(),
                                  systemImage: modelData.systemStatus.summary.icon)
                            .labelStyle(StatusLabelStyle(color: modelData.systemStatus.summary.color))
                            Text(":")
                            Text(modelData.systemStatus.summary.text)
                        }
                        ForEach (modelData.systemStatus.components.keys, id:\.self) { key in
                            let component = modelData.systemStatus.components[key]!
                            NavigationLink(destination: SystemStatusDetailView(key: key)
                                .environmentObject(modelData),
                                           label: {
                                HStack {
                                    Label(component.name, systemImage: component.level.icon)
                                        .labelStyle(StatusLabelStyle(color: component.level.color))
                                }
                            }).isDetailLink(false)
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
                        modelData.systemManageCommand(command: .start)
                    }) {
                        Text("Start System")
                            .frame(width: nil, alignment: .topLeading)
                    }
                    .disabled(!modelData.systemStatus.canStart || !modelData.suitcaseConnected)

                    Button(action: {
                        isConfirmingStop = true
                    }) {
                        Text("Stop System")
                            .frame(width: nil, alignment: .topLeading)
                    }
                    .confirmationDialog(Text("Stop System"), isPresented: $isConfirmingStop) {
                        Button {
                            modelData.systemManageCommand(command: .stop)
                        } label: {
                            Text("Stop")
                        }
                        Button("Cancel", role: .cancel) {
                        }
                    } message: {
                        Text("Are you sure to stop the suitcase system?")
                    }
                    .disabled(!modelData.systemStatus.canStop || !modelData.suitcaseConnected)
                }
            }
            .navigationTitle(LocalizedStringKey("System Status"))
        }
    }
}

struct SystemStatusView_Previews: PreviewProvider {
    static var previews: some View {
        let modelData = CaBotAppModel()
        modelData.suitcaseConnected = true
        modelData.modeType = .Debug
        let path = Bundle.main.resourceURL!.appendingPathComponent("PreviewResource")
            .appendingPathComponent("system.json")

        let fm = FileManager.default
        let data = fm.contents(atPath: path.path)!
        let status = try! JSONDecoder().decode(SystemStatus.self, from: data)
        modelData.systemStatus.update(with: status)

        return SystemStatusView()
            .environmentObject(modelData)
    }
}

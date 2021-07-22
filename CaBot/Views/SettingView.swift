// please remove this line
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

struct SettingView: View {
    @Environment(\.locale) var locale: Locale
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @EnvironmentObject var modelData: CaBotAppModel

    var body: some View {
        return Form {
            Section(header: Text("Speech Voice")) {
                Picker("Voice", selection: $modelData.voice) {
                    ForEach(TTSHelper.getVoices(by: locale), id: \.self) { voice in
                        Text(voice.AVvoice.name).tag(voice as Voice?)
                    }
                }.onChange(of: modelData.voice, perform: { value in
                    if let voice = modelData.voice {
                        TTSHelper.playSample(of: voice)
                    }
                })
                .pickerStyle(DefaultPickerStyle())
            }
            Section(header: Text("Connection")) {

                HStack {
                    Text("Team ID")
                    TextField("Team ID", text: $modelData.teamID)
                }
            }

            Section(header: Text("Others")) {
                Button(action: {
                    modelData.resource = nil
                    modelData.displayedScene = .ResourceSelect
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("SELECT_RESOURCE")
                }
                Toggle("Menu Debug", isOn: $modelData.menuDebug)
            }
        }
    }
}

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        let modelData = CaBotAppModel()

        let resource = modelData.resourceManager.resource(by: "place0")!

        modelData.resource = resource
        modelData.teamID = "test"

        return SettingView()
            .environmentObject(modelData)
            .environment(\.locale, Locale.init(identifier: "en-US"))
    }
}

extension View {
    func print(_ value: Any) -> Self {
        Swift.print(value)
        return self
    }
}

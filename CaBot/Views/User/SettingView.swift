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

    @State var timer:Timer?
    @State var langOverride:String
    @State var isResourceChanging:Bool = false

    @State var userVoicePickerSelection: Voice?

    var body: some View {
        return Form {
            Section(header: Text("Settings")){
                Picker("LANGUAGE", selection: $modelData.selectedLanguage) {
                    ForEach(modelData.languages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }

                Picker(LocalizedStringKey("Handle"), selection: $modelData.suitcaseFeatures.selectedHandleSide) {
                    ForEach(modelData.suitcaseFeatures.possibleHandleSides, id: \.rawValue) { grip in
                        Text(LocalizedStringKey(grip.text)).tag(grip)
                    }
                }

                Picker(LocalizedStringKey("Touch Mode"), selection: $modelData.suitcaseFeatures.selectedTouchMode) {
                    ForEach(modelData.suitcaseFeatures.possibleTouchModes, id: \.rawValue) { touch in
                        Text(LocalizedStringKey(touch.text)).tag(touch)
                    }
                }

                NavigationLink(destination: DetailSettingView().environmentObject(modelData.detailSettingModel).heartbeat("DetailSettingView"), label: {
                    Text("DETAIL_SETTING")
                })
            }

            Section(header:Text("TTS")) {
                Picker(LocalizedStringKey("Voice"), selection: $modelData.userVoice) {
                    ForEach(TTSHelper.getVoices(by: locale), id: \.self) { voice in
                        Text(voice.AVvoice.name).tag(voice as Voice?)
                    }
                }
                .onChange(of: modelData.userVoice, perform: { value in
                    modelData.playSample(mode: .User)
                })
                .pickerStyle(DefaultPickerStyle())

                HStack {
                    Text("Speech Speed")
                        .accessibility(hidden: true)
                    Slider(value: $modelData.userSpeechRate,
                           in: 0...1,
                           step: 0.05,
                           onEditingChanged: { editing in
                        if editing == false {
                            modelData.playSample(mode: .User)
                        }
                    })
                    .accessibility(label: Text("Speech Speed"))
                    .accessibility(value: Text(String(format:"%.0f %%", arguments:[modelData.userSpeechRate*100.0])))
                    Text(String(format:"%.0f %%", arguments:[modelData.userSpeechRate*100.0]))
                        .accessibility(hidden: true)
                }
            }

            Section(header: Text("Connection")) {
                VStack {
                    HStack{
                        Text("PRIORITY_CONNECTION")
                        Spacer()
                    }
                    Picker("", selection: $modelData.connectionType){
                        ForEach(ConnectionType.allCases, id: \.self){ (type) in
                            Text(type.rawValue).tag(type)
                        }
                    }.pickerStyle(SegmentedPickerStyle())
                }
                HStack {
                    Text("ROBOT_NAME_LABEL")
                    TextField("ROBOT_NAME", text: $modelData.teamID)
                }
                HStack {
                    Text("PRIMARY_IP_ADDRESS")
                    TextField("PLACEHOLDER_IP_ADDRESS", text:
                                $modelData.primaryAddr
                    )
                }
                HStack {
                    Text("SECONDARY_IP_ADDRESS")
                    TextField("PLACEHOLDER_IP_ADDRESS", text:
                                $modelData.secondaryAddr)
                }
            }
        }
    }
}

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        preview
        preview_ja
    }

    static var preview: some View {
        let modelData = CaBotAppModel()

        modelData.teamID = "test"

        return SettingView(langOverride: "en-US")
            .environmentObject(modelData)
            .environment(\.locale, Locale.init(identifier: "en-US"))
            .previewDisplayName("preview")
    }

    static var preview_ja: some View {
        let modelData = CaBotAppModel()

        modelData.teamID = "test"

        return SettingView(langOverride: "ja-JP")
            .environmentObject(modelData)
            .environment(\.locale, Locale.init(identifier: "ja-JP"))
            .previewDisplayName("preview_ja")
    }
}

extension View {
    func print(_ value: Any) -> Self {
        Swift.print(value)
        return self
    }
}

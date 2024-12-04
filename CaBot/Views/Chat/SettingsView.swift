/*******************************************************************************
 * Copyright (c) 2024  IBM Corporation and Carnegie Mellon University
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

struct PermissionItem : Identifiable {
    let id : Int
    let permission : Permission
    var flag = false
}


struct SettingsView: View {
    let permissions : [Permission]
    @ObservedObject var config :ChatConfiguration
    @Binding var dismissFlag : Bool
    @State var warning :String? = nil
    @State var permissionItems :[PermissionItem] = []

    var body: some View {
        Text("Settings")
            .font(.title)
        Form {
            PermissionRequestSection
            
            Section("Chat server connection") {
                VStack(alignment:.leading) {
                    Text("Scheme:")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("like \"https\"", text: $config.scheme)
                        .autocapitalization(.none)
                        .keyboardType(.asciiCapable)
                }
                VStack(alignment:.leading) {
                    Text("Host:")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("IP address or Host name", text: $config.host)
                        .autocapitalization(.none)
                        .keyboardType(.asciiCapable)
                }
                VStack(alignment:.leading) {
                    Text("Port:")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("80", value: $config.port, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                }
                VStack(alignment:.leading) {
                    Text("Api Key:")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("", text: $config.apiKey)
                        .autocapitalization(.none)
                        .keyboardType(.asciiCapable)
                }
            }
        }
        Button("Done") {
            config.setToUserDefaults()
            guard validate() else {
                return
            }
            
            Task { @MainActor in
                for item in permissionItems {
                    if item.flag {
                        await item.permission.requestPermission()
                    }
                }
                dismissFlag = false
            }
        }
        
        .alert( warning ?? "",
            isPresented: Binding<Bool>( get:{warning != nil}, set:{_ in warning = nil } ))
        {
            Text( "OK" )
        }
        .onAppear {
            self.permissionItems = permissions.enumerated().map {
                PermissionItem( id:$0, permission:$1 )
            }
        }
        
    }
    
    @ViewBuilder
    var PermissionRequestSection : some View {
        if permissionItems.isEmpty {
            EmptyView()
        }
        else {
            Section("Please allow the app to access below features") {
                ForEach( $permissionItems ) { $item in
                    if item.permission.status == .suspend {
                        Toggle(isOn: $item.flag) {
                            Text(item.permission.requestLabel)
                        }
                    }
                    else {
                        HStack {
                            Text(item.permission.requestLabel)
                            Spacer()
                            Button( "Open Setting App" ) {
                                if  let settingsUrl = URL( string:UIApplication.openSettingsURLString ),
                                    UIApplication.shared.canOpenURL( settingsUrl ) {
                                    UIApplication.shared.open( settingsUrl ) { _ in }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    
    func validate() -> Bool {
        warning = !config.host.isEmpty && !config.scheme.isEmpty && !config.apiKey.isEmpty
                    // connectionConfig.isValid
                    ? nil : "no entry or invalid"
        return warning == nil
    }
}

#Preview {
    SettingsView( permissions:[], config:ChatConfiguration(), dismissFlag:.constant(false) )
}

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

struct ResourceSelectView: View {
    static public let resourceSelectedKey = "resourceSelectedKey"

    @EnvironmentObject var model: CaBotAppModel

    var body: some View {
        Form {
            Section(header:Text("Select Resource")) {
                ForEach (model.resourceManager.resources, id: \.self) { resource in
                    Button(action: {
                        withAnimation() {
                            UserDefaults.standard.setValue(true, forKey: ResourceSelectView.resourceSelectedKey)
                            UserDefaults.standard.synchronize()
                            model.resource = resource
                            model.displayedScene = .App
                        }
                    }) {
                        HStack {
                            Image(systemName: "folder")
                            Text("\(resource.name)")
                        }
                    }
                }
                //.onDelete(perform: delete)
            }
        }
        .onAppear(perform: {
            if let value = UserDefaults.standard.value(forKey: ResourceSelectView.resourceSelectedKey) as? Bool {
                if value {
                    model.displayedScene = .App
                }
            }
        })
    }
}

struct ResourceSelectView_Previews: PreviewProvider {
    static var previews: some View {
        let model = CaBotAppModel()

        ResourceSelectView()
            .environmentObject(model)
    }
}

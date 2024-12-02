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

struct ToursView: View {
    @EnvironmentObject var modelData: CaBotAppModel
    @State private var tours: [Tour] = []
    
    var body: some View {
        Form {
            Section(header: Text("SELECT_TOUR")) {
                ForEach(tours, id: \.id) { tour in
                    NavigationLink(
                        destination: StaticTourDetailView(tour: tour).heartbeat("StaticTourDetailView"),
                        label: {
                            Text(tour.title.text)
                        })
                }
            }
        }
        .listStyle(PlainListStyle())
        .onAppear {
            loadTours()
           
        }
    }
    
    private func loadTours() {
        do {
            tours = try Tour.load()
        } catch {
            NSLog("Error loading tours: \(error)")
        }
    }

}

struct ToursView_Previews: PreviewProvider {
    static var previews: some View {
        let modelData = CaBotAppModel()

        let resource = modelData.resourceManager.resource(by: "Test data")!
        let tours = resource.toursSource!

        return ToursView()
            .environmentObject(modelData)
    }
}

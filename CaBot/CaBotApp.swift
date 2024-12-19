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
import CoreLocation
import HealthKit
import os.log

// override NSLog
public func NSLog(_ format: String, _ args: CVarArg...) {
    withVaList(args) { NavNSLogv(format, $0) }
}
public func Debug( log:String ) {
    NSLog(log)
}

struct SuitcaseStatusView: View {
    @EnvironmentObject var modelData: CaBotAppModel
    var body: some View {
        HStack {
            Image(modelData.suitcaseFeatures.selectedHandleSide.imageName, bundle: Bundle.main)
                .resizable()
                .scaledToFit()
                .frame(width: 33, height: 33)
                .padding(7)
                .background(Color.white)
                .foregroundColor(modelData.suitcaseConnected ? modelData.suitcaseFeatures.selectedHandleSide.color : Color.gray)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            if modelData.suitcaseConnected {
                Image(systemName: "suitcase.rolling")
                    .font(.title2)
                    .padding(12)
                    .background(Color.white)
                    .foregroundColor(Color.blue)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .padding(.trailing, 8)
            } else {
                Image("suitcase.rolling.slash", bundle: Bundle.main)
                    .font(.title2)
                    .padding(12)
                    .background(Color.white)
                    .foregroundColor(Color.red)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .padding(.trailing, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

@main
struct CaBotApp: App {
    @Environment(\.scenePhase) var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    #if ATTEND
    var modelData: CaBotAppModel = CaBotAppModel(preview: false, mode: .Advanced)
    #elseif USER
    var modelData: CaBotAppModel = CaBotAppModel(preview: false, mode: .Normal)
    #endif

    init() {
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(modelData)
#if ATTEND
                .overlay(SuitcaseStatusView().environmentObject(modelData), alignment: .topTrailing)
#endif
        }.onChange(of: scenePhase) { newScenePhase in
            NSLog( "<ScenePhase to \(newScenePhase)>" )

            modelData.onChange(of: newScenePhase)

            switch newScenePhase {
            case .background:
                break
            case .inactive:
                break
            case .active:
                let isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
                if isVoiceOverRunning {
                    modelData.stopSpeak()
                }
                ResourceManager.shared.invalidate()
                if modelData.suitcaseConnected {
                    modelData.loadFromServer()
                }
                break
            @unknown default:
                break
            }
        }
    }
}


class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        Logging.startLog(true)
        let versionNo = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
        let buildNo = Bundle.main.infoDictionary!["CFBundleVersion"] as! String
        let commitHash = Bundle.main.infoDictionary!["GitCommitHash"] as! String
        NSLog( "<Launched> Version: \(versionNo) (\(buildNo)) \(commitHash) - \(CaBotServiceBLE.CABOT_BLE_VERSION)")
        
        NSSetUncaughtExceptionHandler { exception in
            let stacktrace = exception.callStackSymbols.joined(separator:"\n")
            NSLog( "<UncaughtException> \n\(exception)\n\(stacktrace)")
        }
        
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        NSLog( "<Terminate>" )
        Logging.stopLog()
    }
}

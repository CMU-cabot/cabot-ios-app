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
            #if ATTEND
            Image(modelData.suitcaseFeatures.selectedHandleSide.imageName, bundle: Bundle.main)
                .resizable()
                .scaledToFit()
                .frame(width: 33, height: 33)
                .padding(7)
                .background(Color.white)
                .foregroundColor(modelData.suitcaseConnected ? modelData.suitcaseFeatures.selectedHandleSide.color : Color.gray)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            #endif
            if modelData.suitcaseConnected {
                Image(systemName: "suitcase.rolling")
                    .font(.title2)
                    .padding(12)
                    .background(Color.white)
                    .foregroundColor(Color.blue)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .padding(.trailing, 8)
                    .overlay(Text(modelData.iconText).foregroundColor(modelData.iconTextColor).font(.footnote).fontWeight(.bold).background(.white.opacity(0.8)).offset(y: 0).padding(.leading, -8), alignment: .center)
                    .opacity(modelData.reconnecting ? 0 : 1)
            } else {
                Image("suitcase.rolling.slash", bundle: Bundle.main)
                    .font(.title2)
                    .padding(12)
                    .background(Color.white)
                    .foregroundColor(Color.red)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    .padding(.trailing, 8)
                    .opacity(modelData.reconnecting ? 0 : 1)
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
                #if USER
                .overlay(ZoomMeetingIndicatorView().environmentObject(modelData), alignment: .topLeading)
                #endif
                .overlay(SuitcaseStatusView().environmentObject(modelData), alignment: .topTrailing)
        }.onChange(of: scenePhase) { newScenePhase in
            Logging.checkLogDate()
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
        NSLog("<iOS> Version: \(UIDevice.current.systemVersion)")
        
        NSSetUncaughtExceptionHandler { exception in
            let stacktrace = exception.callStackSymbols.joined(separator:"\n")
            NSLog( "<UncaughtException> \n\(exception)\n\(stacktrace)")
        }

        #if USER
        ZoomMeetingController.shared.prepare()
        #endif
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        #if USER
        ZoomMeetingController.shared.applicationWillResignActive()
        #endif
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        #if USER
        ZoomMeetingController.shared.applicationDidBecomeActive()
        #endif
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        #if USER
        ZoomMeetingController.shared.applicationDidEnterBackground()
        #endif
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        #if USER
        ZoomMeetingController.shared.applicationWillTerminate()
        #endif
        NSLog( "<Terminate>" )
        Logging.stopLog()
    }
}

#if USER
struct ZoomMeetingIndicatorView: View {
    @EnvironmentObject var modelData: CaBotAppModel

    private var indicator: (label: String, imageName: String, color: Color)? {
        switch modelData.zoomMeetingStatusText {
        case "authenticating", "joining":
            return (NSLocalizedString("Zoom Connecting", comment: "Zoom meeting indicator while connecting"), "dot.radiowaves.left.and.right", .orange)
        case "in_meeting":
            return (NSLocalizedString("Zoom In Meeting", comment: "Zoom meeting indicator while in meeting"), "video.fill.badge.checkmark", .green)
        case "leaving":
            return (NSLocalizedString("Zoom Leaving", comment: "Zoom meeting indicator while leaving"), "video.slash.fill", .gray)
        default:
            return nil
        }
    }

    var body: some View {
        Group {
            if let indicator {
                Label(indicator.label, systemImage: indicator.imageName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial)
                    .foregroundColor(indicator.color)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}
#endif

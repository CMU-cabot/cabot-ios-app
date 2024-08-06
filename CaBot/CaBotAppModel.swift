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

import Collections
import CoreData
import SwiftUI
import Foundation
import CoreBluetooth
import CoreLocation
import UserNotifications
import Combine
import os.log
import HLPDialog

enum GrantState {
    case Init
    case Granted
    case Denied
    case Off
}

enum DisplayedScene {
    case Onboard
    case ResourceSelect
    case App

    var text: Text {
        get {
            switch self {
            case .Onboard:
                return Text("")
            case .ResourceSelect:
                return Text("SELECT_RESOURCE")
            case .App:
                return Text("MAIN_MENU")
            }
        }
    }
}

enum ModeType: String, CaseIterable{
    case Normal = "Normal"
    case Advanced = "Advanced"
    case Debug  = "Debug"
}

enum VoiceMode: String, CaseIterable{
    case User = "User"
    case Attend = "Attend"
}

enum SpeechPriority: String, CaseIterable {
    case Robot = "Robot"
    case App = "App"
}

class FallbackService: CaBotServiceProtocol {
    private let services: [CaBotServiceProtocol]
    private var selectedService: CaBotServiceProtocol?

    init(services: [CaBotServiceProtocol]) {
        self.services = services
    }

    func select(service: CaBotServiceProtocol) {
        self.selectedService = service
    }

    private func getService() -> CaBotServiceProtocol? {
        if let service = self.selectedService {
            if service.isConnected() {
                return service
            }
        }
        for service in services {
            if service.isConnected() {
                return service
            }
        }
        return nil
    }

    func isConnected() -> Bool {
        for service in services {
            if service.isConnected() {
                return true
            }
        }
        return false
    }

    func activityLog(category: String, text: String, memo: String) -> Bool {
        guard let service = getService() else { return false }
        return service.activityLog(category: category, text: text, memo: memo)
    }

    func send(destination: String) -> Bool {
        guard let service = getService() else { return false }
        return service.send(destination: destination)
    }

    func summon(destination: String) -> Bool {
        guard let service = getService() else { return false }
        return service.summon(destination: destination)
    }

    func manage(command: CaBotManageCommand, param: String? = nil) -> Bool {
        guard let service = getService() else { return false }
        return service.manage(command: command, param: param)
    }
    
    func log_request(request: Dictionary<String, String>) -> Bool {
        guard let service = getService() else { return false }
        return service.log_request(request: request)
    }

    func share(user_info: SharedInfo) -> Bool {
        guard let service = getService() else { return false }
        return service.share(user_info: user_info)
    }
}

final class DetailSettingModel: ObservableObject, NavigationSettingProtocol {
    private let startSoundKey = "startSoundKey"
    private let arrivedSoundKey = "arrivedSoundKey"
    private let speedUpSoundKey = "speedUpSoundKey"
    private let speedDownSoundKey = "speedDownSoundKey"
    private let obstacleAheadSoundKey = "obstacleAheadSoundKey"
    private let browserCloseDelayKey = "browserCloseDelayKey"
    private let enableSubtourOnHandleKey = "enableSubtourOnHandleKey"
    private let showContentWhenArriveKey = "showContentWhenArriveKey"
    private let speechPriorityKey = "speechPriorityKey"
    
    init() {
        if let startSound = UserDefaults.standard.value(forKey: startSoundKey) as? String {
            self.startSound = startSound
        }
        if let arrivedSound = UserDefaults.standard.value(forKey: arrivedSoundKey) as? String {
            self.arrivedSound = arrivedSound
        }
        if let speedUpSound = UserDefaults.standard.value(forKey: speedUpSoundKey) as? String {
            self.speedUpSound = speedUpSound
        }
        if let speedDownSound = UserDefaults.standard.value(forKey: speedDownSoundKey) as? String {
            self.speedDownSound = speedDownSound
        }
        if let browserCloseDelay = UserDefaults.standard.value(forKey: browserCloseDelayKey) as? Double {
            self.browserCloseDelay = browserCloseDelay
        }
        if let enableSubtourOnHandle = UserDefaults.standard.value(forKey: enableSubtourOnHandleKey) as? Bool {
            self.enableSubtourOnHandle = enableSubtourOnHandle
        }
        if let showContentWhenArrive = UserDefaults.standard.value(forKey: showContentWhenArriveKey) as? Bool {
            self.showContentWhenArrive = showContentWhenArrive
        }
        if let speechPriorityString = UserDefaults.standard.value(forKey: speechPriorityKey) as? String {
            if let speechPriority = SpeechPriority(rawValue: speechPriorityString) {
                self.speechPriority = speechPriority
            }
        }
    }
        
    @Published var startSound: String = "/System/Library/Audio/UISounds/nano/3rdParty_Success_Haptic.caf" {
        didSet {
            UserDefaults.standard.setValue(startSound, forKey: startSoundKey)
            UserDefaults.standard.synchronize()
        }
    }
    @Published var arrivedSound: String = "/System/Library/Audio/UISounds/nano/HummingbirdNotification_Haptic.caf" {
        didSet {
            UserDefaults.standard.setValue(arrivedSound, forKey: arrivedSoundKey)
            UserDefaults.standard.synchronize()
        }
    }
    @Published var speedUpSound: String = "/System/Library/Audio/UISounds/nano/WalkieTalkieActiveStart_Haptic.caf" {
        didSet {
            UserDefaults.standard.setValue(speedUpSound, forKey: speedUpSoundKey)
            UserDefaults.standard.synchronize()
        }
    }
    @Published var speedDownSound: String = "/System/Library/Audio/UISounds/nano/ET_RemoteTap_Receive_Haptic.caf" {
        didSet {
            UserDefaults.standard.setValue(speedDownSound, forKey: speedDownSoundKey)
            UserDefaults.standard.synchronize()
        }
    }
    @Published var obstacleAheadSound: String = "/System/Library/Audio/UISounds/nano/MediaPaused.caf" {
        didSet {
            UserDefaults.standard.setValue(obstacleAheadSound, forKey: obstacleAheadSoundKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    @Published var browserCloseDelay: Double = 1.2 {
        didSet {
            UserDefaults.standard.setValue(browserCloseDelay, forKey: browserCloseDelayKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    @Published var enableSubtourOnHandle: Bool = false{
        didSet {
            UserDefaults.standard.setValue(enableSubtourOnHandle, forKey: enableSubtourOnHandleKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    @Published var showContentWhenArrive: Bool = false {
        didSet {
            UserDefaults.standard.setValue(showContentWhenArrive, forKey: showContentWhenArriveKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    @Published var speechPriority:SpeechPriority = .App {
        didSet {
            UserDefaults.standard.setValue(speechPriority.rawValue, forKey: speechPriorityKey)
            UserDefaults.standard.synchronize()
        }
    }

    var audioPlayer: AVAudioPlayer = AVAudioPlayer()
    func playAudio(file: String) {
        DispatchQueue.main.async {
            let fileURL: URL = URL(fileURLWithPath: file)
            do {
                self.audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
                self.audioPlayer.play()
            } catch {
                print("\(error)")
            }
        }
    }
}

class AddressCandidate {
    let addresses: [String]
    private var index:Int = 1
    init(addresses: [String]) {
        self.addresses = addresses
    }
    func getCurrent() -> String {
        addresses[index % addresses.count]
    }
    func getNext() -> String {
        index += 1
        return getCurrent()
    }
}

final class CaBotAppModel: NSObject, ObservableObject, CaBotServiceDelegateBLE, TourManagerDelegate, CLLocationManagerDelegate, CaBotTTSDelegate, LogReportModelDelegate, UNUserNotificationCenterDelegate{
    private let DEFAULT_LANG = "en"
    
    private let selectedResourceKey = "SelectedResourceKey"
    private let selectedResourceLangKey = "selectedResourceLangKey"
    private let selectedVoiceKey = "SelectedVoiceKey"
    private let isTTSEnabledKey = "isTTSEnabledKey"
    private let speechRateKey = "speechRateKey"
    private let attendSpeechRateKey = "attendSpeechRateKey"
    private let connectionTypeKey = "connection_type"
    private let teamIDKey = "team_id"
    private let socketAddrKey = "socket_url"
    private let rosSocketAddrKey = "ros_socket_url"
    private let primaryAddrKey = "primary_ip_address"
    private let secondaryAddrKey = "secondary_ip_address"
    private let menuDebugKey = "menu_debug"
    private let noSuitcaseDebugKey = "noSuitcaseDebugKey"
    private let modeTypeKey = "modeTypeKey"
    private let notificationCenterID = "cabot_state_notification"
    
    let detailSettingModel: DetailSettingModel

    @Published var versionMatchedBLE: Bool = false
    @Published var serverBLEVersion: String? = nil
    @Published var versionMatchedTCP: Bool = false
    @Published var serverTCPVersion: String? = nil

    @Published var debugSystemStatusLevel: CaBotSystemLevel = .Unknown
    @Published var debugDeviceStatusLevel: DeviceStatusLevel = .Unknown

    @Published var locationState: GrantState = .Init {
        didSet {
            self.checkOnboardCondition()
        }
    }
    @Published var bluetoothState: CBManagerState = .unknown {
        didSet {
            self.checkOnboardCondition()
        }
    }
    @Published var notificationState: GrantState = .Init {
        didSet {
            self.checkOnboardCondition()
        }
    }
    func checkOnboardCondition() {
        if (self.bluetoothState == .poweredOn || self.bluetoothState == .poweredOff) &&
            self.notificationState != .Init &&
            self.locationState != .Init
            {
            if authRequestedByUser {
                withAnimation() {
                    self.displayedScene = .App
                }
            } else {
                self.displayedScene = .App
            }
        }
        if self.displayedScene == .ResourceSelect {
            guard let value = UserDefaults.standard.value(forKey: ResourceSelectView.resourceSelectedKey) as? Bool else { return }
            if value {
                displayedScene = .App
            }
        }
    }
    @Published var displayedScene: DisplayedScene = .Onboard
    var authRequestedByUser: Bool = false

    @Published var resource: Resource? = nil {
        didSet {
            if let resource = resource {

                NSLog("resource.identifier = \(resource.identifier)")
                UserDefaults.standard.setValue(resource.identifier, forKey: selectedResourceKey)
                if let langOverride = resource.langOverride {
                    NSLog("resource.langOverride = \(langOverride)")
                    UserDefaults.standard.setValue(langOverride, forKey: selectedResourceLangKey)
                }
                UserDefaults.standard.synchronize()
                
                _ = self.fallbackService.manage(command: .lang, param: resource.lang)
            }
        }
    }

    var resourceLang: String {
        get {
            resource?.lang ?? DEFAULT_LANG
        }
    }

    @Published var isTTSEnabledForAdvanced: Bool = true {
        didSet {
            UserDefaults.standard.setValue(isTTSEnabledForAdvanced, forKey: isTTSEnabledKey)
            UserDefaults.standard.synchronize()
        }
    }

    @Published var attendVoice: Voice? = nil {
        didSet {
            if let id = attendVoice?.AVvoice.identifier {
                let key = "\(selectedVoiceKey)_\(resource?.locale.identifier ?? "en-US")"
                UserDefaults.standard.setValue(id, forKey: key)
                UserDefaults.standard.synchronize()
            }
        }
    }
    
    @Published var userVoice: Voice? = nil {
        didSet {
            if let id = userVoice?.AVvoice.identifier {
                let key = "\(selectedVoiceKey)_\(resource?.locale.identifier ?? "en-US")"
                UserDefaults.standard.setValue(id, forKey: key)
                UserDefaults.standard.synchronize()
            }
        }
    }
    
    #if ATTEND
    @Published var voiceSetting: VoiceMode = .Attend {
        didSet {
            self.updateTTS()
        }
    }
    #elseif USER
    @Published var voiceSetting: VoiceMode = .User {
        didSet {
            self.updateTTS()
        }
    }
    #endif
    
    func initTTS()
    {
        if let resource = self.resource {
            let key = "\(selectedVoiceKey)_\(resource.locale.identifier)"
            if let id = UserDefaults.standard.value(forKey: key) as? String {
                self.userVoice = TTSHelper.getVoice(by: id)
            } else {
                self.userVoice = TTSHelper.getVoices(by: resource.locale)[0]
            }
            if let id = UserDefaults.standard.value(forKey: key) as? String {
                self.attendVoice = TTSHelper.getVoice(by: id)
            } else {
                self.attendVoice = TTSHelper.getVoices(by: resource.locale)[0]
            }
        }
        
        self.updateTTS()
    }
    
    func updateVoice() {
        if let resource = self.resource {
            let key = "\(selectedVoiceKey)_\(resource.locale.identifier)"
            
            if(voiceSetting == .User){
                if let id = UserDefaults.standard.value(forKey: key) as? String {
                    self.userVoice = TTSHelper.getVoice(by: id)
                } else {
                    self.userVoice = TTSHelper.getVoices(by: resource.locale)[0]
                }
            } else if(voiceSetting == .Attend) {
                if let id = UserDefaults.standard.value(forKey: key) as? String {
                    self.attendVoice = TTSHelper.getVoice(by: id)
                } else {
                    self.attendVoice = TTSHelper.getVoices(by: resource.locale)[0]
                }
            }
        }
    }
    
    func updateTTS() {
        if(self.voiceSetting == .User){
            self.tts.rate = self.userSpeechRate
            self.tts.voice = self.userVoice?.AVvoice
        } else if(voiceSetting == .Attend) {
            self.tts.rate = self.attendSpeechRate
            self.tts.voice = self.attendVoice?.AVvoice
        }
    }

    @Published var attendSpeechRate: Double = 0.5 {
        didSet {
            UserDefaults.standard.setValue(attendSpeechRate, forKey: attendSpeechRateKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    @Published var userSpeechRate: Double = 0.5 {
        didSet {
            UserDefaults.standard.setValue(userSpeechRate, forKey: speechRateKey)
            UserDefaults.standard.synchronize()
        }
    }

    @Published var suitcaseConnectedBLE: Bool = false {
        didSet {
            self.suitcaseConnected = self.suitcaseConnectedBLE || self.suitcaseConnectedTCP || self.noSuitcaseDebug
        }
    }
    @Published var suitcaseConnectedTCP: Bool = false {
        didSet {
            self.suitcaseConnected = self.suitcaseConnectedBLE || self.suitcaseConnectedTCP || self.noSuitcaseDebug
        }
    }
    @Published var suitcaseConnected: Bool = false {
        didSet {
            if !self.suitcaseConnected {
                self.deviceStatus = DeviceStatus()
                self.systemStatus.clear()
                self.batteryStatus = BatteryStatus()
                self.touchStatus = TouchStatus()
            }
        }
    }

    @Published var connectionType:ConnectionType = .TCP{
        didSet{
            UserDefaults.standard.setValue(connectionType.rawValue, forKey: connectionTypeKey)
            UserDefaults.standard.synchronize()
            switch(connectionType) {
            case .BLE:
                fallbackService.select(service: bleService)
            case .TCP:
                fallbackService.select(service: tcpService)
            }
        }
    }
    @Published var teamID: String = "" {
        didSet {
            UserDefaults.standard.setValue(teamID, forKey: teamIDKey)
            UserDefaults.standard.synchronize()
            bleService.stopAdvertising()
            bleService.teamID = self.teamID
            bleService.startAdvertising()
        }
    }
    @Published var primaryAddr: String = "172.20.10.7" {
        didSet {
            UserDefaults.standard.setValue(primaryAddr, forKey: primaryAddrKey)
            UserDefaults.standard.synchronize()
            updateNetworkConfig()
        }
    }
    @Published var secondaryAddr: String = "" {
        didSet {
            UserDefaults.standard.setValue(secondaryAddr, forKey: secondaryAddrKey)
            UserDefaults.standard.synchronize()
            updateNetworkConfig()
        }
    }
    let socketPort: String = "5000"
    let rosPort: String = "9091"
    @Published var menuDebug: Bool = false {
        didSet {
            UserDefaults.standard.setValue(menuDebug, forKey: menuDebugKey)
            UserDefaults.standard.synchronize()
        }
    }
    @Published var noSuitcaseDebug: Bool = false {
        didSet {
            UserDefaults.standard.setValue(noSuitcaseDebug, forKey: noSuitcaseDebugKey)
            UserDefaults.standard.synchronize()
            suitcaseConnected = true
        }
    }
    @Published var modeType:ModeType = .Normal{
        didSet {
            UserDefaults.standard.setValue(modeType.rawValue, forKey: modeTypeKey)
            UserDefaults.standard.synchronize()
        }
    }

    @Published var isContentPresenting: Bool = false
    @Published var isConfirmingSummons: Bool = false
    @Published var contentURL: URL? = nil
    @Published var tourUpdated: Bool = false

    @Published var deviceStatus: DeviceStatus = DeviceStatus()
    @Published var showingDeviceStatusNotification: Bool = false
    @Published var showingDeviceStatusMenu: Bool = false
    @Published var systemStatus: SystemStatusData = SystemStatusData()
    @Published var showingSystemStatusNotification: Bool = false
    @Published var showingSystemStatusMenu: Bool = false
    @Published var batteryStatus: BatteryStatus = BatteryStatus()
    @Published var touchStatus: TouchStatus = TouchStatus()
    @Published var resourceDownload: ResourceDownload
    @Published var userInfo: UserInfoBuffer

    private var addressCandidate: AddressCandidate
    private var bleService: CaBotServiceBLE
    private var tcpService: CaBotServiceTCP
    private var fallbackService: FallbackService
    private let tts: CaBotTTS
    private var willSpeakArriveMessage: Bool = false
    private var touchStartTime: CFAbsoluteTime = 0
    private var announceToPushRightButtonTime: CFAbsoluteTime = 0
    private var shouldNoAnnounceToPushRightButton: Bool = false
    private var lastUpdated: Int64 = 0
    let logList: LogReportModel = LogReportModel()
    let preview: Bool
    let resourceManager: ResourceManager
    let tourManager: TourManager
    let dialogViewHelper: DialogViewHelper
    private let feedbackGenerator = UINotificationFeedbackGenerator()
    let notificationCenter = UNUserNotificationCenter.current()

    let locationManager: CLLocationManager
    let locationUpdateTimeLimit: CFAbsoluteTime = 60*15
    var locationUpdateStartTime: CFAbsoluteTime = 0
    var audioAvailableEstimate: Bool = false

    convenience override init() {
        self.init(preview: true)
    }

    init(preview: Bool, mode: ModeType = .Normal) {
        self.modeType = mode
        self.detailSettingModel = DetailSettingModel()
        self.preview = preview
        self.tts = CaBotTTS(voice: nil)
        let bleService = CaBotServiceBLE(with: self.tts, mode: mode)
        let tcpService = CaBotServiceTCP(with: self.tts, mode: mode)
        self.bleService = bleService
        self.tcpService = tcpService
        self.fallbackService = FallbackService(services: [bleService, tcpService])
        self.resourceManager = ResourceManager(preview: preview)
        self.tourManager = TourManager(setting: self.detailSettingModel)
        self.dialogViewHelper = DialogViewHelper()
        self.locationManager =  CLLocationManager()
        self.resourceDownload = ResourceDownload()
        self.userInfo = UserInfoBuffer(modelData: nil)

        // initialize connection type
        var connectionType: ConnectionType = .BLE
        if let conntypestr = UserDefaults.standard.value(forKey: connectionTypeKey) as? String, let storedType = ConnectionType(rawValue: conntypestr){
            connectionType = storedType
        }
        switch(connectionType) {
        case .BLE:
            fallbackService.select(service: bleService)
        case .TCP:
            fallbackService.select(service: tcpService)
        }
        self.connectionType = connectionType
        self.addressCandidate = AddressCandidate(addresses: [""])  // dummy
        super.init()

        self.tts.delegate = self
        self.logList.delegate = self

        if let selectedLang = UserDefaults.standard.value(forKey: selectedResourceLangKey) as? String {
            self.resource?.lang = selectedLang
            self.updateVoice()
        }
        if let groupID = UserDefaults.standard.value(forKey: teamIDKey) as? String {
            self.teamID = groupID
        }
        if let primaryAddr = UserDefaults.standard.value(forKey: primaryAddrKey) as? String{
            self.primaryAddr = primaryAddr
        }
        if let secondaryAddr = UserDefaults.standard.value(forKey: secondaryAddrKey) as? String{
            self.secondaryAddr = secondaryAddr
        }
        updateNetworkConfig()
        if let menuDebug = UserDefaults.standard.value(forKey: menuDebugKey) as? Bool {
            self.menuDebug = menuDebug
        }
        if let attendSpeechRate = UserDefaults.standard.value(forKey: attendSpeechRateKey) as? Double {
            self.attendSpeechRate = attendSpeechRate
        }
        if let speechRate = UserDefaults.standard.value(forKey: speechRateKey) as? Double {
            self.userSpeechRate = speechRate
        }
        if let modeType = UserDefaults.standard.value(forKey: modeTypeKey) as? String {
            self.modeType = ModeType(rawValue: modeType)!
        }
        if let isTTSEnabled = UserDefaults.standard.value(forKey: isTTSEnabledKey) as? Bool {
            self.isTTSEnabledForAdvanced = isTTSEnabled
        }

        // services
        self.locationManager.delegate = self
        self.locationManagerDidChangeAuthorization(self.locationManager)

        self.bleService.delegate = self
        self.bleService.startIfAuthorized()

        self.tcpService.delegate = self
        self.tcpService.start(addressCandidate: addressCandidate, port: socketPort)

        self.notificationCenter.getNotificationSettings { settings in
            if settings.alertSetting == .enabled &&
                settings.soundSetting == .enabled {
                self.notificationState = .Granted
            }
            self.checkOnboardCondition()
        }

        // tour manager
        self.tourManager.delegate = self

        // Error/Warning Notification
        self.notificationCenter.delegate = self

        NSSetUncaughtExceptionHandler { exception in
            NSLog("\(exception)")
            NSLog("\(exception.reason ?? "")")
            NSLog("\(exception.callStackSymbols)")
        }
        
        self.userInfo.modelData = self
        
        self.initTTS()
    }

    func updateNetworkConfig() {
        self.addressCandidate = AddressCandidate(addresses: [primaryAddr, secondaryAddr])
    }

    func getCurrentAddress() -> String {
        self.addressCandidate.getCurrent()
    }

    func onChange(of newScenePhase: ScenePhase) {
        switch newScenePhase {
        case .background:
            resetAudioSession()
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.startUpdatingLocation()
            break
        case .inactive:
            break
        case .active:
            audioAvailableEstimate = true
            self.initNotification()
            self.resetAudioSession()
            locationManager.stopUpdatingLocation()
            break
        @unknown default:
            break
        }
    }

    func initNotification() {
        let generalCategory = UNNotificationCategory(identifier: "GENERAL",
                                                     actions: [],
                                                     intentIdentifiers: [],
                                                     options: [])
        notificationCenter.setNotificationCategories([generalCategory])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.sound, .banner])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if self.showingDeviceStatusNotification{
            self.showingDeviceStatusMenu = true
        } else if self.showingSystemStatusNotification{
            self.showingSystemStatusMenu = true
        }
        completionHandler()
    }

    private func removeNotification() -> Void {
        self.showingDeviceStatusNotification = false
        self.showingSystemStatusNotification = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [self.notificationCenterID])
        }
    }

    private func pushSystemState() -> Void {
        removeNotification()
        let systemStatusString = CustomLocalizedString(self.systemStatus.summary.text, lang: self.resourceLang)
        let notificationTitle = CustomLocalizedString("SYSTEM_ERROR_ALERT%@", lang: self.resourceLang, systemStatusString)
        let notificationMessage = "CHECK_SYSTEM_STATUS"
        let content = UNMutableNotificationContent()
        content.title = NSString.localizedUserNotificationString(forKey: notificationTitle, arguments: nil)
        content.body = NSString.localizedUserNotificationString(forKey: notificationMessage, arguments: nil)
        content.sound = UNNotificationSound.defaultCritical
        if (self.systemStatus.summary == .Error){
            self.feedbackGenerator.notificationOccurred(.error)
        } else {
            self.feedbackGenerator.notificationOccurred(.warning)
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: (0.1), repeats: false)
        let request = UNNotificationRequest(identifier: self.notificationCenterID, content: content, trigger: trigger)

        notificationCenter.add(request) { (error : Error?) in
            if let theError = error {
                print(theError.localizedDescription)
            }
        }
        self.showingSystemStatusNotification = true
    }

    private func pushDeviceState() -> Void {
        removeNotification()
        let deviceStatusString = CustomLocalizedString(self.deviceStatus.level.rawValue, lang: self.resourceLang)
        let notificationTitle = CustomLocalizedString("DEVICE_ERROR_ALERT%@", lang: self.resourceLang, deviceStatusString)
        let notificationMessage = "CHECK_DEVICE_STATUS"
        let content = UNMutableNotificationContent()
        content.title = NSString.localizedUserNotificationString(forKey: notificationTitle, arguments: nil)
        content.body = NSString.localizedUserNotificationString(forKey: notificationMessage, arguments: nil)
        content.sound = UNNotificationSound.defaultCritical
        if self.deviceStatus.level == .Error {
            self.feedbackGenerator.notificationOccurred(.error)
        } else {
            self.feedbackGenerator.notificationOccurred(.warning)
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: (0.1), repeats: false)
        let request = UNNotificationRequest(identifier: self.notificationCenterID, content: content, trigger: trigger)

        notificationCenter.add(request) { (error : Error?) in
            if let theError = error {
                print(theError.localizedDescription)
            }
        }
        self.showingDeviceStatusNotification = true
    }

    // MARK: onboading

    func requestLocationAuthorization() {
        self.authRequestedByUser = true
        self.locationManager.requestAlwaysAuthorization()
    }

    func requestBluetoothAuthorization() {
        self.authRequestedByUser = true
        self.bleService.start()
        self.bleService.startAdvertising()
    }

    func requestNotificationAuthorization() {
        self.authRequestedByUser = true
        self.notificationCenter.requestAuthorization(options:[UNAuthorizationOptions.alert,
                                             UNAuthorizationOptions.sound]) {
            (granted, error) in
            DispatchQueue.main.async {
                self.notificationState = granted ? .Granted : .Denied
            }
        }
    }

    func tcpServiceRestart() {
        if !self.tcpService.isSocket() {
           self.tcpService.start(addressCandidate: addressCandidate, port: socketPort)
        }
    }
 
    // MARK: CaBotTTSDelegate

    func activityLog(category: String, text: String, memo: String) {
        _ = self.fallbackService.activityLog(category: category, text: text, memo: memo)
    }

    func share(user_info: SharedInfo) {
        _ = self.fallbackService.share(user_info: user_info)
    }

    // MARK: LogReportModelDelegate
    
    func refreshLogList() {
        let request = [
            "type": CaBotLogRequestType.list.rawValue
        ]
        _ = self.fallbackService.log_request(request: request)
    }
    
    func isSuitcaseConnected() -> Bool {
        return self.suitcaseConnected
    }
    
    func requestDetail(log_name: String) {
        let request = [
            "type": CaBotLogRequestType.detail.rawValue,
            "log_name": log_name
        ]
        _ = self.fallbackService.log_request(request: request)
    }
    
    func submitLogReport(log_name: String, title: String, detail: String) {
        let request = [
            "type": CaBotLogRequestType.report.rawValue,
            "log_name": log_name,
            "title": title,
            "detail": detail
        ]
        _ = self.fallbackService.log_request(request: request)
    }

    // MARK: LocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch(manager.authorizationStatus) {
        case .notDetermined:
            locationState = .Init
        case .restricted:
            locationState = .Denied
        case .denied:
            locationState = .Denied
        case .authorizedAlways:
            locationState = .Granted
        case .authorizedWhenInUse:
            locationState = .Denied
        @unknown default:
            locationState = .Off
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if suitcaseConnected {
            locationUpdateStartTime = 0
            return
        }

        if locationUpdateStartTime == 0 {
            locationUpdateStartTime = CFAbsoluteTimeGetCurrent()
        }
        if CFAbsoluteTimeGetCurrent() - locationUpdateStartTime > locationUpdateTimeLimit {
            NSLog("Location update time without Bluetooth connection exceeds the limit: %.2f/%.2f sec", CFAbsoluteTimeGetCurrent() - locationUpdateStartTime, locationUpdateTimeLimit)
            manager.stopUpdatingLocation()
            audioAvailableEstimate = false

        } else {
            NSLog("Location update time without Bluetooth connection: %.2f sec", CFAbsoluteTimeGetCurrent() - locationUpdateStartTime)
        }
    }



    // MARK: public functions

    func resetAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback,
                                         mode: .spokenAudio,
                                         options: [])
        } catch {
            NSLog("audioSession category weren't set because of an error. \(error)")
        }
        do {
            try audioSession.setActive(true, options: [])
        } catch {
            NSLog("audioSession cannot be set active. \(error)")
        }
    }

    func open(content: URL) {
        contentURL = content
        isContentPresenting = true
    }

    func summon(destination: String) -> Bool {
        DispatchQueue.main.async {
            print("Show modal waiting")
            NavUtil.showModalWaiting(withMessage: CustomLocalizedString("processing...", lang: self.resourceLang))
        }
        if self.fallbackService.summon(destination: destination) || self.noSuitcaseDebug {
            self.speak(CustomLocalizedString("Sending the command to the suitcase", lang: self.resourceLang)) {}
            DispatchQueue.main.async {
                print("hide modal waiting")
                NavUtil.hideModalWaiting()
            }
            return true
        } else {
            DispatchQueue.main.async {
                print("hide modal waiting")
                NavUtil.hideModalWaiting()
            }
            DispatchQueue.main.async {
                let message = CustomLocalizedString("Suitcase may not be connected", lang: self.resourceLang)

                self.speak(message) {}
            }
            return false
        }
    }
    
    func addSubTour(tour: Tour) -> Void {
        tourManager.addSubTour(tour: tour)
        if tourManager.proceedToNextDestination() {
            self.playAudio(file: self.detailSettingModel.startSound)
        }
    }

    func skipDestination() -> Void {
        guard tourManager.hasDestination else { return }

        let skip = tourManager.skipDestination()
        self.stopSpeak()
        let announce = CustomLocalizedString("Skip Message %@", lang: self.resourceLang, skip.title.pron)
        self.tts.speak(announce){
        }
    }

    func speak(_ text:String, callback: @escaping () -> Void) {
        if (preview) {
            print("previewing speak - \(text)")
        } else {
            self.tts.speak(text, callback: callback)
        }
    }

    func stopSpeak() {
        self.tts.stop(false)
    }

    func playSample(mode: VoiceMode){
        if(self.modeType == .Normal){
            self.tts.rate = self.userSpeechRate
            self.tts.voice = self.userVoice?.AVvoice
            self.tts.speak(CustomLocalizedString("Hello Suitcase!", lang: self.resourceLang), force:true) {_ in
            }
        } else {
            if(mode == .User){
                self.tts.rate = self.userSpeechRate
                self.tts.voice = self.userVoice?.AVvoice
            } else if(mode == .Attend) {
                self.tts.rate = self.attendSpeechRate
                self.tts.voice = self.attendVoice?.AVvoice
            }
            self.tts.speakForAdvanced(CustomLocalizedString("Hello Suitcase!", lang: self.resourceLang), force:true) {_ in
            }
        }
        
        self.updateTTS()
    }

    func playAudio(file: String) {
        detailSettingModel.playAudio(file: file)
    }

    func needToStartAnnounce(wait: Bool) {
        let delay = wait ? self.detailSettingModel.browserCloseDelay : 0
        self.announceToPushRightButtonTime = CFAbsoluteTimeGetCurrent()
        self.shouldNoAnnounceToPushRightButton = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.speak(CustomLocalizedString("You can proceed by pressing the right button of the suitcase handle", lang: self.resourceLang)) {
            }
        }
    }

    func systemManageCommand(command: CaBotManageCommand) {
        if self.fallbackService.manage(command: command) {
            switch(command) {
            case .poweroff, .reboot:
                deviceStatus.level = .Unknown
                systemStatus.level = .Unknown
                break
            case .start:
                systemStatus.level = .Activating
            case .stop:
                systemStatus.level = .Deactivating
                break
            case .lang:
                break
            case .restart_localization:
                break
            }
            systemStatus.components.removeAll()
            objectWillChange.send()
        }
    }

    func debugCabotArrived() {
        self.cabot(service: self.bleService, notification: .arrived)
    }

    func debugCabotSystemStatus(systemStatusFile: String){
        let path = Bundle.main.resourceURL!.appendingPathComponent("PreviewResource")
                .appendingPathComponent(systemStatusFile)
        let fm = FileManager.default
        let data = fm.contents(atPath: path.path)!
        let status = try! JSONDecoder().decode(SystemStatus.self, from: data)
        self.cabot(service: self.tcpService, systemStatus: status)
    }

    func debugCabotDeviceStatus(systemStatusFile: String){
        let path = Bundle.main.resourceURL!.appendingPathComponent("PreviewResource")
                .appendingPathComponent(systemStatusFile)
        let fm = FileManager.default
        let data = fm.contents(atPath: path.path)!
        let status = try! JSONDecoder().decode(DeviceStatus.self, from: data)
        self.cabot(service: self.tcpService, deviceStatus: status)
    }

    func share(tour: Tour) {
        self.share(user_info: SharedInfo(type: .OverrideTour, value: tour.id))
        userInfo.clear()
    }

    func share(destination: Destination, clear: Bool = true) {
        if let value = destination.value {
            self.share(user_info: SharedInfo(type: .OverrideDestination, value: value, flag1: clear))
            userInfo.clear()
        }
    }

    // MARK: TourManagerDelegate
    func tourUpdated(manager: TourManager) {
        tourUpdated = true
        UIApplication.shared.isIdleTimerDisabled = manager.hasDestination
        self.activityLog(category: "tour-text", text: manager.title.text, memo: manager.title.pron)
        self.share(user_info: SharedInfo(type: .Tour, value: manager.title.text))
        self.share(user_info: SharedInfo(type: .CurrentDestination, value: manager.currentDestination?.title.text ?? ""))
        self.share(user_info: SharedInfo(type: .NextDestination, value: manager.nextDestination?.title.text ?? ""))
        self.share(user_info: SharedInfo(type: .Destinations, value: manager.destinations.map { $0.title.text }.joined(separator: ",")))
    }

    func clearAll(){
        self.stopSpeak()
        self.tourManager.clearAllDestinations()
    }

    func tour(manager: TourManager, destinationChanged destination: Destination?) {
        if let dest = destination {
            if let dest_id = dest.value {
                if !send(destination: dest_id) {
                    manager.cannotStartCurrent()
                } else {
                    // cancel all announcement
                    var delay = self.tts.isSpeaking ? 1.0 : 0

                    self.stopSpeak()
                    if self.isContentPresenting {
                        self.isContentPresenting = false
                        delay = self.detailSettingModel.browserCloseDelay
                    }
                    if UIAccessibility.isVoiceOverRunning {
                        delay = 3
                    }
                    // wait at least 1.0 seconds if tts was speaking
                    // wait 1.0 ~ 2.0 seconds if browser was open.
                    // hopefully closing browser and reading the content by voice over will be ended by then
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.willSpeakArriveMessage = true
                        let announce = CustomLocalizedString("Going to %@", lang: self.resourceLang, dest.title.pron)
                            + (dest.startMessage?.content ?? "")
                        self.tts.speak(announce, forceSelfvoice: false, force: true, callback: {code in }, progress: {range in
                            if range.location == 0{
                                self.willSpeakArriveMessage = true
                            }
                        })
                    }
                }
                self.activityLog(category: "destination-text", text: dest.title.text, memo: dest.title.pron)
            }
        } else {
            _ = send(destination: "__cancel__")
        }
    }

    private func send(destination: String) -> Bool {
        DispatchQueue.main.async {
            print("Show modal waiting")
            NavUtil.showModalWaiting(withMessage: CustomLocalizedString("processing...", lang: self.resourceLang))
        }
        if fallbackService.send(destination: destination) || self.noSuitcaseDebug  {
            DispatchQueue.main.async {
                print("hide modal waiting")
                NavUtil.hideModalWaiting()
            }
            return true
        } else {
            DispatchQueue.main.async {
                print("hide modal waiting")
                NavUtil.hideModalWaiting()
            }
            DispatchQueue.main.async {
                let message = CustomLocalizedString("Suitcase may not be connected", lang: self.resourceLang)

                self.speak(message) {}
            }
            return false
        }
    }

    // MARK: CaBotServiceDelegateBLE

    func cabot(service: any CaBotTransportProtocol, bluetoothStateUpdated state: CBManagerState) {
        if bluetoothState != state {
            bluetoothState = state
        }

        #if targetEnvironment(simulator)
        bluetoothState = .poweredOn
        #endif
    }

    // MARK: CaBotServiceDelegate

    func caBot(service: any CaBotTransportProtocol, centralConnected: Bool) {
        guard self.preview == false else {return}
        let saveSuitcaseConnected = self.suitcaseConnected

        switch(service.connectionType()) {
        case .BLE:
            self.suitcaseConnectedBLE = centralConnected
        case .TCP:
            self.suitcaseConnectedTCP = centralConnected
        }

        if self.suitcaseConnected != saveSuitcaseConnected {
            let text = centralConnected ? CustomLocalizedString("Suitcase has been connected", lang: self.resourceLang) :
                CustomLocalizedString("Suitcase has been disconnected", lang: self.resourceLang)
            self.tts.speak(text, force: true) {_ in }
            
            if self.suitcaseConnected {
                if self.modeType != .Normal{
                    self.share(user_info: SharedInfo(type: .RequestUserInfo, value: ""))
                }
                DispatchQueue.main.async {
                    _ = self.fallbackService.manage(command: .lang, param: self.resourceLang)
                }
            }
        }
    }

    func caBot(service: any CaBotTransportProtocol, versionMatched: Bool, with version: String) {
        switch(service.connectionType()) {
        case .BLE:
            self.versionMatchedBLE = versionMatched
            self.serverBLEVersion = version
        case .TCP:
            self.versionMatchedTCP = versionMatched
            self.serverTCPVersion = version
        }
    }

    func cabot(service: any CaBotTransportProtocol, openRequest url: URL) {
        NSLog("open request: %@", url.absoluteString)
        self.open(content: url)
    }

    func cabot(service: any CaBotTransportProtocol, soundRequest: String) {
        switch(soundRequest) {
        case "SpeedUp":
            playAudio(file: detailSettingModel.speedUpSound)
            break
        case "SpeedDown":
            playAudio(file: detailSettingModel.speedDownSound)
            break
        case "OBSTACLE_AHEAD":
            playAudio(file: detailSettingModel.obstacleAheadSound)
            break
        default:
            NSLog("\"\(soundRequest)\" is unknown sound")
        }
    }

    func cabot(service: any CaBotTransportProtocol, notification: NavigationNotification) {
        switch(notification){
        case .subtour:
            self.announceToPushRightButtonTime = CFAbsoluteTimeGetCurrent() - 20
            self.shouldNoAnnounceToPushRightButton = true
            if tourManager.setting.enableSubtourOnHandle {
                if let ad = tourManager.arrivedDestination,
                   let subtour = ad.subtour {
                    tourManager.addSubTour(tour: subtour)
                }
                if tourManager.proceedToNextDestination() {
                    self.playAudio(file: self.detailSettingModel.startSound)
                }
            }
            break
        case .next:
            self.announceToPushRightButtonTime = CFAbsoluteTimeGetCurrent() - 20
            self.shouldNoAnnounceToPushRightButton = true
            if tourManager.proceedToNextDestination() {
                self.playAudio(file: self.detailSettingModel.startSound)
            }else {
                self.speak(CustomLocalizedString("No destination is selected", lang: self.resourceLang)) {
                }
            }
            break
        case .arrived:
            if let cd = tourManager.currentDestination {
                self.playAudio(file: self.detailSettingModel.arrivedSound)
                tourManager.arrivedCurrent()

                var announce = CustomLocalizedString("You have arrived at %@. ", lang: self.resourceLang, cd.title.pron)
                if let count = cd.arriveMessages?.count {
                    for i in 0 ..< count{
                        announce += cd.arriveMessages?[i].content ?? ""
                    }
                } else{
                    if let _ = cd.content?.content,
                       tourManager.setting.showContentWhenArrive {
                        announce += CustomLocalizedString("You can check detail of %@ on the phone. ", lang: self.resourceLang, cd.title.pron)
                    }
                    if let next = tourManager.nextDestination {
                        announce += CustomLocalizedString("You can proceed to %@ by pressing the right button of the suitcase handle. ", lang: self.resourceLang, next.title.pron)
                        self.announceToPushRightButtonTime = CFAbsoluteTimeGetCurrent()
                        self.shouldNoAnnounceToPushRightButton = true
                        if let subtour = cd.subtour,
                           tourManager.setting.enableSubtourOnHandle {
                            announce += CustomLocalizedString("Or by pressing the center button to proceed a subtour %@.", lang: self.resourceLang, subtour.introduction.pron)
                        }
                    } else if let subtour = cd.subtour,
                       tourManager.setting.enableSubtourOnHandle {
                        announce += CustomLocalizedString("Press the center button to proceed a subtour %@.", lang: self.resourceLang, subtour.introduction.pron)
                    }
                }
                var delay = 0.0
                if UIAccessibility.isVoiceOverRunning {
                    delay = 3.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.speak(announce) {
                        // if user pressed the next button while reading announce, skip open content
                        if self.tourManager.currentDestination == nil {
                            if let contentURL = cd.content?.url,
                               self.tourManager.setting.showContentWhenArrive {
                                self.open(content: contentURL)
                            }
                        }
                        self.announceToPushRightButtonTime = CFAbsoluteTimeGetCurrent() - 27
                        self.shouldNoAnnounceToPushRightButton = true
                        self.willSpeakArriveMessage = false
                    }
                }
            }
            break
        case .skip:
            self.skipDestination()
        case .getlanguage:
            DispatchQueue.main.async {
                _ = self.fallbackService.manage(command: .lang, param: I18N.shared.langCode)
            }
            break
        }
    }

    func cabot(service: any CaBotTransportProtocol, deviceStatus: DeviceStatus) -> Void {
        let prevDeviceStatusLevel = self.deviceStatus.level
        self.deviceStatus = deviceStatus
        let deviceStatusLevel = deviceStatus.level
        if (self.modeType == .Advanced || self.modeType == .Debug){
            if (prevDeviceStatusLevel != deviceStatusLevel) {
                if (deviceStatusLevel == .OK){
                    self.removeNotification()
                } else {
                    notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                        if granted {
                            DispatchQueue.main.async {
                                self.pushDeviceState()
                            }
                        } else {
                            print("Permission for notification not granted.")
                        }
                    }
                }
            }
        }
    }

    func cabot(service: any CaBotTransportProtocol, systemStatus: SystemStatus) -> Void {
        let prevSystemStatus = self.systemStatus.summary
        self.systemStatus.update(with: systemStatus)
        let systemStatus = self.systemStatus.summary
        if (self.modeType == .Advanced || self.modeType == .Debug){
            if (prevSystemStatus != systemStatus){
                if (systemStatus == .OK){
                    self.removeNotification()
                } else {
                    notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                        if granted {
                            DispatchQueue.main.async {
                                self.pushSystemState()
                            }
                        } else {
                            print("Permission for notification not granted.")
                        }
                    }
                }
            }
        }
    }

    func cabot(service: any CaBotTransportProtocol, batteryStatus: BatteryStatus) -> Void {
        self.batteryStatus = batteryStatus
    }
    
    func cabot(service: any CaBotTransportProtocol, touchStatus: TouchStatus) -> Void {
        let prevTouchStatus = self.touchStatus
        if prevTouchStatus.level != touchStatus.level{
            DispatchQueue.main.async {
                self.touchStatus = touchStatus
            }
        }
        if CFAbsoluteTimeGetCurrent() - self.announceToPushRightButtonTime > 30{
            self.shouldNoAnnounceToPushRightButton = false
        }
        if self.touchStatus.level == .Touching {
            if prevTouchStatus.level != .Touching {
                touchStartTime = CFAbsoluteTimeGetCurrent()
            } else if CFAbsoluteTimeGetCurrent() - self.touchStartTime > 3{
                if self.shouldNoAnnounceToPushRightButton == false && self.willSpeakArriveMessage == false{
                    if tourManager.hasDestination {
                        let announce = CustomLocalizedString("PRESS_RIGHT_BUTTON", lang: self.resourceLang)
                        self.speak(announce){}
                        self.announceToPushRightButtonTime = CFAbsoluteTimeGetCurrent()
                        self.shouldNoAnnounceToPushRightButton = true
                    }
                }
            }
        }
    }
    
    func cabot(service: any CaBotTransportProtocol, logList: [LogEntry], status: CaBotLogStatus) {
        NSLog("set log list \(logList)")
        self.logList.set(list: logList)
        self.logList.set(status: status)
    }

    func cabot(service: any CaBotTransportProtocol, logDetail: LogEntry) {
        NSLog("set log detail \(logDetail)")
        self.logList.set(detail: logDetail)
    }

    func cabot(service: any CaBotTransportProtocol, userInfo: SharedInfo) {
        if modeType != .Normal {
            self.userInfo.update(userInfo: userInfo)
            if userInfo.type == .Speak {
                if isTTSEnabledForAdvanced {
                    if userInfo.value.isEmpty && userInfo.flag1 { // stop
                        tts.stopSpeakForAdvanced()
                    } else {
                        tts.speakForAdvanced(userInfo.value, force: userInfo.flag1) { _ in
                        }
                    }
                }
            }
            return
        }
        if userInfo.type == .OverrideTour {
            if let src = resource?.toursSource {
                do {
                    let tours = try Tour.load(at: src)
                    for tour in tours {
                        if tour.id == userInfo.value {
                            tourManager.set(tour: tour)
                            needToStartAnnounce(wait: true)
                        }
                    }
                } catch {
                    NSLog("\(src) cannot be loaded")
                }
            }
        }
        if userInfo.type == .OverrideDestination {
            func traverseDest(src: Source) {
                do {
                    let dests = try Destination.load(at: src)
                    for dest in dests {
                        if let value = dest.value {
                            if value == userInfo.value {
                                if userInfo.flag1 { // clear and add
                                    self.clearAll()
                                }
                                tourManager.addToLast(destination: dest)
                                needToStartAnnounce(wait: true)
                                return
                            }
                        } else if let src = dest.file {
                            traverseDest(src: src)
                        }
                    }
                } catch {
                    NSLog("\(src) cannot be loaded")
                }
            }
            if let src = resource?.destinationsSource {
                traverseDest(src: src)
            }
        }
        if userInfo.type == .Skip {
            skipDestination()
        }
        if userInfo.type == .RequestUserInfo {
            self.share(user_info: SharedInfo(type: .Tour, value: self.tourManager.title.text))
            self.share(user_info: SharedInfo(type: .CurrentDestination, value: self.tourManager.currentDestination?.title.text ?? ""))
            self.share(user_info: SharedInfo(type: .NextDestination, value: self.tourManager.nextDestination?.title.text ?? ""))
            self.share(user_info: SharedInfo(type: .Destinations, value: self.tourManager.destinations.map { $0.title.text }.joined(separator: ",")))
            self.share(user_info: SharedInfo(type: .ChangeLanguage, value: self.resourceLang))
            self.share(user_info: SharedInfo(type: .ChangeUserVoiceType, value: "\(self.userVoice?.id ?? "")"))
            self.share(user_info: SharedInfo(type: .ChangeUserVoiceRate, value: "\(self.userSpeechRate)"))
        }
        if userInfo.type == .ClearDestinations {
            self.clearAll()
        }
        if userInfo.type == .ChangeLanguage {
            self.resource?.lang = userInfo.value
            self.updateVoice()
        }
        if userInfo.type == .ChangeUserVoiceRate {
            self.userSpeechRate = Double(userInfo.value) ?? 0.5
            self.updateTTS()
        }
        if userInfo.type == .ChangeUserVoiceType {
            self.userVoice = TTSHelper.getVoice(by: userInfo.value)
            self.updateTTS()
        }
    }

    func getSpeechPriority() -> SpeechPriority {
        return self.detailSettingModel.speechPriority
    }

    func getModeType() -> ModeType {
        return modeType
    }
}

class DiagnosticStatusData: NSObject, ObservableObject {
    @Published var name: String
    @Published var level: DiagnosticLevel
    @Published var message: String
    @Published var values: OrderedDictionary<String,String>
    init(with diagnostic: DiagnosticStatus) {
        self.name = diagnostic.componentName
        self.level = diagnostic.level
        self.message = diagnostic.message
        self.values = OrderedDictionary<String,String>()
        super.init()
        for value in diagnostic.values {
            self.values[value.key] = value.value
        }
    }
}

class ComponentData: DiagnosticStatusData {
    @Published var details: OrderedDictionary<String,DiagnosticStatusData>
    override init(with diagnostic: DiagnosticStatus) {
        self.details = OrderedDictionary<String,DiagnosticStatusData>()
        super.init(with: diagnostic)
    }
    func update(detail: DiagnosticStatus) {
        if let target = self.details[detail.componentName] {
            for value in detail.values {
                target.values[value.key] = value.value
            }
        } else {
            self.details[detail.componentName] = DiagnosticStatusData(with: detail)
        }
    }
}

class SystemStatusData: NSObject, ObservableObject {
    @Published var level: CaBotSystemLevel
    @Published var summary: DiagnosticLevel
    @Published var components: OrderedDictionary<String,ComponentData>

    static var cache:[String:ComponentData] = [:]

    override init() {
        level = .Unknown
        summary = .Stale
        components = OrderedDictionary<String,ComponentData>()
    }
    func levelText() -> String{
        switch(self.level) {
        case .Unknown, .Inactive, .Deactivating, .Error:
            if !self.components.isEmpty {
                return "Debug"
            }
            return self.level.rawValue
        case .Active, .Activating:
            return self.level.rawValue
        }
    }
    func clear() {
        self.components.removeAll()
    }
    func update(with status: SystemStatus) {
        self.level = status.level
        self.components = OrderedDictionary<String,ComponentData>()
        var allKeys = Set(self.components.keys)
        var max_level: Int = -1
        for diagnostic in status.diagnostics {
            if diagnostic.rootName == nil {
                let data = ComponentData(with: diagnostic)
                components[diagnostic.componentName] = data
                max_level = max(max_level, diagnostic.level.rawValue)
                allKeys.remove(diagnostic.componentName)
            }
        }
        for key in allKeys {
            self.components.removeValue(forKey: key)
        }
        self.summary = .Stale
        if max_level >= 0 {
            if let summary = DiagnosticLevel(rawValue: min(2, max_level)) {
                self.summary = summary
            }
        }
        for diagnostic in status.diagnostics {
            if let root = diagnostic.rootName {
                if let data = components[root] {
                    data.update(detail: diagnostic)
                }
            }
        }
    }

    var canStart:Bool {
        get {
            switch(self.level) {
            case .Unknown, .Active, .Activating, .Deactivating, .Error:
                return false
            case .Inactive:
                return true
            }
        }
    }

    var canStop:Bool {
        get {
            switch(self.level) {
            case .Unknown, .Inactive, .Activating, .Deactivating, .Error:
                return false
            case .Active:
                return true
                }
        }
    }
}

protocol LogReportModelDelegate {
    func refreshLogList()
    func isSuitcaseConnected() -> Bool
    func requestDetail(log_name: String)
    func submitLogReport(log_name: String, title: String, detail: String)
}

class LogReportModel: NSObject, ObservableObject {
    @Published var log_list: [LogEntry]
    @Published var isListReady: Bool = false
    @Published var status: CaBotLogStatus = .OK
    @Published var selectedLog: LogEntry = LogEntry(name: "dummy")
    private var originalLog: LogEntry = LogEntry(name: "dummy")
    @Published var isDetailReady: Bool = false
    var delegate: LogReportModelDelegate? = nil
    var debug: Bool = false
    
    override init() {
        self.log_list = []
    }
    
    func set(list: [LogEntry]){
        self.log_list = list
        self.isListReady = true
    }

    func set(status: CaBotLogStatus) {
        self.status = status
    }
    
    func set(detail: LogEntry) {
        self.selectedLog = detail
        self.originalLog.title = detail.title
        self.originalLog.detail = detail.detail
        self.isDetailReady = true
    }
    
    func clear(){
        self.log_list = []
        self.isListReady = false
    }
    
    func refreshLogList() {
        self.delegate?.refreshLogList()
    }
    
    func requestDetail(log: LogEntry) {
        isDetailReady = false || debug
        self.delegate?.requestDetail(log_name: log.name)
    }
    
    func submit(log: LogEntry) {
        if let title = log.title,
           let detail = log.detail {
            self.delegate?.submitLogReport(log_name: log.name, title: title, detail: detail)
        }
    }
    
    var isSuitcaseConnected: Bool {
        get {
            self.delegate?.isSuitcaseConnected() ?? false
        }
    }
    
    var isOkayToSubmit: Bool {
        get {
            isSuitcaseConnected && status == .OK
        }
    }
    
    var isSubmitDataReady: Bool {
        get {
            selectedLog.title?.count ?? 0 > 0 && selectedLog.detail?.count ?? 0 > 0
        }
    }
    
    var isDetailModified: Bool {
        get {
            originalLog.title != selectedLog.title || originalLog.detail != selectedLog.detail
        }
    }
}
    

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        return result
    }()

    static var empty: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "CaBot")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                Typical reasons for an error here include:
                * The parent directory does not exist, cannot be created, or disallows writing.
                * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                * The device is out of space.
                * The store could not be migrated to the current model version.
                Check the error message to determine what the actual problem was.
                */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
    }
}

class SpeakingText: Hashable {
    static func == (lhs: SpeakingText, rhs: SpeakingText) -> Bool {
        lhs.text == rhs.text && lhs.date == rhs.date
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(date)
    }
    var text: String = ""
    var date: Date
    var voiceover: Bool
    var location = 0
    var length = 0
    init(text: String, voiceover: Bool) {
        self.text = text
        self.date = Date()
        self.voiceover = voiceover
    }
    func subTexts() -> (String, String, String, String) {
        let prefix = self.voiceover ? "VO:" : ""
        let i1 = text.index(text.startIndex, offsetBy: min(text.count, location))
        let i2 = text.index(i1, offsetBy: min((text.count - min(text.count, location)), length))
        return (prefix, String(text[..<i1]), String(text[i1..<i2]), String(text[i2...]))
    }
}

class UserInfoBuffer {
    var selectedTour: String = ""
    var currentDestination: String = ""
    var nextDestination: String = ""
    var destinations: [String] = []
    var speakingText: [SpeakingText] = []
    var speakingIndex = -1
    weak var modelData: CaBotAppModel?

    init(modelData: CaBotAppModel? = nil) {
        self.modelData = modelData
    }

    func clear() {
        selectedTour = ""
        currentDestination = ""
        nextDestination = ""
        speakingText = []
    }

    func update(userInfo: SharedInfo) {
        switch(userInfo.type) {
        case .None:
            break
        case .Speak:
            if !userInfo.value.isEmpty {
                speakingText.insert(SpeakingText(text: userInfo.value, voiceover: userInfo.flag2), at: 0)
            }
            break
        case .SpeakProgress:
            for i in 0..<speakingText.count {
                if speakingText[i].text == userInfo.value {
                    if userInfo.flag1 { // speech done
                        if userInfo.flag2 { // voiceover
                            speakingText[i].location = userInfo.length
                            speakingText[i].length = 0
                        } else {
                            speakingText[i].location += speakingText[i].length
                            speakingText[i].length = 0
                        }
                    } else {
                        speakingText[i].location = userInfo.location
                        speakingText[i].length = userInfo.length
                    }
                    break
                }
            }
            break
        case .Tour:
            selectedTour = userInfo.value
            break
        case .CurrentDestination:
            currentDestination = userInfo.value
            break
        case .NextDestination:
            nextDestination = userInfo.value
            break
        case .Destinations:
            destinations = userInfo.value.split(separator: ",").map(String.init)
        case .OverrideTour:
            // do nothing
            break
        case .OverrideDestination:
            // do nothing
            break
        case .Skip:
            // do nothing
            break
        case .RequestUserInfo:
            // do nothing
            break
        case .ClearDestinations:
            // do nothing
            break
        case .ChangeLanguage:
            modelData?.resource?.lang = userInfo.value
            modelData?.updateVoice()
            break
        case .ChangeUserVoiceRate:
            modelData?.userSpeechRate = Double(userInfo.value) ?? 0.5
            modelData?.updateTTS()
            break
        case .ChangeUserVoiceType:
            modelData?.userVoice = TTSHelper.getVoice(by: userInfo.value)
            modelData?.updateTTS()
            break
        }
    }
}

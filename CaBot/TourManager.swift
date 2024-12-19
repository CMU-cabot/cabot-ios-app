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

import Foundation

protocol TourManagerDelegate {
    func tour(manager: TourManager, destinationChanged: (any Destination)?, isStartMessageSpeaking: Bool)
    func tourUpdated(manager: TourManager)
    func needToStartAnnounce(wait: Bool)
}

class TourManager: TourProtocol {
    static let defaultTourID: String = "TourManager"
    static let tourDataStoreKey: String = "tourDataStoreKey"
    var title: I18NText = I18NText(text: [:], pron: [:])
    var id: String = defaultTourID
    var destinations: [any Destination] {
        get {
            _destinations
        }
    }
    var currentDestination: (any Destination)? {
        get {
            _currentDestination
        }
    }
    var arrivedDestination: (any Destination)? {
        get {
            _arrivedDestination
        }
    }
    var hasDestination: Bool {
        get {
            return _destinations.count > 0 || _currentDestination != nil
        }
    }
    var nextDestination: (any Destination)? {
        get {
            return _destinations.first
        }
    }
    var destinationCount: Int {
        get {
            _destinations.count + (currentDestination == nil ? 0 : 1)
        }
    }
    var isSubtour: Bool {
        get {
            _subtours.count > 0
        }
    }
    var setting: NavigationSettingProtocol {
        get {
            if let setting = _tempNavigationSetting {
                return setting
            }
            return _defaultNavigationSetting
        }
    }
    var tourSaveData: TourSaveData {
        get {
            _tourSaveData
        }
    }
    var currentTour: Tour? {
        get {
            _tour
        }
    }

    private var _tour: Tour?
    private var _destinations: [any Destination]
    private var _currentDestination: (any Destination)?
    private var _arrivedDestination: (any Destination)?
    private var _subtours: [Tour]
    private var _defaultNavigationSetting: NavigationSettingProtocol
    private var _tempNavigationSetting: NavigationSettingProtocol?
    private var _tourSaveData: TourSaveData = TourSaveData()
    var delegate:TourManagerDelegate?

    init(setting: NavigationSettingProtocol) {
        _destinations = []
        _subtours = []
        _defaultNavigationSetting = setting
    }

    func first(n: Int) -> [(any Destination)] {
        return _destinations[0..<min(_destinations.count, n)].map{ $0 }
    }

    func addToLast(destination: (any Destination)) {
        _destinations.append(destination)
        delegate?.tourUpdated(manager: self)
        save()
    }

    func addToFirst(destination: (any Destination)) {
        _destinations.insert(destination, at: 0)
        delegate?.tourUpdated(manager: self)
        save()
    }

    func set(tour: Tour) {
        _tour = tour
        _destinations.removeAll()
        _currentDestination = nil
        _arrivedDestination = nil
        //_tempNavigationSetting = tour.setting
        self.id = tour.id
        self.title = tour.title
        SetDestination(tour:tour)
        delegate?.tourUpdated(manager: self)
        delegate?.tour(manager: self, destinationChanged: nil, isStartMessageSpeaking: true)
        save()
    }
    
    func SetDestination(tour: Tour)
    {
        for d in tour.destinations {
            _destinations.append(d)
        }
    }

    func cannotStartCurrent() {
        if let cd = _currentDestination {
            addToFirst(destination: cd)
            _currentDestination = nil
            delegate?.tourUpdated(manager: self)
            save()
        }
    }

    func stopCurrent() {
        if let cd = _currentDestination {
            addToFirst(destination: cd)
            _currentDestination = nil
            delegate?.tour(manager: self, destinationChanged: nil, isStartMessageSpeaking: true)
            save()
        }
    }

    func arrivedCurrent() {
        _arrivedDestination = _currentDestination
        _currentDestination = nil
        delegate?.tourUpdated(manager: self)
        save()
    }

    func clearCurrent() {
        _currentDestination = nil
        delegate?.tourUpdated(manager: self)
        delegate?.tour(manager: self, destinationChanged: nil, isStartMessageSpeaking: true)
        save()
    }

    func clearAllDestinations() {
        _destinations.removeAll()
        _currentDestination = nil
        _arrivedDestination = nil
        _tour = nil
        id = TourManager.defaultTourID
        title = I18NText(text: [:], pron: [:])
        delegate?.tourUpdated(manager: self)
        delegate?.tour(manager: self, destinationChanged: nil, isStartMessageSpeaking: true)
        saveDataClear()
    }
        
    func addSubTour(tour: Tour) {
        _subtours.append(tour)
        delegate?.tourUpdated(manager: self)
        save()
    }

    func clearSubTour() {
        if let tour = _subtours.popLast() {
            _destinations = _destinations.filter { dest in
                // TODO dest.parent != tour
                true
            }
        }
        _arrivedDestination = nil
        delegate?.tourUpdated(manager: self)
        delegate?.tour(manager: self, destinationChanged: nil, isStartMessageSpeaking: true)
    }

    func proceedToNextDestination(isStartMessageSpeaking: Bool = true) -> Bool {
        if _destinations.count == 0  {
            self._currentDestination = nil
            delegate?.tourUpdated(manager: self)
            saveDataClear()
            return false
        }
        self._arrivedDestination = nil
        self._currentDestination = pop()
        delegate?.tourUpdated(manager: self)
        delegate?.tour(manager: self, destinationChanged: currentDestination, isStartMessageSpeaking: isStartMessageSpeaking)
        save()
        return true
    }

    func skipDestination() -> (any Destination) {
        let skip: any Destination = _currentDestination ?? pop()
        if (_currentDestination != nil) {
            clearCurrent()
        } else {
            delegate?.tourUpdated(manager: self)
        }
        save()
        return skip
    }

    func pop() -> (any Destination) {
        let dest = _destinations.removeFirst()
        save()
        return dest
    }

    func getTourSaveData() -> TourSaveData {
        var data = TourSaveData()
        if destinations.count == 0 && data.currentDestination == "" {
            _tour = nil
            id = TourManager.defaultTourID
        }
        data.id = id
        for d in destinations {
            if let tourDestination = d as? TourDestination {
                data.destinations.append(tourDestination.ref.description)
            } else {
                data.destinations.append(d.value)
            }
        }
        if let tourDestination = currentDestination as? TourDestination {
            data.currentDestination = tourDestination.ref.description
        } else {
            if let value = currentDestination?.value {
                data.currentDestination = value
            } else {
                data.currentDestination = ""
            }
        }
        return data
    }

    func save(){
        var data = getTourSaveData()
        let encoder = JSONEncoder()
        print("restore save \(data)")
        if let encoded = try? encoder.encode(data) {
            UserDefaults.standard.set(encoded, forKey: TourManager.tourDataStoreKey)
        }
        else {
            NSLog("Failed to save tour data")
        }
    }
    
    func update(){
        _tourSaveData.currentDestination = currentDestination?.value ?? ""
        UserDefaults.standard.set(_tourSaveData, forKey: TourManager.tourDataStoreKey)
    }
    
    func saveDataClear(){
        var data = TourSaveData()
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(data) {
            UserDefaults.standard.set(encoded, forKey: TourManager.tourDataStoreKey)
        }
        else {
            NSLog("Failed to save tour data")
        }
    }
    
    func tourDataLoad() {
        _destinations.removeAll()
        _currentDestination = nil
        _arrivedDestination = nil
        _tour =  nil
        id = TourManager.defaultTourID
        if let data = UserDefaults.standard.data(forKey: TourManager.tourDataStoreKey) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(TourSaveData.self, from: data) {
                _tourSaveData = decoded
                print("restore \(decoded)")

                id = _tourSaveData.id
                _tour = TourData.getTour(by: _tourSaveData.id)
                if let _ = try? ResourceManager.shared.load() {
                    if _tourSaveData.currentDestination != "" {
                        if let dest = ResourceManager.shared.getDestination(by: _tourSaveData.currentDestination) {
                            addToFirst(destination: dest)
                            let _ = proceedToNextDestination(isStartMessageSpeaking: false)
                        }
                    }
                    for destination in _tourSaveData.destinations {
                        if let dest = ResourceManager.shared.getDestination(by: destination) {
                            addToLast(destination: dest)
                        }
                    }
                    if decoded.destinations.count > 0 && decoded.currentDestination == "" {
                        delegate?.needToStartAnnounce(wait: true)
                    }
                }
            }
        }
    }
}

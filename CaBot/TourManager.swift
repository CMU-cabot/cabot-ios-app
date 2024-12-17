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
}

class TourManager: TourProtocol {
    var title: I18NText = I18NText(text: [:], pron: [:])
    var id: String = "TourManager"
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
        _destinations.removeAll()
        _currentDestination = nil
        _arrivedDestination = nil
        //_tempNavigationSetting = tour.setting
        self.id = tour.id
        self.title = tour.title
        //SetDestination(tour:tour)
        delegate?.tourUpdated(manager: self)
        delegate?.tour(manager: self, destinationChanged: nil, isStartMessageSpeaking: true)
        save()
    }
    
    /*
    func SetDestination(tour: Tour)
    {
        for d in tour.destinations {
            let arrivalAngleString = d.matchedDestinationRef?.arrivalAngle.map { "@" + String($0) } ?? ""
            let valueString = d.matchedDestinationRef?.value ?? d.ref
            let destination = Destination(
                floorTitle: I18NText(text: [:], pron: [:]),
                title: d.title,
                value: valueString+arrivalAngleString,
                pron: "porn",
                file: nil,
                summaryMessage: d.summaryMessage?.text ?? I18NText(text: [:], pron: [:]),
                startMessage: d.startMessage?.text ?? I18NText(text: [:], pron: [:]),
                arriveMessages: d.arriveMessages.map { $0.text } ,
                content: nil,
                waitingDestination: nil,
                subtour: nil, forDemonstration: false
            )
            _destinations.append(destination)
        }
    }
     */

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
        id = "TourManager"
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
    
    func save(){
        var data = TourSaveData()
        data.id = id
        for d in destinations {
            data.destinations.append(d.value ?? "") //d.ref?.value ?? "")
        }
        // TODO data.currentDestination = currentDestination?.value ?? currentDestination?.ref?.value ?? ""
        data.currentDestination = currentDestination?.value ?? ""

        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(data) {
            UserDefaults.standard.set(encoded, forKey: "tourSaveData")
            NSLog("--- Save tour data ---")
            for d in data.destinations {
                NSLog(d)
            }
        }
        else {
            NSLog("Failed to save tour data")
        }
    }
    
    func update(){
        // TODO _tourSaveData.currentDestination = currentDestination?.value ?? currentDestination?.ref?.value ?? ""
        _tourSaveData.currentDestination = currentDestination?.value ?? ""
        UserDefaults.standard.set(_tourSaveData, forKey: "tourSaveData")
    }
    
    func saveDataClear(){
        var data = TourSaveData()
        data.id = ""
        
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(data) {
            UserDefaults.standard.set(encoded, forKey: "tourSaveData")
        }
        else {
            NSLog("Failed to save tour data")
        }
    }
    
    func tourDataLoad(model: CaBotAppModel){
        if let data = UserDefaults.standard.data(forKey: "tourSaveData") {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(TourSaveData.self, from: data) {
                _tourSaveData = decoded
                
                if(_tourSaveData.id == ""){
                    NSLog("Tour save data not found")
                    return
                }
                else if (_tourSaveData.id == "TourManager") {
                    // load destinations
                    do {
                        let sections: Directory.DirectorySections = try ResourceManager.shared.load().directory
                        let allDestinations: [any Destination] = sections.sections.flatMap { $0.items }

                        for destination in allDestinations {
                            //TODO if decoded.currentDestination == (destination.value ?? destination.ref?.value ?? "") {
                            if decoded.currentDestination == (destination.value ?? "") {
                                addToFirst(destination: destination)
                                let _ = proceedToNextDestination(isStartMessageSpeaking: false)
                            }
                        }

                        for decodedDestination in decoded.destinations {
                            for destination in allDestinations {
                                // TODO if decodedDestination == (destination.value ?? destination.ref?.value ?? "") {
                                if decodedDestination == (destination.value ?? "") {
                                    addToLast(destination: destination)
                                }
                            }
                        }


                        if decoded.destinations.count > 0 && decoded.currentDestination == "" {
                            model.needToStartAnnounce(wait: true)
                        }
                    } catch {
                        NSLog("Error loading destinations: \(error)")
                    }
                }
                else{
                    // load tour
                    do {
                        let tours = try ResourceManager.shared.load().tours
                        for tour in tours {
                            if tour.id == decoded.id {
                                set(tour: tour)
                                if(_tourSaveData.currentDestination != ""){
                                    for d in destinations {
                                        // TODO if d.value ?? d.ref?.value != _tourSaveData.currentDestination {
                                        if d.value != _tourSaveData.currentDestination {
                                            var _ = pop()
                                        }
                                        else{
                                            var _ = proceedToNextDestination(isStartMessageSpeaking: false)
                                            break
                                        }
                                    }
                                }
                                else{
                                    if(_tourSaveData.destinations.count > 0){
                                        for d in destinations{
                                            if(destinations.count > 0){
                                                // TODO if(destinations[0].value ?? destinations[0].ref?.value != _tourSaveData.destinations[0]){
                                                if(destinations[0].value != _tourSaveData.destinations[0]){
                                                    var _ = pop()
                                                }
                                            }
                                            else{
                                                break
                                            }
                                        }
                                        model.needToStartAnnounce(wait: true)
                                    }
                                    else{
                                        clearAllDestinations()
                                    }
                                }

                                return
                            }
                        }
                    } catch {
                        NSLog("cannot be loaded")
                    }

                }
            }
        }
    }
}

/*******************************************************************************
 * Copyright (c) 2014, 2024  IBM Corporation, Carnegie Mellon University and others
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

import Contacts

class ContactsUtil {
    static let shared = ContactsUtil()
    private var dictionary: [String: String] = [:]

    func load() {
        self.dictionary = [:]
        let contactStore = CNContactStore()
        let keysToFetch = [CNContactGivenNameKey, CNContactPhoneticGivenNameKey, CNContactFamilyNameKey, CNContactPhoneticFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey]
        let request = CNContactFetchRequest(keysToFetch: keysToFetch as [CNKeyDescriptor])
        do {
            func addDictionary(from: String, to:String) {
                if from.count > 0 && to.count > 0 {
                    self.dictionary[from] = to;
                }
            }
            try contactStore.enumerateContacts(with: request) { (contact, stop) in
                if contact.phoneNumbers.count + contact.emailAddresses.count == 0 {
                    addDictionary(from: contact.phoneticFamilyName + contact.phoneticGivenName, to: contact.familyName + contact.givenName)
                }
            }
        } catch {
            NSLog("Error loading contacts \(error)")
        }
        NSLog("Contact dictionary: \(self.dictionary)")
    }

    func convert(_ text: String) -> String {
        var _text = text
        self.dictionary.keys.forEach{from in
            if let to = self.dictionary[from] {
                _text = _text.replacingOccurrences(of: from, with: to)
            }
        }
        return _text
    }

    func test() {
        
    }
}

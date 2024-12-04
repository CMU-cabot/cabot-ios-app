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

import Combine
import UIKit
import ChatView
import PriorityQueueTTS
import AVFoundation

class PriorityQueueTTSWrapper: NSObject, TTSProtocol, PriorityQueueTTSDelegate {

    func progress(queue: PriorityQueueTTS, entry: QueueEntry) {

    }

    func completed(queue: PriorityQueueTTS, entry: QueueEntry) {
        if let callback = map[entry] {
            callback()
        }
    }

    static var shared = PriorityQueueTTSWrapper()

    let tts = PriorityQueueTTS.shared
    var map: [QueueEntry: ()->Void] = [:]
    var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        tts.delegate = self
        tts.start()
    }

    func speak(_ text: PassthroughSubject<String, any Error>?, callback: @escaping () -> Void) {
        guard let text = text else { return callback() }
        let entry = TokenizerEntry(separators: [".", "!", "?", "\n"], timeout_sec: 30)
        map[entry] = callback
        text.sink(receiveCompletion: { _ in
            entry.close()
        }) { chunk in
            try? entry.append(text: chunk)
        }
        .store(in: &cancellables)
        tts.append(entry: entry)
    }

    func stop() {
        tts.cancel()
    }

    func stop(_ immediate: Bool) {
        tts.cancel()
    }

    func vibrate() {
        print("needs to implement vibrate")
    }

    func playVoiceRecoStart() {
        print("needs to implement playVoiceRecoStart")
    }
}

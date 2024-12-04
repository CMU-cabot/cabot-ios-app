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

import Foundation


struct LimitedArray<T> : Sequence {
    typealias Iterator = Array<T>.Iterator
    typealias Element = T
    
    public let limit :Int
    private var _array = Array<T>()
    
    public init( limit: Int ) {
        assert(limit > 0, "'limit' must be greater than 0.")
        self.limit = limit
    }
    
    public mutating func append( _ newElement: Element ) {
        while _array.count >= limit {
            _array.removeFirst()
        }
        _array.append(newElement)
    }

    public mutating func removeFirst() {
        _array.removeFirst()
    }
    
    public mutating func removeAll() {
        _array.removeAll()
    }
    
    public func makeIterator() -> Array<T>.Iterator {
        return _array.makeIterator()
    }
    
    public var array : Array<T> {
        return _array
    }
}

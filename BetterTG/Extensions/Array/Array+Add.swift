// Array+Add.swift

import Foundation

extension Array {
    @inlinable mutating func add(_ newElement: Element) {
        insert(newElement, at: 0)
    }
}

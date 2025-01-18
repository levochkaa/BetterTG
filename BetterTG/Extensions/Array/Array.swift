// Array.swift

import TDLibKit

extension Array {
    @inlinable mutating func add(_ newElement: Element) {
        insert(newElement, at: 0)
    }
    
    @inlinable mutating func add(contentsOf array: Array) {
        insert(contentsOf: array, at: 0)
    }
    
    mutating func place(_ element: Element, at index: Int) {
        if index >= count {
            append(element)
        } else {
            self[index] = element
        }
    }
}

extension Array where Element: Equatable {
    func uniqued() -> [Element] {
        var result = [Element]()
        
        for value in self where !result.contains(value) {
            result.append(value)
        }
        
        return result
    }
}

extension [ChatPosition] {
    func first(_ chatList: ChatList) -> ChatPosition? {
        first(where: { $0.list == chatList })
    }
}

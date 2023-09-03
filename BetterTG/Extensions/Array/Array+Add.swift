// Array+Add.swift

extension Array {
    @inlinable mutating func add(_ newElement: Element) {
        insert(newElement, at: 0)
    }
    
    @inlinable mutating func add(contentsOf array: Array) {
        insert(contentsOf: array, at: 0)
    }
}

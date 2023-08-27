// Array+Add.swift

extension Array {
    @inlinable mutating func add(_ newElement: Element) {
        insert(newElement, at: 0)
    }
}

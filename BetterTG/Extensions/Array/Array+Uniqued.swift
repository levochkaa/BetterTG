// Array+Uniqued.swift

extension Array where Element: Equatable {
    func uniqued() -> [Element] {
        var result = [Element]()
        
        for value in self where !result.contains(value) {
            result.append(value)
        }
        
        return result
    }
}

// View+Equatable.swift

import SwiftUI

extension View {
    func equatable<V: Equatable>(by value: V) -> some View {
        EquatableView(content: self, value: value)
            .equatable()
    }
}

private struct EquatableView<Content: View, Value: Equatable>: Equatable, View {
    let content: Content
    let value: Value
    
    var body: some View {
        content
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }
}

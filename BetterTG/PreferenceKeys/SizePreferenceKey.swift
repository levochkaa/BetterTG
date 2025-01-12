// SizePreferenceKey.swift

import SwiftUI

struct SizePreferenceKey: PreferenceKey {
    typealias Value = CGSize
    static let defaultValue: Value = .zero
    static func reduce(value: inout Value, nextValue: () -> Value) {}
}

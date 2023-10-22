// VisiblePreferenceKey.swift

import SwiftUI

struct VisiblePreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { }
}

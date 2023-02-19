// VisibleKey.swift

import SwiftUI

struct VisibleKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { }
}

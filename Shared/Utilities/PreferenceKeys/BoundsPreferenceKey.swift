// BoundsPreferenceKey.swift

import SwiftUI

struct BoundsPreferenceKey: PreferenceKey {
    static var defaultValue = [[Int64: ChatViewVM]: Anchor<CGRect>]()
    
    static func reduce(
        value: inout [[Int64: ChatViewVM]: Anchor<CGRect>],
        nextValue: () -> [[Int64: ChatViewVM]: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

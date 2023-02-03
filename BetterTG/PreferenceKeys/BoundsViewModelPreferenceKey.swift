// BoundsViewModelPreferenceKey.swift

import SwiftUI

struct BoundsAnchorWithChatViewModel {
    var anchor: Anchor<CGRect>
    var chatViewModel: ChatViewModel
}

struct BoundsViewModelPreferenceKey: PreferenceKey {
    typealias Value = [Int64: BoundsAnchorWithChatViewModel]
    
    static var defaultValue = Value()
    
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { $1 }
    }
}

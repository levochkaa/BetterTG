// Button.swift

import SwiftUI

extension Button where Label == SwiftUI.Label<Text, Image> {
    public init(
        _ title: String = "",
        systemImage: String,
        action: @escaping () -> Void
    ) {
        self.init(action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

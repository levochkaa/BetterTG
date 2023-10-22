// Button.swift

import SwiftUI

extension Button where Label == SwiftUI.Label<Text, Image> {
    init(
        _ title: String = "",
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

// menuOnPress.swift

import SwiftUI

extension View {
    func menuOnPress<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Menu(content: content) {
            self
        }
        .menuOrder(.fixed)
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }
}

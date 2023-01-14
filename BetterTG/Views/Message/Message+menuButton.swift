// Message+menuButton.swift

import SwiftUI
import SwiftUIX

extension MessageView {
    @ViewBuilder var menuButton: some View {
        Image(systemName: "ellipsis.circle")
            .foregroundColor(.white)
            .font(.title2)
            .menuOnPress {
                menu
            }
    }
}

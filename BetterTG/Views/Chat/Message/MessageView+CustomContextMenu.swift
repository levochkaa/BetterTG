// MessageView+CustomContextMenu.swift

import SwiftUI

extension MessageView {
    @ViewBuilder func customContextMenu(buttons: [ContextButtonInfo]) -> some View {
        let buttonsCount = CGFloat(buttons.count)
        let offsetY = CGFloat(buttonsCount * contextMenuButtonHeight + spacing * buttonsCount)
        VStack(spacing: spacing) {
            ForEach(buttons) { button in
                contextButton(
                    text: button.text,
                    systemImage: button.systemImage,
                    role: button.role,
                    action: button.action
                )
            }
        }
        .frame(width: 200)
        .offset(y: offsetY)
    }
}

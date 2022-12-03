// MessageView+ContextMenuButton.swift

import SwiftUI

extension MessageView {
    @ViewBuilder func contextButton(
        text: LocalizedStringKey,
        systemImage: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(text)
            Spacer()
            Image(systemName: systemImage)
        }
        .if(role == nil) {
            $0.foregroundColor(.white)
        }
        .if(role == .destructive) {
            $0.foregroundColor(.red)
        }
        .if(role == .cancel) {
            $0.foregroundColor(.blue)
        }
        .padding(.horizontal, 10)
        .frame(height: contextMenuButtonHeight)
        .background(.bar)
        .cornerRadius(20)
        .onTapGesture {
            withAnimation {
                showContextMenu = false
                onDismiss?()
            }
            action()
        }
    }
}

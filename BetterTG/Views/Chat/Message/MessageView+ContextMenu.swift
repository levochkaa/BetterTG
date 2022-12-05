// MessageView+ContextMenu.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var contextMenu: some View {
        AsyncButton {
            // TODO: implement reply
        } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }
        
        Divider()
        
        AsyncButton(role: .destructive) {
            try await viewModel.deleteMessages(
                ids: [customMessage.message.id],
                deleteForBoth: false
            )
        } label: {
            Label("Delete for me", systemImage: "trash")
        }
        
        AsyncButton(role: .destructive) {
            try await viewModel.deleteMessages(
                ids: [customMessage.message.id],
                deleteForBoth: true
            )
        } label: {
            Label("**Delete for both**", systemImage: "trash.fill")
        }
    }
}

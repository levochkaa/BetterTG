// MessageView+ContextMenu.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var contextMenu: some View {
        Button {
            withAnimation {
                viewModel.replyMessage = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + 0.05) { // defaultAnimationDuration = 0.35
                withAnimation {
                    viewModel.replyMessage = customMessage
                }
            }
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

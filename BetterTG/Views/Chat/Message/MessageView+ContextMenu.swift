// MessageView+ContextMenu.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var contextMenu: some View {
        Button {
            if viewModel.replyMessage != nil {
                withAnimation {
                    viewModel.replyMessage = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + 0.05) { // defaultAnimationDuration = 0.35
                    withAnimation {
                        viewModel.replyMessage = customMessage
                    }
                }
            } else {
                withAnimation {
                    viewModel.replyMessage = customMessage
                }
            }
        } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }
        
        if customMessage.message.isOutgoing {
            Button {
                if viewModel.editMessage != nil {
                    withAnimation {
                        viewModel.editMessage = nil
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 + 0.05) { // defaultAnimationDuration = 0.35
                        withAnimation {
                            viewModel.editMessage = customMessage
                        }
                        if case let .messageText(messageText) = customMessage.message.content {
                            viewModel.editMessageText = messageText.text.text
                        }
                    }
                } else {
                    withAnimation {
                        viewModel.editMessage = customMessage
                    }
                    if case let .messageText(messageText) = customMessage.message.content {
                        viewModel.editMessageText = messageText.text.text
                    }
                }
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
        }
        
        Divider()
        
        AsyncButton(role: .destructive) {
            try await viewModel.deleteMessage(
                id: customMessage.message.id,
                deleteForBoth: false
            )
        } label: {
            Label("Delete for me", systemImage: "trash")
        }
        
        AsyncButton(role: .destructive) {
            try await viewModel.deleteMessage(
                id: customMessage.message.id,
                deleteForBoth: true
            )
        } label: {
            Label("Delete for both", systemImage: "trash.fill")
        }
    }
}

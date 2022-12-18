// MessageView+ContextMenu.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var contextMenu: some View {
        Button {
            if viewModel.replyMessage != nil {
                withAnimation {
                    viewModel.replyMessage = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Utils.defaultAnimationDuration + 0.05) {
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + Utils.defaultAnimationDuration + 0.05) {
                        withAnimation {
                            viewModel.editMessage = customMessage
                            setEditMessageText()
                        }
                    }
                } else {
                    withAnimation {
                        viewModel.editMessage = customMessage
                        setEditMessageText()
                    }
                    
                }
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
        }
        
        Divider()
        
        AsyncButton(role: .destructive) {
            await viewModel.deleteMessage(
                id: customMessage.message.id,
                deleteForBoth: false
            )
        } label: {
            Label("Delete for me", systemImage: "trash")
        }
        
        AsyncButton(role: .destructive) {
            await viewModel.deleteMessage(
                id: customMessage.message.id,
                deleteForBoth: true
            )
        } label: {
            Label("Delete for both", systemImage: "trash.fill")
        }
    }
    
    func setEditMessageText() {
        switch customMessage.message.content {
            case let .messageText(messageText):
                viewModel.editMessageText = messageText.text.text
            case let .messagePhoto(messagePhoto):
                viewModel.editMessageText = messagePhoto.caption.text
            default:
                break
        }
    }
}

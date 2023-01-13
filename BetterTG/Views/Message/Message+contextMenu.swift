// MessageView+ContextMenu.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var contextMenu: some View {
        if !customMessage.message.isChannelPost {
            Button {
                if viewModel.replyMessage != nil {
                    withAnimation {
                        viewModel.replyMessage = nil
                    }
                    Task.async(after: Utils.defaultAnimationDuration + 0.05) {
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
        }
        
        if customMessage.message.canBeEdited {
            Button {
                if viewModel.editMessage != nil {
                    withAnimation {
                        viewModel.editMessage = nil
                    }
                    Task.async(after: Utils.defaultAnimationDuration + 0.05) {
                        withAnimation {
                            viewModel.editMessage = customMessage
                        }
                    }
                } else {
                    withAnimation {
                        viewModel.editMessage = customMessage
                    }
                }
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
        }
        
        Divider()
        
        if customMessage.message.canBeDeletedOnlyForSelf {
            AsyncButton(role: .destructive) {
                await viewModel.deleteMessage(
                    id: customMessage.message.id,
                    deleteForBoth: false
                )
            } label: {
                Label("Delete for me", systemImage: "trash")
            }
        }
        
        if customMessage.message.canBeDeletedForAllUsers {
            AsyncButton(role: .destructive) {
                await viewModel.deleteMessage(
                    id: customMessage.message.id,
                    deleteForBoth: true
                )
            } label: {
                Label("Delete for both", systemImage: "trash.fill")
            }
        }
    }
}

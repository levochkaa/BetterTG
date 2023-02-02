// Message+menu.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var menu: some View {
        if !customMessage.message.isChannelPost {
            Button("Reply", systemImage: "arrowshape.turn.up.left") {
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
            }
        }
        
        if customMessage.message.canBeEdited {
            Button("Edit", systemImage: "square.and.pencil") {
                if viewModel.editCustomMessage != nil {
                    withAnimation {
                        viewModel.editCustomMessage = nil
                    }
                    Task.async(after: Utils.defaultAnimationDuration + 0.05) {
                        withAnimation {
                            viewModel.editCustomMessage = customMessage
                        }
                    }
                } else {
                    withAnimation {
                        viewModel.editCustomMessage = customMessage
                    }
                }
            }
        }
        
        if !text.isEmpty {
            Button {
                UIPasteboard.general.string = text
            } label: {
                Label("Copy", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
        }
        
        Divider()
        
        if customMessage.message.canBeDeletedOnlyForSelf, !customMessage.message.canBeDeletedForAllUsers {
            Button(role: .destructive) {
                Task {
                    await viewModel.deleteMessage(
                        id: customMessage.message.id,
                        deleteForBoth: false
                    )
                }
            } label: {
                Label("Delete only for me", systemImage: "trash")
            }
        }
        
        if !customMessage.message.canBeDeletedOnlyForSelf, customMessage.message.canBeDeletedForAllUsers {
            Button(role: .destructive) {
                Task {
                    await viewModel.deleteMessage(
                        id: customMessage.message.id,
                        deleteForBoth: true
                    )
                }
            } label: {
                Label("Delete for both", systemImage: "trash.fill")
            }
        }
        
        if customMessage.message.canBeDeletedOnlyForSelf, customMessage.message.canBeDeletedForAllUsers {
            Menu("Delete") {
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteMessage(
                            id: customMessage.message.id,
                            deleteForBoth: false
                        )
                    }
                } label: {
                    Label("Delete only for me", systemImage: "trash")
                }
                
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteMessage(
                            id: customMessage.message.id,
                            deleteForBoth: true
                        )
                    }
                } label: {
                    Label("Delete for both", systemImage: "trash.fill")
                }
            }
        }
    }
}

// Message+menu.swift

import SwiftUI
import SwiftUIX

extension MessageView {
    @ViewBuilder var menu: some View {
        if !customMessage.message.isChannelPost {
            Button("Reply", systemImage: .arrowshapeTurnUpLeft) {
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
            Button("Edit", systemImage: .squareAndPencil) {
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
            }
        }
        
        Divider()
        
        Menu("Delete") {
            if customMessage.message.canBeDeletedOnlyForSelf {
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
            
            if customMessage.message.canBeDeletedForAllUsers {
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

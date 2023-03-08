// MessageView+Menu.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var menu: some View {
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
            Button("Copy", systemImage: "rectangle.portrait.on.rectangle.portrait") {
                UIPasteboard.general.string = text
            }
        }
        
        Divider()
        
        if customMessage.message.canBeDeletedOnlyForSelf { // , !customMessage.message.canBeDeletedForAllUsers {
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task {
                    await viewModel.deleteMessage(
                        id: customMessage.message.id,
                        deleteForBoth: false
                    )
                }
            }
        }
        
        if !customMessage.message.canBeDeletedOnlyForSelf { // , customMessage.message.canBeDeletedForAllUsers {
            Button("Delete for both", systemImage: "trash.fill", role: .destructive) {
                Task {
                    await viewModel.deleteMessage(
                        id: customMessage.message.id,
                        deleteForBoth: true
                    )
                }
            }
        }
        
//        if customMessage.message.canBeDeletedOnlyForSelf, customMessage.message.canBeDeletedForAllUsers {
//            Menu("Delete") {
//                Button("Delete only for me", systemImage: "trash", role: .destructive) {
//                    Task {
//                        await viewModel.deleteMessage(
//                            id: customMessage.message.id,
//                            deleteForBoth: false
//                        )
//                    }
//                }
//
//                Button("Delete for both", systemImage: "trash.fill", role: .destructive) {
//                    Task {
//                        await viewModel.deleteMessage(
//                            id: customMessage.message.id,
//                            deleteForBoth: true
//                        )
//                    }
//                }
//            }
//        }
    }
}

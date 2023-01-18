// Root+contextMenu.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder func contextMenu(for chat: Chat) -> some View {
        if !chat.canBeDeletedOnlyForSelf, chat.canBeDeletedForAllUsers {
            Button(role: .destructive) {
                deleteChatForAllUsers = true
                confirmedChat = chat
                showConfirmChatDelete = true
            } label: {
                Label("Delete for all users", systemImage: "trash.fill")
            }
        }
        
        if chat.canBeDeletedOnlyForSelf, !chat.canBeDeletedForAllUsers {
            Button(role: .destructive) {
                deleteChatForAllUsers = false
                confirmedChat = chat
                showConfirmChatDelete = true
            } label: {
                Label("Delete only for me", systemImage: "trash")
            }
        }
        
        if chat.canBeDeletedOnlyForSelf, chat.canBeDeletedForAllUsers {
            Menu("Delete") {
                Button(role: .destructive) {
                    deleteChatForAllUsers = false
                    confirmedChat = chat
                    showConfirmChatDelete = true
                } label: {
                    Label("Delete only for me", systemImage: "trash")
                }
                
                Button(role: .destructive) {
                    deleteChatForAllUsers = true
                    confirmedChat = chat
                    showConfirmChatDelete = true
                } label: {
                    Label("Delete for all users", systemImage: "trash.fill")
                }
            }
        }
    }
}

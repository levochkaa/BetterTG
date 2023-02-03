// Root+contextMenu.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder func contextMenu(for chat: Chat) -> some View {
        if !chat.canBeDeletedOnlyForSelf, chat.canBeDeletedForAllUsers {
            Button("Delete for all users", systemImage: "trash.fill", role: .destructive) {
                deleteChatForAllUsers = true
                confirmedChat = chat
                showConfirmChatDelete = true
            }
        }
        
        if chat.canBeDeletedOnlyForSelf, !chat.canBeDeletedForAllUsers {
            Button("Delete only for me", systemImage: "trash", role: .destructive) {
                deleteChatForAllUsers = false
                confirmedChat = chat
                showConfirmChatDelete = true
            }
        }
        
        if chat.canBeDeletedOnlyForSelf, chat.canBeDeletedForAllUsers {
            Menu("Delete") {
                Button("Delete only for me", systemImage: "trash", role: .destructive) {
                    deleteChatForAllUsers = false
                    confirmedChat = chat
                    showConfirmChatDelete = true
                }
                
                Button("Delete for all users", systemImage: "trash.fill", role: .destructive) {
                    deleteChatForAllUsers = true
                    confirmedChat = chat
                    showConfirmChatDelete = true
                }
            }
        }
    }
}

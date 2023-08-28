// RootView+ContextMenu.swift

import TDLibKit

extension RootView {
    @ViewBuilder func contextMenu(for customChat: CustomChat) -> some View {
        if let isPinned = customChat.positions.main?.isPinned, isPinned {
            Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash.fill" : "pin.fill") {
                viewModel.togglePinned(chatId: customChat.chat.id, value: !isPinned)
            }
        }
        
        if !customChat.chat.canBeDeletedOnlyForSelf, customChat.chat.canBeDeletedForAllUsers {
            Button("Delete for everyone", systemImage: "trash.fill", role: .destructive) {
                deleteChatForAllUsers = true
                confirmedChat = customChat.chat
                showConfirmChatDelete = true
            }
        }
        
        if customChat.chat.canBeDeletedOnlyForSelf, !customChat.chat.canBeDeletedForAllUsers {
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteChatForAllUsers = false
                confirmedChat = customChat.chat
                showConfirmChatDelete = true
            }
        }
        
        if customChat.chat.canBeDeletedOnlyForSelf, customChat.chat.canBeDeletedForAllUsers {
            Menu("Delete") {
                Button("Delete only for me", systemImage: "trash", role: .destructive) {
                    deleteChatForAllUsers = false
                    confirmedChat = customChat.chat
                    showConfirmChatDelete = true
                }
                
                Button("Delete for all users", systemImage: "trash.fill", role: .destructive) {
                    deleteChatForAllUsers = true
                    confirmedChat = customChat.chat
                    showConfirmChatDelete = true
                }
            }
        }
    }
}

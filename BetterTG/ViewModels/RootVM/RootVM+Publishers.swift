// RootVM+Publishers.swift

import SwiftUI
import TDLibKit

extension RootVM {
    func setPublishers() {
        nc.publisher(&cancellables, for: .updateChatFolders) { [weak self] updateChatFolders in
            guard let self else { return }
            self.updateChatFolders(updateChatFolders)
        }
        nc.publisher(&cancellables, for: .authorizationStateReady) { [weak self] _ in
            guard let self else { return }
            Task.main { withAnimation { self.loggedIn = true } }
        }
        nc.mergeMany(&cancellables, [
            .authorizationStateClosed,
            .authorizationStateClosing,
            .authorizationStateLoggingOut,
            .authorizationStateWaitPhoneNumber,
            .authorizationStateWaitCode,
            .authorizationStateWaitPassword
        ]) { [weak self] _ in
            guard let self else { return }
            Task.main { withAnimation { self.loggedIn = false } }
        }
        nc.publisher(&cancellables, for: .updateChatReadInbox) { [weak self] updateChatReadInbox in
            guard let self, let chat = allChats.first(where: { $0.chat.id == updateChatReadInbox.chatId }) else { return }
            Task.main { withAnimation { chat.unreadCount = updateChatReadInbox.unreadCount } }
        }
        nc.publisher(&cancellables, for: .updateNewChat) { [weak self] updateNewChat in
            guard let self else { return }
            self.updateNewChat(updateNewChat)
        }
        nc.publisher(&cancellables, for: .updateChatPosition) { [weak self] updateChatPosition in
            guard let self else { return }
            self.updateChatPosition(updateChatPosition)
        }
        nc.publisher(&cancellables, for: .updateChatDraftMessage) { [weak self] updateChatDraftMessage in
            guard let self else { return }
            self.updateChatDraftMessage(updateChatDraftMessage)
        }
        nc.publisher(&cancellables, for: .updateChatLastMessage) { [weak self] updateChatLastMessage in
            guard let self else { return }
            self.updateChatLastMessage(updateChatLastMessage)
        }
    }
    
    func updateChatFolders(_ updateChatFolders: UpdateChatFolders) {
        Task.background {
            var folders = await updateChatFolders.chatFolders.asyncCompactMap { await getCustomFolder(from: $0) }
            let mainFolder = await CustomFolder(chats: getCustomChats(for: .chatListMain) ?? [], type: .main)
            let archive = await CustomFolder(chats: getCustomChats(for: .chatListArchive) ?? [], type: .archive)
            folders.insert(mainFolder, at: updateChatFolders.mainChatListPosition)
            await main { [folders] in
                withAnimation {
                    self.folders = folders
                    self.archive = archive
                }
            }
        }
    }
    
    func updateNewChat(_ updateNewChat: UpdateNewChat) {
        Task.background {
            guard let customChat = await getCustomChat(from: updateNewChat.chat.id, for: .chatListMain) else { return }
            await main { withAnimation { self.mainFolder?.chats.append(customChat) } }
        }
    }
    
    func updateChatPosition(_ updateChatPosition: UpdateChatPosition) {
        guard let folder = folders.first(where: { $0.chatList == updateChatPosition.position.list }) else { return }
        guard updateChatPosition.position.order != 0 else {
            Task.main { folder.chats.removeAll(where: { $0.chat.id == updateChatPosition.chatId }) }
            return
        }
        guard let chat = folder.chats.first(where: { $0.chat.id == updateChatPosition.chatId }) else { return }
        Task.main { withAnimation { chat.position = updateChatPosition.position } }
    }
    
    func updateChatDraftMessage(_ updateChatDraftMessage: UpdateChatDraftMessage) {
        for folder in folders {
            if let chat = folder.chats.first(where: { $0.chat.id == updateChatDraftMessage.chatId }),
               let position = updateChatDraftMessage.positions.first(folder.chatList) {
                Task.main {
                    withAnimation {
                        chat.draftMessage = updateChatDraftMessage.draftMessage
                        chat.position = position
                    }
                }
            }
        }
    }
    
    func updateChatLastMessage(_ updateChatLastMessage: UpdateChatLastMessage) {
        for folder in folders {
            if let chat = folder.chats.first(where: { $0.chat.id == updateChatLastMessage.chatId }),
               let position = updateChatLastMessage.positions.first(folder.chatList) {
                Task.main {
                    withAnimation {
                        chat.lastMessage = updateChatLastMessage.lastMessage
                        chat.position = position
                    }
                }
            }
        }
    }
}

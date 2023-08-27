// RootViewModel+Td.swift

import TDLibKit

extension RootViewModel {
    func tdGetChat(id: Int64) async -> Chat? {
        do {
            return try await td.getChat(chatId: id)
        } catch {
            log("Error getting chat: \(error)")
            return nil
        }
    }
    
    func tdGetMessage(chatId: Int64, messageId: Int64) async -> Message? {
        do {
            return try await td.getMessage(chatId: chatId, messageId: messageId)
        } catch {
            log("Error getting message: \(error)")
            return nil
        }
    }
    
    func tdGetChatHistory(chatId: Int64) async {
        do {
            _ = try await td.getChatHistory(
                chatId: chatId,
                fromMessageId: 0,
                limit: 30,
                offset: 0,
                onlyLocal: false
            )
        } catch {
            log("Error getting historyOfChat: \(error)")
        }
    }
    
    func tdToggleChatIsPinned(chatId: Int64, isPinned: Bool) async {
        do {
            try await td.toggleChatIsPinned(chatId: chatId, chatList: .chatListMain, isPinned: isPinned)
        } catch {
            log("Error toggling chatIsPinned: \(isPinned)")
        }
    }
    
    func tdDeleteChatHistory(chatId: Int64, forAll: Bool) async {
        do {
            try await td.deleteChatHistory(chatId: chatId, removeFromChatList: true, revoke: forAll)
        } catch {
            log("Error deleting chat: \(error)")
        }
    }
    
    func tdSearchPublicChats(query: String) async -> [Int64] {
        do {
            return try await td.searchPublicChats(query: query).chatIds
        } catch {
            log("Error searching publicChats (global): \(error)")
            return []
        }
    }
    
    func tdLoadChats() async {
        do {
            try await td.loadChats(chatList: .chatListMain, limit: 200)
        } catch {
            log("Error loading chats: \(error)")
        }
    }
    
    func tdGetChats() async -> [Int64] {
        do {
            return try await td.getChats(chatList: .chatListMain, limit: 200).chatIds
        } catch {
            log("Error getting chats: \(error)")
            return []
        }
    }
    
    func tdGetUser(id: Int64) async -> User? {
        do {
            return try await td.getUser(userId: id)
        } catch {
            log("Error getting user: \(error)")
            return nil
        }
    }
}

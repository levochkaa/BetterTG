// Root+td.swift

import SwiftUI
import TDLibKit

extension RootViewModel {
    func tdGetChat(id: Int64) async -> Chat? {
        do {
            return try await tdApi.getChat(chatId: id)
        } catch {
            log("Error getting chat: \(error)")
            return nil
        }
    }
    
    func tdGetMessage(chatId: Int64, messageId: Int64) async -> Message? {
        do {
            return try await tdApi.getMessage(chatId: chatId, messageId: messageId)
        } catch {
            log("Error getting message: \(error)")
            return nil
        }
    }
    
    func tdGetChatHistory(id: Int64) async {
        do {
            _ = try await tdApi.getChatHistory(
                chatId: id,
                fromMessageId: 0,
                limit: 30,
                offset: 0,
                onlyLocal: false
            )
        } catch {
            log("Error getting historyOfChat: \(error)")
        }
    }
    
    func tdDeleteChatHistory(id: Int64, forAll: Bool) async {
        do {
            _ = try await tdApi.deleteChatHistory(chatId: id, removeFromChatList: true, revoke: forAll)
        } catch {
            log("Error deleting chat: \(error)")
        }
    }
    
    func tdLoadChats(for chatList: ChatList = .chatListMain) async {
        do {
            _ = try await tdApi.loadChats(chatList: chatList, limit: 200)
        } catch {
            log("Error loading chats: \(error)")
        }
    }
    
    func tdGetChats(for chatList: ChatList = .chatListMain) async -> [Int64] {
        do {
            return try await tdApi.getChats(chatList: chatList, limit: 200).chatIds
        } catch {
            log("Error getting chats: \(error)")
            return []
        }
    }
    
    func tdGetUser(id: Int64) async -> User? {
        do {
            return try await tdApi.getUser(userId: id)
        } catch {
            log("Error getting user: \(error)")
            return nil
        }
    }
}

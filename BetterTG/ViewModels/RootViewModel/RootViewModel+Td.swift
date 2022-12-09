// RootViewModel+Td.swift

import SwiftUI
import TDLibKit

extension RootViewModel {
    func tdGetChat(id: Int64) async -> Chat? {
        do {
            return try await tdApi.getChat(chatId: id)
        } catch {
            logger.log("Error getting chat: \(error)")
            return nil
        }
    }
    
    func tdGetMessage(chatId: Int64, messageId: Int64) async -> Message? {
        do {
            return try await tdApi.getMessage(chatId: chatId, messageId: messageId)
        } catch {
            logger.log("Error getting message: \(error)")
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
            logger.log("Error getting historyOfChat: \(error)")
        }
    }
    
    func tdDeleteChat(id: Int64) async {
        do {
            _ = try await tdApi.deleteChat(chatId: id)
        } catch {
            logger.log("Error deleting chat: \(error)")
        }
    }
    
    func tdLoadChats() async {
        do {
            _ = try await tdApi.loadChats(chatList: .chatListMain, limit: limit)
        } catch {
            logger.log("Error loading chats: \(error)")
        }
    }
    
    func tdGetChats() async -> Chats? {
        do {
            return try await tdApi.getChats(chatList: .chatListMain, limit: limit)
        } catch {
            logger.log("Error getting chats: \(error)")
            return nil
        }
    }
    
    func tdGetUser(id: Int64) async -> User? {
        do {
            return try await tdApi.getUser(userId: id)
        } catch {
            logger.log("Error getting user: \(error)")
            return nil
        }
    }
}

// RootViewModel.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit

class RootViewModel: ObservableObject {
    
    @Published var loggedIn: Bool?
    @Published var mainChats = [Chat]()
    
    var loadedUsers = 0
    var limit = 10
    var loadingUsers = false
    
    let tdApi: TdApi = .shared
    let nc: NotificationCenter = .default
    
    init() {
        setPublishers()
    }
    
    func fetchChatsHistory() async {
        await mainChats.asyncForEach { chat in
            await tdGetChatHistory(id: chat.id)
        }
    }
    
    func getMainChats(from chats: Chats) async -> [Chat] {
        await chats.chatIds.asyncCompactMap { id in
            guard let chat = await tdGetChat(id: id) else { return nil }
            
            if case .chatTypePrivate = chat.type {
                guard let user = await tdGetUser(id: chat.id) else { return nil }
                
                if case .userTypeRegular = user.type {
                    return chat
                }
            }
            
            return nil
        }
    }
    
    func loadMainChats() async {
        await tdLoadChats()
        
        await MainActor.run {
            loadingUsers = true
        }
        
        guard let chats = await tdGetChats() else { return }
        let mainChats = await getMainChats(from: chats)
        
        loadedUsers = mainChats.count
        limit += 10
        
        await MainActor.run {
            self.mainChats += mainChats[self.mainChats.count...]
            self.loadingUsers = false
        }
    }
    
    func sortMainChats() {
        self.mainChats.sort(by: {
            let firstMessageDate = $0.draftMessage?.date ?? $0.lastMessage?.date ?? 1
            let secondMessageDate = $1.draftMessage?.date ?? $1.lastMessage?.date ?? 0
            
            let firstPosition = $0.positions.first(where: { $0.list == .chatListMain })
            let firstMessagePinned = firstPosition?.isPinned ?? false
            
            let secondPosition = $1.positions.first(where: { $0.list == .chatListMain })
            let secondMessagePinned = firstPosition?.isPinned ?? false
            
            let firstOrder = firstPosition?.order ?? -1
            let secondOrder = secondPosition?.order ?? -1
            
            if firstMessagePinned && !secondMessagePinned {
                return true
            } else if !firstMessagePinned && secondMessagePinned {
                return false
            } else if !firstMessagePinned && !secondMessagePinned {
                return firstMessageDate > secondMessageDate
            } else {
                return firstOrder > secondOrder
            }
        })
    }
}

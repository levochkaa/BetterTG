// RootViewModel.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit

class RootViewModel: ObservableObject {
    
    @Published var loggedIn: Bool?
    @Published var mainChats = [CustomChat]()
    
    var loadedUsers = 0
    var limit = 10
    var loadingUsers = false
    
    let tdApi: TdApi = .shared
    let nc: NotificationCenter = .default
    
    init() {
        setPublishers()
    }
    
    func fetchChatsHistory() async {
        await mainChats.asyncForEach { customChat in
            await tdGetChatHistory(id: customChat.chat.id)
        }
    }
    
    func getCustomChat(from id: Int64) async -> CustomChat? {
        guard let chat = await tdGetChat(id: id) else { return nil }
        
        if case .chatTypePrivate = chat.type {
            guard let user = await tdGetUser(id: id) else { return nil }
            
            if case .userTypeRegular = user.type {
                return CustomChat(chat: chat, user: user)
            }
        }
        
        return nil
    }
    
    func loadMainChats() async {
        await tdLoadChats()
        
        await MainActor.run {
            loadingUsers = true
        }
        
        guard let chats = await tdGetChats() else { return }
        let mainChats = await chats.chatIds.asyncCompactMap { await getCustomChat(from: $0) }
        let filteredMainChats = mainChats.filter { mainChat in
            !self.mainChats.contains(where: { mainChat.chat.id == $0.chat.id })
        }
        
        loadedUsers = mainChats.count
        limit += 10
        
        await MainActor.run {
            self.mainChats.append(contentsOf: filteredMainChats)
            self.loadingUsers = false
            
            withAnimation {
                self.sortMainChats()
            }
        }
    }
    
    @MainActor func sortMainChats() {
        self.mainChats.sort(by: {
            let firstMessageDate = $0.chat.draftMessage?.date ?? $0.chat.lastMessage?.date ?? 1
            let secondMessageDate = $1.chat.draftMessage?.date ?? $1.chat.lastMessage?.date ?? 0
            
            let firstPosition = $0.chat.positions.first(where: { $0.list == .chatListMain })
            let firstMessagePinned = firstPosition?.isPinned ?? false
            
            let secondPosition = $1.chat.positions.first(where: { $0.list == .chatListMain })
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

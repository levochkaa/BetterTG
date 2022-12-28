// RootViewModel.swift

import SwiftUI
import Combine
import TDLibKit
import CollectionConcurrencyKit

class RootViewModel: ObservableObject {
    
    @Published var loggedIn: Bool?
    @Published var mainChats = [Chat]()
    @Published var pinnedChatIds = Set<Int64>()
    
    var loadedUsers = 0
    var limit = 10
    var loadingUsers = false
    
    let tdApi: TdApi = .shared
    let logger = Logger("RootVM")
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
                    guard let chatPosition = chat.positions.first(where: { $0.list == .chatListMain })
                    else { return chat }
                    
                    if chatPosition.isPinned {
                        await MainActor.run {
                            _ = pinnedChatIds.insert(chat.id)
                        }
                    }
                    
                    return chat
                }
            }
            
            return nil
        }
    }
    
    func loadMainChats() async {
        await tdLoadChats()
        
        loadingUsers = true
        
        guard let chats = await tdGetChats() else { return }
        let mainChats = await getMainChats(from: chats)
        
        loadedUsers = mainChats.count
        limit += 10
        
        await MainActor.run {
            self.mainChats += mainChats[self.mainChats.count...]
            self.loadingUsers = false
        }
    }
}

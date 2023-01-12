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
    
    init() {
        setPublishers()
    }
    
    func fetchChatsHistory() async {
        await mainChats.asyncForEach { customChat in
            await tdGetChatHistory(id: customChat.chat.id)
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

// RootViewModel.swift

import SwiftUI
import Combine
import TDLibKit
import Observation

@Observable final class RootViewModel {
    var mainChats = [CustomChat]()
    var openedItem: OpenedItem? = nil
    
    @ObservationIgnored var namespace: Namespace.ID! = nil
    
    var cancellables = Set<AnyCancellable>()
    
    init() {
        setPublishers()
    }
    
    func togglePinned(chatId: Int64, value: Bool) {
        Task {
            await tdToggleChatIsPinned(
                chatId: chatId,
                isPinned: value
            )
        }
    }
    
    func filteredSortedChats(_ query: String) -> [CustomChat] {
        let query = query.lowercased()
        return mainChats
            .uniqued()
            .sorted {
                if let firstOrder = $0.positions.main?.order, let secondOrder = $1.positions.main?.order {
                    return firstOrder > secondOrder
                } else {
                    return $0.chat.id > $1.chat.id
                }
            }
            .filter {
                query.isEmpty || $0.chat.title.lowercased().contains(query)
                    || $0.user.firstName.lowercased().contains(query)
                    || $0.user.lastName.lowercased().contains(query)
            }
    }
    
    func loadMainChats() {
        Task {
            let chatIds = await tdGetChats()
            let customChats = await chatIds.asyncCompactMap { await getCustomChat(from: $0) }
            await MainActor.run {
                withAnimation {
                    mainChats = customChats
                }
            }
        }
    }
    
    func getCustomChat(from id: Int64) async -> CustomChat? {
        guard let chat = await tdGetChat(id: id) else { return nil }
        
        if case .chatTypePrivate(let chatTypePrivate) = chat.type {
            guard let user = await tdGetUser(id: chatTypePrivate.userId) else { return nil }
            
            if case .userTypeRegular = user.type {
                return CustomChat(
                    chat: chat,
                    positions: chat.positions,
                    unreadCount: chat.unreadCount,
                    user: user,
                    lastMessage: chat.lastMessage,
                    draftMessage: chat.draftMessage
                )
            }
        }
        
        return nil
    }
}

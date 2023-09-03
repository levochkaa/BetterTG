// RootViewModel.swift

import Combine
import TDLibKit
import Observation

@Observable final class RootViewModel {
    var mainChats = [CustomChat]()
    var archivedChats = [CustomChat]()
    var openedItem: OpenedItem? = nil
    @ObservationIgnored var namespace: Namespace.ID! = nil
    
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
            .sorted {
                if let firstOrder = $0.positions.main?.order, let secondOrder = $1.positions.main?.order {
                    return firstOrder > secondOrder
                } else {
                    return $0.chat.id > $1.chat.id
                }
            }
            .filter {
                query.isEmpty
                || $0.user.firstName.lowercased().contains(query)
                || $0.user.lastName.lowercased().contains(query)
                || $0.chat.title.lowercased().contains(query)
            }
    }
}

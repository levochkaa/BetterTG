// RootViewModel.swift

import SwiftUI
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
    
    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
            case .active:
                log("App is Active")
                Task {
                    await mainChats.asyncForEach { customChat in
                        await tdGetChatHistory(chatId: customChat.chat.id)
                    }
                }
            case .inactive:
                log("App is Inactive")
            case .background:
                log("App is in a Background")
            @unknown default:
                log("Unknown state of an App")
        }
    }
    
    func togglePinned(chatId: Int64, chatList: ChatList, value: Bool) {
        Task {
            await tdToggleChatIsPinned(
                chatId: chatId,
                chatList: chatList,
                isPinned: value
            )
        }
    }
    
    func filteredSortedChats(_ query: String, for list: ChatList = .chatListMain) -> [CustomChat] {
        let query = query.lowercased()
        var customChats = [CustomChat]()
        switch list {
            case .chatListMain:
                customChats = mainChats
            case .chatListArchive:
                customChats = archivedChats
            default:
                return []
        }
        
        return customChats
            .sorted {
                let firstOrder = $0.positions.first(where: { $0.list == list })?.order
                let secondOrder = $1.positions.first(where: { $0.list == list })?.order
                
                if let firstOrder, let secondOrder {
                    return firstOrder > secondOrder
                } else {
                    return $0.chat.id < $1.chat.id
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

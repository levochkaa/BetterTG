// FolderUnreadStore.swift

import Combine
import TDLibKitDynamic

// MARK: - FolderUnreadState

struct FolderUnreadState: Equatable {
    static let empty = FolderUnreadState(count: 0, hasUnmuted: false)

    let count: Int
    let hasUnmuted: Bool
}

// MARK: - FolderUnreadStore

@MainActor final class FolderUnreadStore: ObservableObject {
    // MARK: Internal

    static let shared = FolderUnreadStore()

    // MARK: Private

    private var statesByClient = [Int32: [ChatList: FolderUnreadState]]()

    private init() {}

    func states(for clientID: Int32) -> [ChatList: FolderUnreadState] {
        statesByClient[clientID] ?? [:]
    }

    func update(_ update: UpdateUnreadChatCount, clientID: Int32) {
        let state = FolderUnreadState(
            count: update.unreadCount,
            hasUnmuted: update.unreadUnmutedCount > 0,
        )
        guard statesByClient[clientID]?[update.chatList] != state else { return }
        objectWillChange.send()
        statesByClient[clientID, default: [:]][update.chatList] = state
    }
}

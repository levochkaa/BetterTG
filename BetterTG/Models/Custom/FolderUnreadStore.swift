// FolderUnreadStore.swift

import Combine
import TDLibKit

struct FolderUnreadState: Equatable {
    static let empty = FolderUnreadState(count: 0, hasUnmuted: false)

    let count: Int
    let hasUnmuted: Bool
}

@MainActor final class FolderUnreadStore: ObservableObject {
    static let shared = FolderUnreadStore()

    private init() {}

    private var statesByClient = [Int32: [ChatList: FolderUnreadState]]()

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

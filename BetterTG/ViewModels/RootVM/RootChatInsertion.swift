// RootChatInsertion.swift

import Foundation
import TDLibKitDynamic

/// Serializes membership intents while peer metadata is being hydrated. The
/// captured client/root ticket remains the authority for every asynchronous read.
@MainActor final class RootChatInsertion {
    private struct Key: Hashable {
        let accountID: UUID
        let clientID: Int32
        let chatID: Int64
        let list: ChatList
    }

    private final class Pending {
        let key: Key
        weak var folder: CustomFolder?
        var position: ChatPosition
        var revision: UInt64 = 0
        var task: Task<Void, Never>?
        let accepts: () -> Bool
        let hydrate: () async -> CustomChat?

        init(
            key: Key,
            folder: CustomFolder,
            position: ChatPosition,
            accepts: @escaping () -> Bool,
            hydrate: @escaping () async -> CustomChat?,
        ) {
            self.key = key
            self.folder = folder
            self.position = position
            self.accepts = accepts
            self.hydrate = hydrate
        }
    }

    private var pending = [Key: Pending]()

    /// Last-message/draft updates contain the complete position vector. TDLib
    /// omits zero-order lists, so omission revokes a pending insertion as well.
    static func position(in positions: [ChatPosition], for list: ChatList) -> ChatPosition {
        positions.first { $0.list == list }
            ?? ChatPosition(isPinned: false, list: list, order: 0, source: nil)
    }

    func invalidate() {
        let retired = pending.values
        pending.removeAll()
        for entry in retired {
            entry.task?.cancel()
            entry.task = nil
        }
    }

    func apply(
        source: TdUpdateSource,
        chatID: Int64,
        position: ChatPosition,
        folder: CustomFolder,
        accepts: @escaping () -> Bool,
        hydrate: @escaping () async -> CustomChat?,
    ) {
        guard position.list == folder.chatList, accepts() else { return }
        let key = Key(accountID: source.accountID, clientID: source.clientID, chatID: chatID, list: position.list)
        if position.order == 0 {
            retire(key)
            folder.chats.removeAll { $0.id == chatID }
            return
        }
        if let chat = folder.chats.first(where: { $0.id == chatID }) {
            retire(key)
            chat.position = position
            return
        }
        if let entry = pending[key], entry.folder === folder {
            entry.position = position
            entry.revision &+= 1
            return
        }
        retire(key)
        let entry = Pending(key: key, folder: folder, position: position, accepts: accepts, hydrate: hydrate)
        pending[key] = entry
        entry.task = Task { [weak self] in await self?.load(entry) }
    }

    private func retire(_ key: Key) {
        guard let entry = pending.removeValue(forKey: key) else { return }
        entry.task?.cancel()
        entry.task = nil
    }

    private func isCurrent(_ entry: Pending) -> Bool {
        !Task.isCancelled && pending[entry.key] === entry && entry.folder != nil && entry.accepts()
    }

    private func load(_ entry: Pending) async {
        defer {
            // A canceled read can finish after remove→re-add or client rollover.
            // It must never release the replacement request's ownership.
            if pending[entry.key] === entry { pending[entry.key] = nil }
            entry.task = nil
        }
        while isCurrent(entry) {
            let revision = entry.revision
            let chat = await entry.hydrate()
            guard isCurrent(entry) else { return }
            // One in-flight read per intent; coalesce updates received during it.
            // Read again after those updates, including their last/draft values.
            guard entry.revision == revision else { continue }
            guard let chat, chat.id == entry.key.chatID, let folder = entry.folder,
                  folder.chatList == entry.key.list,
                  !folder.chats.contains(where: { $0.id == entry.key.chatID }) else { return }
            chat.position = entry.position
            folder.chats.append(chat)
            return
        }
    }
}

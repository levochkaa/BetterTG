// PendingChatRemovals.swift

import Combine
import Foundation

/// Telegram's scheduled chat removal (ChatListController `schedulePeerChatRemoval`): a deleted or left chat leaves
/// the list at once, the Undo toast stays 5 s, and only then the request runs; Undo brings the row back untouched.
@MainActor final class PendingChatRemovals: ObservableObject {
    // MARK: Internal

    struct Key: Hashable {
        let clientID: Int32
        let chatID: Int64
    }

    static let shared = PendingChatRemovals()
    /// Matches the Undo toast's lifetime.
    static let delay: TimeInterval = 5

    /// Chats hidden from the list while their removal waits.
    @Published private(set) var hiddenKeys = Set<Key>()

    // MARK: Private

    private var pending = [Key: DispatchWorkItem]()

    func isHidden(clientID: Int32, chatID: Int64) -> Bool {
        hiddenKeys.contains(Key(clientID: clientID, chatID: chatID))
    }

    /// Hides the chat when `hides`, then runs `commit` after the delay unless `cancel` comes first. The row comes
    /// back once the commit finishes; TDLib's own updates have removed it by then if the request succeeded.
    func schedule(_ key: Key, hides: Bool, commit: @escaping @MainActor () async -> Void) -> () -> Void {
        pending[key]?.cancel()
        if hides { hiddenKeys.insert(key) }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                await commit()
                guard let self, pending[key] == nil else { return }
                hiddenKeys.remove(key)
            }
            self?.pending[key] = nil
        }
        pending[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: work)
        return { [weak self] in
            guard let self, let scheduled = pending[key], scheduled === work else { return }
            scheduled.cancel()
            pending[key] = nil
            hiddenKeys.remove(key)
        }
    }

    /// Hides chats until the returned closure runs: ChatFolderLinkPreviewScreen's addHiddenChatIds for the chats a
    /// folder's removal leaves while it waits behind its Undo toast. A chat with its own removal pending stays hidden.
    func hide(_ keys: [Key]) -> () -> Void {
        let added = keys.filter { hiddenKeys.insert($0).inserted }
        return { [weak self] in
            guard let self else { return }
            for key in added where pending[key] == nil {
                hiddenKeys.remove(key)
            }
        }
    }
}

// RecentEmojiStore.swift

import Foundation

// MARK: - RecentEmojiStore

/// Telegram's LocalRecentEmoji list for each account: the latest emoji first, at most 20
/// (addOrMoveToFirstPositionOrderedItemListItem with removeTailIfCountExceeds 20). Logging out removes the list.
@MainActor final class RecentEmojiStore {
    static let shared = RecentEmojiStore()

    private static let limit = 20

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(_ accountID: UUID) -> String {
        "RecentEmoji.\(accountID.uuidString)"
    }

    func emojis(accountID: UUID) -> [String] {
        defaults.stringArray(forKey: Self.key(accountID)) ?? []
    }

    func record(_ emoji: String, accountID: UUID) {
        var emojis = emojis(accountID: accountID).filter { $0 != emoji }
        emojis.insert(emoji, at: 0)
        defaults.set(Array(emojis.prefix(Self.limit)), forKey: Self.key(accountID))
    }

    func discardAccount(_ accountID: UUID) {
        defaults.removeObject(forKey: Self.key(accountID))
    }
}

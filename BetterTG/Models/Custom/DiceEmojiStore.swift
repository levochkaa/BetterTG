// DiceEmojiStore.swift

import Foundation

/// The emoji each client's server rolls as dice (`updateDiceEmojis`). Telegram sends a message that is only one of
/// them as a die (ChatControllerNode.sendCurrentMessage, `interactiveEmojis`).
@MainActor enum DiceEmojiStore {
    private static var emojisByClient = [Int32: Set<String>]()

    static func update(_ emojis: [String], clientID: Int32) {
        emojisByClient[clientID] = Set(emojis)
    }

    static func contains(_ text: String, clientID: Int32) -> Bool {
        emojisByClient[clientID]?.contains(text) == true
    }
}

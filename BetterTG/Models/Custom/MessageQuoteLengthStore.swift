// MessageQuoteLengthStore.swift

import Foundation

/// Each client's `message_reply_quote_length_max` from `updateOption`, so a quote is built the moment it is chosen.
/// Telegram's quoteMaxLength reads the app configuration synchronously and falls back to 1024, TDLib's default.
@MainActor enum MessageQuoteLengthStore {
    static let optionName = "message_reply_quote_length_max"
    static let defaultLength = 1024

    private static var lengthByClient = [Int32: Int]()

    /// A nil value is `optionValueEmpty`: TDLib's default applies again.
    static func update(_ value: Int64?, clientID: Int32) {
        lengthByClient[clientID] = value.map { max(1, Int(clamping: $0)) }
    }

    static func maximumLength(clientID: Int32) -> Int {
        lengthByClient[clientID] ?? defaultLength
    }
}

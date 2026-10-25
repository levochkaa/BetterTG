// SensitiveContent.swift

import Foundation
import TDLibKit

// MARK: - SensitiveContentStore

/// Telegram's sensitive content (ContentSettings' `sensitiveContentEnabled`) per client: TDLib's
/// `ignore_sensitive_content_restrictions` (Show 18+ Content) and `can_ignore_sensitive_content_restrictions`
/// (whether the account may turn it on), and which messages TDLib marks as 18+.
@MainActor enum SensitiveContentStore {
    static let ignoreOptionName = "ignore_sensitive_content_restrictions"
    static let canIgnoreOptionName = "can_ignore_sensitive_content_restrictions"

    /// Posted when either option changes for a client.
    static let didChange = Notification.Name("BetterTG.SensitiveContentStore.didChange")

    private static var ignores = [Int32: Bool]()
    private static var canIgnore = [Int32: Bool]()

    #if DEBUG
        /// `-debug-sensitive-chat CHAT_ID`: the chat's media counts as 18+ and stays covered, to check the cover
        /// without such media or a change to the account's Show 18+ Content.
        private nonisolated static let debugSensitiveChatID: Int64? = {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-debug-sensitive-chat"), index + 1 < arguments.count else {
                return nil
            }
            return Int64(arguments[index + 1])
        }()
    #endif

    static func update(option name: String, value: OptionValue, clientID: Int32) {
        guard name == ignoreOptionName || name == canIgnoreOptionName else { return }
        let flag =
            if case .optionValueBoolean(let boolean) = value {
                boolean.value
            } else {
                false
            }
        if name == ignoreOptionName {
            ignores[clientID] = flag
        } else {
            canIgnore[clientID] = flag
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Whether 18+ media shows without a cover for the client.
    static func ignores(clientID: Int32?) -> Bool {
        clientID.flatMap { ignores[$0] } ?? false
    }

    /// Whether 18+ media of the chat shows without a cover. The debug chat always covers it, so the cover can be
    /// checked without changing the account's setting.
    static func shows(chatID: Int64, clientID: Int32?) -> Bool {
        #if DEBUG
            if chatID == debugSensitiveChatID { return false }
        #endif
        return ignores(clientID: clientID)
    }

    static func canIgnore(clientID: Int32?) -> Bool {
        clientID.flatMap { canIgnore[$0] } ?? false
    }

    /// TDLib's `restriction_info.has_sensitive_content`.
    nonisolated static func isSensitive(_ message: Message) -> Bool {
        #if DEBUG
            if message.chatId == debugSensitiveChatID { return true }
        #endif
        return message.restrictionInfo?.hasSensitiveContent == true
    }
}

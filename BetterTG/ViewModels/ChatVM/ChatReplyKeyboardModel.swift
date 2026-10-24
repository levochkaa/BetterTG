// ChatReplyKeyboardModel.swift

import Combine
import Foundation
import TDLibKit

/// The chat's bot reply keyboard: TDLib's `reply_markup_message_id` and `updateChatReplyMarkup`, with Telegram's
/// per-chat keyboard state (`keyboardButtonsMessage` and `ChatInterfaceMessageActionsState`).
@MainActor final class ChatReplyKeyboardModel: ObservableObject {
    /// A keyboard of buttons the composer can show in place of the system keyboard (`visibleButtonKeyboardMarkup`).
    struct Keyboard {
        let messageID: Int64
        let markup: TDNativeReplyMarkupShowKeyboard
        /// Changes with every new keyboard message or markup, so the panel rebuilds only then.
        let revision: Int
    }

    // MARK: Private

    private static var closedMessageIDs = [String: Int64]()

    // MARK: Internal

    /// The message whose reply markup the chat uses; nil when the chat has none.
    @Published private(set) var message: Message?
    /// Bumped whenever `message` changes; Telegram re-evaluates the input mode on such a change.
    @Published private(set) var revision = 0

    private let chatID: Int64
    private let client: TDLibClient
    private let closedKey: String
    private let isCurrent: () -> Bool
    private var generation = 0
    private var loadTask: Task<Void, Never>?
    /// The message's keyboard of buttons, read once per change: every composer update asks for it.
    private var keyboard: Keyboard?
    private var dismissedMessageID: Int64?
    private var processedSetupReplyMessageID: Int64?
    private var unfocusedReplyMessageID: Int64?
    private var releasedMessageIDs = Set<Int64>()

    /// The keyboard the composer offers. A used one-time keyboard is hidden until TDLib removes it
    /// (`dismissedButtonKeyboardMessageId`).
    var offeredKeyboard: Keyboard? {
        guard let keyboard, keyboard.messageID != dismissedMessageID else { return nil }
        return keyboard
    }

    /// The user closed this keyboard with the input button or by dismissing it (`closedButtonKeyboardMessageId`).
    /// Telegram keeps this in the chat's interface state; BetterTG keeps it for the app session.
    var isClosed: Bool {
        guard let message else { return false }
        return Self.closedMessageIDs[closedKey] == message.id
    }

    /// Telegram's `requestsSetupReply`: a force reply, or a keyboard that forces a reply to its message.
    var requestsSetupReply: Bool {
        guard let message, message.id != dismissedMessageID else { return false }
        return switch message.replyMarkup {
        case .replyMarkupForceReply: true
        case .replyMarkupShowKeyboard(let markup): markup.forceReply
        case nil,
             .replyMarkupInlineKeyboard,
             .replyMarkupRemoveKeyboard: false
        }
    }

    init(chatID: Int64, accountID: UUID?, client: TDLibClient, isCurrent: @escaping () -> Bool) {
        self.chatID = chatID
        self.client = client
        self.closedKey = "\(accountID?.uuidString ?? "-"):\(chatID)"
        self.isCurrent = isCurrent
    }

    deinit {
        loadTask?.cancel()
    }

    /// The input placeholder a keyboard or force reply asks for (`visibleReplyMarkupPlaceholder`). A force reply
    /// shows it only while the composer replies to its message.
    func placeholder(replyMessageID: Int64?) -> String? {
        guard let message, message.id != dismissedMessageID else { return nil }
        if requestsSetupReply, replyMessageID != message.id { return nil }
        let placeholder =
            switch message.replyMarkup {
            case .replyMarkupForceReply(let markup): markup.inputFieldPlaceholder
            case .replyMarkupShowKeyboard(let markup): markup.inputFieldPlaceholder
            case nil,
                 .replyMarkupInlineKeyboard,
                 .replyMarkupRemoveKeyboard: ""
            }
        return placeholder.isEmpty ? nil : placeholder
    }

    /// Telegram opens a new keyboard in place of the system keyboard unless a message is being edited or typed, or
    /// the user closed or used this keyboard.
    func opensAutomatically(isEditing: Bool, hasText: Bool) -> Bool {
        offeredKeyboard != nil && !isClosed && !isEditing && !hasText
    }

    /// The keyboard message the chat should reply to, once (`processedSetupReplyMessageId`): a force reply in any
    /// chat, and any keyboard in a group, so that the bot receives the answer.
    func replySetupCandidate(isGroup: Bool) -> Message? {
        guard let message, message.id != processedSetupReplyMessageID,
              requestsSetupReply || (isGroup && offeredKeyboard != nil)
        else { return nil }
        return message
    }

    func markReplySetUp(messageID: Int64) {
        processedSetupReplyMessageID = messageID
        unfocusedReplyMessageID = messageID
    }

    /// A reply the keyboard set up doesn't raise the system keyboard over the bot keyboard; true once for it.
    func takeUnfocusedReply(_ messageID: Int64) -> Bool {
        guard unfocusedReplyMessageID == messageID else { return false }
        unfocusedReplyMessageID = nil
        return true
    }

    func setClosed(_ closed: Bool) {
        guard let message else { return }
        if closed {
            Self.closedMessageIDs[closedKey] = message.id
        } else if Self.closedMessageIDs[closedKey] == message.id {
            Self.closedMessageIDs[closedKey] = nil
        }
    }

    /// A button of a one-time keyboard was used: Telegram hides the keyboard (`dismissReplyMarkupMessage`), and TDLib
    /// asks for `deleteChatReplyMarkup`.
    func noteButtonUsed(messageID: Int64) {
        guard let keyboard = offeredKeyboard, keyboard.messageID == messageID, keyboard.markup.oneTime else { return }
        dismissedMessageID = messageID
        Self.closedMessageIDs[closedKey] = messageID
        objectWillChange.send()
        release(messageID: messageID)
    }

    /// The composer stopped replying to a message: a force reply to it was used or dismissed, which TDLib asks to
    /// report with `deleteChatReplyMarkup`.
    func noteReplyEnded(messageID: Int64) {
        guard let message, message.id == messageID,
              case .replyMarkupForceReply = message.replyMarkup else { return }
        release(messageID: messageID)
    }

    /// Reads the chat's current reply markup message; an update that arrives meanwhile wins.
    func load() {
        loadTask?.cancel()
        let generation = generation
        let chatID = chatID
        let client = client
        loadTask = Task { [weak self] in
            let message: Message?
            do {
                let chat = try await client.getChat(chatId: chatID)
                message =
                    if chat.replyMarkupMessageId == 0 {
                        nil
                    } else {
                        try await client.getMessage(chatId: chatID, messageId: chat.replyMarkupMessageId)
                    }
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.generation == generation, isCurrent(),
                  TDLib.shared.activeClient.id == client.id else { return }
            loadTask = nil
            replace(message)
        }
    }

    func apply(_ update: TDNativeUpdateChatReplyMarkup) {
        guard update.chatId == chatID, isCurrent(), TDLib.shared.activeClient.id == client.id else { return }
        generation &+= 1
        loadTask?.cancel()
        loadTask = nil
        replace(update.replyMarkupMessage)
    }

    private func replace(_ message: Message?) {
        guard message != self.message else { return }
        let revision = revision &+ 1
        keyboard =
            if let message, case .replyMarkupShowKeyboard(let markup) = message.replyMarkup,
            markup.rows.contains(where: { !$0.isEmpty }) {
                Keyboard(messageID: message.id, markup: markup, revision: revision)
            } else {
                nil
            }
        self.message = message
        self.revision = revision
    }

    private func release(messageID: Int64) {
        guard isCurrent(), TDLib.shared.activeClient.id == client.id,
              releasedMessageIDs.insert(messageID).inserted else { return }
        let chatID = chatID
        let client = client
        Task { try? await client.deleteChatReplyMarkup(chatId: chatID, messageId: messageID) }
    }
}

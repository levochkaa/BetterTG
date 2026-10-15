// MessageDeliveryState.swift

import Foundation
import TDLibKit

// MARK: - MessageDeliveryState

enum MessageDeliveryState: Equatable {
    case none, sending, failed, delivered, read

    var symbol: String {
        switch self {
        case .none: ""
        case .sending: "◷"
        case .failed: "!"
        case .delivered: "✓"
        case .read: "✓✓"
        }
    }

    var spoken: String? {
        switch self {
        case .none: nil
        case .sending: L10n.telegram("VoiceOver.Chat.Sending")
        case .failed: L10n.telegram("VoiceOver.Chat.Failed")
        case .delivered: L10n.telegram("Conversation.ChecksTooltip.Delivered")
        case .read: L10n.telegram("Conversation.ChecksTooltip.Read")
        }
    }

    static func resolve(
        _ message: Message,
        permitsFinalStatus: Bool,
        readOutbox: Int64?,
        topic: MessageTopic? = nil,
    ) -> Self {
        // Temporary IDs are never compared with a read watermark.
        if case .messageSendingStateFailed = message.sendingState { return .failed }
        if case .messageSendingStatePending = message.sendingState { return .sending }
        guard permitsFinalStatus, message.isOutgoing, !message.isChannelPost,
              MessageDeliveryReceiptScope(topic: topic) != nil, message.topicId == topic else { return .none }
        return readOutbox.map { message.id <= $0 } == true ? .read : .delivered
    }
}

// MARK: - MessageDeliveryReceiptScope

enum MessageDeliveryReceiptScope: Equatable {
    case chat
    case forum(Int)
    case thread(Int64)

    init?(topic: MessageTopic?) {
        switch topic {
        case nil: self = .chat
        case .messageTopicForum(let forum) where forum.forumTopicId > 0: self = .forum(forum.forumTopicId)
        case .messageTopicThread(let thread) where thread.messageThreadId > 0: self = .thread(thread.messageThreadId)
        default: return nil
        }
    }
}

// MARK: - ChatDeliveryReceiptState

/// One immutable chat, explicit forum-topic or reply-thread receipt key. Cached history values are not
/// accepted here: only a scoped update or a revision-fenced fresh read can seed it.
struct ChatDeliveryReceiptState {
    struct Read {
        fileprivate let id: UUID
        fileprivate let revision: UInt64
    }

    let location: ChatLocation
    private(set) var lastReadOutbox: Int64?

    private var revision = UInt64.zero
    private var readID: UUID?
    private var retired = false

    init(location: ChatLocation) { self.location = location }

    func permits(_ source: TdUpdateSource?, location: ChatLocation) -> Bool {
        !retired && self.location == location && MessageDeliveryReceiptScope(topic: location.topic) != nil
            && source?.matches(location) == true
    }

    mutating func beginRead(source: TdUpdateSource?, location: ChatLocation) -> Read? {
        guard permits(source, location: location) else { return nil }
        let id = UUID()
        readID = id
        return Read(id: id, revision: revision)
    }

    @discardableResult mutating func finishRead(
        _ read: Read,
        value: Int64?,
        source: TdUpdateSource?,
        location: ChatLocation,
    ) -> Bool {
        guard location.topic == nil else { return false }
        return finishValue(read, value: value, source: source, location: location)
    }

    @discardableResult mutating func receive(
        _ update: UpdateChatReadOutbox,
        source: TdUpdateSource?,
        location: ChatLocation,
    ) -> Bool {
        guard permits(source, location: location), location.topic == nil,
              update.chatId == location.chatID else { return false }
        return acceptUpdate(update.lastReadOutboxMessageId)
    }

    @discardableResult mutating func receive(
        _ update: UpdateForumTopic,
        source: TdUpdateSource?,
        location: ChatLocation,
    ) -> Bool {
        guard permits(source, location: location), update.chatId == location.chatID,
              update.forumTopicId == location.forumTopicID else { return false }
        return acceptUpdate(update.lastReadOutboxMessageId)
    }

    @discardableResult mutating func finishForumRead(
        _ read: Read,
        topic: ForumTopic?,
        source: TdUpdateSource?,
        location: ChatLocation,
    ) -> Bool {
        guard location.forumTopicID != nil else { return false }
        let matches = topic?.info.chatId == location.chatID
            && topic?.info.forumTopicId == location.forumTopicID
        return finishValue(
            read,
            value: matches ? topic?.lastReadOutboxMessageId : nil,
            source: source,
            location: location,
        )
    }

    /// A reply thread's watermark is its root's reply info (Telegram's `maxReadOutgoingMessageId` of the thread),
    /// read with `getMessageThread`.
    @discardableResult mutating func finishThreadRead(
        _ read: Read,
        thread: MessageThreadInfo?,
        source: TdUpdateSource?,
        location: ChatLocation,
    ) -> Bool {
        guard location.messageThreadID != nil else { return false }
        let matches = thread?.chatId == location.chatID && thread?.messageThreadId == location.messageThreadID
        return finishValue(
            read,
            value: matches ? thread?.replyInfo?.lastReadOutboxMessageId : nil,
            source: source,
            location: location,
        )
    }

    /// TDLib republishes the root's reply info when the thread's outbox is read (`updateReadChannelDiscussionOutbox`).
    @discardableResult mutating func receiveThreadRoot(
        _ replyInfo: MessageReplyInfo,
        chatID: Int64,
        messageID: Int64,
        source: TdUpdateSource?,
        location: ChatLocation,
    ) -> Bool {
        guard permits(source, location: location), chatID == location.chatID,
              messageID == location.messageThreadID else { return false }
        return acceptUpdate(replyInfo.lastReadOutboxMessageId)
    }

    mutating func retire() {
        retired = true
        readID = nil
        lastReadOutbox = nil
    }

    private mutating func finishValue(
        _ read: Read,
        value: Int64?,
        source: TdUpdateSource?,
        location: ChatLocation,
    ) -> Bool {
        guard permits(source, location: location), readID == read.id else { return false }
        readID = nil
        guard revision == read.revision, let value else { return false }
        let changed = lastReadOutbox != value
        lastReadOutbox = value
        return changed
    }

    private mutating func acceptUpdate(_ value: Int64) -> Bool {
        revision &+= 1 // Even a repeated accepted update supersedes an earlier read.
        let changed = lastReadOutbox != value
        lastReadOutbox = value
        return changed
    }
}

// MARK: - ChatMessageRenderOwners

/// Same stable album ID may acquire a new wrapper whose state was derived before
/// subscriptions were installed. Reconfigure that row in the structural apply.
@MainActor struct ChatMessageRenderOwners {
    private var owners = [DisplayedMessageID: CustomMessage]()

    mutating func replace(_ messages: [CustomMessage]) -> Set<DisplayedMessageID> {
        let next = Dictionary(
            messages.map { ($0.displayedID, $0) },
            uniquingKeysWith: { _, new in new },
        )
        let changed = Set(next.keys.filter { owners[$0] != nil && owners[$0] !== next[$0] })
        owners = next
        return changed
    }
}

// MARK: - ChatMessageRenderInvalidations

/// Coalesce a synchronous receipt burst into one stable-ID apply. Queued owners
/// are held only until the next main-queue turn and validated against that turn's model.
@MainActor struct ChatMessageRenderInvalidations {
    private var pending = [ObjectIdentifier: (message: CustomMessage, owner: AnyObject)]()

    mutating func enqueue(_ message: CustomMessage, owner: AnyObject) -> Bool {
        let needsFlush = pending.isEmpty
        pending[ObjectIdentifier(message)] = (message, owner)
        return needsFlush
    }

    mutating func drain(current: [CustomMessage], owner: AnyObject) -> [DisplayedMessageID] {
        let requests = pending
        pending.removeAll()
        return current.compactMap { message in
            guard let request = requests[ObjectIdentifier(message)],
                  request.message === message, request.owner === owner else { return nil }
            return message.displayedID
        }
    }
}

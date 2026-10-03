// MessageDeliveryState.swift

import Foundation
import TDLibKitDynamic

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
        case .sending: "Sending"
        case .failed: "Failed to send"
        case .delivered: "Delivered"
        case .read: "Read"
        }
    }

    static func resolve(_ message: Message, permitsFinalStatus: Bool, readOutbox: Int64?) -> Self {
        // Temporary IDs are never compared with a read watermark.
        if case .messageSendingStateFailed = message.sendingState { return .failed }
        if case .messageSendingStatePending = message.sendingState { return .sending }
        guard permitsFinalStatus, message.isOutgoing, !message.isChannelPost,
              message.topicId == nil else { return .none }
        return readOutbox.map { message.id <= $0 } == true ? .read : .delivered
    }
}

// MARK: - ChatDeliveryReceiptState

/// One immutable ordinary-chat receipt key. Cached Chat/history values are not
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
        !retired && self.location == location && location.topic == nil && source?.matches(location) == true
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
        guard permits(source, location: location), readID == read.id else { return false }
        readID = nil
        guard revision == read.revision, let value else { return false }
        let changed = lastReadOutbox != value
        lastReadOutbox = value
        return changed
    }

    @discardableResult mutating func receive(
        _ update: UpdateChatReadOutbox,
        source: TdUpdateSource?,
        location: ChatLocation,
    ) -> Bool {
        guard permits(source, location: location), update.chatId == location.chatID else { return false }
        revision &+= 1 // Even a repeated accepted update supersedes an earlier read.
        let changed = lastReadOutbox != update.lastReadOutboxMessageId
        lastReadOutbox = update.lastReadOutboxMessageId
        return changed
    }

    mutating func retire() {
        retired = true
        readID = nil
        lastReadOutbox = nil
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

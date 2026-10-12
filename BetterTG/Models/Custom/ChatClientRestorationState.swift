// ChatClientRestorationState.swift

import TDLibKit
import UIKit

// MARK: - ChatHistoryMessageValue

/// A display seed, not proof of current TDLib or server state. Mutable wrappers
/// and in-flight mutation flags never cross the client boundary.
struct ChatHistoryMessageValue {
    let message: Message
    let sender: User?
    let serviceText: String?
    let reply: MessageReplyPresentation?
    let forward: MessageForwardPresentation?
    let album: [Message]
    let sendFailed: Bool
    let formattedText: FormattedText?
    let properties: MessageProperties
    let reactions: MessageReactions?
    let unreadReactions: [UnreadReaction]
    let isPinned: Bool
    let isReplyQuoteExpanded: Bool

    var sourceMessages: [Message] {
        album.isEmpty ? [message] : album.contains(where: { $0.id == message.id }) ? album : [message] + album
    }

    @MainActor init(_ value: CustomMessage) {
        self.message = value.message
        self.sender = value.senderUser
        self.serviceText = value.serviceText
        self.reply = value.replyPresentation
        self.forward = value.forwardPresentation
        self.album = value.album
        self.sendFailed = value.sendFailed
        self.formattedText = value.formattedText
        self.properties = value.properties
        self.reactions = value.reactions
        self.unreadReactions = value.unreadReactions
        self.isPinned = value.isPinned
        self.isReplyQuoteExpanded = value.isReplyQuoteExpanded
    }

    @MainActor func makeMessage() -> CustomMessage {
        let result = CustomMessage(
            message: message, senderUser: sender, replyPresentation: reply, forwardPresentation: forward,
            album: album, sendFailed: sendFailed, formattedText: formattedText, properties: properties,
            reactions: reactions, unreadReactions: unreadReactions, isPinned: isPinned,
        )
        // Initializer fallback must not replace an explicitly absent cached value.
        result.reactions = reactions
        result.isReplyQuoteExpanded = isReplyQuoteExpanded
        result.serviceText = serviceText
        return result
    }
}

// MARK: - ChatHistoryRestorationState

struct ChatHistoryRestorationState {
    let location: ChatLocation
    let messages: [ChatHistoryMessageValue]
    let oldestHistoryMessageID: Int64?
    let hasMoreMessages: Bool

    var sourceMessageIDs: [Int64] {
        var seen = Set<Int64>()
        return messages.flatMap(\.sourceMessages).map(\.id).filter { seen.insert($0).inserted }
    }

    @MainActor func makeMessages() -> [CustomMessage] { messages.map { $0.makeMessage() } }

    /// Reconcile individual source IDs, then rebuild album groups. Neither a
    /// partial latest page nor a failed read means other seed IDs were deleted.
    @MainActor func reconciling(
        confirmed: [ChatHistoryMessageValue],
        removedIDs: Set<Int64>,
    ) -> Self {
        var values = [Int64: CustomMessage]()
        func include(_ value: ChatHistoryMessageValue) {
            for member in value.sourceMessages where location.matches(message: member) {
                let wrapper: CustomMessage
                if member.id == value.message.id {
                    wrapper = value.makeMessage()
                } else {
                    wrapper = CustomMessage(
                        message: member, formattedText: MessageContentPresentation.make(member).formattedText,
                        properties: .default,
                    )
                    if member.senderId == value.message.senderId { wrapper.senderUser = value.sender }
                }
                wrapper.album = []
                values[member.id] = wrapper
            }
        }
        messages.forEach(include)
        confirmed.forEach(include)
        removedIDs.forEach { values.removeValue(forKey: $0) }
        let ordered = values.values.sorted { lhs, rhs in
            lhs.message.date == rhs.message.date ? lhs.id > rhs.id : lhs.message.date > rhs.message.date
        }
        var groups = [CustomMessage]()
        var indices = [DisplayedMessageID: Int]()
        for value in ordered {
            if let index = indices[value.displayedID] {
                groups[index].album.append(value.message)
            } else {
                indices[value.displayedID] = groups.count
                if value.message.mediaAlbumId != 0 { value.album = [value.message] }
                groups.append(value)
            }
        }
        return Self(
            location: location, messages: groups.map(ChatHistoryMessageValue.init),
            oldestHistoryMessageID: oldestHistoryMessageID, hasMoreMessages: hasMoreMessages,
        )
    }
}

// MARK: - ChatHistoryLatestRefreshCursor

/// A separate latest-history cursor bridges toward the seed instead of jumping
/// to its old pagination cursor. The caller issues one bounded page at a time.
struct ChatHistoryLatestRefreshCursor {
    private(set) var fromMessageID: Int64 = 0
    private(set) var isComplete = false

    private let seedIDs: Set<Int64>
    private let oldestSeed: Message?
    private let chatID: Int64

    init(seed: ChatHistoryRestorationState) {
        self.seedIDs = Set(seed.sourceMessageIDs)
        self.chatID = seed.location.chatID
        self.oldestSeed = seed.messages.flatMap(\.sourceMessages).min { lhs, rhs in
            lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date < rhs.date
        }
    }

    /// Use the raw TDLib page, before topic filtering or album grouping. A
    /// repeated cursor is a retryable failure, never invented end-of-history.
    @discardableResult mutating func accept(rawPage: [Message], requestedFromMessageID: Int64) -> Bool {
        guard !isComplete, requestedFromMessageID == fromMessageID,
              rawPage.allSatisfy({ $0.chatId == chatID }) else { return false }
        guard let last = rawPage.last else {
            isComplete = true
            return true
        }
        let overlaps = rawPage.contains { seedIDs.contains($0.id) }
        let passedSeed = oldestSeed.map {
            last.date < $0.date || last.date == $0.date && last.id <= $0.id
        } ?? true
        guard overlaps || passedSeed || last.id != fromMessageID else { return false }
        fromMessageID = last.id
        isComplete = overlaps || passedSeed
        return true
    }
}

// MARK: - ChatComposerImportBarrier

/// Local imports can finish into the retained owner after a same-account client
/// replacement. Their completion is not permission to send on an obsolete client.
@MainActor final class ChatComposerImportBarrier {
    struct Token: Hashable { fileprivate let id: UUID }

    let location: ChatLocation
    var onQuiescent: (() -> Void)?

    private var pending = Set<Token>()
    private var retired = false

    var isQuiescent: Bool { pending.isEmpty }

    init(location: ChatLocation) { self.location = location }

    func begin() -> Token? {
        guard !retired else { return nil }
        let token = Token(id: UUID())
        pending.insert(token)
        return token
    }

    /// Apply accepted local values before retrying restoration in onQuiescent.
    /// A foreign account, removed route or retired owner never receives values.
    @discardableResult func finish(
        _ token: Token,
        currentAccountID: UUID?,
        routeIsRetained: Bool,
        apply: () -> Void,
    ) -> Bool {
        guard pending.remove(token) != nil else { return false }
        let accepts = !retired && routeIsRetained && location.accountID != nil
            && location.accountID == currentAccountID
        if accepts { apply() }
        if pending.isEmpty { onQuiescent?() }
        return accepts
    }

    @discardableResult func retire() -> Bool {
        guard !retired, pending.isEmpty else { return false }
        retired = true
        onQuiescent = nil
        return true
    }
}

// MARK: - ChatHistoryRestorationRefresh

/// Results are applied only if no accepted update for that source message has
/// arrived since the read began. Call noteLiveUpdate at the accepted-update edge.
@MainActor final class ChatHistoryRestorationRefresh {
    enum UpdateKind {
        case authoritativeMessage
        case partial
    }

    enum MutationOwner: Hashable { case reaction, pin }

    enum Result {
        case message(ChatHistoryMessageValue)
        case missing
        case retry
    }

    struct Delivery {
        let source: TdUpdateSource
        let messageID: Int64
        let result: Result
    }

    struct LatestReadToken {
        fileprivate let id: UUID
        fileprivate let generation: UInt64
        fileprivate let latestGeneration: UInt64
        fileprivate let revisions: [Int64: UInt64]
    }

    struct ReadToken {
        fileprivate let owner: UUID
        fileprivate let generation: UInt64
        fileprivate let revisions: [Int64: UInt64]
    }

    private struct Request {
        let messageID: Int64
        let revision: UInt64
        let generation: UInt64
    }

    private let location: ChatLocation
    private let source: TdUpdateSource
    private let currentSource: () -> TdUpdateSource?
    private let read: (Int64) async throws -> Message
    private let hydrate: ((Message) async -> ChatHistoryMessageValue)?
    private let deliver: (Delivery) -> Void
    private let identity = UUID()
    private let retriesPartialRaces: Bool
    private var revisions = [Int64: UInt64]()
    private var authoritativeRevisions = [Int64: UInt64]()
    private var deletedIDs = Set<Int64>()
    private var mutationOwners = [Int64: Set<MutationOwner>]()
    private var latestReadID: UUID?
    private var latestGeneration = UInt64.zero
    private var queue: [Int64]
    private var queuedIDs: Set<Int64>
    private var queuedPayloads = [Int64: (message: Message, revision: UInt64)]()
    private var queueIndex = 0
    private var failed = Set<Int64>()
    private var generation = UInt64.zero
    private var cancelled = false
    private var running = false
    private var retryRequestedWhileRunning = false

    var failedMessageIDs: Set<Int64> { failed }
    var remainingCount: Int { queue.count - queueIndex }

    private var isCurrent: Bool {
        !cancelled && source.matches(location) && currentSource() == source
    }

    init(
        location: ChatLocation,
        source: TdUpdateSource,
        seedIDs: [Int64],
        visibleIDs: [Int64],
        currentSource: @escaping () -> TdUpdateSource?,
        read: @escaping (Int64) async throws -> Message,
        hydrate: ((Message) async -> ChatHistoryMessageValue)? = nil,
        retriesPartialRaces: Bool = false,
        deliver: @escaping (Delivery) -> Void,
    ) {
        self.location = location
        self.source = source
        self.currentSource = currentSource
        self.read = read
        self.hydrate = hydrate
        self.retriesPartialRaces = retriesPartialRaces
        self.deliver = deliver
        let seeded = Set(seedIDs)
        var seen = Set<Int64>()
        self.queue = (visibleIDs.filter(seeded.contains) + seedIDs).filter { seen.insert($0).inserted }
        self.queuedIDs = seen
    }

    func beginRead() -> ReadToken? {
        guard isCurrent, !Task.isCancelled else { return nil }
        return ReadToken(owner: identity, generation: generation, revisions: revisions)
    }

    /// Caller merges these values synchronously, with no await after admission.
    /// Normal pagination shares the ledger without a second hydration pass.
    func takeCurrentValues(_ values: [ChatHistoryMessageValue], token: ReadToken) -> [ChatHistoryMessageValue] {
        guard token.owner == identity, token.generation == generation else { return [] }
        return values.filter { value in
            let request = Request(
                messageID: value.message.id, revision: token.revisions[value.message.id, default: 0],
                generation: token.generation,
            )
            guard location.matches(message: value.message), permits(request) else {
                markUnresolved(request)
                return false
            }
            noteLiveUpdate(messageIDs: [request.messageID], kind: .authoritativeMessage)
            return true
        }
    }

    /// Install a complete accepted TD payload before metadata awaits. Field-only
    /// updates can then apply immediately without dropping the new message body.
    @discardableResult func acceptLiveMessage(_ value: ChatHistoryMessageValue) -> Bool {
        guard isCurrent, !Task.isCancelled, location.matches(message: value.message),
              !deletedIDs.contains(value.message.id) else { return false }
        guard mutationOwners[value.message.id] == nil else {
            noteLiveUpdate(messageIDs: [value.message.id])
            failed.insert(value.message.id)
            return false
        }
        noteLiveUpdate(messageIDs: [value.message.id], kind: .authoritativeMessage)
        deliver(.init(source: source, messageID: value.message.id, result: .message(value)))
        return true
    }

    func enqueue(messageIDs: [Int64]) {
        guard isCurrent else { return }
        queue.append(contentsOf: messageIDs.filter {
            !deletedIDs.contains($0) && mutationOwners[$0] == nil && queuedIDs.insert($0).inserted
        })
    }

    func enqueueHydration(message: Message) {
        guard isCurrent, location.matches(message: message), !deletedIDs.contains(message.id) else { return }
        queuedPayloads[message.id] = (message, revisions[message.id, default: 0])
        enqueue(messageIDs: [message.id])
    }

    /// A local mutation retains its original wrapper until its callback settles.
    /// Settlement is an explicit retry event, not an error-driven poll.
    func setMutationBlocked(_ blocked: Bool, messageID: Int64, owner: MutationOwner) {
        guard isCurrent, !deletedIDs.contains(messageID) else { return }
        if blocked {
            mutationOwners[messageID, default: []].insert(owner)
            noteLiveUpdate(messageIDs: [messageID])
            failed.insert(messageID)
        } else if mutationOwners[messageID]?.remove(owner) != nil, mutationOwners[messageID]?.isEmpty == true {
            mutationOwners[messageID] = nil
            enqueue(messageIDs: [messageID])
        }
    }

    /// Partial reactions, pins and other field updates invalidate an older read,
    /// but cannot establish that the seeded body is current. Only a complete
    /// accepted message satisfies the read that it superseded.
    func noteLiveUpdate(messageIDs: [Int64], kind: UpdateKind = .partial) {
        for id in messageIDs {
            revisions[id, default: 0] &+= 1
            if case .authoritativeMessage = kind {
                authoritativeRevisions[id] = revisions[id]
                failed.remove(id)
                queuedIDs.remove(id)
                queuedPayloads[id] = nil
            }
        }
    }

    func notePermanentDeletion(messageIDs: [Int64]) {
        noteLiveUpdate(messageIDs: messageIDs, kind: .authoritativeMessage)
        deletedIDs.formUnion(messageIDs)
        messageIDs.forEach { mutationOwners[$0] = nil }
    }

    /// Capture before requesting a raw latest page, including before its async
    /// presentation hydration. A newer request supersedes the previous token.
    func beginLatestRead() -> LatestReadToken? {
        guard isCurrent, !Task.isCancelled else { return nil }
        let id = UUID()
        latestReadID = id
        latestGeneration &+= 1
        return LatestReadToken(
            id: id, generation: generation, latestGeneration: latestGeneration, revisions: revisions,
        )
    }

    /// True permits advancing the separate raw-page cursor. Individual messages
    /// still obey accepted-update revisions and permanent deletion tombstones.
    @discardableResult func deliverLatest(_ values: [ChatHistoryMessageValue], token: LatestReadToken) -> Bool {
        guard isCurrent, !Task.isCancelled, token.id == latestReadID,
              token.generation == generation else { return false }
        latestReadID = nil
        defer { settleDeferredRetries() }
        for value in values where location.matches(message: value.message) {
            guard token.latestGeneration == latestGeneration else { return false }
            let request = Request(
                messageID: value.message.id, revision: token.revisions[value.message.id, default: 0],
                generation: token.generation,
            )
            apply(.message(value), for: request)
        }
        return isCurrent && !Task.isCancelled && token.latestGeneration == latestGeneration
    }

    /// Queue raw page values through the same four-message hydration lane. A
    /// later partial update makes its cached payload unusable and forces a read.
    @discardableResult func enqueueLatest(_ messages: [Message], token: LatestReadToken) -> Bool {
        guard isCurrent, !Task.isCancelled, token.id == latestReadID,
              token.generation == generation else { return false }
        latestReadID = nil
        defer { settleDeferredRetries() }
        for message in messages where location.matches(message: message) {
            let request = Request(
                messageID: message.id, revision: token.revisions[message.id, default: 0], generation: token.generation,
            )
            if permits(request) { enqueueHydration(message: message) }
            else { markUnresolved(request) }
        }
        return true
    }

    /// A Ready event received while the page RPC was busy authorizes one retry.
    /// Without that event, a failed/repeated page stops until the next event.
    func failLatestRead(token: LatestReadToken) -> Bool {
        guard isCurrent, !Task.isCancelled, token.id == latestReadID,
              token.generation == generation else { return false }
        latestReadID = nil
        return settleDeferredRetries()
    }

    func cancel() {
        cancelled = true
        generation &+= 1
        latestReadID = nil
        retryRequestedWhileRunning = false
    }

    /// Explicit connection/user event only. Errors never auto-poll or delete.
    func retryFailures() {
        guard isCurrent else { return }
        guard !running, latestReadID == nil else {
            retryRequestedWhileRunning = true
            return
        }
        enqueue(messageIDs: failed.sorted())
        failed.removeAll()
    }

    /// Four reads maximum, with no task allocated for the rest of the history.
    /// The caller drives further batches from completions while its route lives.
    @discardableResult func refreshNextBatch() async -> Bool {
        guard !running, isCurrent, !Task.isCancelled, queueIndex < queue.count else { return false }
        running = true
        defer {
            running = false
            if queueIndex == queue.count {
                queue.removeAll(keepingCapacity: true)
                queueIndex = 0
            }
            settleDeferredRetries()
        }
        let end = min(queueIndex + 4, queue.count)
        let requests = queue[queueIndex..<end].filter { queuedIDs.remove($0) != nil }.map {
            Request(messageID: $0, revision: revisions[$0, default: 0], generation: generation)
        }
        queueIndex = end
        guard !requests.isEmpty else { return true }
        async let first = fetch(requests[0])
        async let second = fetch(requests.count > 1 ? requests[1] : nil)
        async let third = fetch(requests.count > 2 ? requests[2] : nil)
        async let fourth = fetch(requests.count > 3 ? requests[3] : nil)
        let results = await [first, second, third, fourth]
        for (request, result) in zip(requests, results) {
            apply(result, for: request)
        }
        return true
    }

    private func apply(_ result: Result?, for request: Request) {
        guard let result, permits(request) else {
            markUnresolved(request)
            return
        }
        if case .retry = result {
            failed.insert(request.messageID)
        } else {
            // This complete value (or confirmed absence) also supersedes older
            // latest-page requests still waiting for presentation hydration.
            noteLiveUpdate(messageIDs: [request.messageID], kind: .authoritativeMessage)
        }
        // No await between the last source/revision check and delivery.
        deliver(.init(source: source, messageID: request.messageID, result: result))
    }

    @discardableResult private func settleDeferredRetries() -> Bool {
        guard retryRequestedWhileRunning else { return false }
        retryRequestedWhileRunning = false
        retryFailures()
        return isCurrent && !Task.isCancelled
    }

    private func markUnresolved(_ request: Request) {
        guard isCurrent, !Task.isCancelled, request.generation == generation,
              !deletedIDs.contains(request.messageID),
              revisions[request.messageID, default: 0] != request.revision,
              authoritativeRevisions[request.messageID, default: 0] <= request.revision else { return }
        failed.insert(request.messageID)
        // One coalesced read for a superseding external partial update. A plain
        // failed request has no newer revision, so it never enqueues itself.
        if retriesPartialRaces { enqueue(messageIDs: [request.messageID]) }
    }

    private func permits(_ request: Request) -> Bool {
        isCurrent && !Task.isCancelled && request.generation == generation
            && !deletedIDs.contains(request.messageID)
            && mutationOwners[request.messageID] == nil
            && revisions[request.messageID, default: 0] == request.revision
    }

    private func fetch(_ request: Request?) async -> Result? {
        guard let request, permits(request) else { return nil }
        let result: Result
        do {
            let payload = queuedPayloads.removeValue(forKey: request.messageID)
            let message: Message =
                if let payload, payload.revision == request.revision {
                    payload.message
                } else {
                    try await read(request.messageID)
                }
            guard permits(request) else { return nil }
            result =
                if message.id != request.messageID || message.chatId != location.chatID {
                    .retry
                } else if !location.matches(message: message) {
                    .missing // Confirmed moved out of this exact topic route.
                } else {
                    if let hydrate {
                        await .message(hydrate(message))
                    } else {
                        .message(ChatHistoryMessageValue(CustomMessage(
                            message: message, formattedText: MessageContentPresentation.make(message).formattedText,
                            properties: .default,
                        )))
                    }
                }
        } catch {
            // TDLib 022d6020: Requests.cpp GetMessageRequest passes a missing
            // object to Td.cpp send_result (1400-1401), producing this exact error.
            // Permission/400 errors, transport failures and decode errors retry.
            result =
                if let error = error as? TDLibError,
                error.code == 404, error.message == "Not Found" {
                    .missing
                } else {
                    .retry
                }
        }
        return permits(request) ? result : nil
    }
}

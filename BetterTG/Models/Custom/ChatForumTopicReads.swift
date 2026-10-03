// ChatForumTopicReads.swift

import Foundation
import TDLibKitDynamic

/// One metadata owner for the base forum timeline and its composer. Canceled
/// TDLib continuations still occupy a transport slot until their callback returns.
@MainActor final class ChatForumTopicReads {
    struct ReceiptProjection {
        static let unavailable = ReceiptProjection(permitsFinalStatus: false, readOutbox: nil, topic: nil)

        let permitsFinalStatus: Bool
        let readOutbox: Int64?
        let topic: MessageTopic?
    }

    private final class Entry {
        let id = UUID()
        var updates: ForumTopicLiveUpdateState
        var receipts: ChatDeliveryReceiptState
        var value: ForumTopic?
        var info: ForumTopicInfo?
        var infoRevision = UInt64.zero
        var attempted = false

        init(location: ChatLocation) {
            self.updates = ForumTopicLiveUpdateState(location: location)
            self.receipts = ChatDeliveryReceiptState(location: location)
        }

        func retire() {
            updates.retire()
            receipts.retire()
        }
    }

    private struct Request {
        let topicID: Int
        let entryID: UUID
        let task: Task<Void, Never>
    }

    private(set) var isRetired = false
    #if DEBUG
        private(set) var probeCompletedCount = 0
        var probeTasks: [Task<Void, Never>] { requests.values.map(\.task) }
        var probeDemandIDs: Set<Int> { Set(entries.keys) }
        var probeOutstandingCount: Int { requests.count }
    #endif

    private let location: ChatLocation
    private let currentSource: () -> TdUpdateSource?
    private let read: (Int) async throws -> ForumTopic
    private let publish: (Int, ForumTopic?) -> Void
    private let receiptChanged: (Int) -> Void
    private var entries = [Int: Entry]()
    private var order = [Int]()
    private var requests = [UUID: Request]()

    init(
        location: ChatLocation,
        currentSource: @escaping () -> TdUpdateSource?,
        read: @escaping (Int) async throws -> ForumTopic,
        publish: @escaping (Int, ForumTopic?) -> Void,
        receiptChanged: @escaping (Int) -> Void = { _ in },
    ) {
        self.location = location
        self.currentSource = currentSource
        self.read = read
        self.publish = publish
        self.receiptChanged = receiptChanged
    }

    deinit { requests.values.forEach { $0.task.cancel() } }

    /// Only raw forum identities enter the timeline demand. General is a caller's
    /// separate composer reason, never an inferred topic for a message.
    static func demandedIDs(chatID: Int64, messages: [Message], composerTopics: [MessageTopic?]) -> [Int] {
        var seen = Set<Int>()
        return (composerTopics + messages.filter { $0.chatId == chatID }.map(\.topicId)).compactMap { topic in
            guard case .messageTopicForum(let value) = topic, value.forumTopicId > 0,
                  seen.insert(value.forumTopicId).inserted else { return nil }
            return value.forumTopicId
        }
    }

    func receipt(for message: Message) -> ReceiptProjection {
        guard !isRetired, currentSource()?.matches(location) == true, message.chatId == location.chatID,
              case .messageTopicForum(let topic) = message.topicId, topic.forumTopicId > 0,
              let entry = entries[topic.forumTopicId],
              entry.receipts.permits(currentSource(), location: location.withForumTopic(id: topic.forumTopicId))
        else { return .unavailable }
        return ReceiptProjection(
            permitsFinalStatus: true,
            readOutbox: entry.receipts.lastReadOutbox,
            topic: message.topicId,
        )
    }

    func synchronize(_ ids: [Int]) {
        guard admitsWork() else { return }
        var seen = Set<Int>()
        order = ids.filter { $0 > 0 && seen.insert($0).inserted }
        for id in Array(entries.keys) where !seen.contains(id) {
            entries.removeValue(forKey: id)?.retire()
            requests.values.filter { $0.topicID == id }.forEach { $0.task.cancel() }
            publish(id, nil)
            receiptChanged(id)
        }
        for id in order where entries[id] == nil {
            entries[id] = Entry(location: location.withForumTopic(id: id))
        }
        pump()
    }

    /// Explicit composer refresh, coalesced with the same history read. The
    /// consumer reconciles this temporary demand after installing its context.
    func request(_ id: Int) {
        guard id > 0, admitsWork() else { return }
        if entries[id] == nil {
            entries[id] = Entry(location: location.withForumTopic(id: id))
            order.append(id)
        }
        if !requests.values.contains(where: { $0.topicID == id && $0.entryID == entries[id]?.id }) {
            entries[id]?.attempted = false
        }
        pump()
    }

    func retryMissing() {
        guard admitsWork() else { return }
        for (id, entry) in entries where entry.value == nil {
            guard !requests.values.contains(where: { $0.topicID == id && $0.entryID == entry.id }) else { continue }
            entry.attempted = false
        }
        pump()
    }

    func receive(_ update: UpdateForumTopic, source: TdUpdateSource) {
        guard admitsWork(), source.matches(location), update.chatId == location.chatID,
              let entry = entries[update.forumTopicId] else { return }
        if entry.receipts.receive(update, source: source, location: entry.receipts.location) {
            receiptChanged(update.forumTopicId)
        }
        guard
            let change = entry.updates.receive(update, current: entry.value, source: source)
        else { return }
        if change.metadataChanged, let value = entry.value {
            accept(entry.updates.applyingLatest(to: value), for: update.forumTopicId, entry: entry)
        }
    }

    func receive(_ info: ForumTopicInfo, source: TdUpdateSource) {
        guard admitsWork(), source.matches(location), info.chatId == location.chatID,
              let entry = entries[info.forumTopicId] else { return }
        entry.infoRevision &+= 1
        entry.info = info
        if let value = entry.value { accept(value.replacing(info: info), for: info.forumTopicId, entry: entry) }
    }

    func retire() {
        guard !isRetired else { return }
        isRetired = true
        let ids = Array(entries.keys)
        entries.values.forEach { $0.retire() }
        entries.removeAll()
        order.removeAll()
        requests.values.forEach { $0.task.cancel() }
        for id in ids {
            publish(id, nil)
            receiptChanged(id)
        }
    }

    private func admitsWork() -> Bool {
        guard !isRetired else { return false }
        guard location.topic == nil, currentSource()?.matches(location) == true else {
            retire()
            return false
        }
        return true
    }

    private func pump() {
        guard admitsWork() else { return }
        while requests.count < 2,
              let id = order.first(where: { id in
                  entries[id]?.attempted == false && !requests.values.contains { $0.topicID == id }
              }),
              let entry = entries[id], let ticket = entry.updates.beginRead(source: currentSource()),
              let receiptTicket = entry.receipts.beginRead(source: currentSource(), location: entry.receipts.location)
        {
            entry.attempted = true
            let requestID = UUID()
            let entryID = entry.id
            let infoRevision = entry.infoRevision
            let read = read
            let task = Task { [weak self] in
                defer { self?.finished(requestID) }
                guard !Task.isCancelled, self?.owns(requestID, entryID: entryID) == true else { return }
                let value = try? await read(id)
                guard !Task.isCancelled, let self, owns(requestID, entryID: entryID), let entry = entries[id]
                else { return }
                if entry.receipts.finishForumRead(
                    receiptTicket, topic: value, source: currentSource(), location: entry.receipts.location,
                ) { receiptChanged(id) }
                guard var accepted = entry.updates.finishRead(ticket, topic: value, source: currentSource())
                else { return }
                if entry.infoRevision != infoRevision, let info = entry.info {
                    accepted = accepted.replacing(info: info)
                } else {
                    entry.info = accepted.info
                }
                accept(accepted, for: id, entry: entry)
            }
            requests[requestID] = Request(topicID: id, entryID: entryID, task: task)
        }
    }

    private func owns(_ id: UUID, entryID: UUID) -> Bool {
        guard admitsWork(), let request = requests[id] else { return false }
        return request.entryID == entryID && entries[request.topicID]?.id == entryID
    }

    private func finished(_ id: UUID) {
        requests[id] = nil
        #if DEBUG
            probeCompletedCount += 1
        #endif
        pump()
    }

    private func accept(_ value: ForumTopic, for id: Int, entry: Entry) {
        guard entry.value != value else { return }
        entry.value = value
        publish(id, value)
    }
}

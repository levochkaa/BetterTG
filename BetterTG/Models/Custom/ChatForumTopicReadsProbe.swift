// ChatForumTopicReadsProbe.swift

#if DEBUG
import Foundation
import TDLibKit

@MainActor enum ChatForumTopicReadsProbe {
    @MainActor final class Transport {
        let source = TdUpdateSource(accountID: UUID(), clientID: 1)
        let chatID: Int64
        var current: TdUpdateSource?
        var calls = [(id: Int, continuation: CheckedContinuation<ForumTopic, Swift.Error>)]()
        var completed = Set<Int>()
        var values = [Int: ForumTopic]()
        var peak = 0
        var receiptEvents = [Int]()

        init(chatID: Int64 = 7) {
            self.chatID = chatID
            self.current = source
        }

        func read(_ id: Int) async throws -> ForumTopic {
            try await withCheckedThrowingContinuation { continuation in
                calls.append((id, continuation))
                peak = max(peak, calls.count - completed.count)
            }
        }

        func finish(_ index: Int, _ value: ForumTopic?) {
            guard completed.insert(index).inserted else { return }
            if let value { calls[index].continuation.resume(returning: value) }
            else { calls[index].continuation.resume(throwing: CancellationError()) }
        }

        func pendingIndex(topicID: Int) throws -> Int {
            let indices = calls.indices.filter { calls[$0].id == topicID && !completed.contains($0) }
            guard indices.count == 1, let index = indices.first else {
                throw Failure(description: "expected one outstanding read for exact topic")
            }
            return index
        }

        func clear() {
            for index in calls.indices where !completed.contains(index) {
                finish(index, nil)
            }
        }

        func reader(receiptChanged: @escaping (Int) -> Void = { _ in }) -> ChatForumTopicReads {
            ChatForumTopicReads(
                location: .init(accountID: source.accountID, chatID: chatID, clientID: 1, topic: nil),
                currentSource: { [self] in current },
                read: { [self] in try await read($0) },
                publish: { [self] in values[$0] = $1 },
                receiptChanged: { [self] id in
                    receiptEvents.append(id)
                    receiptChanged(id)
                },
            )
        }
    }

    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-forum-topic-reads") else { return }
        Task { @MainActor in
            let result: String
            do {
                try verifyDemand()
                try await verifyQueue()
                try await verifyMetadata()
                try await verifyIdentityAndRetry()
                try await verifyFailureProgress()
                try await verifyRetirement()
                try await verifyReceipts()
                result = "Forum topic reads probe passed: production-reader/max-two-uncancellable-RPCs/coalescing=true; "
                    + "exact-raw-demand/canonical-album/composer-reasons/pruning/re-demand=true; "
                    + "scalar-info-after-dispatch/raw-identity/failure-hold/explicit-retry=true; "
                    + "terminal-retire/ABA/weak-lifetime/late-cleanup=true; "
                    + "shared-read/per-topic-receipt/direct-before-metadata/late-baseline/re-demand=true; "
                    + "source-subscription/whole-ChatVM/pop-draft/receipt-UI/live-RPC=unverified; injected-reads-only"
            } catch {
                result = "Forum topic reads probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("forum-topic-reads-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func verifyDemand() throws {
        let oldest = MessageDeliveryProbe.fixture(id: 10, chatID: 7, album: 2, topic: forum(11))
        let newest = MessageDeliveryProbe.fixture(id: 12, chatID: 7, album: 2, topic: forum(22))
        let album = CustomMessage(message: newest, album: [newest, oldest], properties: .default)
        let values = album.sourceMessages + [
            MessageDeliveryProbe.fixture(id: 15, chatID: 8, topic: forum(33)),
            MessageDeliveryProbe.fixture(id: 16, chatID: 7, topic: forum(0)),
            MessageDeliveryProbe.fixture(id: 17, chatID: 7),
            MessageDeliveryProbe.fixture(id: 18, chatID: 7, topic: .messageTopicThread(.init(messageThreadId: 55))),
            MessageDeliveryProbe.fixture(
                id: 19,
                chatID: 7,
                topic: .messageTopicSavedMessages(.init(savedMessagesTopicId: 55)),
            ),
            MessageDeliveryProbe.fixture(
                id: 20,
                chatID: 7,
                topic: .messageTopicDirectMessages(.init(directMessagesChatTopicId: 55)),
            ),
        ]
        try require(album.deliverySourceMessage.id == oldest.id, "canonical album fixture mismatch")
        let ids = ChatForumTopicReads.demandedIDs(
            chatID: 7,
            messages: values,
            composerTopics: [forum(1), forum(44), forum(44)],
        )
        try require(
            Set(ids) == [1, 11, 22, 44] && ids.count == 4,
            "raw message/composer demand guessed or dropped identity",
        )
        try require(
            ChatForumTopicReads.demandedIDs(chatID: 7, messages: [], composerTopics: [forum(44)]) == [44],
            "composer-only reason disappeared with pruned history",
        )
        try require(
            ChatForumTopicReads.demandedIDs(chatID: 7, messages: [values[4]], composerTopics: []).isEmpty,
            "nil raw topic acquired General fallback",
        )
    }

    private static func verifyQueue() async throws {
        let transport = Transport()
        let reader = transport.reader()
        defer { reader.retire()
        transport.clear()
        }
        reader.synchronize([1, 2, 3, 4, 5])
        try await until("first two actual reads") { transport.calls.count == 2 }
        reader.synchronize([1, 2, 3, 4, 5, 2])
        reader.request(1)
        try require(reader.probeOutstandingCount == 2, "coalescing exceeded two slots")
        try await complete(1, topic(1), reader: reader, transport: transport)
        try await until("third read") { transport.calls.count == 3 }
        try require(transport.calls[2].id == 3 && transport.peak == 2, "queued read order/concurrency changed")

        // Both active reads ignore cancellation, just like TDLib's continuation.
        reader.synchronize([3, 6])
        reader.synchronize([6, 7])
        reader.synchronize([3, 6, 7])
        await Task.yield()
        try require(
            transport.calls.count == 3 && reader.probeOutstandingCount == 2 && transport.values[1] == nil,
            "pruning freed an outstanding transport slot or retained metadata",
        )
        try await complete(3, topic(3, name: "old generation"), reader: reader, transport: transport)
        try await until("re-demand after terminal callback") { transport.calls.count == 4 }
        try require(
            transport.values[3] == nil && transport.calls[3].id == 3,
            "pruned same-ID answer published or displaced its successor",
        )
        try await complete(2, topic(2), reader: reader, transport: transport)
        try await until("queued six") { transport.calls.count == 5 }
        try require(
            transport.calls[4].id == 6 && transport.values[2] == nil && transport.peak == 2,
            "late canceled callback corrupted next demand",
        )
        try await complete(3, topic(3, name: "fresh generation"), reader: reader, transport: transport)
        try await until("queued seven") { transport.calls.count == 6 }
        try await complete(6, topic(6), reader: reader, transport: transport)
        try await complete(7, topic(7), reader: reader, transport: transport)
        try require(
            transport.values[3]?.info.name == "fresh generation" && reader.probeOutstandingCount == 0,
            "fresh generation did not settle",
        )
        reader.synchronize([6])
        try require(reader.probeDemandIDs == [6] && Set(transport.values.keys) == [6], "cache/demand pruning failed")
    }

    private static func verifyMetadata() async throws {
        let transport = Transport()
        let reader = transport.reader()
        defer { reader.retire()
        transport.clear()
        }
        reader.synchronize([11])
        try await until("metadata read") { transport.calls.count == 1 }
        let changed = topic(11, name: "closed now", closed: true, hidden: true)
        reader.receive(changed.info, source: transport.source)
        let update = payload(id: 11, outbox: 90, draft: nil)
        reader.receive(update, source: transport.source)
        reader.receive(topic(12, name: "wrong topic").info, source: transport.source)
        reader.receive(topic(11, name: "wrong source").info, source: .init(accountID: UUID(), clientID: 1))
        let old = topic(11).applying(update: payload(id: 11, outbox: 1, draft: "stale"))
        try await complete(11, old, reader: reader, transport: transport)
        try require(
            transport.values[11]?.info == changed.info && transport.values[11]?.draftMessage == nil
                    && transport.values[11]?.lastReadOutboxMessageId == 90,
            "late metadata restored old permission/draft/scalar",
        )
        reader.receive(update, source: transport.source)
        reader.receive(changed.info, source: transport.source)
        reader.synchronize([11])
        await Task.yield()
        try require(transport.calls.count == 1, "scalar/info response echo started another read")
        reader.request(11)
        try await until("explicit fresh read") { transport.calls.count == 2 }
        try await complete(11, topic(11, name: "fresh open"), reader: reader, transport: transport)
        try require(
            transport.values[11]?.info.name == "fresh open" && transport.values[11]?.lastReadOutboxMessageId == 0,
            "pre-dispatch cached fields indefinitely overrode a fresh response",
        )
    }

    private static func verifyIdentityAndRetry() async throws {
        let transport = Transport()
        let reader = transport.reader()
        defer { reader.retire()
        transport.clear()
        }
        reader.synchronize([0, -1, 11, 12])
        try await until("identity reads") { transport.calls.count == 2 }
        try await complete(11, topic(11, chatID: 8), reader: reader, transport: transport)
        try await complete(12, topic(13), reader: reader, transport: transport)
        try require(transport.values.isEmpty && reader.probeDemandIDs == [11, 12], "malformed raw identity admitted")
        reader.synchronize([11, 12])
        reader.receive(payload(id: 11, outbox: 5), source: transport.source)
        await Task.yield()
        try require(transport.calls.count == 2, "failed read retried on unchanged demand or scalar")
        reader.retryMissing()
        try await until("explicit retry") { transport.calls.count == 4 }
        try await complete(11, nil, reader: reader, transport: transport)
        try await complete(12, topic(12), reader: reader, transport: transport)
        reader.synchronize([11, 12])
        try require(transport.values[12] != nil && transport.calls.count == 4, "retry failure looped")
    }

    private static func verifyRetirement() async throws {
        let transport = Transport()
        let reader = transport.reader()
        defer { reader.retire()
        transport.clear()
        }
        reader.synchronize([11, 12, 13])
        try await until("retirement reads") { transport.calls.count == 2 }
        transport.current = .init(accountID: transport.source.accountID, clientID: 2)
        reader.retire() // The production synchronous active-client/transfer sink calls this same method.
        transport.current = transport.source
        reader.synchronize([11, 12, 13])
        reader.request(14)
        reader.receive(topic(11).info, source: transport.source)
        try await complete(11, topic(11), reader: reader, transport: transport)
        try await complete(12, topic(12), reader: reader, transport: transport)
        try require(
            reader.isRetired && transport.values.isEmpty && transport.calls.count == 2,
            "retired source ABA revived work/cache",
        )

        let weakTransport = Transport()
        var owner: ChatForumTopicReads? = weakTransport.reader()
        let ownerIsReleased = { [weak owner] in owner == nil }
        owner?.synchronize([21, 22, 23])
        try await until("weak lifetime reads") { weakTransport.calls.count == 2 }
        let tasks = owner!.probeTasks
        owner = nil
        try require(ownerIsReleased(), "uncancellable read retained metadata owner")
        weakTransport.clear()
        for task in tasks {
            await task.value
        }
        try require(
            weakTransport.calls.count == 2 && weakTransport.values.isEmpty,
            "deinit dispatched or published late work",
        )
    }

    private static func verifyFailureProgress() async throws {
        let transport = Transport()
        let reader = transport.reader()
        defer { reader.retire()
        transport.clear()
        }
        reader.synchronize([41, 42, 43])
        try await until("failure head reads") { transport.calls.count == 2 }
        reader.retryMissing() // Ready during an active read must not schedule a second attempt.
        try await complete(41, nil, reader: reader, transport: transport)
        try await until("failure did not starve queue") { transport.calls.count == 3 }
        try require(transport.calls[2].id == 43, "failed head starved next topic")
        try await complete(42, topic(42), reader: reader, transport: transport)
        try await complete(43, topic(43), reader: reader, transport: transport)
        try require(
            transport.calls.count == 3 && reader.probeOutstandingCount == 0,
            "in-flight Ready scheduled a retry loop",
        )
        reader.retryMissing()
        try await until("failed head explicit retry") { transport.calls.count == 4 }
        try await complete(41, topic(41), reader: reader, transport: transport)
        try require(Set(transport.values.keys) == [41, 42, 43], "explicit retry did not recover failed head")
    }

    private static func verifyReceipts() async throws {
        let transport = Transport()
        let reader = transport.reader()
        defer { reader.retire()
        transport.clear()
        }
        let first = MessageDeliveryProbe.fixture(id: 50, chatID: 7, topic: forum(11))
        let second = MessageDeliveryProbe.fixture(id: 50, chatID: 7, topic: forum(12))
        reader.synchronize([11, 12])
        try await until("shared receipt reads") { transport.calls.count == 2 }
        try require(
            state(first, reader) == .delivered && state(second, reader) == .delivered,
            "unknown current-topic baseline guessed Read",
        )
        reader.receive(payload(id: 11, outbox: 60), source: transport.source)
        reader.receive(payload(id: 11, outbox: 60), source: transport.source)
        try require(
            state(first, reader) == .read && state(second, reader) == .delivered
                    && transport.values.isEmpty && transport.receiptEvents == [11] && transport.calls.count == 2,
            "direct receipt required metadata, crossed topic, or refetched",
        )
        try await complete(11, topic(11), reader: reader, transport: transport)
        try await complete(12, nil, reader: reader, transport: transport)
        try require(
            state(first, reader) == .read && state(second, reader) == .delivered,
            "late/failing baseline reverted scoped update",
        )
        reader.receive(payload(id: 12, outbox: 80), source: transport.source)
        try require(
            state(second, reader) == .read && transport.values[12] == nil,
            "failed metadata suppressed live Read",
        )

        let before = transport.receiptEvents.count
        reader.request(11)
        try await until("same-value baseline revision") { transport.calls.count == 3 }
        reader.receive(payload(id: 11, outbox: 60), source: transport.source)
        try await complete(
            11,
            topic(11).applying(update: payload(id: 11, outbox: 1)),
            reader: reader,
            transport: transport,
        )
        try require(
            state(first, reader) == .read && transport.receiptEvents.count == before,
            "same-value update failed to fence a stale baseline or republished",
        )

        reader.synchronize([11])
        try require(
            !reader.receipt(for: second).permitsFinalStatus && transport.receiptEvents.last == 12,
            "pruning nil-metadata entry omitted receipt invalidation",
        )
        reader.synchronize([11, 12])
        try await until("new receipt generation") { transport.calls.count == 4 }
        try require(state(second, reader) == .delivered, "re-demand inherited old receipt")
        try await complete(12, topic(12), reader: reader, transport: transport)
        reader.receive(payload(id: 12, outbox: 80), source: transport.source)
        for invalid in [
            MessageDeliveryProbe.fixture(id: 1, chatID: 8, topic: forum(11)),
            MessageDeliveryProbe.fixture(id: 1, chatID: 7),
            MessageDeliveryProbe.fixture(id: 1, chatID: 7, topic: forum(0)),
            MessageDeliveryProbe.fixture(id: 1, chatID: 7, topic: forum(-1)),
            MessageDeliveryProbe.fixture(id: 1, chatID: 7, topic: .messageTopicThread(.init(messageThreadId: 11))),
            MessageDeliveryProbe.fixture(
                id: 1,
                chatID: 7,
                topic: .messageTopicSavedMessages(.init(savedMessagesTopicId: 11)),
            ),
            MessageDeliveryProbe.fixture(
                id: 1,
                chatID: 7,
                topic: .messageTopicDirectMessages(.init(directMessagesChatTopicId: 11)),
            ),
        ] {
            try require(!reader.receipt(for: invalid).permitsFinalStatus, "invalid raw receipt scope accepted")
        }
        try require(
            state(first, reader) == .read && state(second, reader) == .read,
            "invalid-scope checks ran without live valid receipt controls",
        )
        try require(
            state(MessageDeliveryProbe.fixture(id: 1, chatID: 7, channel: true, topic: forum(11)), reader) == .none,
            "broadcast raw message gained final checks",
        )
        transport.current = .init(accountID: transport.source.accountID, clientID: 2)
        try require(!reader.receipt(for: first).permitsFinalStatus, "departed source still projected Delivered/Read")
        reader.retire()
        transport.current = transport.source
        try require(
            !reader.receipt(for: first).permitsFinalStatus && !reader.receipt(for: second).permitsFinalStatus,
            "source ABA restored read authority",
        )
        let pending = MessageDeliveryProbe.fixture(
            id: -1,
            chatID: 7,
            state: .messageSendingStatePending(.init(sendingId: 1)),
            topic: forum(11),
        )
        try require(state(pending, reader) == .sending, "retired receipts hid raw pending state")
    }

    private static func state(_ message: Message, _ reader: ChatForumTopicReads) -> MessageDeliveryState {
        let projection = reader.receipt(for: message)
        return MessageDeliveryState.resolve(
            message,
            permitsFinalStatus: projection.permitsFinalStatus,
            readOutbox: projection.readOutbox,
            topic: projection.topic,
        )
    }

    private static func complete(
        _ topicID: Int,
        _ value: ForumTopic?,
        reader: ChatForumTopicReads,
        transport: Transport,
    ) async throws {
        let count = reader.probeCompletedCount
        try transport.finish(transport.pendingIndex(topicID: topicID), value)
        try await until("exact read terminal") { reader.probeCompletedCount > count }
    }

    private static func forum(_ id: Int) -> MessageTopic { .messageTopicForum(.init(forumTopicId: id)) }

    private static func topic(
        _ id: Int,
        name: String = "topic",
        chatID: Int64 = 7,
        closed: Bool = false,
        hidden: Bool = false,
    ) -> ForumTopic {
        let base = ForumTopicsRestorationProbe.topic(id: id, name: name)
        return base.replacing(info: .init(
            chatId: chatID, creationDate: 1, creatorId: .messageSenderUser(.init(userId: 1)), forumTopicId: id,
            icon: base.info.icon, isClosed: closed, isGeneral: id == 1, isHidden: hidden,
            isNameImplicit: false, isOutgoing: false, name: name,
        ))
    }

    private static func payload(id: Int, outbox: Int64, draft: String? = nil) -> UpdateForumTopic {
        let draft = draft.map { DraftMessage(
            content: .draftMessageContentText(.init(linkPreviewOptions: nil, text: .init(entities: [], text: $0))),
            date: 1, effectId: 0, replyTo: nil, suggestedPostInfo: nil,
        ) }
        return UpdateForumTopic(
            chatId: 7, draftMessage: draft, forumTopicId: id, isPinned: false,
            lastReadInboxMessageId: 0, lastReadOutboxMessageId: outbox,
            notificationSettings: topic(id).notificationSettings, unreadMentionCount: 0,
            unreadPollVoteCount: 0, unreadReactionCount: 0,
        )
    }

    private static func until(_ label: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            guard Date() < deadline else { throw Failure(description: "timed out: \(label)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func require(_ value: Bool, _ message: String) throws {
        guard value else { throw Failure(description: message) }
    }
}
#endif

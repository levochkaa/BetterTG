// MessageDeliveryProbe.swift

#if DEBUG
import Combine
import TDLibKitDynamic
import UIKit

@MainActor enum MessageDeliveryProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    @MainActor private final class NativeRows {
        let collection: UICollectionView
        let chat = RootChatInsertionProbe.chat(
            .init(isPinned: false, list: .chatListMain, order: 1, source: nil),
            id: 100,
        )
        let client = TDLib.shared.activeClient
        let polls = MessagePollInteractionStore()
        var messages = [CustomMessage]()
        var owners = ChatMessageRenderOwners()
        var data: UICollectionViewDiffableDataSource<Int, DisplayedMessageID>!
        var completed = 0

        init() {
            let layout = UICollectionViewFlowLayout()
            layout.itemSize = CGSize(width: 350, height: 85)
            layout.minimumLineSpacing = 0
            self.collection = UICollectionView(
                frame: CGRect(x: 0, y: 0, width: 390, height: 550),
                collectionViewLayout: layout,
            )
            collection.register(MessageCell.self, forCellWithReuseIdentifier: "delivery")
            self
                .data = UICollectionViewDiffableDataSource<
                    Int,
                    DisplayedMessageID,
                >(collectionView: collection) { [weak self] list, path, id in
                let cell = list.dequeueReusableCell(withReuseIdentifier: "delivery", for: path) as! MessageCell
                if let self, let message = messages.first(where: { $0.displayedID == id }) { configure(
                    cell,
                    message: message,
                ) }
                return cell
            }
        }

        func configure(_ cell: MessageCell, message: CustomMessage) {
            cell.configure(
                message: message,
                chat: chat,
                highlighted: false,
                client: client,
                pollInteractionStore: polls,
                canAddReactions: false,
                selectionActive: false,
                selected: false,
                onSwipeToReply: nil,
                onSelectionToggle: nil,
                onReactionTap: { _ in },
                onMetadataNavigate: { _ in },
                onReplyQuoteExpand: {},
                onContentAction: { _ in },
                onMediaTap: { _, _ in },
            )
            cell.layoutIfNeeded()
        }

        func apply() {
            let changed = owners.replace(messages)
            var snapshot = NSDiffableDataSourceSnapshot<Int, DisplayedMessageID>()
            snapshot.appendSections([0])
            snapshot.appendItems(messages.map(\.displayedID))
            snapshot.reconfigureItems(Array(changed))
            data.apply(snapshot, animatingDifferences: false) { [weak self] in self?.completed += 1 }
        }

        func reconfigure(_ ids: [DisplayedMessageID]) {
            var snapshot = data.snapshot()
            snapshot.reconfigureItems(ids)
            data.apply(snapshot, animatingDifferences: false) { [weak self] in self?.completed += 1 }
        }
    }

    private static var failure: MessageSendingState {
        .messageSendingStateFailed(.init(
            canRetry: true,
            error: .init(code: 400, message: "probe"),
            needAnotherReplyQuote: false,
            needAnotherSender: false,
            needDropReply: false,
            requiredPaidMessageStarCount: 0,
            retryAfter: 0,
        ))
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-message-delivery") else { return }
        Task { @MainActor in
            let result: String
            do {
                try verifyReceipts()
                try verifyStates()
                try await verifyCells()
                result = "Message delivery probe passed: production-receipt/read-revision/source-route-retirement=true; "
                    + "pending/failed/final/album-canonical-promotion/seed-reset=true; "
                    + "actual-MessageCell/text-footer/media-overlay/spoken-state=true; "
                    + "native-stable-ID-owner-replacement/queued-old-owner/batched-receipt/offset=true; "
                    + "forum-receipts/final-self/whole-ChatVM/live-peer-read=unverified; RPC/sends=0"
            } catch { result = "Message delivery probe failed: \(error)" }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("message-delivery-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func verifyReceipts() throws {
        let location = ChatLocation(accountID: UUID(), chatID: 100, clientID: 1, topic: nil)
        let source = TdUpdateSource(accountID: location.accountID!, clientID: 1)
        var state = ChatDeliveryReceiptState(location: location)
        let old = state.beginRead(source: source, location: location)!
        try require(state.lastReadOutbox == nil, "cached restoration data seeded receipt")
        try require(
            state.receive(.init(chatId: 100, lastReadOutboxMessageId: 10), source: source, location: location),
            "current update rejected",
        )
        try require(
            !state.finishRead(old, value: 2, source: source, location: location) && state.lastReadOutbox == 10,
            "late getChat overwrote accepted receipt",
        )
        let same = state.beginRead(source: source, location: location)!
        try require(
            !state.receive(.init(chatId: 100, lastReadOutboxMessageId: 10), source: source, location: location),
            "duplicate receipt republished",
        )
        try require(
            !state.finishRead(same, value: 1, source: source, location: location),
            "duplicate live revision did not fence read",
        )
        for wrong in [TdUpdateSource(accountID: UUID(), clientID: 1), .init(accountID: source.accountID, clientID: 2)] {
            try require(
                !state.receive(.init(chatId: 100, lastReadOutboxMessageId: 99), source: wrong, location: location),
                "foreign source changed receipt",
            )
        }
        try require(
            !state.receive(.init(chatId: 101, lastReadOutboxMessageId: 99), source: source, location: location),
            "other chat changed receipt",
        )
        let topic = location.withForumTopic(id: 7)
        try require(state.beginRead(source: source, location: topic) == nil, "topic route adopted ordinary receipt")
        let first = state.beginRead(source: source, location: location)!
        let latest = state.beginRead(source: source, location: location)!
        try require(
            !state.finishRead(first, value: 20, source: source, location: location),
            "superseded baseline accepted",
        )
        try require(
            state.finishRead(latest, value: 11, source: source, location: location),
            "current baseline rejected",
        )
        let retiring = state.beginRead(source: source, location: location)!
        state.retire()
        try require(
            !state.finishRead(retiring, value: 99, source: source, location: location)
                    && !state.receive(
                        .init(chatId: 100, lastReadOutboxMessageId: 99),
                        source: source,
                        location: location,
                    )
                    && state.lastReadOutbox == nil,
            "source ABA revived retired receipts",
        )
    }

    private static func verifyStates() throws {
        let pending = fixture(id: -1, state: .messageSendingStatePending(.init(sendingId: 1)))
        let failed = fixture(id: -1, state: failure)
        try require(
            MessageDeliveryState.resolve(pending, permitsFinalStatus: true, readOutbox: .max) == .sending,
            "temporary ID appeared Read while pending",
        )
        try require(
            MessageDeliveryState.resolve(failed, permitsFinalStatus: true, readOutbox: .max) == .failed,
            "failed ID appeared Read",
        )
        try require(
            MessageDeliveryState.resolve(fixture(id: 9), permitsFinalStatus: true, readOutbox: nil) == .delivered,
            "unknown receipt claimed Read",
        )
        try require(
            MessageDeliveryState.resolve(fixture(id: 9), permitsFinalStatus: true, readOutbox: 9) == .read,
            "accepted watermark not shown",
        )
        for message in [
            fixture(id: 9, outgoing: false),
            fixture(id: 9, channel: true),
            fixture(id: 9, topic: .messageTopicForum(.init(forumTopicId: 7))),
        ] {
            try require(
                MessageDeliveryState.resolve(message, permitsFinalStatus: true, readOutbox: .max) == .none,
                "incoming/broadcast/forum claimed ordinary Read",
            )
        }
        try require(
            MessageDeliveryState
                .resolve(
                    fixture(id: -1, outgoing: false, state: failure),
                    permitsFinalStatus: false,
                    readOutbox: .max,
                ) ==
                .failed,
            "self failure hidden by TD outgoing flag",
        )
        let wrapper = CustomMessage(
            message: fixture(id: 12, album: 4),
            album: [fixture(id: 12, album: 4), fixture(id: 10, album: 4)],
            properties: .default,
        )
        wrapper.updateDeliveryState(permitsFinalStatus: true, readOutbox: 10)
        try require(
            wrapper.deliverySourceMessage.id == 10 && wrapper.deliveryState == .read,
            "newest album member supplied status",
        )
        var publications = 0
        let subscription = wrapper.$deliveryState.dropFirst().sink { _ in publications += 1 }
        wrapper.updateDeliveryState(permitsFinalStatus: true, readOutbox: 10)
        try require(publications == 0, "unchanged derived status republished")
        wrapper.sendFailed = true // A removed representative's legacy flag is not raw authority.
        wrapper.album = [fixture(id: 12, album: 4)]
        wrapper.updateDeliveryState(permitsFinalStatus: true, readOutbox: 10)
        try require(wrapper.deliveryState == .delivered && publications == 1, "album promotion kept stale failure/read")
        wrapper.message = fixture(id: 12, album: 4, state: .messageSendingStatePending(.init(sendingId: 2)))
        wrapper.album = [wrapper.message]
        wrapper.updateDeliveryState(permitsFinalStatus: true, readOutbox: .max)
        try require(wrapper.deliveryState == .sending, "album pending replacement did not replace final status")
        wrapper.message = fixture(id: 13, album: 4)
        wrapper.album = [wrapper.message]
        wrapper.updateDeliveryState(permitsFinalStatus: true, readOutbox: 13)
        try require(wrapper.deliveryState == .read, "final replacement kept temporary pending status")
        let seed = ChatHistoryMessageValue(wrapper).makeMessage()
        try require(seed.deliveryState == .none, "derived current-client receipt crossed history restoration")
        subscription.cancel()
    }

    private static func verifyCells() async throws {
        let rows = NativeRows()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
            else { throw Failure(description: "missing scene") }
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(rows.collection)
        window.isHidden = false
        defer { window.isHidden = true
        window.rootViewController = nil
        }
        for id in 1...24 {
            let value = fixture(id: Int64(id), album: id == 3 ? 4 : 0)
            let message = CustomMessage(
                message: value,
                formattedText: MessageContentPresentation.make(value).formattedText,
                properties: .default,
            )
            message.updateDeliveryState(permitsFinalStatus: true, readOutbox: nil)
            rows.messages.append(message)
        }
        rows.apply()
        try await until("initial MessageCells") { rows.completed == 1 }
        // The first diffable completion can precede UIWindow's automatic safe-area
        // inset adjustment. Capture the viewport only after that initial layout.
        try await until("initial safe-area layout") {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            rows.collection.layoutIfNeeded()
            return rows.collection.adjustedContentInset.top == window.safeAreaInsets.top
                && rows.collection.contentOffset.y == -rows.collection.adjustedContentInset.top
        }
        let path = IndexPath(item: 2, section: 0)
        guard let original = rows.collection.cellForItem(at: path) as? MessageCell
            else { throw Failure(description: "missing actual MessageCell") }
        let old = rows.messages[2]
        let offset = rows.collection.contentOffset
        var invalidations = ChatMessageRenderInvalidations()
        var staleCallbacks = 0
        let subscription = old.objectWillChange.receive(on: DispatchQueue.main).sink {
            guard invalidations.enqueue(old, owner: rows) else { return }
            DispatchQueue.main.async {
                staleCallbacks += invalidations.drain(current: rows.messages, owner: rows).count
            }
        }
        old.updateDeliveryState(permitsFinalStatus: true, readOutbox: .max)
        let next = CustomMessage(
            message: fixture(id: 30, album: 4),
            formattedText: .init(entities: [], text: "replacement"),
            properties: .default,
        )
        next.updateDeliveryState(permitsFinalStatus: true, readOutbox: .max)
        rows.messages[2] = next
        rows.apply()
        try await until("same-ID new owner MessageCell") { rows.completed == 2 }
        await events()
        try require(
            rows.collection.cellForItem(at: path) === original && rows.collection.contentOffset == offset
                    && original.accessibilityLabel?.contains("Read") == true && staleCallbacks == 0,
            "same-ID replacement: retained-cell=\(rows.collection.cellForItem(at: path) === original), "
                + "offset=\(offset)->\(rows.collection.contentOffset), "
                + "AX=\(original.accessibilityLabel ?? "nil"), stale-callbacks=\(staleCallbacks)",
        )
        subscription.cancel()
        let otherOwner = NSObject()
        _ = invalidations.enqueue(next, owner: otherOwner)
        try require(
            invalidations.drain(current: rows.messages, owner: rows).isEmpty,
            "other model supplied a current wrapper invalidation",
        )
        var flushes = 0
        var burstIDs = [DisplayedMessageID]()
        let burstSubscriptions = rows.messages.map { message in
            message.objectWillChange.receive(on: DispatchQueue.main).sink {
                guard invalidations.enqueue(message, owner: rows) else { return }
                flushes += 1
                DispatchQueue.main.async {
                    burstIDs = invalidations.drain(current: rows.messages, owner: rows)
                    rows.reconfigure(burstIDs)
                }
            }
        }
        for message in rows.messages {
            message.updateDeliveryState(permitsFinalStatus: true, readOutbox: .max)
        }
        try await until("batched receipt MessageCells") { rows.completed == 3 }
        await events()
        try require(
            flushes == 1 && burstIDs.count == rows.messages.count - 1
                && rows.collection.contentOffset == offset
                && rows.collection.visibleCells.allSatisfy { $0.accessibilityLabel?.contains("Read") == true },
            "receipt burst did not coalesce, missed visible status or moved viewport",
        )
        burstSubscriptions.forEach { $0.cancel() }
        for state in [MessageDeliveryState.sending, .failed, .delivered, .read] {
            let raw: MessageSendingState? = state == .sending
                ? .messageSendingStatePending(.init(sendingId: 1))
                : state == .failed ? failure : nil
            for mode in 0...2 {
                let content: MessageContent? = mode == 2
                    ? .messagePhoto(.init(
                        caption: .init(entities: [], text: ""),
                        hasSpoiler: false,
                        isSecret: false,
                        photo: .init(hasStickers: false, minithumbnail: nil, sizes: []),
                        showCaptionAboveMedia: false,
                        video: nil,
                    ))
                    : nil
                let value = fixture(id: 31, state: raw, content: content)
                let message = CustomMessage(
                    message: value,
                    formattedText: mode == 0
                    ? .init(entities: [], text: "status")
                    : nil,
                    properties: .default,
                )
                message.updateDeliveryState(permitsFinalStatus: true, readOutbox: state == .read ? 31 : nil)
                rows.configure(original, message: message)
                let labels = allLabels(original).filter { visible($0) && $0.text?.contains(state.symbol) == true }
                try require(
                    !labels.isEmpty && original.accessibilityLabel?.contains(state.spoken!) == true,
                    "text/footer/media status or spoken state missing",
                )
                try require(
                    original.accessibilityLabel?.contains(state.symbol) != true,
                    "VoiceOver received glyph instead of spoken status",
                )
            }
        }
    }

    private static func fixture(
        id: Int64,
        album: Int64 = 0,
        outgoing: Bool = true,
        channel: Bool = false,
        state: MessageSendingState? = nil,
        topic: MessageTopic? = nil,
        content: MessageContent? = nil,
    ) -> Message {
        Message(
            authorSignature: "",
            autoDeleteIn: 0,
            canBeSaved: true,
            chatId: 100,
            containsUnreadMention: false,
            containsUnreadPollVotes: false,
            content: content ?? .messageText(.init(
                linkPreview: nil,
                linkPreviewOptions: nil,
                text: .init(entities: [], text: "message"),
            )),
            date: Int(max(1, id)),
            editDate: 0,
            effectId: 0,
            ephemeralMessageId: 0,
            factCheck: nil,
            forwardInfo: nil,
            guestBotCallerId: nil,
            hasTimestampedMedia: false,
            id: id,
            importInfo: nil,
            interactionInfo: nil,
            isChannelPost: channel,
            isFromOffline: false,
            isOutgoing: outgoing,
            isPaidGramSuggestedPost: false,
            isPaidStarSuggestedPost: false,
            isPinned: false,
            mediaAlbumId: TdInt64(album),
            paidMessageStarCount: 0,
            receiverId: nil,
            replyMarkup: nil,
            replyTo: nil,
            restrictionInfo: nil,
            schedulingState: nil,
            selfDestructIn: 0,
            selfDestructType: nil,
            senderBoostCount: 0,
            senderBusinessBotUserId: 0,
            senderId: .messageSenderUser(.init(userId: 1)),
            senderTag: "",
            sendingState: state,
            suggestedPostInfo: nil,
            summaryLanguageCode: "",
            topicId: topic,
            unreadReactions: [],
            viaBotUserId: 0,
        )
    }

    private static func allLabels(_ view: UIView) -> [UILabel] {
        ((view as? UILabel).map { [$0] } ?? []) + view.subviews.flatMap(allLabels)
    }

    private static func visible(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let node = current {
            if node.isHidden || node.alpha == 0 { return false }
            current = node.superview
        }
        return true
    }

    private static func require(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(description: message) }
    }

    private static func events() async { for _ in 0..<5 {
        await withCheckedContinuation { c in
        DispatchQueue.main.async { c.resume() }
        }
    } }
    private static func until(_ label: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(condition(), "timed out: \(label)")
    }
}
#endif

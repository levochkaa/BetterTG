// MessageDeliveryProbe.swift

#if DEBUG
import Combine
import TDLibKitDynamic
import UIKit

@MainActor enum MessageDeliveryProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    private final class NativeCollection: UICollectionView {
        private(set) var dequeueIDs = [IndexPath: ObjectIdentifier]()
        private(set) var dequeueCount = 0
        var providerCount = 0

        override func dequeueReusableCell(withReuseIdentifier identifier: String, for path: IndexPath)
            -> UICollectionViewCell
        {
            let cell = super.dequeueReusableCell(withReuseIdentifier: identifier, for: path)
            dequeueIDs[path] = ObjectIdentifier(cell)
            dequeueCount += 1
            return cell
        }
    }

    @MainActor private final class NativeRows {
        let collection: NativeCollection
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
        var selectionActive = false
        var selectionTaps = 0

        init() {
            let layout = UICollectionViewFlowLayout()
            layout.itemSize = CGSize(width: 350, height: 85)
            layout.minimumLineSpacing = 0
            self.collection = NativeCollection(
                frame: CGRect(x: 0, y: 0, width: 390, height: 550),
                collectionViewLayout: layout,
            )
            collection.register(MessageCell.self, forCellWithReuseIdentifier: "delivery")
            self
                .data = UICollectionViewDiffableDataSource<
                    Int,
                    DisplayedMessageID,
                >(collectionView: collection) { [weak self] list, path, id in
                (list as? NativeCollection)?.providerCount += 1
                return ChatTimelineCellProvider.dequeue(
                    MessageCell.self, from: list, at: path, reuseIdentifier: "delivery",
                    configure: { [weak self] cell in
                        guard let self,
                              let message = messages.first(where: { $0.displayedID == id }) else { return false }
                        configure(cell, message: message)
                        return true
                    },
                    unavailable: { $0.resetUnavailableContent() },
                )
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
                selectionActive: selectionActive,
                selected: selectionActive,
                onSwipeToReply: nil,
                onSelectionToggle: selectionActive ? { [weak self] in self?.selectionTaps += 1 } : nil,
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

    @MainActor private final class ForumReceiptRows {
        let rows: NativeRows
        let transport = ChatForumTopicReadsProbe.Transport(chatID: 100)
        lazy var reader = transport.reader { [weak self] id in self?.refresh(topicID: id) }

        init(rows: NativeRows) { self.rows = rows }

        func refresh(topicID: Int? = nil) {
            for message in rows.messages {
                let raw = message.deliverySourceMessage
                if let topicID, raw.topicId != .messageTopicForum(.init(forumTopicId: topicID)) { continue }
                let projection = reader.receipt(for: raw)
                message.updateDeliveryState(
                    permitsFinalStatus: projection.permitsFinalStatus,
                    readOutbox: projection.readOutbox,
                    topic: projection.topic,
                )
            }
        }

        func install(_ messages: [CustomMessage]) {
            rows.messages = messages
            reader.synchronize(ChatForumTopicReads.demandedIDs(
                chatID: 100, messages: messages.flatMap(\.sourceMessages), composerTopics: [],
            ))
            refresh()
            rows.apply()
        }

        func stop() { reader.retire()
        transport.clear()
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
        ChatForumTopicReadsProbe.runIfRequested()
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-message-delivery") else { return }
        Task { @MainActor in
            let result: String
            do {
                try verifyReceipts()
                try verifyForumReceipts()
                try verifyStates()
                try await verifyCells()
                try await verifyUnavailableCells()
                try await verifySelectionTouchBinding()
                try await ChatMessageActionAuthorityProbe.verify()
                result = "Message delivery probe passed: production-receipt/read-revision/source-route-retirement=true; "
                    + "pending/failed/final/album-canonical-promotion/seed-reset=true; "
                    + "actual-MessageCell/text-footer/media-overlay/spoken-state=true; "
                    + "native-stable-ID-owner-replacement/queued-old-owner/batched-receipt/offset=true; "
                    + "shared-provider/exact-dequeue/inert-reconfigure/same-ID-recovery/weak-owner=true; "
                    + "extracted-content-concealed-without-reparenting=true; "
                    + "shared-action-authority/native-cell/old-AX-media-binding/payload-source-permissions/exact-poll=true; "
                    + "selection-control/synthetic-down-reconfigure-up/cancel-outside-reset/one-shot/AX=true; "
                    + "explicit-forum/raw-topic/revision/echo-dedup/late-draft/targeted-cell=true; "
                    + "all-messages-forum/shared-reader/canonical-topic/targeted-cell/seed-reset=true; "
                    + "final-self/whole-ChatVM/live-peer-read/real-deletion-window/snapshot-ownership=unverified; "
                    + "loaded-media/suspended-pan/context-menu-actions/physical-selection-touch=unverified; RPC/sends=0"
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

    static func fixture(
        id: Int64,
        chatID: Int64 = 100,
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
            chatId: chatID,
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

    private static func verifyReceipts() throws {
        let location = ChatLocation(accountID: UUID(), chatID: 100, clientID: 1, topic: nil)
        let source = TdUpdateSource(accountID: location.accountID!, clientID: 1)
        var state = ChatDeliveryReceiptState(location: location)
        let old = state.beginRead(source: source, location: location)!
        try require(state.lastReadOutbox == nil, "cached restoration data seeded receipt")
        try require(
            !state.finishForumRead(old, topic: forumTopic(outbox: .max), source: source, location: location),
            "ordinary route accepted forum completion",
        )
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

    private static func verifyForumReceipts() throws {
        let location = ChatLocation(accountID: UUID(), chatID: 100, clientID: 1, topic: nil).withForumTopic(id: 7)
        let source = TdUpdateSource(accountID: location.accountID!, clientID: 1)
        var state = ChatDeliveryReceiptState(location: location)
        let first = state.beginRead(source: source, location: location)!
        try require(state.lastReadOutbox == nil, "forum route inherited a restoration watermark")
        try require(
            !state.receive(.init(chatId: 100, lastReadOutboxMessageId: .max), source: source, location: location)
                && !state.receive(forumUpdate(id: 8, outbox: .max), source: source, location: location)
                && !state.finishRead(first, value: .max, source: source, location: location),
            "forum route accepted a global/other-topic baseline",
        )
        try require(
            state.finishForumRead(first, topic: forumTopic(outbox: 10), source: source, location: location),
            "unrelated topic advanced this receipt revision",
        )
        let late = state.beginRead(source: source, location: location)!
        try require(
            !state.receive(forumUpdate(outbox: 10), source: source, location: location),
            "duplicate republished",
        )
        try require(
            !state.finishForumRead(late, topic: forumTopic(outbox: 1), source: source, location: location)
                && state.lastReadOutbox == 10,
            "same-call/duplicate topic update failed to fence old baseline",
        )
        for wrong in [forumTopic(id: 8, outbox: .max), forumTopic(chatID: 101, outbox: .max)] {
            let read = state.beginRead(source: source, location: location)!
            try require(
                !state.finishForumRead(read, topic: wrong, source: source, location: location),
                "wrong raw topic identity seeded receipt",
            )
        }
        for wrongTopic in [
            MessageTopic.messageTopicThread(.init(messageThreadId: 7)),
            .messageTopicDirectMessages(.init(directMessagesChatTopicId: 7)),
            .messageTopicSavedMessages(.init(savedMessagesTopicId: 7)),
            .messageTopicForum(.init(forumTopicId: 0)),
        ] {
            let wrong = ChatLocation(accountID: location.accountID, chatID: 100, clientID: 1, topic: wrongTopic)
            var unsupported = ChatDeliveryReceiptState(location: wrong)
            try require(
                unsupported.beginRead(source: source, location: wrong) == nil,
                "numeric topic collision accepted",
            )
        }
        let wrongRawTopics: [MessageTopic?] = [
            nil, location.withForumTopic(id: 8).topic, .messageTopicThread(.init(messageThreadId: 7)),
        ]
        for rawTopic in wrongRawTopics {
            try require(
                MessageDeliveryState.resolve(
                    fixture(id: 5, topic: rawTopic), permitsFinalStatus: true, readOutbox: .max, topic: location.topic,
                ) == .none,
                "unknown/other raw topic received route receipt or General fallback",
            )
        }
        let album = CustomMessage(
            message: fixture(id: 12, album: 4, topic: location.withForumTopic(id: 8).topic),
            album: [
                fixture(id: 12, album: 4, topic: location.withForumTopic(id: 8).topic),
                fixture(id: 10, album: 4, topic: location.topic),
            ], properties: .default,
        )
        album.updateDeliveryState(permitsFinalStatus: true, readOutbox: 10, topic: location.topic)
        try require(album.deliveryState == .read, "album used representative topic instead of canonical raw member")
        album.album = [album.message]
        album.updateDeliveryState(permitsFinalStatus: true, readOutbox: .max, topic: location.topic)
        try require(album.deliveryState == .none, "album promotion retained another topic's Read")
        let retiring = state.beginRead(source: source, location: location)!
        state.retire()
        try require(
            !state.finishForumRead(retiring, topic: forumTopic(outbox: .max), source: source, location: location)
                && !state.receive(forumUpdate(outbox: .max), source: source, location: location),
            "retired forum key revived after source ABA",
        )

        var metadata = ForumTopicLiveUpdateState(location: location)
        let base = forumTopic(outbox: 10, draft: "initial")
        let echo = forumUpdate(outbox: 10, draft: "initial")
        var requests = 1
        let read = metadata.beginRead(source: source)!
        if metadata.receive(echo, current: base, source: source)!.refreshUnreadCount { requests += 1 }
        let accepted = metadata.finishRead(read, topic: base, source: source)!
        if metadata.receive(echo, current: accepted, source: source)!.refreshUnreadCount { requests += 1 }
        try require(requests == 1, "identical response echo scheduled another full fetch")
        let older = metadata.beginRead(source: source)!
        let changed = metadata.receive(forumUpdate(outbox: 12, draft: "newer"), current: accepted, source: source)!
        let merged = metadata.finishRead(older, topic: base, source: source)!
        try require(
            changed.draftChanged && !changed.refreshUnreadCount && merged.lastReadOutboxMessageId == 12
                && merged.draftMessage == draft("newer") && merged.info == base.info
                && merged.lastMessage == base.lastMessage && merged.order == base.order && merged.unreadCount == base
                    .unreadCount,
            "late full topic reverted draft/scalars or direct payload discarded absent fields",
        )
        let clearing = metadata.beginRead(source: source)!
        _ = metadata.receive(forumUpdate(outbox: 12), current: merged, source: source)
        try require(
            metadata.finishRead(clearing, topic: base, source: source)?.draftMessage == nil,
            "late baseline revived cleared draft",
        )
        let inbox = forumUpdate(outbox: 12, inbox: 3)
        if metadata.receive(inbox, current: merged, source: source)!.refreshUnreadCount { requests += 1 }
        if metadata.receive(inbox, current: merged, source: source)!.refreshUnreadCount { requests += 1 }
        try require(requests == 2, "changed inbox edge was lost or repeated")
        let superseded = metadata.beginRead(source: source)!
        let current = metadata.beginRead(source: source)!
        try require(
            metadata.finishRead(superseded, topic: base, source: source) == nil,
            "superseded full read accepted",
        )
        let foreign = TdUpdateSource(accountID: UUID(), clientID: 1)
        try require(
            metadata.receive(echo, current: base, source: foreign) == nil
                && metadata.receive(forumUpdate(id: 8), current: base, source: source) == nil,
            "foreign source/topic changed metadata",
        )
        try require(
            metadata.finishRead(current, topic: base, source: source) != nil,
            "other topic/source consumed current metadata ticket",
        )
        let malformed = metadata.beginRead(source: source)!
        try require(
            metadata.finishRead(malformed, topic: forumTopic(chatID: 101), source: source) == nil,
            "malformed full topic changed metadata",
        )
        let retiringMetadata = metadata.beginRead(source: source)!
        metadata.retire()
        try require(
            metadata.finishRead(retiringMetadata, topic: base, source: source) == nil
                && metadata.beginRead(source: source) == nil,
            "retired metadata key revived",
        )
    }

    private static func verifyUnavailableCells() async throws {
        var owner: NativeRows? = NativeRows()
        let ownerReleased = { [weak owner] in owner == nil }
        guard let collection = owner?.collection, let data = owner?.data,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else {
            throw Failure(description: "missing unavailable-cell fixture")
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(collection)
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let id = DisplayedMessageID.message(70)
        let path = IndexPath(item: 0, section: 0)
        func message(_ text: String) -> CustomMessage {
            CustomMessage(
                message: fixture(id: 70),
                formattedText: .init(entities: [], text: text),
                properties: .default,
            )
        }
        owner?.selectionActive = true
        owner?.messages = [message("original fallback fixture")]
        owner?.apply()
        try await until("configured fallback MessageCell") { owner?.completed == 1 }
        collection.layoutIfNeeded()
        guard let cell = collection.cellForItem(at: path) as? MessageCell,
              let selection = allControls(cell).first(where: {
                  $0.accessibilityIdentifier == "message-selection-control"
              }),
              let oldSelectionAction = cell.accessibilityCustomActions?.first(where: { $0.name == "Deselect Message" }),
              let container = cell.contextPreviewView as? TelegramContextMenuExtractableView,
              let extracted = container.probeTakeContextMenuContent()
        else {
            throw Failure(description: "missing configured selection or extracted content")
        }
        let externalHost = UIView()
        host.view.addSubview(externalHost)
        externalHost.addSubview(extracted)
        var contentReturned = false
        defer { if !contentReturned { container.probePutBackContextMenuContent(extracted) } }
        try require(
            !cell.probeUnavailableResourcesAreReset && !extracted.isHidden,
            "fallback fixture was not armed with real content",
        )
        selection.sendActions(for: .touchDown)
        selection.sendActions(for: .touchUpInside)
        try require(owner?.selectionTaps == 1, "initial selection callback missing")
        let reuseCount = cell.probeReuseCount
        var heightChanges = 0
        cell.onSelfSizingHeightChange = { heightChanges += 1 }
        cell.alpha = 0.4
        cell.transform = CGAffineTransform(translationX: 24, y: 0)
        container.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        container.alpha = 0.7
        extracted.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        extracted.alpha = 0.8
        let externalTransform = extracted.transform
        let externalAlpha = extracted.alpha
        try require(
            externalTransform != .identity && externalAlpha > 0 && externalAlpha < 1,
            "external extraction presentation baseline was not armed",
        )
        owner?.messages = []
        owner?.reconfigure([id])
        try await until("missing-model native reconfigure") { owner?.completed == 2 }
        try require(
            collection.cellForItem(at: path) === cell
            && collection.dequeueIDs[path] == ObjectIdentifier(cell)
            && cell.probeReuseCount == reuseCount,
            "fallback replaced dequeued cell or relied on prepareForReuse",
        )
        try require(
            cell.probeUnavailableResourcesAreReset && inert(cell)
            && cell.alpha == 1 && cell.transform == .identity,
            "missing-model cell retained resources, accessibility, actions or animation state",
        )
        try require(
            extracted.superview === externalHost && extracted.isHidden
                && extracted.transform == externalTransform && extracted.alpha == externalAlpha
                && container.transform == .identity && container.alpha == 1,
            "fallback stole or exposed extracted content: "
                + "externalHost=\(extracted.superview === externalHost), hidden=\(extracted.isHidden), "
                + "extractedTransform=\(extracted.transform), expectedTransform=\(externalTransform), "
                + "extractedAlpha=\(String(format: "%.17g", Double(extracted.alpha))), "
                + "expectedAlpha=\(String(format: "%.17g", Double(externalAlpha))), "
                + "containerTransform=\(container.transform), "
                + "containerAlpha=\(String(format: "%.17g", Double(container.alpha)))",
        )
        selection.sendActions(for: .touchUpInside)
        _ = oldSelectionAction.actionHandler?(oldSelectionAction)
        cell.onSelfSizingHeightChange?()
        try require(owner?.selectionTaps == 1 && heightChanges == 0, "cleared selection/height callbacks fired")
        // The external owner restores its own presentation before returning content.
        extracted.transform = .identity
        extracted.alpha = 1
        container.probePutBackContextMenuContent(extracted)
        contentReturned = true
        owner?.messages = [message("recovered fallback fixture")]
        owner?.reconfigure([id])
        try await until("same-ID native recovery") { owner?.completed == 3 }
        try require(
            collection.cellForItem(at: path) === cell && !cell.contentView.isHidden
            && !extracted.isHidden && !cell.accessibilityElementsHidden && cell.isUserInteractionEnabled
            && cell.accessibilityLabel?.contains("recovered fallback fixture") == true
            && cell.accessibilityTraits.contains(.selected),
            "same-ID recovery did not restore content/selection",
        )
        selection.sendActions(for: .touchDown)
        selection.sendActions(for: .touchUpInside)
        try require(owner?.selectionTaps == 2, "recovered selection callback missing")
        owner = nil
        try require(ownerReleased(), "fixture provider owner did not release")
        var snapshot = data.snapshot()
        snapshot.reconfigureItems([id])
        var completed = false
        data.apply(snapshot, animatingDifferences: false) { completed = true }
        try await until("released-owner native reconfigure") { completed }
        try require(
            collection.cellForItem(at: path) === cell && inert(cell)
            && cell.probeUnavailableResourcesAreReset && collection.dequeueIDs[path] == ObjectIdentifier(cell),
            "released owner replaced cell or retained resources",
        )
        try require(
            collection.providerCount > 0 && collection.dequeueCount == collection.providerCount,
            "provider did not return exactly one dequeue per request",
        )
        try await verifyUnavailableHeaders(scene: scene)
    }

    private static func verifySelectionTouchBinding() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw Failure(description: "missing selection-touch scene")
        }
        let rows = NativeRows()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(rows.collection)
        window.isHidden = false
        defer { window.isHidden = true
        window.rootViewController = nil
        }
        let message = CustomMessage(message: fixture(id: 70), properties: .default)
        rows.selectionActive = true
        rows.messages = [message]
        rows.apply()
        try await until("selection-touch initial snapshot") { rows.completed == 1 }
        rows.collection.layoutIfNeeded()
        let path = IndexPath(item: 0, section: 0)
        guard let cell = rows.collection.cellForItem(at: path) as? MessageCell,
              let control = allControls(cell)
              .first(where: { $0.accessibilityIdentifier == "message-selection-control" }),
              let oldAX = cell.accessibilityCustomActions?.first(where: { $0.name == "Deselect Message" })
        else { throw Failure(description: "selection-touch fixture was not armed") }
        guard let binding = cell.actionBindingID else { throw Failure(description: "selection cell has no binding") }
        let reuseCount = cell.probeReuseCount
        control.sendActions(for: .touchDown)
        try require(cell.probeSelectionTouchBindingID == binding, "selection touchDown did not capture current binding")
        rows.reconfigure([message.displayedID])
        try await until("selection-touch held-down reconfigure") { rows.completed == 2 }
        try require(
            rows.collection.cellForItem(at: path) === cell && cell.probeReuseCount == reuseCount
                && allControls(cell).contains(where: { $0 === control }) && cell.actionBindingID != binding
                && cell.probeSelectionTouchBindingID == nil,
            "selection-touch reconfigure did not retain exact cell/control with a new binding",
        )
        control.sendActions(for: .touchUpInside)
        control.sendActions(for: .touchUpInside)
        _ = oldAX.actionHandler?(oldAX)
        try require(rows.selectionTaps == 0, "old touch/AX invoked an old or rebound selection handler")
        guard let currentAX = cell.accessibilityCustomActions?.first(where: { $0.name == "Deselect Message" }) else {
            throw Failure(description: "current selection AX action missing")
        }
        _ = currentAX.actionHandler?(currentAX)
        try require(rows.selectionTaps == 1, "current selection AX incorrectly requires touchDown")
        control.sendActions(for: .touchDown)
        control.sendActions(for: .touchUpInside)
        control.sendActions(for: .touchUpInside)
        try require(rows.selectionTaps == 2, "fresh selection touch was not consumed exactly once")
        control.sendActions(for: .touchDown)
        control.sendActions(for: .touchCancel)
        control.sendActions(for: .touchUpInside)
        control.sendActions(for: .touchDown)
        control.sendActions(for: .touchUpOutside)
        control.sendActions(for: .touchUpInside)
        try require(rows.selectionTaps == 2, "canceled/outside selection touch survived")
        control.sendActions(for: .touchDown)
        cell.resetUnavailableContent()
        rows.reconfigure([message.displayedID])
        try await until("selection-touch unavailable recovery") { rows.completed == 3 }
        try require(
            rows.collection.cellForItem(at: path) === cell && allControls(cell).contains(where: { $0 === control }),
            "selection-touch reset replaced native cell/control",
        )
        control.sendActions(for: .touchUpInside)
        try require(rows.selectionTaps == 2, "reset/rebound cell inherited an old touch")
        control.sendActions(for: .touchDown)
        control.sendActions(for: .touchUpInside)
        try require(rows.selectionTaps == 3, "reset/rebound cell rejected a fresh touch")
    }

    private static func inert(_ cell: UICollectionViewCell) -> Bool {
        cell.contentView.isHidden && !cell.isUserInteractionEnabled && !cell.isAccessibilityElement
            && cell.accessibilityElementsHidden && cell.accessibilityLabel == nil && cell.accessibilityValue == nil
            && cell.accessibilityHint == nil && cell.accessibilityIdentifier == nil
            && cell.accessibilityTraits.isEmpty && cell.accessibilityCustomActions == nil
    }

    private static func allControls(_ view: UIView) -> [UIControl] {
        ((view as? UIControl).map { [$0] } ?? []) + view.subviews.flatMap(allControls)
    }

    private static func verifyUnavailableHeaders(scene: UIWindowScene) async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 50)
        let collection = NativeCollection(
            frame: CGRect(x: 0, y: 0, width: 390, height: 500),
            collectionViewLayout: layout,
        )
        collection.register(ChatDateHeaderCell.self, forCellWithReuseIdentifier: "date")
        collection.register(ForumTopicRunHeaderCell.self, forCellWithReuseIdentifier: "topic")
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cast-mismatch")
        var hasOwner = true
        var topicTaps = 0
        var castConfigurationRan = false
        let client = TDLib.shared.activeClient
        let data = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collection) { list, path, id in
            collection.providerCount += 1
            switch id {
            case 0:
                return ChatTimelineCellProvider.dequeue(
                    ChatDateHeaderCell.self, from: list, at: path, reuseIdentifier: "date",
                    configure: { cell in
                        guard hasOwner else { return false }
                        cell.configure(id: .init(dayTimestamp: 1))
                        return true
                    }, unavailable: { $0.resetUnavailableContent() },
                )
            case 1:
                return ChatTimelineCellProvider.dequeue(
                    ForumTopicRunHeaderCell.self, from: list, at: path, reuseIdentifier: "topic",
                    configure: { cell in
                        guard hasOwner else { return false }
                        cell.configure(id: .init(topicID: 1, runStartMessageID: 7), info: nil, client: client) {
                            topicTaps += 1
                        }
                        return true
                    }, unavailable: { $0.resetUnavailableContent() },
                )
            default:
                return ChatTimelineCellProvider.dequeue(
                    MessageCell.self, from: list, at: path, reuseIdentifier: "cast-mismatch",
                    configure: { _ in castConfigurationRan = true
                    return true
                    },
                    unavailable: { $0.resetUnavailableContent() },
                )
            }
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(collection)
        window.isHidden = false
        defer { window.isHidden = true
        window.rootViewController = nil
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems([0, 1, 2])
        var completions = 0
        data.apply(snapshot, animatingDifferences: false) { completions += 1 }
        try await until("header and cast fixture initial native apply") { completions == 1 }
        collection.layoutIfNeeded()
        let paths = (0...2).map { IndexPath(item: $0, section: 0) }
        let cells = paths.compactMap { collection.cellForItem(at: $0) }
        try require(cells.count == 3, "header fixture cells missing")
        guard let control = allControls(cells[1]).first else { throw Failure(description: "topic control missing") }
        control.sendActions(for: .touchUpInside)
        try require(topicTaps == 1 && inert(cells[2]) && !castConfigurationRan, "header/cast fixture not armed")
        hasOwner = false
        snapshot.reconfigureItems([0, 1, 2])
        data.apply(snapshot, animatingDifferences: false) { completions += 1 }
        try await until("header no-owner native reconfigure") { completions == 2 }
        try require(zip(paths, cells).allSatisfy { path, cell in
            collection.cellForItem(at: path) === cell && collection.dequeueIDs[path] == ObjectIdentifier(cell)
                && inert(cell)
        }, "header/cast fallback changed dequeued type or exposed old content")
        control.sendActions(for: .touchUpInside)
        try require(
            topicTaps == 1 && control.accessibilityLabel == nil,
            "unavailable topic retained callback/accessibility",
        )
        hasOwner = true
        data.apply(snapshot, animatingDifferences: false) { completions += 1 }
        try await until("header native recovery") { completions == 3 }
        control.sendActions(for: .touchUpInside)
        try require(
            topicTaps == 2 && !cells[0].contentView.isHidden && !cells[1].contentView.isHidden
            && collection.dequeueCount == collection.providerCount && !castConfigurationRan,
            "header recovery or one-dequeue contract failed",
        )
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
        let location = ChatLocation(accountID: UUID(), chatID: 100, clientID: 1, topic: nil).withForumTopic(id: 7)
        let source = TdUpdateSource(accountID: location.accountID!, clientID: 1)
        var receipts = ChatDeliveryReceiptState(location: location)
        rows.messages = [location.topic, location.withForumTopic(id: 8).topic, nil].enumerated().map { index, topic in
            let message = CustomMessage(
                message: fixture(id: Int64(index + 1), topic: topic),
                formattedText: .init(entities: [], text: "topic row"), properties: .default,
            )
            message.updateDeliveryState(permitsFinalStatus: true, readOutbox: nil, topic: location.topic)
            return message
        }
        rows.apply()
        try await until("explicit-topic MessageCells") { rows.completed == 4 }
        await events()
        rows.collection.layoutIfNeeded()
        let topicOffset = rows.collection.contentOffset
        var topicIDs = [DisplayedMessageID]()
        let topicSubscriptions = rows.messages.map { message in
            message.objectWillChange.receive(on: DispatchQueue.main).sink {
                guard invalidations.enqueue(message, owner: rows) else { return }
                DispatchQueue.main.async {
                    topicIDs = invalidations.drain(current: rows.messages, owner: rows)
                    rows.reconfigure(topicIDs)
                }
            }
        }
        _ = receipts.receive(forumUpdate(outbox: 1), source: source, location: location)
        for message in rows.messages {
            message.updateDeliveryState(
                permitsFinalStatus: true, readOutbox: receipts.lastReadOutbox, topic: location.topic,
            )
        }
        try await until("targeted explicit-topic receipt") { rows.completed == 5 }
        await events()
        try require(
            topicIDs == [rows.messages[0].displayedID] && rows.collection.contentOffset == topicOffset
                && rows.collection
.cellForItem(at: IndexPath(item: 0, section: 0))?
.accessibilityLabel?
                    .contains("Read") == true
                && rows.collection
.cellForItem(at: IndexPath(item: 1, section: 0))?
.accessibilityLabel?
                    .contains("Read") != true
                && rows.collection
.cellForItem(at: IndexPath(item: 2, section: 0))?
.accessibilityLabel?
                    .contains("Read") != true,
            "explicit-topic update reconfigured or marked a foreign/unknown topic, or moved viewport",
        )
        topicSubscriptions.forEach { $0.cancel() }
        try await verifyAllMessagesForumCells(rows)
    }

    private static func verifyAllMessagesForumCells(_ rows: NativeRows) async throws {
        let owner = ForumReceiptRows(rows: rows)
        defer { owner.stop() }
        let firstTopic = MessageTopic.messageTopicForum(.init(forumTopicId: 11))
        let secondTopic = MessageTopic.messageTopicForum(.init(forumTopicId: 12))
        let oldest = fixture(id: 10, album: 4, topic: firstTopic)
        let newest = fixture(id: 12, album: 4, topic: secondTopic)
        let album = CustomMessage(message: newest, album: [newest, oldest], properties: .default)
        let second = CustomMessage(message: fixture(id: 20, topic: secondTopic), properties: .default)
        let unknown = CustomMessage(message: fixture(id: 30), properties: .default)
        let before = rows.completed
        owner.install([album, second, unknown])
        try await until("all-forum rows and shared reads") {
            rows.completed == before + 1 && owner.transport.calls.count == 2
        }
        await events()
        rows.collection.layoutIfNeeded()
        let offset = rows.collection.contentOffset
        let original = rows.collection.cellForItem(at: .init(item: 0, section: 0))
        try require(
            original != nil && album.deliveryState == .delivered && second.deliveryState == .delivered
                    && unknown.deliveryState == .none,
            "unknown watermark or raw topic guessed read authority",
        )

        var invalidations = ChatMessageRenderInvalidations()
        var changedIDs = [DisplayedMessageID]()
        let subscriptions = rows.messages.map { message in
            message.objectWillChange.receive(on: DispatchQueue.main).sink { [weak owner] in
                guard let owner, invalidations.enqueue(message, owner: owner) else { return }
                DispatchQueue.main.async { [weak owner] in
                    guard let owner else { return }
                    changedIDs = invalidations.drain(current: owner.rows.messages, owner: owner)
                    if !changedIDs.isEmpty { owner.rows.reconfigure(changedIDs) }
                }
            }
        }
        defer { subscriptions.forEach { $0.cancel() } }
        owner.reader.receive(forumUpdate(id: 11, outbox: 10), source: owner.transport.source)
        owner.reader.receive(forumUpdate(id: 12, outbox: 5), source: owner.transport.source)
        try await until("independent topic MessageCells") { rows.completed == before + 2 }
        await events()
        try require(
            changedIDs == [album.displayedID] && album.deliveryState == .read && second.deliveryState == .delivered
                    && owner.transport.values.isEmpty && original === rows.collection.cellForItem(at: .init(
                        item: 0,
                        section: 0,
                    ))
                    && original?.accessibilityLabel?.contains("Read") == true && rows.collection
                        .contentOffset == offset,
            "canonical topic update crossed topic, replaced cell, or moved viewport",
        )
        let terminal = owner.reader.probeCompletedCount
        try owner.transport.finish(owner.transport.pendingIndex(topicID: 11), forumTopic(id: 11, outbox: 0))
        try owner.transport.finish(owner.transport.pendingIndex(topicID: 12), nil)
        try await until("late/failing forum baselines") { owner.reader.probeCompletedCount == terminal + 2 }
        try require(
            album.deliveryState == .read && second.deliveryState == .delivered && owner.transport.calls.count == 2,
            "metadata baseline failure rewrote live receipts or started extra RPC",
        )

        // Replace the stable album wrapper before subscriptions can publish. The
        // canonical source is now topic 12; the structural apply must repaint it.
        let replacement = CustomMessage(message: newest, album: [newest], properties: .default)
        owner.install([replacement, second, unknown])
        try await until("canonical promotion same-ID owner") { rows.completed == before + 3 }
        await events()
        try require(
            replacement.displayedID == album.displayedID && replacement.deliveryState == .delivered
                    && original === rows.collection.cellForItem(at: .init(item: 0, section: 0))
                    && original?.accessibilityLabel?.contains("Delivered") == true,
            "same-ID canonical promotion retained removed topic Read",
        )
        album.updateDeliveryState(permitsFinalStatus: true, readOutbox: nil, topic: firstTopic)
        await events()
        try require(
            replacement.deliveryState == .delivered && rows.completed == before + 3,
            "queued removed wrapper reconfigured the current stable-ID owner",
        )
        owner.reader.receive(forumUpdate(id: 11, outbox: .max), source: owner.transport.source)
        try require(
            replacement.deliveryState == .delivered && !owner.reader.probeDemandIDs.contains(11),
            "pruned old canonical topic affected replacement",
        )
        replacement.message = fixture(
            id: -1,
            album: 4,
            state: .messageSendingStatePending(.init(sendingId: 3)),
            topic: secondTopic,
        )
        replacement.album = [replacement.message]
        owner.refresh()
        try require(replacement.deliveryState == .sending, "temporary album compared against topic watermark")
        replacement.message = fixture(id: -1, album: 4, state: failure, topic: secondTopic)
        replacement.album = [replacement.message]
        owner.refresh()
        try require(replacement.deliveryState == .failed, "raw album failure hidden")
        replacement.message = fixture(id: 4, album: 4, topic: secondTopic)
        replacement.album = [replacement.message]
        owner.refresh()
        try require(replacement.deliveryState == .read, "final alias did not acquire exact current-topic watermark")
        let seed = ChatHistoryMessageValue(replacement).makeMessage()
        let newTransport = ChatForumTopicReadsProbe.Transport(chatID: 100)
        let newReader = newTransport.reader()
        defer { newReader.retire()
        newTransport.clear()
        }
        try require(seed.deliveryState == .none, "restoration carried derived Read")
        newReader.synchronize([12])
        let projection = newReader.receipt(for: seed.deliverySourceMessage)
        seed.updateDeliveryState(
            permitsFinalStatus: projection.permitsFinalStatus,
            readOutbox: projection.readOutbox,
            topic: projection.topic,
        )
        try require(seed.deliveryState == .delivered, "fresh source inferred Read from seed")
        owner.reader.retire()
        try require(
            replacement.deliveryState == .none && second.deliveryState == .none,
            "retirement kept old-source final receipt status",
        )
        await events()
    }

    private static func draft(_ text: String?) -> DraftMessage? {
        text.map { DraftMessage(
            content: .draftMessageContentText(.init(linkPreviewOptions: nil, text: .init(entities: [], text: $0))),
            date: 1, effectId: 0, replyTo: nil, suggestedPostInfo: nil,
        ) }
    }

    private static func forumTopic(
        id: Int = 7, chatID: Int64 = 100, outbox: Int64 = 0, inbox: Int64 = 2, draft text: String? = nil,
    ) -> ForumTopic {
        let base = ForumTopicsRestorationProbe.topic(id: id)
        return ForumTopic(
            draftMessage: draft(text), info: .init(
                chatId: chatID, creationDate: 1, creatorId: base.info.creatorId, forumTopicId: id, icon: base.info.icon,
                isClosed: false, isGeneral: false, isHidden: false, isNameImplicit: false, isOutgoing: true,
                name: "topic",
            ), isPinned: false, lastMessage: nil, lastReadInboxMessageId: inbox, lastReadOutboxMessageId: outbox,
            notificationSettings: base.notificationSettings, order: 10, unreadCount: 4,
            unreadMentionCount: 0, unreadPollVoteCount: 0, unreadReactionCount: 0,
        )
    }

    private static func forumUpdate(
        id: Int = 7, outbox: Int64 = 0, inbox: Int64 = 2, draft text: String? = nil,
    ) -> UpdateForumTopic {
        UpdateForumTopic(
            chatId: 100, draftMessage: draft(text), forumTopicId: id, isPinned: false,
            lastReadInboxMessageId: inbox, lastReadOutboxMessageId: outbox,
            notificationSettings: forumTopic().notificationSettings, unreadMentionCount: 0,
            unreadPollVoteCount: 0, unreadReactionCount: 0,
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

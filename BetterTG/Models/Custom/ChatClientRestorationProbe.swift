// ChatClientRestorationProbe.swift

#if DEBUG
    import TDLibKitDynamic
    import UIKit

    @MainActor enum ChatClientRestorationProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-chat-restoration-state") else { return }
            Task { @MainActor in
                let result: String
                do {
                    try verifyValuesAndAlbums()
                    try verifyImports()
                    try await verifyRefresh()
                    try await verifyProductionRefreshPolicy()
                    result = "Chat restoration state probe passed: detached-display-values/raw-cursor=true; "
                        + "album-edit/delete/latest-overlap=true; local-import-once/same-account/retirement=true; "
                        + "bounded-four-reads/visible-first=true; update/delete/source/cancel/hydration-fences=true; "
                        + "partial-update-retry/full-message-satisfied/permanent-tombstones=true; "
                        + "latest-page-revision/token-fences=true; missing-vs-error/retry-event=true; "
                        + "live-body/shared-hydration/partial-race-retry=true; pagination-ledger/mutation-owner=true; "
                        + "deferred-ready/error/cancel/retirement=true; "
                        + "Chat-navigation-not-enabled; server-reads/sends=0"
                } catch {
                    result = "Chat restoration state probe failed: \(error)"
                }
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("chat-restoration-state-probe.txt"), options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func verifyValuesAndAlbums() throws {
            let location = ChatLocation(accountID: UUID(), chatID: 100, clientID: 1, topic: nil)
            let representative = CustomMessage(message: fixture(id: 20, album: 77), properties: .default)
            representative.album = [representative.message, fixture(id: 19, album: 77)]
            representative.formattedText = .init(entities: [], text: "cached caption")
            representative.sendFailed = true
            representative.isPinned = true
            representative.isReplyQuoteExpanded = true
            representative.reactionMutationInFlight = true
            representative.replyPresentation = .fallback(
                for: .inputMessageReplyToMessage(.init(checklistTaskId: 0, messageId: 5, pollOptionId: "", quote: nil)),
                currentChatID: 100,
            )
            representative.forwardPresentation = .init(
                avatar: nil, headline: "Forwarded", navigationTarget: nil, originalSourceTitle: "Origin",
                publicServiceAnnouncementType: nil, referencedChatIDs: [200], referencedUserIDs: [2],
                sourceTitle: "Source", targetChatID: 200, targetMessageID: 5,
            )
            let seed = ChatHistoryRestorationState(
                location: location, messages: [.init(representative)], oldestHistoryMessageID: 3, hasMoreMessages: true,
            )
            representative.album = []
            representative.formattedText = nil
            let copy = seed.makeMessages()[0]
            try require(
                copy !== representative && copy.album.map(\.id) == [20, 19]
                    && copy.formattedText?.text == "cached caption" && copy.sendFailed
                    && copy.isPinned && copy.isReplyQuoteExpanded && !copy.reactionMutationInFlight
                    && copy.replyPresentation?.targetMessageID == 5
                    && copy.forwardPresentation?.sourceTitle == "Source",
                "display seed shared wrappers or dropped layout state",
            )
            let changed = value(fixture(id: 19, album: 77, text: "edited member"))
            let fresh = seed.reconciling(confirmed: [changed, value(fixture(id: 21, album: 77))], removedIDs: [20])
            try require(
                fresh.messages.count == 1 && fresh.messages[0].sourceMessages.map(\.id) == [21, 19]
                    && fresh.messages[0].sourceMessages[1] == changed.message
                    && fresh.oldestHistoryMessageID == 3 && fresh.hasMoreMessages,
                "album reconciliation lost edits, deletion or raw cursor",
            )
            let deleted = fresh.reconciling(confirmed: [], removedIDs: [21, 19])
            try require(deleted.messages.isEmpty && deleted.oldestHistoryMessageID == 3, "empty album remained")
            var latest = ChatHistoryLatestRefreshCursor(seed: seed)
            try require(
                latest.accept(rawPage: [fixture(id: 40), fixture(id: 35)], requestedFromMessageID: 0)
                && latest.fromMessageID == 35 && !latest.isComplete,
                "latest cursor jumped into old history",
            )
            try require(
                !latest.accept(rawPage: [fixture(id: 35)], requestedFromMessageID: 35) && !latest.isComplete,
                "repeated cursor invented EOF",
            )
            try require(
                !latest.accept(rawPage: [], requestedFromMessageID: 0) && !latest.isComplete,
                "late latest page changed the newer cursor",
            )
            try require(
                latest.accept(rawPage: [fixture(id: 34), fixture(id: 20, album: 77)], requestedFromMessageID: 35)
                && latest.isComplete && latest.fromMessageID == 20,
                "raw overlap was lost at album seam",
            )
        }

        private static func verifyImports() throws {
            let account = UUID()
            let gate = ChatComposerImportBarrier(location: .init(
                accountID: account,
                chatID: 100,
                clientID: 1,
                topic: nil,
            ))
            let first = gate.begin()!
            let second = gate.begin()!
            var applied = 0
            var idle = 0
            gate.onQuiescent = { idle += 1 }
            try require(!gate.retire(), "busy import owner retired")
            try require(
                gate.finish(first, currentAccountID: account, routeIsRetained: true) { applied += 1 }
                && applied == 1 && idle == 0,
                "same-account local completion rejected",
            )
            try require(
                !gate.finish(first, currentAccountID: account, routeIsRetained: true) { applied += 1 },
                "import token applied twice",
            )
            try require(
                !gate.finish(second, currentAccountID: UUID(), routeIsRetained: true) { applied += 1 }
                && applied == 1 && idle == 1 && gate.isQuiescent,
                "foreign account accepted local files",
            )
            let removed = gate.begin()!
            try require(
                !gate.finish(removed, currentAccountID: account, routeIsRetained: false) { applied += 1 },
                "removed route accepted local files",
            )
            try require(gate.retire() && gate.begin() == nil, "retired import owner reopened")
        }

        private static func verifyRefresh() async throws {
            let account = UUID()
            let location = ChatLocation(accountID: account, chatID: 100, clientID: 10, topic: nil)
            let source = TdUpdateSource(accountID: account, clientID: 10)
            var current = source
            var reads = [Int64]()
            var active = 0
            var maximum = 0
            var deliveries = [ChatHistoryRestorationRefresh.Delivery]()
            var fail = true
            let refresh = ChatHistoryRestorationRefresh(
                location: location, source: source, seedIDs: [1, 2, 3, 4, 5, 6], visibleIDs: [4, 3, 4, 100],
                currentSource: { current },
                read: { id in
                    reads.append(id)
                    active += 1
                    maximum = max(maximum, active)
                    defer { active -= 1 }
                    await Task.yield()
                    if id == 3 { throw TDLibKit.Error(code: 404, message: "Not Found") }
                    if id == 2, fail { throw TDLibKit.Error(code: 500, message: "network unavailable") }
                    return fixture(id: id)
                },
                deliver: { deliveries.append($0) },
            )
            try await require(refresh.refreshNextBatch(), "first batch was skipped")
            try require(
                Set(reads) == [4, 3, 1, 2] && maximum <= 4 && refresh.remainingCount == 2,
                "visible ordering, deduplication or batch bound changed",
            )
            try require(
                deliveries.contains {
                    if case .missing = $0.result {
                        $0.messageID == 3
                    } else {
                        false
                    }
                }
                && refresh.failedMessageIDs == [2],
                "missing and transport failure conflated",
            )
            refresh.noteLiveUpdate(messageIDs: [2], kind: .partial)
            try require(refresh.failedMessageIDs == [2], "partial update cleared an unresolved failed body read")
            try await require(refresh.refreshNextBatch(), "second batch was skipped")
            try await require(!(refresh.refreshNextBatch()) && reads.count == 6, "failed read auto-polled")
            fail = false
            refresh.retryFailures()
            try await require(refresh.refreshNextBatch(), "explicit retry did not resume")
            try require(reads.last == 2 && refresh.failedMessageIDs.isEmpty, "retry state did not clear")

            var guarded: ChatHistoryRestorationRefresh!
            defer { guarded = nil }
            var guardedDeliveries = [Int64]()
            var guardedReads = [Int64]()
            var updateDuringRead = true
            var updateDuringHydration = true
            guarded = ChatHistoryRestorationRefresh(
                location: location, source: source, seedIDs: [1, 2, 3, 4, 5], visibleIDs: [],
                currentSource: { current },
                read: { id in
                    guardedReads.append(id)
                    if id == 1, updateDuringRead {
                        updateDuringRead = false
                        guarded.noteLiveUpdate(messageIDs: [1], kind: .partial)
                    }
                    if id == 2 { guarded.notePermanentDeletion(messageIDs: [2]) }
                    return fixture(id: id)
                },
                hydrate: { message in
                    if message.id == 3, updateDuringHydration {
                        updateDuringHydration = false
                        guarded.noteLiveUpdate(messageIDs: [3], kind: .partial)
                    }
                    return value(message)
                },
                deliver: { guardedDeliveries.append($0.messageID) },
            )
            guarded.notePermanentDeletion(messageIDs: [5])
            try await require(guarded.refreshNextBatch(), "guarded batch skipped")
            try require(
                guardedDeliveries == [4] && guarded.failedMessageIDs == [1, 3],
                "partial update lost to older read/hydration or silently satisfied stale seed",
            )
            try await require(guarded.refreshNextBatch(), "deleted queued message batch skipped")
            try await require(!guarded.refreshNextBatch(), "partial-update race auto-polled")
            try require(!guardedReads.contains(5), "deletion before queued fetch still performed read")
            guarded.retryFailures()
            try await require(guarded.refreshNextBatch(), "partial update did not allow explicit retry")
            try require(
                guardedDeliveries == [4, 1, 3] && guarded.failedMessageIDs.isEmpty
                    && guardedReads.filter { $0 == 1 || $0 == 3 }.count == 4,
                "retry did not resolve both read and hydration races",
            )
            let latest = guarded.beginLatestRead()!
            guarded.noteLiveUpdate(messageIDs: [7], kind: .partial)
            guarded.notePermanentDeletion(messageIDs: [6])
            try require(
                guarded.deliverLatest([
                    value(fixture(id: 5)),
                    value(fixture(id: 6)),
                    value(fixture(id: 7)),
                    value(fixture(id: 8)),
                ], token: latest)
                    && guardedDeliveries == [4, 1, 3, 8] && guarded.failedMessageIDs == [7],
                "latest-page hydration bypassed partial-update or permanent-deletion fences",
            )
            guarded.retryFailures()
            try await require(guarded.refreshNextBatch(), "latest partial-update retry was lost")
            try require(
                guardedDeliveries == [4, 1, 3, 8, 7] && guarded.failedMessageIDs.isEmpty
                    && !guardedReads.contains(5) && !guardedReads.contains(6),
                "retry resurrected a permanently deleted source ID",
            )
            let authoritative = guarded.beginLatestRead()!
            guarded.noteLiveUpdate(messageIDs: [9], kind: .authoritativeMessage)
            guarded.noteLiveUpdate(messageIDs: [9], kind: .partial)
            try require(
                guarded.deliverLatest([value(fixture(id: 9))], token: authoritative)
                    && guarded.failedMessageIDs.isEmpty && !guardedDeliveries.contains(9),
                "full accepted message failed to satisfy the superseded read",
            )
            guarded.retryFailures()
            try await require(!guarded.refreshNextBatch(), "full accepted message required redundant retry")
            let older = guarded.beginLatestRead()!
            let newer = guarded.beginLatestRead()!
            try require(
                !guarded.deliverLatest([value(fixture(id: 10))], token: older)
                    && guarded.deliverLatest([value(fixture(id: 11))], token: newer)
                    && !guarded.deliverLatest([value(fixture(id: 11))], token: newer)
                    && !guardedDeliveries.contains(10) && guardedDeliveries.last == 11,
                "superseded or repeated latest-page token delivered",
            )
            var reentrant: ChatHistoryRestorationRefresh!
            defer { reentrant = nil }
            var reentrantToken: ChatHistoryRestorationRefresh.LatestReadToken?
            var reentrantDeliveries = [Int64]()
            reentrant = ChatHistoryRestorationRefresh(
                location: location, source: source, seedIDs: [], visibleIDs: [], currentSource: { current },
                read: { fixture(id: $0) },
                deliver: {
                    reentrantDeliveries.append($0.messageID)
                    if $0.messageID == 30 { reentrantToken = reentrant.beginLatestRead() }
                },
            )
            try require(
                !reentrant.deliverLatest(
                    [value(fixture(id: 30)), value(fixture(id: 31))], token: reentrant.beginLatestRead()!,
                ) && reentrantDeliveries == [30],
                "new latest request during delivery accepted the superseded remainder or cursor",
            )
            try require(
                reentrant.deliverLatest([value(fixture(id: 32))], token: reentrantToken!)
                    && reentrantDeliveries == [30, 32],
                "new latest request was invalidated by the older delivery",
            )
            let finalDeliveries = guardedDeliveries
            var cancelled: ChatHistoryRestorationRefresh!
            defer { cancelled = nil }
            cancelled = ChatHistoryRestorationRefresh(
                location: location, source: source, seedIDs: [1, 2], visibleIDs: [],
                currentSource: { current },
                read: { id in cancelled.cancel()
                return fixture(id: id)
                },
                deliver: { _ in guardedDeliveries.append(-1) },
            )
            _ = await cancelled.refreshNextBatch()
            let cancelledResumed = await cancelled.refreshNextBatch()
            try require(guardedDeliveries == finalDeliveries && !cancelledResumed, "cancelled read delivered")
            let superseded = ChatHistoryRestorationRefresh(
                location: location, source: source, seedIDs: [1], visibleIDs: [],
                currentSource: { current },
                read: { id in current = .init(accountID: account, clientID: 11)
                return fixture(id: id)
                },
                deliver: { _ in guardedDeliveries.append(-2) },
            )
            _ = await superseded.refreshNextBatch()
            try require(guardedDeliveries == finalDeliveries, "old-client completion delivered")
        }

        private static func verifyProductionRefreshPolicy() async throws {
            let location = ChatLocation(accountID: UUID(), chatID: 100, clientID: 42, topic: nil)
            let source = TdUpdateSource(accountID: location.accountID!, clientID: location.clientID)
            var refresh: ChatHistoryRestorationRefresh!
            defer { refresh = nil }
            var reads = [Int64]()
            var hydrated = [Int64]()
            var deliveries = [ChatHistoryMessageValue]()
            var partialDuringHydration = true
            var fail = false
            refresh = ChatHistoryRestorationRefresh(
                location: location, source: source, seedIDs: [], visibleIDs: [], currentSource: { source },
                read: { id in
                    reads.append(id)
                    if fail { throw TDLibKit.Error(code: 500, message: "offline") }
                    return fixture(id: id, text: "read-\(reads.count)")
                },
                hydrate: { message in
                    hydrated.append(message.id)
                    if message.id == 12 { refresh.notePermanentDeletion(messageIDs: [12]) }
                    if partialDuringHydration {
                        partialDuringHydration = false
                        refresh.noteLiveUpdate(messageIDs: [message.id])
                    }
                    return value(message)
                }, retriesPartialRaces: true,
                deliver: { if case .message(let value) = $0.result { deliveries.append(value) } },
            )
            let oldPage = refresh.beginRead()!
            let live = fixture(id: 1, text: "complete live body")
            try require(refresh.acceptLiveMessage(value(live)), "complete TD body was not applied before metadata")
            refresh.enqueueHydration(message: live)
            refresh.noteLiveUpdate(messageIDs: [1]) // Pin/reaction arrives before queued hydration starts.
            try await require(refresh.refreshNextBatch(), "live hydration was not queued")
            try require(
                reads == [1] && deliveries.map(\.message) == [live] && refresh.remainingCount == 1,
                "older cached payload or hydration replaced a newer partial update",
            )
            try await require(refresh.refreshNextBatch(), "partial race did not enqueue one coalesced read")
            try require(
                reads == [1, 1] && deliveries.last?.message == fixture(id: 1, text: "read-2")
                    && refresh.failedMessageIDs.isEmpty,
                "partial retry did not refresh the unresolved body",
            )
            try await require(!refresh.refreshNextBatch(), "settled partial retry hot-polled")
            try require(
                refresh.takeCurrentValues([value(fixture(id: 1, text: "old page"))], token: oldPage).isEmpty,
                "normal pagination bypassed the live-message revision ledger",
            )

            refresh.setMutationBlocked(true, messageID: 2, owner: .reaction)
            refresh.setMutationBlocked(true, messageID: 2, owner: .pin)
            try require(!refresh.acceptLiveMessage(value(fixture(id: 2))), "in-flight mutation wrapper was replaced")
            refresh.enqueue(messageIDs: [2])
            try await require(!refresh.refreshNextBatch(), "blocked mutation launched a read")
            refresh.setMutationBlocked(false, messageID: 2, owner: .reaction)
            try await require(!refresh.refreshNextBatch(), "reaction completion released the active pin owner")
            refresh.setMutationBlocked(false, messageID: 2, owner: .pin)
            try await require(refresh.refreshNextBatch(), "mutation settlement did not refresh")
            try require(deliveries.last?.message.id == 2, "settled mutation did not deliver")
            refresh.setMutationBlocked(true, messageID: 3, owner: .pin)
            refresh.notePermanentDeletion(messageIDs: [3])
            refresh.setMutationBlocked(false, messageID: 3, owner: .pin)
            refresh.retryFailures()
            try await require(!refresh.refreshNextBatch() && !reads.contains(3), "deleted mutation owner resurrected")

            fail = true
            refresh.enqueue(messageIDs: [4])
            _ = await refresh.refreshNextBatch()
            try await require(
                !refresh.refreshNextBatch() && refresh.failedMessageIDs == [4], "plain read error retried itself",
            )
            fail = false
            refresh.retryFailures()
            _ = await refresh.refreshNextBatch()
            try require(deliveries.last?.message.id == 4, "explicit error retry failed")

            let token = refresh.beginRead()!
            refresh.notePermanentDeletion(messageIDs: [5])
            let accepted = refresh.takeCurrentValues([value(fixture(id: 5)), value(fixture(id: 6))], token: token)
            try require(accepted.map(\.message.id) == [6], "normal page read resurrected permanent deletion")
            let partialBeforeBody = refresh.beginRead()!
            refresh.noteLiveUpdate(messageIDs: [11])
            try require(
                refresh.takeCurrentValues([value(fixture(id: 11))], token: partialBeforeBody).isEmpty,
                "pin/reaction before initial body accepted the older page",
            )
            refresh.enqueue(messageIDs: [12])
            _ = await refresh.refreshNextBatch()
            refresh.retryFailures()
            try await require(
                !refresh.refreshNextBatch() && deliveries.contains { $0.message.id == 11 }
                    && !deliveries.contains { $0.message.id == 12 },
                "partial-before-body stayed unresolved or deletion during hydration resurrected",
            )
            let hydrationCount = hydrated.count
            let latest = refresh.beginLatestRead()!
            try require(
                refresh.enqueueLatest([fixture(id: 7), fixture(id: 8)], token: latest),
                "raw latest page rejected",
            )
            _ = await refresh.refreshNextBatch()
            try require(
                hydrated.count == hydrationCount + 2 && !reads.contains(7) && !reads.contains(8)
                    && Set(deliveries.suffix(2).map(\.message.id)) == [7, 8],
                "raw latest page duplicated reads or bypassed shared hydration",
            )

            let topicLocation = location.withForumTopic(id: 1)
            let topicSeed = ChatHistoryRestorationState(
                location: topicLocation, messages: [value(fixture(id: 20, topic: topicLocation.topic))],
                oldestHistoryMessageID: 10, hasMoreMessages: true,
            )
            var bridge = ChatHistoryLatestRefreshCursor(seed: topicSeed)
            var topicDeliveries = [Int64]()
            let topicRefresh = ChatHistoryRestorationRefresh(
                location: topicLocation, source: source, seedIDs: [], visibleIDs: [], currentSource: { source },
                read: { fixture(id: $0, topic: topicLocation.topic) },
                deliver: { topicDeliveries.append($0.messageID) },
            )
            let foreign = [fixture(id: 40, topic: location.withForumTopic(id: 2).topic), fixture(id: 35)]
            try require(
                bridge.accept(rawPage: foreign, requestedFromMessageID: 0) && bridge.fromMessageID == 35
                    && !bridge.isComplete && topicRefresh.enqueueLatest(
                        foreign,
                        token: topicRefresh.beginLatestRead()!,
                    ),
                "foreign-topic page lost the raw bridge cursor",
            )
            try await require(
                !topicRefresh.refreshNextBatch() && topicDeliveries.isEmpty,
                "foreign topic hydrated into route",
            )
            let overlap = [fixture(id: 34), fixture(id: 20, topic: topicLocation.topic)]
            try require(
                bridge.accept(rawPage: overlap, requestedFromMessageID: 35) && bridge.isComplete
                    && topicRefresh.enqueueLatest(overlap, token: topicRefresh.beginLatestRead()!),
                "raw overlap did not finish the topic bridge",
            )
            _ = await topicRefresh.refreshNextBatch()
            try require(topicDeliveries == [20], "topic bridge admitted a foreign message")

            var deferred: ChatHistoryRestorationRefresh!
            defer { deferred = nil }
            var attempts = 0
            var deferredDeliveries = 0
            var cancelDuringRead = false
            deferred = ChatHistoryRestorationRefresh(
                location: location, source: source, seedIDs: [9], visibleIDs: [], currentSource: { source },
                read: { id in
                    attempts += 1
                    if attempts == 1 || cancelDuringRead {
                        deferred.retryFailures() // Ready/manual retry while a batch owns the worker.
                        if cancelDuringRead { deferred.cancel() }
                        throw TDLibKit.Error(code: 500, message: "interrupted")
                    }
                    return fixture(id: id)
                }, retriesPartialRaces: true,
                deliver: { if case .message = $0.result { deferredDeliveries += 1 } },
            )
            try require(
                deferred.takeCurrentValues([value(fixture(id: 10))], token: token).isEmpty,
                "read token crossed owners",
            )
            _ = await deferred.refreshNextBatch()
            try require(deferred.remainingCount == 1, "ready event was dropped during a failing request")
            _ = await deferred.refreshNextBatch()
            try await require(
                !deferred.refreshNextBatch() && attempts == 2 && deferredDeliveries == 1,
                "deferred ready retry did not settle exactly once",
            )
            let failedLatest = deferred.beginLatestRead()!
            deferred.retryFailures()
            try require(
                deferred.failLatestRead(token: failedLatest),
                "ready during latest RPC was overwritten by failure",
            )
            try require(
                !deferred.failLatestRead(token: deferred.beginLatestRead()!),
                "latest failure retried without a new event",
            )
            let successfulLatest = deferred.beginLatestRead()!
            deferred.retryFailures()
            try require(
                deferred.enqueueLatest([], token: successfulLatest),
                "ready during successful latest wedged its token",
            )
            cancelDuringRead = true
            deferred.enqueue(messageIDs: [10])
            _ = await deferred.refreshNextBatch()
            try await require(
                !deferred.refreshNextBatch() && deferredDeliveries == 1 && deferred.beginRead() == nil,
                "cancelled/retired owner resumed a deferred request",
            )
        }

        private static func value(_ message: Message) -> ChatHistoryMessageValue {
            .init(CustomMessage(message: message, properties: .default))
        }

        private static func fixture(
            id: Int64, album: Int64 = 0, text: String = "message", topic: MessageTopic? = nil,
        ) -> Message {
            Message(
                authorSignature: "", autoDeleteIn: 0, canBeSaved: true, chatId: 100,
                containsUnreadMention: false, containsUnreadPollVotes: false,
                content: .messageText(.init(
                    linkPreview: nil,
                    linkPreviewOptions: nil,
                    text: .init(entities: [], text: text),
                )),
                date: Int(id), editDate: 0, effectId: 0, ephemeralMessageId: 0, factCheck: nil,
                forwardInfo: nil, guestBotCallerId: nil, hasTimestampedMedia: false, id: id,
                importInfo: nil, interactionInfo: nil, isChannelPost: false, isFromOffline: false,
                isOutgoing: true, isPaidGramSuggestedPost: false, isPaidStarSuggestedPost: false,
                isPinned: false, mediaAlbumId: TdInt64(album), paidMessageStarCount: 0, receiverId: nil,
                replyMarkup: nil, replyTo: nil, restrictionInfo: nil, schedulingState: nil,
                selfDestructIn: 0, selfDestructType: nil, senderBoostCount: 0, senderBusinessBotUserId: 0,
                senderId: .messageSenderUser(.init(userId: 1)), senderTag: "", sendingState: nil,
                suggestedPostInfo: nil, summaryLanguageCode: "", topicId: topic, unreadReactions: [], viaBotUserId: 0,
            )
        }
    }
#endif

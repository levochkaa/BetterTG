// ForumTopicsUpdatesProbe.swift

#if DEBUG
import Combine
import TDLibKitDynamic
import UIKit

@MainActor enum ForumTopicsUpdatesProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    @MainActor private final class Fixture {
        let client = TDLib.shared.activeClient
        let source: TdUpdateSource
        var current: TdUpdateSource?
        let changes = PassthroughSubject<TdUpdateSource, Never>()
        let center = NotificationCenter()
        var pages = [(
            query: String,
            cursor: ForumTopicPageCursor,
            continuation: CheckedContinuation<ForumTopics, Swift.Error>,
        )]()
        var topics = [(id: Int, continuation: CheckedContinuation<ForumTopic, Swift.Error>)]()
        var completedPages = Set<Int>()
        var completedTopics = Set<Int>()
        var model: ForumTopicsVM!

        init(restoration: ForumTopicsRestorationState? = nil) {
            self.source = TdUpdateSource(accountID: restoration?.location.accountID ?? UUID(), clientID: client.id)
            self.current = source
            let chat = RootChatInsertionProbe.chat(
                .init(isPinned: false, list: .chatListMain, order: 1, source: nil),
                id: 7,
            )
            let location = ChatLocation(accountID: source.accountID, chatID: 7, clientID: client.id, topic: nil)
            self.model = ForumTopicsVM.controlled(customChat: chat, location: location, client: client, reads: .init(
                currentSource: { [weak self] in self?.current }, sourceChanges: changes.eraseToAnyPublisher(),
                center: center, opensChat: false,
                page: { [weak self] _, cursor, query in
                    try await withCheckedThrowingContinuation { continuation in
                        guard let self else { continuation.resume(throwing: CancellationError())
                        return
                        }
                        self.pages.append((query, cursor, continuation))
                    }
                },
                topic: { [weak self] _, id in
                    try await withCheckedThrowingContinuation { continuation in
                        guard let self else { continuation.resume(throwing: CancellationError())
                        return
                        }
                        self.topics.append((id, continuation))
                    }
                },
            ), restoration: restoration)
        }

        func post(_ topic: ForumTopic, source: TdUpdateSource? = nil) {
            update(.updateForumTopic(topic.updatePayload), source: source ?? self.source, notificationCenter: center)
        }

        func postInfo(_ topic: ForumTopic) {
            update(.updateForumTopicInfo(.init(info: topic.info)), source: source, notificationCenter: center)
        }

        func finishPage(_ index: Int, _ values: [ForumTopic], cursor: Int = 40) {
            completedPages.insert(index)
            pages[index].continuation.resume(returning: .init(
                nextOffsetDate: cursor, nextOffsetForumTopicId: cursor, nextOffsetMessageId: Int64(cursor),
                topics: values, totalCount: 100,
            ))
        }

        func finishTopic(_ index: Int, _ value: ForumTopic?) {
            completedTopics.insert(index)
            if let value { topics[index].continuation.resume(returning: value) }
            else { topics[index].continuation.resume(throwing: Failure(description: "controlled read failure")) }
        }

        func failPage(_ index: Int) {
            completedPages.insert(index)
            pages[index].continuation.resume(throwing: Failure(description: "controlled page failure"))
        }

        func cancelOutstanding() {
            for index in pages.indices where !completedPages.contains(index) {
                pages[index].continuation.resume(throwing: CancellationError())
            }
            for index in topics.indices where !completedTopics.contains(index) {
                topics[index].continuation.resume(throwing: CancellationError())
            }
        }
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-forum-updates") else { return }
        Task { @MainActor in
            let result: String
            do {
                try await verify()
                try await verifyDeferredDemand()
                try await verifyFullReadOrdering()
                try await verifyPageTombstones()
                try await verifyServerSearchMembership()
                try await verifyRetainedSearchMembership()
                result = "Forum updates probe passed: real-VM/injected-page-topic-reads/local-scoped-updates=true; "
                    + "echo-before-after-page-topic/unknown-coalescing/failed-echo-no-retry=true; "
                    + "direct-scalar/no-RPC/native-cell/late-page-scalar/draft-inbox-one-refresh=true; "
                    + "semantic-demand-after-page/individual-to-page/page-failure/hidden-unknown=true; "
                    + "query-source-retirement/request-owner/wrong-response/late-error=true; "
                    + "full-read-order/both-completions/unrelated-event/newer-failure/info-tombstones/raw-cursor=true; "
                    + "server-query-membership/same-name-info-echo/newer-rename/hidden=true; "
                    + "retained-query-name/closed-info/inbox-draft-read/rename-hide-query-source-ABA/display-seed=true; "
                    + "full-controller/real-RPC=unverified; server-writes=0"
            } catch { result = "Forum updates probe failed: \(error)" }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("forum-updates-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func verify() async throws {
        let f = Fixture()
        defer { f.model.retire()
        f.cancelOutstanding()
        }
        let first = topic(id: 1)
        f.model.loadInitial()
        try await until("initial page dispatch") { f.pages.count == 1 }
        f.postInfo(first)
        f.post(first)
        f.post(first)
        await events()
        try require(f.topics.isEmpty, "page echoes spawned individual reads before page completion")
        let pageTask = f.model.probeReadTasks
        f.finishPage(0, [first])
        try await terminal(pageTask)
        f.post(first)
        await events()
        try require(f.topics.isEmpty && f.model.topics.count == 1, "page response echo recursively fetched topic")

        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 390, height: 500), style: .plain)
        let cell = ForumTopicCell(style: .default, reuseIdentifier: nil)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { throw Failure(description: "no scene") }
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(table)
        table.tableHeaderView = cell
        cell.frame.size = CGSize(width: 390, height: 70)
        window.isHidden = false
        defer { window.isHidden = true
        window.rootViewController = nil
        }
        let observation = f.model.$topics.sink { values in
            if let value = values.first(where: { $0.info.forumTopicId == 1 }) { cell.configure(
                topic: value,
                client: f.client,
            ) }
        }
        defer { observation.cancel() }
        let read = topic(id: 1, outbox: 12, mentions: 3)
        f.post(read)
        await events()
        try require(
            f.topics.isEmpty && f.model.topics[0].lastReadOutboxMessageId == 12
                && cell.window === window && cell.accessibilityLabel?.contains("3 unread mentions") == true,
            "direct scalar did not update real VM/cell without RPC",
        )

        f.model.loadMore()
        try await until("append page dispatch") { f.pages.count == 2 }
        f.post(topic(id: 1, outbox: 20, mentions: 4))
        await events()
        let append = f.model.probeReadTasks
        f.finishPage(1, [read], cursor: 80)
        try await terminal(append)
        try require(
            f.model.topics[0].lastReadOutboxMessageId == 20
                && f.model.restorationState(rawQuery: "").cursor == .init(date: 80, forumTopicID: 80, messageID: 80),
            "late page reverted direct scalar or changed raw cursor",
        )

        let drafted = topic(id: 1, outbox: 20, draft: "fresh", mentions: 4)
        f.post(drafted)
        try await until("draft omitted-order refresh") { f.topics.count == 1 }
        f.post(drafted)
        await events()
        let draftTask = f.model.probeReadTasks
        f.finishTopic(0, drafted)
        try await terminal(draftTask)
        f.post(drafted)
        await events()
        try require(f.topics.count == 1, "draft response echo started another request")

        let inbox = topic(id: 1, outbox: 20, inbox: 9, draft: "fresh", mentions: 4)
        f.post(inbox)
        try await until("inbox omitted-count refresh") { f.topics.count == 2 }
        f.post(inbox)
        await events()
        let inboxTask = f.model.probeReadTasks
        f.finishTopic(1, inbox)
        try await terminal(inboxTask)
        f.post(inbox)
        await events()
        try require(f.topics.count == 2, "inbox response echo started another request")

        let unknown = topic(id: 2)
        f.post(unknown)
        try await until("unknown topic once") { f.topics.count == 3 }
        f.postInfo(unknown)
        f.post(unknown)
        await events()
        let unknownTask = f.model.probeReadTasks
        f.finishTopic(2, unknown)
        try await terminal(unknownTask)
        f.post(unknown)
        await events()
        try require(f.topics.count == 3 && f.model.topics.contains { $0.info.forumTopicId == 2 }, "unknown echo looped")

        f.post(topic(id: 3))
        try await until("failed unknown read") { f.topics.count == 4 }
        let failedTask = f.model.probeReadTasks
        f.finishTopic(3, nil)
        try await terminal(failedTask)
        f.post(topic(id: 3))
        await events()
        try require(f.topics.count == 4, "identical failed echo automatically retried")

        f.post(topic(id: 4))
        try await until("wrong identity read") { f.topics.count == 5 }
        let wrongTask = f.model.probeReadTasks
        f.finishTopic(4, topic(id: 99))
        try await terminal(wrongTask)
        try require(!f.model.topics.contains { $0.info.forumTopicId == 99 }, "wrong returned topic accepted")

        f.post(topic(id: 5))
        try await until("old query topic") { f.topics.count == 6 }
        let oldQueryTask = f.model.probeReadTasks
        f.model.search("Other")
        try await until("new query page") { f.pages.count == 3 }
        f.post(topic(id: 5, name: "Other"))
        await events()
        let newPageTask = f.model.probeReadTasks
        f.finishPage(2, [])
        try await terminal(newPageTask)
        try await until("replacement topic same ID") { f.topics.count == 7 }
        let replacementTask = f.model.probeReadTasks
        f.finishTopic(5, nil)
        try await terminal(oldQueryTask)
        try require(f.model.errorMessage == nil && !f.model.probeReadTasks.isEmpty, "old callback cleared successor")
        f.finishTopic(6, topic(id: 5, name: "Other"))
        try await terminal(replacementTask)
        try require(f.model.topics.map(\.info.forumTopicId) == [5], "current query row did not commit")

        let filtered = topic(id: 6, name: "Unrelated")
        f.post(filtered)
        try await until("unknown filtered topic") { f.topics.count == 8 }
        f.postInfo(filtered)
        f.post(filtered)
        await events()
        let filteredTask = f.model.probeReadTasks
        f.finishTopic(7, filtered)
        try await terminal(filteredTask)
        f.post(filtered)
        await events()
        try require(f.topics.count == 8 && f.model.topics.map(\.info.forumTopicId) == [5], "filtered echo looped")

        f.post(topic(id: 7, name: "Other"))
        try await until("source-lifetime read") { f.topics.count == 9 }
        let sourceTask = f.model.probeReadTasks
        let foreign = TdUpdateSource(accountID: UUID(), clientID: f.source.clientID)
        f.current = foreign
        f.changes.send(foreign)
        f.current = f.source
        f.changes.send(f.source)
        f.finishTopic(8, topic(id: 7, name: "Other"))
        try await terminal(sourceTask)
        f.post(topic(id: 8, name: "Other"))
        await events()
        try require(
            f.topics.count == 9 && f.model.topics.map(\.info.forumTopicId) == [5],
            "source ABA revived retired VM",
        )
    }

    private static func topic(
        id: Int, name: String = "Swift", outbox: Int64 = 0, inbox: Int64 = 0,
        draft: String? = nil, mentions: Int = 0, hidden: Bool = false, closed: Bool = false,
        unreadCount: Int = 0, order: Int64 = 10, lastID: Int64? = nil,
    ) -> ForumTopic {
        let base = ForumTopicsRestorationProbe.topic(id: id, name: name)
        let payload = UpdateForumTopic(
            chatId: 7, draftMessage: draft.map { .init(
                content: .draftMessageContentText(.init(linkPreviewOptions: nil, text: .init(entities: [], text: $0))),
                date: 1, effectId: 0, replyTo: nil, suggestedPostInfo: nil,
            ) }, forumTopicId: id, isPinned: false, lastReadInboxMessageId: inbox, lastReadOutboxMessageId: outbox,
            notificationSettings: base.notificationSettings, unreadMentionCount: mentions,
            unreadPollVoteCount: 0, unreadReactionCount: 0,
        )
        let result = base.applying(update: payload)
        return ForumTopic(
            draftMessage: result.draftMessage,
            info: .init(
                chatId: 7, creationDate: 1, creatorId: base.info.creatorId, forumTopicId: id, icon: base.info.icon,
                isClosed: closed, isGeneral: false, isHidden: hidden, isNameImplicit: false, isOutgoing: false,
                name: name,
            ), isPinned: result.isPinned, lastMessage: lastID.map { lastMessage(id: $0, topicID: id) },
            lastReadInboxMessageId: inbox,
            lastReadOutboxMessageId: outbox,
            notificationSettings: result.notificationSettings, order: TdInt64(order), unreadCount: unreadCount,
            unreadMentionCount: mentions, unreadPollVoteCount: 0, unreadReactionCount: 0,
        )
    }

    private static func verifyDeferredDemand() async throws {
        let f = Fixture()
        defer { f.model.retire()
        f.cancelOutstanding()
        }
        let base = topic(id: 1)
        f.model.loadInitial()
        try await until("semantic initial page") { f.pages.count == 1 }
        let firstPage = f.model.probeReadTasks
        f.finishPage(0, [base])
        try await terminal(firstPage)
        f.model.loadMore()
        try await until("semantic append page") { f.pages.count == 2 }
        let newer = topic(id: 1, outbox: 12, inbox: 3, draft: "new")
        f.post(newer)
        f.post(newer)
        await events()
        try require(f.topics.isEmpty, "semantic page demand bypassed page suppression")
        let append = f.model.probeReadTasks
        f.finishPage(1, [base], cursor: 80)
        try await terminal(append)
        try await until("semantic demand survived returned row") { f.topics.count == 1 }
        let one = f.model.probeReadTasks
        f.finishTopic(0, topic(id: 1, outbox: 12, inbox: 3, draft: "new", unreadCount: 5, order: 90))
        try await terminal(one)
        try require(
            f.topics.count == 1 && f.model.topics[0].unreadCount == 5 && f.model.topics[0].order == 90,
            "page swallowed omitted count/order semantic refresh",
        )

        f.post(topic(id: 1, outbox: 12, inbox: 4, draft: "new"))
        try await until("individual before page") { f.topics.count == 2 }
        let individual = f.model.probeReadTasks
        f.post(topic(id: 1, outbox: 12, inbox: 5, draft: "new"))
        await events()
        f.model.loadMore()
        try await until("overlapping append") { f.pages.count == 3 }
        f.finishTopic(1, topic(id: 1, outbox: 12, inbox: 4, draft: "new"))
        try await terminal(individual)
        let overlappingPage = f.model.probeReadTasks
        f.finishPage(2, [base], cursor: 120)
        try await terminal(overlappingPage)
        try await until("semantic flag survived individual defer and page") { f.topics.count == 3 }
        let finalRead = f.model.probeReadTasks
        f.finishTopic(2, topic(id: 1, outbox: 12, inbox: 5, draft: "new", unreadCount: 7))
        try await terminal(finalRead)
        try require(f.topics.count == 3 && f.model.topics[0].unreadCount == 7, "semantic follow-up lost or repeated")

        f.model.loadMore()
        try await until("failing page") { f.pages.count == 4 }
        f.post(topic(id: 2))
        await events()
        let failedPage = f.model.probeReadTasks
        f.failPage(3)
        try await terminal(failedPage)
        try await until("unknown demand after page failure") { f.topics.count == 4 }
        let unknown = f.model.probeReadTasks
        f.postInfo(topic(id: 2, hidden: true))
        await events()
        f.finishTopic(3, topic(id: 2))
        try await terminal(unknown)
        f.post(topic(id: 2))
        await events()
        try require(
            f.topics.count == 4 && !f.model.topics.contains { $0.info.forumTopicId == 2 },
            "hidden unknown echo looped",
        )
    }

    private static func verifyFullReadOrdering() async throws {
        for pageFirst in [false, true] {
            let f = Fixture()
            defer { f.model.retire()
            f.cancelOutstanding()
            }
            f.model.loadInitial()
            try await until("ordering initial page") { f.pages.count == 1 }
            let initial = f.model.probeReadTasks
            f.finishPage(0, [topic(id: 1), topic(id: 2)])
            try await terminal(initial)
            f.post(topic(id: 1, inbox: 1))
            try await until("older individual dispatch") { f.topics.count == 1 }
            let individual = f.model.probeReadTasks
            f.model.loadMore()
            try await until("newer page dispatch") { f.pages.count == 2 }
            let page = [f.model.probePageTask].compactMap(\.self)
            // Unrelated revision changes must not turn a full-read baseline into a live event.
            f.post(topic(id: 2, outbox: 900))
            await events()
            let older = topic(id: 1, name: "Older", outbox: 10, inbox: 1, unreadCount: 10, order: 100, lastID: 100)
            let newer = topic(id: 1, name: "Newer", outbox: 20, inbox: 2, unreadCount: 20, order: 200, lastID: 200)
            if pageFirst {
                f.finishPage(1, [newer], cursor: 80)
                try await terminal(page)
                f.finishTopic(0, older)
                try await terminal(individual)
            } else {
                f.finishTopic(0, older)
                try await terminal(individual)
                try require(
                    f.model.topics.first { $0.info.forumTopicId == 1 }?.lastMessage?.id == 100
                        && f.model.topics.first { $0.info.forumTopicId == 1 }?.info.name == "Older",
                    "pending newer request suppressed valid older response",
                )
                f.finishPage(1, [newer], cursor: 80)
                try await terminal(page)
            }
            let row = f.model.topics.first { $0.info.forumTopicId == 1 }
            try require(
                row?.lastMessage?.id == 200 && row?.order == 200 && row?.unreadCount == 20
                    && row?.info.name == "Newer" && row?.lastReadOutboxMessageId == 20,
                "full response ordering or unrelated live revision corrupted newer row (pageFirst=\(pageFirst))",
            )
            f.post(newer)
            await events()
            try require(f.topics.count == 1, "rejected old response regressed echo comparison baseline")
        }

        let f = Fixture()
        defer { f.model.retire()
        f.cancelOutstanding()
        }
        f.model.loadInitial()
        try await until("failed newer initial page") { f.pages.count == 1 }
        let initial = f.model.probeReadTasks
        f.finishPage(0, [topic(id: 1)])
        try await terminal(initial)
        f.post(topic(id: 1, inbox: 1))
        try await until("valid older read") { f.topics.count == 1 }
        let individual = f.model.probeReadTasks
        f.model.loadMore()
        try await until("failed newer page") { f.pages.count == 2 }
        let page = [f.model.probePageTask].compactMap(\.self)
        f.failPage(1)
        try await terminal(page)
        f.finishTopic(0, topic(id: 1, inbox: 1, unreadCount: 77, order: 77, lastID: 77))
        try await terminal(individual)
        try require(
            f.model.topics.first?.lastMessage?.id == 77 && f.model.topics.first?.unreadCount == 77,
            "failed newer request suppressed valid older full response",
        )
    }

    private static func verifyPageTombstones() async throws {
        for hidden in [true, false] {
            let f = Fixture()
            defer { f.model.retire()
            f.cancelOutstanding()
            }
            f.model.search("Swift")
            try await until("tombstone initial page") { f.pages.count == 1 }
            let initial = f.model.probeReadTasks
            f.finishPage(0, [topic(id: 1)])
            try await terminal(initial)
            f.post(topic(id: 1, inbox: 1))
            try await until("tombstone old individual") { f.topics.count == 1 }
            let individual = f.model.probeReadTasks
            f.model.loadMore()
            try await until("tombstone append") { f.pages.count == 2 }
            let page = [f.model.probePageTask].compactMap(\.self)
            f.postInfo(topic(id: 1, name: hidden ? "Swift" : "Other", hidden: hidden))
            await events()
            try require(f.model.topics.isEmpty, "live hidden/nonmatching info did not remove row")
            f.finishPage(1, [topic(id: 1)], cursor: 80)
            try await terminal(page)
            f.finishTopic(0, topic(id: 1, inbox: 1, unreadCount: 9, lastID: 9))
            try await terminal(individual)
            try require(
                f.model.topics.isEmpty && f.model.hasMore
                    && f.model.restorationState(rawQuery: "Swift").cursor == .init(
                        date: 80,
                        forumTopicID: 80,
                        messageID: 80,
                    )
                    && f.topics.count == 1,
                "stale page/individual revived tombstone, changed raw cursor or spawned read",
            )
            // A later full read can replace pre-dispatch info; tombstones aren't permanent exclusions.
            f.model.loadMore()
            try await until("fresh after tombstone") { f.pages.count == 3 }
            let fresh = [f.model.probePageTask].compactMap(\.self)
            f.finishPage(2, [topic(id: 1, inbox: 2, unreadCount: 2)], cursor: 120)
            try await terminal(fresh)
            try require(
                f.model.topics.count == 1 && f.model.topics[0].info.name == "Swift"
                    && !f.model.topics[0].info.isHidden && f.model.topics[0].unreadCount == 2,
                "pre-dispatch info was reapplied over fresh full response",
            )
        }
    }

    private static func lastMessage(id: Int64, topicID: Int) -> Message {
        Message(
            authorSignature: "", autoDeleteIn: 0, canBeSaved: true, chatId: 7,
            containsUnreadMention: false, containsUnreadPollVotes: false,
            content: .messageText(.init(
                linkPreview: nil,
                linkPreviewOptions: nil,
                text: .init(entities: [], text: "probe"),
            )),
            date: 1, editDate: 0, effectId: 0, ephemeralMessageId: 0, factCheck: nil, forwardInfo: nil,
            guestBotCallerId: nil, hasTimestampedMedia: false, id: id, importInfo: nil, interactionInfo: nil,
            isChannelPost: false, isFromOffline: false, isOutgoing: false, isPaidGramSuggestedPost: false,
            isPaidStarSuggestedPost: false, isPinned: false, mediaAlbumId: 0, paidMessageStarCount: 0,
            receiverId: nil, replyMarkup: nil, replyTo: nil, restrictionInfo: nil, schedulingState: nil,
            selfDestructIn: 0, selfDestructType: nil, senderBoostCount: 0, senderBusinessBotUserId: 0,
            senderId: .messageSenderUser(.init(userId: 1)), senderTag: "", sendingState: nil,
            suggestedPostInfo: nil, summaryLanguageCode: "", topicId: .messageTopicForum(.init(forumTopicId: topicID)),
            unreadReactions: [], viaBotUserId: 0,
        )
    }

    private static func verifyServerSearchMembership() async throws {
        let f = Fixture()
        defer { f.model.retire()
        f.cancelOutstanding()
        }
        f.model.search("Geberal")
        try await until("server search initial page") { f.pages.count == 1 }
        let initial = [f.model.probePageTask].compactMap(\.self)
        let serverMatch = topic(id: 1, name: "General")
        f.postInfo(serverMatch)
        await events()
        f.finishPage(0, [serverMatch])
        try await terminal(initial)
        try require(
            f.model.topics.map(\.info.name) == ["General"] && f.topics.isEmpty,
            "server fuzzy match or its same-name info echo was locally filtered",
        )
        f.model.loadMore()
        try await until("server search append") { f.pages.count == 2 }
        let append = [f.model.probePageTask].compactMap(\.self)
        f.postInfo(serverMatch)
        await events()
        f.finishPage(1, [serverMatch], cursor: 80)
        try await terminal(append)
        try require(f.model.topics.map(\.info.name) == ["General"], "append info echo lost server membership")

        f.model.loadMore()
        try await until("server search renamed page") { f.pages.count == 3 }
        let renamed = [f.model.probePageTask].compactMap(\.self)
        f.postInfo(topic(id: 1, name: "Other"))
        await events()
        f.finishPage(2, [serverMatch], cursor: 120)
        try await terminal(renamed)
        try require(f.model.topics.isEmpty, "newer different name failed to invalidate old server membership")

        f.model.loadMore()
        try await until("server search hidden page") { f.pages.count == 4 }
        let hidden = [f.model.probePageTask].compactMap(\.self)
        f.finishPage(3, [topic(id: 1, name: "General", hidden: true)], cursor: 160)
        try await terminal(hidden)
        try require(
            f.model.topics.isEmpty && f.model.hasMore && f.topics.isEmpty,
            "server-membership exception admitted hidden topic or spawned reads",
        )
    }

    private static func loadFuzzyResult(_ f: Fixture) async throws {
        f.model.search("Geberal")
        try await until("retained fuzzy initial page") { f.pages.count == 1 }
        let task = [f.model.probePageTask].compactMap(\.self)
        f.finishPage(0, [topic(id: 1, name: "General")])
        try await terminal(task)
    }

    private static func verifyRetainedSearchMembership() async throws {
        let f = Fixture()
        defer { f.model.retire()
        f.cancelOutstanding()
        }
        try await loadFuzzyResult(f)
        f.postInfo(topic(id: 1, name: "General", closed: true))
        await events()
        try require(
            f.model.topics.count == 1 && f.model.topics[0].info.isClosed && f.topics.isEmpty,
            "same-name changed info removed server-admitted row or started read",
        )
        f.post(topic(id: 1, name: "General", inbox: 1))
        try await until("known fuzzy inbox refresh") { f.topics.count == 1 }
        let inbox = f.model.probeReadTasks
        f.finishTopic(0, topic(id: 1, name: "General", inbox: 1, closed: true, unreadCount: 5, order: 50, lastID: 50))
        try await terminal(inbox)
        try require(f.model.topics.first?.lastMessage?.id == 50, "known fuzzy individual result was removed")
        let drafted = topic(id: 1, name: "General", inbox: 1, draft: "draft", closed: true, unreadCount: 5, order: 60)
        f.post(drafted)
        try await until("known fuzzy draft refresh") { f.topics.count == 2 }
        let draft = f.model.probeReadTasks
        f.finishTopic(1, drafted)
        try await terminal(draft)
        f.post(drafted)
        f.postInfo(drafted)
        await events()
        try require(
            f.model.topics.first?.order == 60 && f.topics.count == 2,
            "known fuzzy membership or echo dedup failed after semantic refresh",
        )

        let seed = f.model.restorationState(rawQuery: "Geberal")
        let restored = Fixture(restoration: seed)
        defer { restored.model.retire()
        restored.cancelOutstanding()
        }
        restored.model.start()
        restored.postInfo(topic(id: 1, name: "General"))
        await events()
        try require(
            restored.model.topics.first?.info.name == "General" && restored.pages.isEmpty,
            "accepted-query display seed lost unchanged-name membership",
        )
        restored.post(topic(id: 1, name: "General", inbox: 2, draft: "draft"))
        try await until("restored display row current read") { restored.topics.count == 1 }
        let restoredRead = restored.model.probeReadTasks
        restored.finishTopic(0, topic(id: 1, name: "General", inbox: 2, draft: "draft", unreadCount: 2))
        try await terminal(restoredRead)
        try require(restored.model.topics.first?.unreadCount == 2, "restored current read removed unchanged-name row")

        // Another ID with the same fuzzy name has never been admitted by the server page.
        f.post(topic(id: 2, name: "General"))
        try await until("unknown fuzzy individual") { f.topics.count == 3 }
        let unknown = f.model.probeReadTasks
        f.finishTopic(2, topic(id: 2, name: "General"))
        try await terminal(unknown)
        try require(
            f.model.topics.map(\.info.forumTopicId) == [1],
            "unknown fuzzy lookup borrowed known row membership",
        )

        for hides in [false, true] {
            let changed = Fixture()
            defer { changed.model.retire()
            changed.cancelOutstanding()
            }
            try await loadFuzzyResult(changed)
            changed.post(topic(id: 1, name: "General", inbox: 1))
            try await until("fuzzy read before identity departure") { changed.topics.count == 1 }
            let pending = changed.model.probeReadTasks
            changed.postInfo(topic(id: 1, name: hides ? "General" : "Other", hidden: hides))
            changed.postInfo(topic(id: 1, name: "General"))
            await events()
            try require(changed.model.topics.isEmpty, "rename/hide ABA retained departed fuzzy membership")
            changed.finishTopic(0, topic(id: 1, name: "General", inbox: 1, unreadCount: 9))
            try await terminal(pending)
            try require(
                changed.model.topics.isEmpty && changed.topics.count == 1,
                "late unchanged-name result revived removed fuzzy row",
            )
        }
        for changesSource in [false, true] {
            let changed = Fixture()
            defer { changed.model.retire()
            changed.cancelOutstanding()
            }
            try await loadFuzzyResult(changed)
            changed.post(topic(id: 1, name: "General", inbox: 1))
            try await until("fuzzy read before query/source departure") { changed.topics.count == 1 }
            let pending = changed.model.probeReadTasks
            if changesSource {
                let other = TdUpdateSource(accountID: UUID(), clientID: changed.source.clientID)
                changed.current = other
                changed.changes.send(other)
                changed.current = changed.source
                changed.changes.send(changed.source)
            } else {
                changed.model.search("Other")
                try await until("fuzzy different query") { changed.pages.count == 2 }
                let departed = [changed.model.probePageTask].compactMap(\.self)
                changed.model.search("Geberal")
                try await until("fuzzy query ABA") { changed.pages.count == 3 }
                let current = [changed.model.probePageTask].compactMap(\.self)
                changed.finishPage(2, [topic(id: 1, name: "General", unreadCount: 2)])
                try await terminal(current)
                changed.finishPage(1, [topic(id: 2, name: "Other")])
                try await terminal(departed)
            }
            changed.finishTopic(0, topic(id: 1, name: "General", unreadCount: 9))
            try await terminal(pending)
            try require(
                changed.model.topics.map(\.info.forumTopicId) == [1]
                    && changed.model.topics[0].unreadCount == (changesSource ? 0 : 2),
                "late fuzzy read crossed query/source ABA",
            )
        }
    }

    private static func terminal(_ tasks: [Task<Void, Never>]) async throws {
        var done = false
        Task { for task in tasks {
            await task.value
        }
        done = true
        }
        try await until("exact task completion") { done }
    }

    private static func events() async {
        for _ in 0..<5 {
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
        }
    }

    private static func until(_ label: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(condition(), "timed out: \(label)")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }
}
#endif

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

        init() {
            self.source = TdUpdateSource(accountID: UUID(), clientID: client.id)
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
            ))
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
                result = "Forum updates probe passed: real-VM/injected-page-topic-reads/local-scoped-updates=true; "
                    + "echo-before-after-page-topic/unknown-coalescing/failed-echo-no-retry=true; "
                    + "direct-scalar/no-RPC/native-cell/late-page-scalar/draft-inbox-one-refresh=true; "
                    + "semantic-demand-after-page/individual-to-page/page-failure/hidden-unknown=true; "
                    + "query-source-retirement/request-owner/wrong-response/late-error=true; "
                    + "page-full-omitted-fields/info-tombstones/real-RPC=unverified; server-writes=0"
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
        draft: String? = nil, mentions: Int = 0, hidden: Bool = false,
        unreadCount: Int = 0, order: Int64 = 10,
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
                isClosed: false, isGeneral: false, isHidden: hidden, isNameImplicit: false, isOutgoing: false,
                name: name,
            ), isPinned: result.isPinned, lastMessage: nil, lastReadInboxMessageId: inbox,
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

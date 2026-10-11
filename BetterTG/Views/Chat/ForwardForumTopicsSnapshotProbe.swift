// ForwardForumTopicsSnapshotProbe.swift

#if DEBUG
import TDLibKit
import UIKit

/// Runs the production controller, page admission, provider and selection path.
/// Only read results/source/rights are injected; no TDLib mutation is available.
@MainActor enum ForwardForumTopicsSnapshotProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    @MainActor private final class Reads {
        struct Request {
            let query: String
            let cursor: ForumTopicPageCursor
            var continuation: CheckedContinuation<ForumTopics, Swift.Error>?
        }

        var requests = [Request]()
        var completions = [() -> Void]()
        var errors = [String]()
        var selections = [(Int, Bool)]()
        var current = true

        func read(_ query: String, _ cursor: ForumTopicPageCursor) async throws -> ForumTopics {
            try await withCheckedThrowingContinuation { continuation in
                requests.append(.init(query: query, cursor: cursor, continuation: continuation))
            }
        }

        func finish(_ index: Int, _ page: ForumTopics?) throws {
            guard requests.indices.contains(index), let continuation = requests[index].continuation
            else { throw Failure(description: "missing read \(index)") }
            requests[index].continuation = nil
            if let page { continuation.resume(returning: page) }
            else { continuation.resume(throwing: Failure(description: "controlled read failure")) }
        }

        func release() throws -> () -> Void {
            guard !completions.isEmpty else { throw Failure(description: "missing native completion") }
            let completion = completions.removeFirst()
            completion()
            return completion
        }

        func close() {
            current = false
            for index in requests.indices where requests[index].continuation != nil {
                try? finish(index, nil)
            }
            let pending = completions
            completions.removeAll()
            pending.forEach { $0() }
        }
    }

    @MainActor private final class Fixture {
        let reads = Reads()
        let controller: ForwardForumTopicsViewController
        let navigation: UINavigationController
        let window: UIWindow

        init() throws {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
            else { throw Failure(description: "no window scene") }
            let chat = ProbeFixtures.chat(.init(isPinned: false, list: .chatListMain, order: 1, source: nil))
                .chat
            let prepared = try PreparedMessageForward(
                request: .init(sourceChatID: 8, messageIDs: [1]), canForward: true,
                canCopy: true, canCopyToSecretChat: false, contentRequirements: [], hasCaptions: false,
            )
            self.controller = ForwardForumTopicsViewController(
                chat: chat, preparedForward: prepared, client: TDLib.shared.activeClient,
                accountID: UUID(), selectedTopicIDs: [],
            )
            controller.probeInitialRights = false
            controller.probeCurrentContext = { [reads] in reads.current }
            controller.probeReadPage = { [reads] query, cursor in try await reads.read(query, cursor) }
            controller.probeError = { [reads] in reads.errors.append($0) }
            controller.probeSnapshotCompletion = { [reads] in reads.completions.append($0) }
            controller.onSelect = { [reads] in reads.selections.append(($0.info.forumTopicId, true)) }
            self.navigation = UINavigationController(rootViewController: UIViewController())
            navigation.pushViewController(controller, animated: false)
            self.window = UIWindow(windowScene: scene)
            window.rootViewController = navigation
            window.isHidden = false
            navigation.view.layoutIfNeeded()
        }

        func close() {
            navigation.setViewControllers([navigation.viewControllers[0]], animated: false)
            reads.close()
            window.isHidden = true
            window.rootViewController = nil
        }

        func finish(_ index: Int, _ page: ForumTopics?) async throws {
            guard let task = controller.probeTask else { throw Failure(description: "missing exact page task") }
            try reads.finish(index, page)
            await task.value
            controller.probeTable.layoutIfNeeded()
        }

        func settle() async throws {
            try await until("native apply completion") { !self.reads.completions.isEmpty }
            _ = try reads.release()
            controller.probeTable.layoutIfNeeded()
            try require(!controller.probeSnapshotBusy, "snapshot did not settle")
        }

        func readCount(_ count: Int) async throws {
            try await until("read \(count)") { self.reads.requests.count == count }
        }
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-forward-forum-snapshot") else { return }
        Task { @MainActor in
            let result: String
            do {
                try await verifyTransactions()
                try await verifyQueryRetryAndSource()
                try await verifyPinnedOrder()
                try await verifyRetainedParent()
                let teardown = try await verifyTeardown()
                result = "Forward forum snapshot probe passed: production-controller/native-table/provider=true; "
                    + "serialized/coalesced/outgoing-models/exact-completion/selection-reconfigure=true; "
                    + "accepted-query/failed-head-retry/raw-cursor/stale-query-source/teardown=true; "
                    + "raw-head-pin-rank/append-membership-revocation/query-rank/selected-identity=true; "
                    + "initial-containment/synthetic-retained-parent-removal=true; "
                    + "same-instance/fallback-cleanup=true; read-only-injection/server-writes=0; "
                    + "baseline-UIKit-crash/live-TDLib/real-forward-delivery/interactive-pop-gesture=unverified; \(teardown)"
            } catch { result = "Forward forum snapshot probe failed: \(error)" }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("forward-forum-snapshot-probe.txt"), options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func require(_ value: Bool, _ description: String) throws {
        guard value else { throw Failure(description: description) }
    }

    private static func until(_ description: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(condition(), "timed out: \(description)")
    }

    private static func topic(
        _ id: Int, _ name: String, closed: Bool = false, pinned: Bool = false, order: Int64 = 10,
        chatID: Int64 = 7, hidden: Bool = false,
    ) -> ForumTopic {
        let base = ForumTopicsRestorationProbe.topic(id: id, name: name)
        return ForumTopic(
            draftMessage: nil, info: .init(
                chatId: chatID, creationDate: 1, creatorId: .messageSenderUser(.init(userId: 1)), forumTopicId: id,
                icon: .init(color: 0x4A9EF1, customEmojiId: 0), isClosed: closed, isGeneral: false,
                isHidden: hidden, isNameImplicit: false, isOutgoing: false, name: name,
            ), isPinned: pinned, lastMessage: nil, lastReadInboxMessageId: 0, lastReadOutboxMessageId: 0,
            notificationSettings: base.notificationSettings, order: .init(order), unreadCount: 0,
            unreadMentionCount: 0, unreadPollVoteCount: 0, unreadReactionCount: 0,
        )
    }

    private static func page(_ topics: [ForumTopic], cursor: ForumTopicPageCursor = .zero) -> ForumTopics {
        .init(
            nextOffsetDate: cursor.date, nextOffsetForumTopicId: cursor.forumTopicID,
            nextOffsetMessageId: cursor.messageID, topics: topics, totalCount: topics.count,
        )
    }

    private static func verifyTransactions() async throws {
        let f = try Fixture()
        defer { f.close() }
        let c = f.controller
        try await f.readCount(1)
        try await f.finish(0, page([topic(1, "A"), topic(2, "B")]))
        try await f.settle()
        guard let original = c.probeTable.cellForRow(at: IndexPath(row: 0, section: 0)) as? ForumTopicCell
        else { throw Failure(description: "initial production cell missing") }

        c.probeSearch("a")
        c.probeSelect(0)
        try require(f.reads.selections.isEmpty, "pending query selected old result")
        try await f.readCount(2)
        try await f.finish(1, page([topic(1, "A-prime"), topic(3, "C")]))
        try await until("held reconfigure") { f.reads.completions.count == 1 }
        let starts = c.probeSnapshotStarts
        try require(
            c.probeTable.cellForRow(at: IndexPath(row: 0, section: 0)) === original,
            "reconfigure replaced initial cell",
        )
        try require(original.accessibilityLabel?.hasPrefix("A-prime,") == true, "wrong reconfigure model")

        c.probeSearch("b")
        try await f.readCount(3)
        try await f.finish(2, page([topic(2, "B-prime")]))
        c.probeSearch("c")
        try await f.readCount(4)
        try await f.finish(3, page([topic(3, "C-prime"), topic(4, "Closed", closed: true)]))
        c.probeSelect(0)
        try require(
            c.probeSnapshotStarts == starts && c.probeTopic(1)?.info.name == "A-prime"
            && c.probeTopic(2)?.info.name == "B" && f.reads.selections.isEmpty,
            "pending result replaced active models or admitted selection",
        )
        let completed = try f.reads.release()
        try require(
            c.probeSnapshotStarts == starts + 1 && c.probeTopic(1) != nil,
            "coalesced apply missing or outgoing row pruned",
        )
        completed()
        try require(c.probeSnapshotBusy, "duplicate completion finished another transaction")
        try await f.settle()
        try require(
            c.probeIDs == [3, 4] && c.probeTopic(1) == nil && c.probeTopic(2) == nil,
            "latest query did not settle exactly",
        )

        c.probeSelect(1)
        try require(f.reads.selections.isEmpty, "closed row admitted")
        c.probeSelect(0)
        c.probeSelect(0)
        try require(
            f.reads.selections.count == 1 && f.reads.selections[0].0 == 3
            && f.reads.selections[0].1,
            "toggle was duplicated or wrong identity",
        )
        try await f.settle()
        let selected = c.probeTable.cellForRow(at: IndexPath(row: 0, section: 0))
        try require(selected?.accessoryType == .checkmark, "selected decoration missing")
        c.probeSelect(0)
        try await f.settle()
        try require(
            f.reads.selections.count == 2 && !f.reads.selections[1].1
            && selected?.accessoryType == UITableViewCell.AccessoryType.none,
            "deselection changed semantics",
        )

        c.probeSelect(0)
        try await f.settle()
        c.probeOmitCellModel = true
        c.probeReconfigure()
        try await f.settle()
        try require(
            c.probeTable.cellForRow(at: IndexPath(row: 0, section: 0)) === selected
            && selected?.accessibilityLabel == "Topic unavailable" && selected?.accessibilityIdentifier == nil
            && selected?.accessoryType == UITableViewCell.AccessoryType.none
            && selected?.isUserInteractionEnabled == false,
            "fallback replaced cell or retained selection/content",
        )
    }

    private static func verifyQueryRetryAndSource() async throws {
        let f = try Fixture()
        defer { f.close() }
        let c = f.controller
        try await f.readCount(1)
        try await f.finish(0, page([topic(1, "Old")]))
        try await f.settle()
        c.probeSearch("new")
        try await f.readCount(2)
        try await f.finish(1, nil)
        c.probeSelect(0)
        try require(
            f.reads.errors.count == 1 && f.reads.selections.isEmpty,
            "failed reset exposed old query selection",
        )
        c.probeLoadMore()
        try await f.readCount(3)
        try require(
            f.reads.requests[2].query == "new" && f.reads.requests[2].cursor == .zero,
            "failed head retry changed query or raw cursor",
        )
        let raw = ForumTopicPageCursor(date: 80, forumTopicID: 99, messageID: 500)
        try await f.finish(2, page([topic(2, "New")], cursor: raw))
        try await f.settle()
        try require(
            c.probeIDs == [2] && c.probeTopic(1) == nil && c.probeCursor == raw,
            "cursor-zero retry merged old-query rows or changed cursor",
        )
        // Visible near-end rows start the next page after snapshot settlement.
        try await f.readCount(4)
        try require(f.reads.requests[3].cursor == raw, "pagination lost raw server cursor")
        try await f.finish(3, page([topic(3, "Append")]))
        try await f.settle()
        try require(c.probeIDs == [2, 3], "append replaced accepted same-query rows")

        c.probeSearch("stale")
        try await f.readCount(5)
        guard let oldTask = c.probeTask else { throw Failure(description: "missing stale task") }
        c.probeSearch("latest")
        try await f.readCount(6)
        try f.reads.finish(4, page([topic(99, "Wrong query")]))
        await oldTask.value
        try require(c.probeIDs == [2, 3] && c.probeLoading, "stale query replaced rows or cleared successor")
        try await f.finish(5, page([topic(4, "Latest")]))
        try await f.settle()
        c.probeSearch("departed")
        try await f.readCount(7)
        f.reads.current = false
        try await f.finish(6, nil)
        c.probeSelect(0)
        c.probeLoadMore()
        try require(
            c.probeIDs == [4] && f.reads.errors.count == 1 && f.reads.selections.isEmpty
            && f.reads.requests.count == 7,
            "departed source presented error, selected, or dispatched",
        )
    }

    private static func verifyPinnedOrder() async throws {
        let f = try Fixture()
        defer { f.close() }
        let c = f.controller
        let firstPin = topic(9, "First pin", pinned: true, order: 10)
        let secondPin = topic(3, "Second pin", pinned: true, order: 20)
        let ordinary = topic(1, "Ordinary", order: 100)
        let newer = topic(5, "Newer", order: 200)
        let a = ForumTopicPageCursor(date: 31, forumTopicID: 44, messageID: 301)
        let b = ForumTopicPageCursor(date: 32, forumTopicID: 45, messageID: 302)
        let d = ForumTopicPageCursor(date: 33, forumTopicID: 46, messageID: 303)
        try await f.readCount(1)
        try await f.finish(0, page([
            firstPin, secondPin, ordinary, firstPin,
            topic(0, "Invalid", pinned: true, order: 1000),
            topic(6, "Foreign", pinned: true, order: 1000, chatID: 8),
            topic(7, "Hidden", pinned: true, order: 1000, hidden: true),
        ], cursor: a))
        try await f.settle()
        try require(
            c.probeIDs == [9, 3, 1] && c.probePinnedIDs == [9, 3] && c.probeCursor == a,
            "head lost raw pin order, eligible identity, or cursor",
        )
        try await f.readCount(2)
        c.probeSelect(0)
        try await f.settle()
        try require(
            f.reads.selections.count == 1 && f.reads.selections[0].0 == 9 && f.reads.selections[0].1,
            "ranked first row selected another topic",
        )

        try require(f.reads.requests[1].cursor == a, "first append did not use raw cursor")
        try await f.finish(1, page([secondPin, firstPin, newer], cursor: b))
        try await f.settle()
        try require(
            c.probeIDs == [9, 3, 5, 1] && c.probePinnedIDs == [9, 3] && c.probeCursor == b,
            "append replaced head pin order with append order",
        )
        try await f.readCount(3)
        try require(f.reads.requests[2].cursor == b, "second append did not use raw cursor")
        try await f.finish(2, page([topic(9, "Unpinned", order: 10)], cursor: d))
        try await f.settle()
        try require(c.probeIDs == [3, 5, 1, 9] && c.probePinnedIDs == [3], "append unpin retained rank")
        try await f.readCount(4)
        try require(f.reads.requests[3].cursor == d, "third append did not use raw cursor")
        try await f.finish(3, page([firstPin]))
        try await f.settle()
        try require(
            c.probeIDs == [3, 5, 1, 9] && c.probePinnedIDs == [3]
                    && c.probeTable.cellForRow(at: IndexPath(row: 3, section: 0))?.accessoryType == .checkmark,
            "append re-pin revived stale rank or lost selected identity",
        )

        c.probeSearch("matching")
        try require(c.probePinnedIDs.isEmpty, "new query retained previous head ranks")
        try await f.readCount(5)
        try await f.finish(4, nil)
        c.probeSelect(3)
        try require(
            f.reads.selections.count == 1 && c.probeIDs == [3, 5, 1, 9],
            "failed head mutated selection or displayed rows",
        )
        c.probeLoadMore()
        try await f.readCount(6)
        try require(
            f.reads.requests[5].query == "matching" && f.reads.requests[5].cursor == .zero,
            "failed head retry lost exact query/cursor",
        )
        try await f.finish(5, page([firstPin, secondPin, ordinary]))
        try await f.settle()
        try require(
            c.probeIDs == [9, 3, 1] && c.probePinnedIDs == [9, 3]
                    && c.probeTable.cellForRow(at: IndexPath(row: 0, section: 0))?.accessoryType == .checkmark,
            "new head did not restore configured rank and selected identity",
        )
        c.probeSearch("other")
        try require(c.probePinnedIDs.isEmpty, "second query kept ranks")
        try await f.readCount(7)
        try await f.finish(6, page([secondPin, firstPin]))
        try await f.settle()
        try require(c.probeIDs == [3, 9] && c.probePinnedIDs == [3, 9], "new query did not own its head order")
        c.probeSelect(1)
        try await f.settle()
        c.probeSelect(0)
        try await f.settle()
        try require(
            f.reads.selections.count == 3 && f.reads.selections[1].0 == 9
                    && !f.reads.selections[1].1 && f.reads.selections[2].0 == 3 && f.reads.selections[2].1,
            "query reordering changed callback topic identity or toggle semantics",
        )
    }

    private static func verifyTeardown() async throws -> String {
        let f = try Fixture()
        defer { f.close() }
        let c = f.controller
        try await f.readCount(1)
        try await f.finish(0, page([topic(1, "A")]))
        try await f.settle()
        c.probeSearch("next")
        try await f.readCount(2)
        try await f.finish(1, page([topic(2, "B")]))
        try await until("teardown held completion") { f.reads.completions.count == 1 }
        c.probeSearch("pending")
        try await f.readCount(3)
        try await f.finish(2, page([topic(3, "Queued")]))
        c.probeSearch("late")
        try await f.readCount(4)
        guard let task = c.probeTask else { throw Failure(description: "missing teardown task") }
        let starts = c.probeSnapshotStarts
        func state() -> String {
            "retired=\(c.probeRetired), owner=\(c.probeContextIsCurrent), contained=\(c.probeWasContained), parent-nil=\(c.parent == nil), "
                + "in-stack=\(f.navigation.viewControllers.contains(where: { $0 === c })), "
                + "top=\(f.navigation.topViewController === c), transition=\(f.navigation.transitionCoordinator != nil), "
                + "ids=\(c.probeIDs), models=\([1, 2, 3, 4].filter { c.probeTopic($0) != nil }), "
                + "busy=\(c.probeSnapshotBusy), starts=\(c.probeSnapshotStarts)/\(starts), "
                + "held=\(f.reads.completions.count), selections=\(f.reads.selections.count)"
        }
        try require(c.probeWasContained && c.parent === f.navigation, "initial containment receipt missing: \(state())")
        let cursorBeforePop = c.probeCursor
        let beforePop = state()
        let popped = f.navigation.popViewController(animated: false)
        let afterPop = state()
        try require(
            popped === c,
            "native pop did not remove fixture controller: before={\(beforePop)} after={\(afterPop)}",
        )
        try require(
            !c.probeContextIsCurrent,
            "detached owner retained admission before lifecycle retirement: \(state())",
        )
        try require(
            c.probeTopic(1) != nil && c.probeTopic(2) != nil,
            "detachment removed UIKit-owned rows before completion: \(state())",
        )
        c.probeSelect(0)
        c.probeReconfigure()
        // Complete the outstanding native read and release UIKit's held receipt
        // before awaiting didMove(nil), reproducing the original failing ordering.
        let lateCursor = ForumTopicPageCursor(date: 91, forumTopicID: 44, messageID: 900)
        try f.reads.finish(3, page([topic(4, "Late")], cursor: lateCursor))
        await task.value
        try require(
            c.probeCursor == cursorBeforePop && c.probeSnapshotStarts == starts,
            "detached late page mutated cursor or began an apply: \(state())",
        )
        let completion = try f.reads.release()
        completion()
        let beforeRetirementWait = state()
        try require(
            c.probeSnapshotStarts == starts && c.probeTopic(3) == nil && c.probeTopic(4) == nil
                    && f.reads.selections.isEmpty,
            "detached callback/enqueue/pending drain was admitted: \(beforeRetirementWait)",
        )
        // A nonanimated pop may finish UIKit containment on a later run-loop turn.
        // Wait for the actual lifecycle receipt, not an arbitrary delay or empty rows.
        do {
            try await until("native pop containment retirement") {
                c.probeRetired && c.parent == nil && f.navigation.topViewController !== c
                    && !f.navigation.viewControllers.contains(where: { $0 === c })
            }
        } catch {
            throw Failure(
                description: "pop did not retire: before={\(beforePop)} after={\(afterPop)} final={\(state())}",
            )
        }
        try require(
            c.probeIDs.isEmpty && c.probeTopic(1) == nil && c.probeTopic(2) == nil
            && !c.probeSnapshotBusy && c.probeSnapshotStarts == starts && f.reads.selections.isEmpty,
            "retired callback revived rows, selection, or pending apply: before={\(beforePop)} "
                + "after-pop={\(afterPop)} final={\(state())}",
        )
        return "teardown-receipts: immediate={\(afterPop)} before-retirement-wait={\(beforeRetirementWait)} settled={\(state())}"
    }

    private static func verifyRetainedParent() async throws {
        let f = try Fixture()
        defer { f.close() }
        let c = f.controller
        try await f.readCount(1)
        try await until("initial native containment receipt") {
            c.probeWasContained && c.parent === f.navigation
        }
        try require(
            c.probeWasContained && c.parent === f.navigation && c.probeContextIsCurrent,
            "initial attached picker did not admit its first read",
        )
        // Synthetic cancellation contract only: a willMove(nil) notification does
        // not remove the parent. This is not an actual interactive swipe gesture.
        c.willMove(toParent: nil)
        try require(
            c.parent === f.navigation && c.probeContextIsCurrent && !c.probeRetired,
            "retained-parent transition revoked or retired the owner",
        )
        try await f.finish(0, page([topic(1, "Retained")]))
        try await f.settle()
        c.willMove(toParent: f.navigation)
        c.didMove(toParent: f.navigation)
        c.probeSelect(0)
        try await f.settle()
        try require(
            c.probeIDs == [1] && c.probeContextIsCurrent && !c.probeRetired
                    && f.reads.selections.count == 1 && f.reads.selections[0].1,
            "canceled retained-parent removal lost load or selection",
        )
    }
}
#endif

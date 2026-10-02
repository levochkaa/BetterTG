// ForumTopicsRestorationProbe.swift

#if DEBUG
    import Combine
    import TDLibKitDynamic
    import UIKit

    @MainActor enum ForumTopicsRestorationProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        /// Exercises the real coordinator with value-only entries, not live ForumTopicsVM transport.
        private final class Entry: UIViewController, ClientRestorableNavigationEntry {
            let navigationClientSource: TdUpdateSource?
            let payload: ForumTopicsViewController.ClientRestorationState
            var metadataReady = true
            var preflight: (() -> Bool)?
            var commits = 0

            init(source: TdUpdateSource, payload: ForumTopicsViewController.ClientRestorationState) {
                self.navigationClientSource = source
                self.payload = payload
                super.init(nibName: nil, bundle: nil)
            }

            @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

            func prepareReplacementForReadyClient(_ source: TdUpdateSource) -> PreparedClientNavigationReplacement? {
                guard metadataReady else { return nil }
                return PreparedClientNavigationReplacement(
                    preflight: { [self] in preflight?() ?? true },
                    commit: { [self] in
                        commits += 1
                        return Entry(source: source, payload: payload)
                    },
                )
            }
        }

        private final class Rows: NSObject, UITableViewDataSource {
            var ids = Array(Int64(1)...80)

            func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int { ids.count }
            func tableView(_: UITableView, cellForRowAt _: IndexPath) -> UITableViewCell {
                UITableViewCell(style: .default, reuseIdentifier: nil)
            }

            func path(_ id: Int64) -> IndexPath? { ids.firstIndex(of: id).map { IndexPath(row: $0, section: 0) } }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-forum-restoration") else { return }
            let result: String
            do {
                try verifySeed()
                try verifyTarget()
                try verifyCoordinator()
                try verifyViewport()
                result = "Forum restoration probe passed: accepted-page/pending-reset/pending-append=true; "
                    + "raw-query/empty/failed-reset/cursor-retry=true; account/chat/topic-isolation=true; "
                    + "target-cancel/retry/stale-completion/consumed=true; "
                    + "production-coordinator/current-slot/retained-child/modal/epoch/stack-fences=true; "
                    + "production-UIKit-viewport/stable-topic/pending-layout/drag=true; "
                    + "full-VM-RPC/controller/foreground/search-runtime=unverified; server-writes=0"
            } catch { result = "Forum restoration probe failed: \(error)" }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("forum-restoration-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }

        private static func require(_ value: Bool, _ message: String) throws {
            guard value else { throw Failure(description: message) }
        }

        private static func seed(
            location: ChatLocation, raw: String = "  Swift  ", model: String = "Swift", accepted: String = "Swift",
            topics: [ForumTopic]? = nil, request: ForumTopicPageRequest? = nil,
        ) -> ForumTopicsRestorationState {
            let cursor = ForumTopicPageCursor(date: 10, forumTopicID: 42, messageID: 99)
            return ForumTopicsRestorationState(
                location: location, rawQuery: raw, modelQuery: model, acceptedQuery: accepted,
                topics: topics ?? [topic(id: 42)], cursor: cursor,
                requestedCursors: [.zero, cursor], hasMore: true, request: request,
            )
        }

        private static func verifySeed() throws {
            let location = ChatLocation(accountID: UUID(), chatID: 7, clientID: 101, topic: nil)
            let ready = ChatLocation(accountID: location.accountID, chatID: 7, clientID: 102, topic: nil)
            let accepted = seed(location: location)
            try require(
                accepted.accepts(ready) && accepted.query == "Swift" && accepted.pendingReset == nil
                        && accepted.topics.map(\.info.forumTopicId) == [42],
                "accepted page/raw query lost",
            )
            try require(
                !accepted.accepts(.init(accountID: UUID(), chatID: 7, clientID: 102, topic: nil))
                        && !accepted.accepts(.init(accountID: location.accountID, chatID: 8, clientID: 102, topic: nil))
                        && !accepted.accepts(ready.withForumTopic(id: 42)),
                "route mismatch accepted",
            )
            let append = seed(location: location, request: .init(cursor: accepted.cursor, resets: false))
            try require(
                append.cursor == accepted.cursor && append.pendingReset == false
                        && append.completedCursors == [.zero] && append.topics.count == 1,
                "in-flight append was remembered as completed",
            )
            let reset = seed(location: location, request: .init(cursor: .zero, resets: true))
            try require(
                reset.pendingReset == true && !reset.completedCursors.contains(.zero),
                "pending or failed same-query reset was lost",
            )
            let staleQuery = seed(location: location, raw: "  New query \n")
            try require(
                staleQuery.query == "New query" && staleQuery.cursor == .zero
                        && staleQuery.completedCursors.isEmpty && staleQuery.pendingReset == true
                        && staleQuery.topics.isEmpty && staleQuery.hasMore,
                "raw search ahead of stale VM inherited another query's page",
            )
            let pendingSearch = seed(
                location: location,
                raw: "New",
                model: "New",
                accepted: "Swift",
                request: .init(cursor: .zero, resets: true),
            )
            try require(
                pendingSearch.topics.isEmpty && pendingSearch.pendingReset == true,
                "pending reset retained unrelated accepted rows",
            )
            let empty = seed(location: location, topics: [])
            try require(empty.pendingReset == true, "empty seed did not schedule initial load")
            let anonymous = seed(location: .init(accountID: nil, chatID: 7, clientID: 1, topic: nil))
            try require(
                !anonymous.accepts(.init(accountID: nil, chatID: 7, clientID: 2, topic: nil)),
                "nil account became restoration authority",
            )
        }

        private static func verifyTarget() throws {
            var intent = ForumTopicTargetIntent()
            guard let old = intent.begin() else { throw Failure(description: "missing target attempt") }
            try require(intent.begin() == nil, "duplicate lookup started")
            intent.cancel()
            guard let current = intent.begin() else { throw Failure(description: "cancel consumed target") }
            intent.finish(old, opened: true)
            try require(intent.owns(current) && !intent.consumed, "late old lookup consumed or cleared retry")
            intent.finish(current)
            guard let opened = intent.begin() else { throw Failure(description: "failed lookup became consumed") }
            intent.finish(opened, opened: true)
            try require(intent.consumed && intent.begin() == nil, "opened target replayed")
            var restored = ForumTopicTargetIntent(consumed: intent.consumed)
            try require(restored.begin() == nil, "replacement parent replayed existing child target")
        }

        private static func verifyCoordinator() throws {
            let account = UUID()
            let a1 = TdUpdateSource(accountID: account, clientID: 1)
            let a2 = TdUpdateSource(accountID: account, clientID: 2)
            let a3 = TdUpdateSource(accountID: account, clientID: 3)
            let a4 = TdUpdateSource(accountID: account, clientID: 4)
            let payload = ForumTopicsViewController.ClientRestorationState(
                pages: seed(location: .init(accountID: account, chatID: 7, clientID: 1, topic: nil)),
                rawQuery: "  Swift  ", targetConsumed: true,
                viewport: .init(chatID: 42, rowMinYRelativeToViewport: -17, offsetFromTop: 900),
            )
            let forum = Entry(source: a1, payload: payload)
            let child = Entry(source: a1, payload: payload)
            let other = Entry(source: .init(accountID: UUID(), clientID: 1), payload: payload)
            var stack: [UIViewController] = [forum, child, other]
            var current = a2
            var allowed = true
            let readiness = CurrentValueSubject<TdUpdateSource?, Never>(nil)
            let coordinator = NavigationClientRestoration(
                readiness: readiness.eraseToAnyPublisher(), currentSource: { current }, stack: { stack },
                canReplace: { allowed }, replace: { stack = $0 },
            )
            forum.metadataReady = false
            readiness.send(a2)
            let newChild = stack[1]
            try require(
                forum.commits == 0 && child.commits == 1 && stack[2] === other,
                "deferred forum blocked child or touched another account",
            )
            forum.metadataReady = true
            allowed = false
            coordinator.retry()
            try require(forum.commits == 0, "generic modal/search barrier bypassed")
            allowed = true
            coordinator.retry()
            guard let restored = stack[0] as? Entry else { throw Failure(description: "missing forum replacement") }
            try require(
                restored.navigationClientSource == a2 && forum.commits == 1 && stack[1] === newChild
                        && restored.payload.rawQuery == "  Swift  " && restored.payload.targetConsumed
                        && restored.payload.viewport.chatID == 42,
                "current slot or payload was lost",
            )
            readiness.send(a2)
            try require(forum.commits == 1 && restored.commits == 0, "duplicate Ready replayed replacement")
            // A stale prepared source cannot commit after a readiness epoch or stack change.
            readiness.send(a3) // Still a2: the readiness alone is not authority.
            try require(restored.commits == 0, "non-current Ready became authority")
            current = a3
            restored.preflight = { current = a4
            return true
            }
            coordinator.retry()
            try require(restored.commits == 0, "prepared plan committed after source changed")
            current = a3
            let pushed = UIViewController()
            restored.preflight = { stack.append(pushed)
            return true
            }
            readiness.send(a3)
            try require(restored.commits == 0 && stack.last === pushed, "changed-stack plan committed")
            restored.preflight = nil
            coordinator.retry()
            try require(
                restored.commits == 1 && stack.last === pushed && stack[2] === other,
                "deferred replacement failed to retain latest stack",
            )
        }

        private static func verifyViewport() throws {
            let rows = Rows()
            let table = UITableView(frame: CGRect(x: 0, y: 0, width: 390, height: 500), style: .plain)
            table.dataSource = rows
            table.rowHeight = 70
            table.estimatedRowHeight = 0
            table.reloadData()
            table.layoutIfNeeded()
            table.contentOffset.y = 912
            table.layoutIfNeeded()
            let saved = ChatListViewportSnapshot.capture(tableView: table, chatID: { rows.ids[$0.row] })
            guard let id = saved.chatID else { throw Failure(description: "no visible topic anchor") }
            var gate = ChatListViewportRestoration(saved)
            let old = gate.beginApply()
            let latest = gate.beginApply()
            gate.completeApply(old)
            try require(gate.takeForLayout(usable: true) == nil, "older snapshot consumed viewport")
            gate.completeApply(latest)
            try require(gate.takeForLayout(usable: false) == nil, "unlaid-out table consumed viewport")
            rows.ids.insert(contentsOf: [90, 91], at: 0)
            table.reloadData()
            guard let pending = gate.takeForLayout(usable: true)
                else { throw Failure(description: "lost latest viewport") }
            pending.restore(tableView: table, indexPath: rows.path)
            guard let path = rows.path(id) else { throw Failure(description: "lost topic id") }
            try require(
                abs(table.rectForRow(at: path).minY - table.contentOffset.y - saved.rowMinYRelativeToViewport) < 0.5,
                "prepend moved stable topic anchor",
            )
            try require(gate.takeForLayout(usable: true) == nil, "viewport restored twice")
            gate = ChatListViewportRestoration(saved)
            gate.completeApply(gate.beginApply())
            gate.cancel()
            try require(gate.takeForLayout(usable: true) == nil, "user drag failed to cancel pending restore")
        }

        private static func topic(id: Int) -> ForumTopic {
            ForumTopic(
                draftMessage: nil,
                info: .init(
                    chatId: 7,
                    creationDate: 1,
                    creatorId: .messageSenderUser(.init(userId: 1)),
                    forumTopicId: id,
                    icon: .init(color: 0x4A9EF1, customEmojiId: 0),
                    isClosed: false,
                    isGeneral: false,
                    isHidden: false,
                    isNameImplicit: false,
                    isOutgoing: false,
                    name: "Swift",
                ),
                isPinned: false, lastMessage: nil, lastReadInboxMessageId: 0, lastReadOutboxMessageId: 0,
                notificationSettings: .init(
                    disableMentionNotifications: false, disablePinnedMessageNotifications: false, muteFor: 0,
                    muteStories: false, showPreview: true, showStoryPoster: true, soundId: 0, storySoundId: 0,
                    useDefaultDisableMentionNotifications: true, useDefaultDisablePinnedMessageNotifications: true,
                    useDefaultMuteFor: true, useDefaultMuteStories: true, useDefaultShowPreview: true,
                    useDefaultShowStoryPoster: true, useDefaultSound: true, useDefaultStorySound: true,
                ),
                order: 10, unreadCount: 0, unreadMentionCount: 0, unreadPollVoteCount: 0, unreadReactionCount: 0,
            )
        }
    }
#endif

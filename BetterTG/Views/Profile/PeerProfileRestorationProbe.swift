// PeerProfileRestorationProbe.swift

#if DEBUG
import Combine
import TDLibKit
import UIKit

@MainActor enum PeerProfileRestorationProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    @MainActor private final class Rows: NSObject, UICollectionViewDataSource {
        var ids = Array(Int64(1)...90)

        func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int { ids.count }
        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath,
        ) -> UICollectionViewCell {
            collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        }

        func path(_ id: Int64) -> IndexPath? { ids.firstIndex(of: id).map { IndexPath(item: $0, section: 0) } }
    }

    @MainActor private final class Collection: UICollectionView {
        override var isDragging: Bool { simulatedDragging }

        var simulatedDragging = false
    }

    @MainActor private final class Gate {
        var continuation: CheckedContinuation<CustomChat?, Never>?
        var finished = false

        func read() async -> CustomChat? {
            let result = await withCheckedContinuation { continuation = $0 }
            finished = true
            return result
        }

        func release(_ value: CustomChat?) {
            let pending = continuation
            continuation = nil
            pending?.resume(returning: value)
        }
    }

    /// Value-only route; real coordinator, metadata cancellation and UIKit owner checks.
    private final class Entry: UIViewController, ClientRestorableNavigationEntry {
        let payload: PeerProfileRestorationState
        var identity: PeerProfileRestorationIdentity
        let metadata = PeerProfileMetadataPreparation()
        weak var fixture: Fixture?
        var accepted: CustomChat?
        var commits = 0

        var navigationClientSource: TdUpdateSource? { identity.origin }

        init(source: TdUpdateSource, payload: PeerProfileRestorationState, fixture: Fixture) {
            self.identity = .init(origin: source, actorID: 77)
            self.payload = payload
            self.fixture = fixture
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

        func canRestore(_ source: TdUpdateSource) -> Bool {
            guard let fixture else { return false }
            return identity.accepts(source, current: fixture.current, actorID: 77)
                && chatListActionOwnerIsAttached && navigationController?.topViewController === self
                && navigationController?.viewControllers.dropLast().last === fixture.host
        }

        func prepareReplacementForReadyClient(_ source: TdUpdateSource) -> PreparedClientNavigationReplacement? {
            guard canRestore(source), let fixture else { return nil }
            guard accepted != nil else {
                let gate = fixture.gates[source.clientID] ?? Gate()
                fixture.gates[source.clientID] = gate
                metadata.request(source: source, fetch: { [weak fixture] in
                    fixture?.reads += 1
                    return await gate.read()
                }, accepts: { [weak self] in self?.canRestore(source) == true }, completion: { [weak self] chat in
                    self?.accepted = chat
                    if chat != nil { self?.fixture?.coordinator.retry() }
                })
                return nil
            }
            return PreparedClientNavigationReplacement(preflight: { [weak self] in
                self?.canRestore(source) == true
            }, commit: { [self] in
                guard canRestore(source) else { return nil }
                commits += 1
                metadata.cancel()
                return Entry(source: source, payload: payload, fixture: fixture)
            })
        }
    }

    @MainActor private final class Fixture {
        let first = TdUpdateSource(accountID: UUID(), clientID: 1)
        var current: TdUpdateSource?
        let ready = CurrentValueSubject<TdUpdateSource?, Never>(nil)
        let host = UIViewController()
        let root = UIViewController()
        let navigation = UINavigationController()
        let window: UIWindow
        var gates = [Int32: Gate]()
        var reads = 0
        var allowed = true
        lazy var coordinator = NavigationClientRestoration(
            readiness: ready.eraseToAnyPublisher(), currentSource: { [weak self] in self?.current },
            stack: { [weak self] in self?.navigation.viewControllers ?? [] },
            canReplace: { [weak self] in self?.allowed == true },
            replace: { [weak self] in self?.navigation.setViewControllers($0, animated: false) },
        )

        init(scene: UIWindowScene) {
            self.window = UIWindow(windowScene: scene)
            self.current = first
            let payload = PeerProfileRestorationState(
                source: first, actorID: 77, chatID: 8, topic: nil, tab: .files,
                messages: [message(id: 70)], cursor: 61, hasMore: true, total: 200, error: nil,
                resumePage: true, bio: "accepted bio", details: ["accepted detail"],
                viewport: .init(messageID: 70, minY: -12, distanceFromTop: 600),
            )
            let entry = Entry(source: first, payload: payload, fixture: self)
            navigation.setViewControllers([root, host, entry], animated: false)
            window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
            window.rootViewController = navigation
            window.isHidden = false
            navigation.loadViewIfNeeded()
            navigation.view.layoutIfNeeded()
            _ = coordinator
        }

        func rotate(_ client: Int32, ready isReady: Bool = true) {
            let source = TdUpdateSource(accountID: first.accountID, clientID: client)
            current = source
            for entry in navigation.viewControllers.compactMap({ $0 as? Entry }) {
                entry.identity.observe(source: source, actorID: 77)
                entry.identity.readySource = isReady ? source : nil
                entry.accepted = nil
                entry.metadata.cancel()
            }
            ready.send(isReady ? source : nil)
        }

        func close() {
            navigation.viewControllers.compactMap { $0 as? Entry }.forEach { $0.metadata.cancel() }
            gates.values.forEach { $0.release(nil) }
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    static func runIfRequested() {
        PeerProfileSharedRefreshProbe.runIfRequested()
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-profile-restoration") else { return }
        Task {
            let result: String
            do {
                try verifySeed()
                try verifyViewport()
                try verifyPageSettlement()
                try verifyIdentity()
                try await verifyCoordinator()
                try await PeerProfileSharedRefreshProbe.verify()
                result = "Profile restoration probe passed: production-seed/tab/page/cursor/metadata=true; "
                    + "account/actor/chat/topic-isolation=true; success/error-settled/cancel-stale-resume=true; "
                    + "actual-UICollectionView/stable-message/header-resize/prepend/empty/drag/layout=true; "
                    + "production-coordinator/metadata/identity/owner-membership/repeated-rollover=true; "
                    + "late-metadata/replacement/child/detached-owner/predispatch-cancel=fenced; "
                    + PeerProfileSharedRefreshProbe.coverage + "; "
                    + "navigation-entries=value-only; actual-PeerProfile/ChatVM/TDLib/foreground=unverified; "
                    + "server-reads/writes=0"
            } catch {
                result = "Profile restoration probe failed: \(error)"
            }
            log(result)
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("profile-restoration-probe.txt"), options: .atomic,
                )
            }
        }
    }

    private static func require(_ value: Bool, _ reason: String) throws {
        if !value { throw Failure(description: reason) }
    }

    private static func until(_ reason: String, _ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw Failure(description: "timeout: \(reason)")
    }

    private static func verifyPageSettlement() throws {
        for settled in [true, false] {
            var request = PeerProfileHistoryRequest()
            let old = request.begin()
            let current = request.begin()
            try require(!request.finish(old, settled: true) && request.needsResume, "old page settled successor")
            try require(request.finish(current, settled: settled), "current page rejected")
            try require(request.needsResume == !settled, "success/handled-error vs cancellation/stale resume lost")
            request.invalidate()
            try require(!request.needsResume && request.currentID == nil, "tab reset inherited resume")
        }
        for error in [nil, "handled failure"] {
            let state = PeerProfileRestorationState(
                source: .init(accountID: UUID(), clientID: 1), actorID: 77, chatID: 8, topic: nil,
                tab: .files, messages: [], cursor: nil, hasMore: true, total: nil, error: error,
                resumePage: false, bio: "", details: [],
                viewport: .init(messageID: nil, minY: 0, distanceFromTop: 0),
            )
            try require(state.shouldResumePage == (error == nil), "empty tab confused handled error with missing page")
        }
    }

    private static func verifyIdentity() throws {
        let first = TdUpdateSource(accountID: UUID(), clientID: 1)
        let second = TdUpdateSource(accountID: first.accountID, clientID: 2)
        var identity = PeerProfileRestorationIdentity(origin: first, actorID: 77)
        try require(!identity.accepts(second, current: second, actorID: 77), "unready source admitted")
        identity.readySource = second
        try require(identity.accepts(second, current: second, actorID: 77), "ready same-account source rejected")
        try require(!identity.accepts(second, current: first, actorID: 77), "noncurrent source admitted")
        try require(!identity.accepts(second, current: second, actorID: nil), "missing actor admitted")
        identity.observe(source: second, actorID: 78)
        try require(!identity.accepts(second, current: second, actorID: 77), "actor departure revived")
        identity = .init(origin: first, actorID: 77)
        identity.observe(source: .init(accountID: UUID(), clientID: 3), actorID: 77)
        identity.observe(source: second, actorID: 77)
        identity.readySource = second
        try require(!identity.accepts(second, current: second, actorID: 77), "A-B-A revived origin")
    }

    private static func verifyCoordinator() async throws {
        try await until("window scene") { UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene } }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw Failure(description: "missing window scene")
        }
        let f = Fixture(scene: scene)
        defer { f.close() }
        guard let original = f.navigation.topViewController as? Entry
            else { throw Failure(description: "missing entry") }
        let helper = PeerProfileMetadataPreparation()
        var canceledReads = 0
        helper.request(source: f.first, fetch: { canceledReads += 1
        return nil
        }, accepts: { true }, completion: { _ in })
        helper.cancel()
        await Task.yield()
        try require(canceledReads == 0, "scheduled cancellation performed read")
        f.rotate(2, ready: false)
        try require(f.reads == 0 && original.commits == 0, "unready restoration issued metadata")
        f.rotate(2)
        try await until("client 2 metadata") { f.gates[2]?.continuation != nil }
        f.coordinator.retry()
        try require(f.reads == 1, "duplicate retry duplicated metadata")
        f.rotate(3)
        try await until("client 3 metadata") { f.gates[3]?.continuation != nil }
        f.gates[2]?.release(chat(title: "retired"))
        try await until("retired read completion") { f.gates[2]?.finished == true }
        try require(
            original.accepted == nil && original.metadata.source?.clientID == 3,
            "old response cleared successor",
        )
        f.allowed = false
        f.gates[3]?.release(chat(title: "fresh"))
        try await until("fresh metadata acceptance") { original.accepted != nil }
        try require(original.commits == 0, "generic modal/search barrier bypassed")
        f.allowed = true
        f.coordinator.retry()
        guard let restored = f.navigation.topViewController as? Entry
            else { throw Failure(description: "missing replacement") }
        try require(
            restored !== original && original.commits == 1 && restored.navigationClientSource?.clientID == 3
            && f.navigation.viewControllers[0] === f.root && f.navigation.viewControllers[1] === f.host
            && restored.payload.messages.map(\.id) == [70] && restored.payload.cursor == 61
            && restored.payload.tab == .files && restored.payload.viewport.messageID == 70,
            "slot or accepted payload lost",
        )
        f.coordinator.retry()
        try require(restored.commits == 0, "duplicate ready replaced current owner")
        f.rotate(4)
        try await until("second rollover") { f.gates[4]?.continuation != nil }
        let child = UIViewController()
        f.navigation.pushViewController(child, animated: false)
        f.gates[4]?.release(chat(title: "covered"))
        try await until("covered response") { f.gates[4]?.finished == true }
        try require(restored.accepted == nil && restored.commits == 0, "covered parent accepted metadata")
        f.navigation.popViewController(animated: false)
        f.coordinator.retry()
        try await until("uncovered retry") { f.gates[4]?.continuation != nil }
        f.gates[4]?.release(chat(title: "retry"))
        try await until("second replacement") { restored.commits == 1 }
        guard let latest = f.navigation.topViewController as? Entry
            else { throw Failure(description: "missing latest") }
        f.rotate(5)
        try await until("detached pending read") { f.gates[5]?.continuation != nil }
        let replacementRoot = UIViewController()
        f.window.rootViewController = replacementRoot
        replacementRoot.view.addSubview(f.navigation.view)
        try require(
            f.navigation.view.window != nil && !latest.chatListActionOwnerIsAttached,
            "detached test lacks retained pixels",
        )
        f.gates[5]?.release(chat(title: "detached"))
        try await until("detached response") { f.gates[5]?.finished == true }
        try require(latest.accepted == nil && latest.commits == 0, "detached owner accepted response")
    }

    private static func chat(title: String) -> CustomChat {
        ProbeFixtures.chat(
            .init(isPinned: false, list: .chatListMain, order: 1, source: nil),
            title: title,
            id: 8,
        )
    }

    private static func verifySeed() throws {
        let source = TdUpdateSource(accountID: UUID(), clientID: 71)
        let forum = MessageTopic.messageTopicForum(.init(forumTopicId: 42))
        for topic in [nil, forum] {
            for tab in PeerProfileViewController.SharedTab.allCases {
                var request = PeerProfileHistoryRequest()
                let old = request.begin()
                let seed = PeerProfileRestorationState(
                    source: source, actorID: 77, chatID: 8, topic: topic, tab: tab,
                    messages: [message(id: 90), message(id: 70)], cursor: 61, hasMore: true,
                    total: 200, error: "prior retry", resumePage: request.currentID != nil,
                    bio: "accepted bio", details: ["accepted username"],
                    viewport: .init(messageID: 70, minY: -12, distanceFromTop: 600),
                )
                request.invalidate()
                let current = request.begin()
                try require(!request.finish(old) && request.currentID == current, "retired page consumed retry")
                try require(
                    seed.matches(accountID: source.accountID, actorID: 77, chatID: 8, topic: topic)
                        && seed.messages.map(\.id) == [90, 70] && seed.cursor == 61 && seed.resumePage
                        && seed.hasMore && seed.total == 200 && seed.tab == tab && seed.error == "prior retry"
                        && seed.bio == "accepted bio" && seed.details == ["accepted username"],
                    "accepted display/cursor replaced by pending page",
                )
                try require(
                    !seed.matches(accountID: UUID(), actorID: 77, chatID: 8, topic: topic)
                        && !seed.matches(accountID: source.accountID, actorID: 78, chatID: 8, topic: topic)
                        && !seed.matches(accountID: source.accountID, actorID: nil, chatID: 8, topic: topic)
                        && !seed.matches(accountID: source.accountID, actorID: 77, chatID: 9, topic: topic)
                        && !seed.matches(
                            accountID: source.accountID,
                            actorID: 77,
                            chatID: 8,
                            topic: topic == nil
                            ? forum
                            : nil,
                        ),
                    "foreign seed admitted",
                )
            }
        }
    }

    private static func verifyViewport() throws {
        let rows = Rows()
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 100, height: 100)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let collection = Collection(frame: CGRect(x: 0, y: 0, width: 300, height: 420), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.dataSource = rows
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collection.contentInset.top = 260
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 412
        collection.layoutIfNeeded()
        let saved = PeerProfileViewport.capture(collection, messageID: { rows.ids[$0.item] })
        guard let id = saved.messageID else { throw Failure(description: "missing actual grid anchor") }
        rows.ids.insert(contentsOf: [100, 101, 102], at: 0)
        collection.contentInset.top = 390
        collection.reloadData()
        try require(saved.restore(collection, indexPath: rows.path), "restore rejected laid-out grid")
        guard let path = rows.path(id), let attributes = collection.layoutAttributesForItem(at: path)
        else { throw Failure(description: "missing restored attributes") }
        try require(
            abs(attributes.frame.minY - collection.contentOffset.y - saved.minY) < 0.5,
            "prepend/header moved message pixels",
        )
        collection.simulatedDragging = true
        try require(!saved.restore(collection, indexPath: rows.path), "restore overrode active drag")
        collection.simulatedDragging = false
        collection.bounds.size.height = 0
        try require(!saved.restore(collection, indexPath: rows.path), "unlaid-out view consumed anchor")
        collection.bounds.size.height = 420
        collection.contentOffset.y = -300
        let header = PeerProfileViewport.capture(collection, messageID: { rows.ids[$0.item] })
        try require(header.messageID == nil && header.distanceFromTop == 90, "header offset classified as grid")
        collection.contentInset.top = 440
        try require(
            header.restore(collection, indexPath: rows.path) && collection.contentOffset.y == -350,
            "header resize lost top distance",
        )
        rows.ids = []
        collection.reloadData()
        try require(
            saved.restore(collection, indexPath: rows.path) && collection.contentOffset.y == -420,
            "removed anchor escaped empty bounds",
        )
    }

    private static func message(id: Int64) -> Message {
        Message(
            id: id,
            senderId: .messageSenderUser(.init(userId: 1)),
            receiverId: nil,
            chatId: 8,
            sendingState: nil,
            schedulingState: nil,
            isOutgoing: false,
            isPinned: false,
            isFromOffline: false,
            canBeSaved: true,
            hasTimestampedMedia: false,
            isChannelPost: false,
            isPaidStarSuggestedPost: false,
            isPaidGramSuggestedPost: false,
            containsUnreadMention: false,
            containsUnreadPollVotes: false,
            date: Int(id),
            editDate: 0,
            forwardInfo: nil,
            importInfo: nil,
            interactionInfo: nil,
            unreadReactions: [],
            factCheck: nil,
            suggestedPostInfo: nil,
            replyTo: nil,
            topicId: nil,
            selfDestructType: nil,
            selfDestructIn: 0,
            autoDeleteIn: 0,
            viaBotUserId: 0,
            guestBotCallerId: nil,
            senderBusinessBotUserId: 0,
            senderBoostCount: 0,
            senderTag: "",
            paidMessageStarCount: 0,
            authorSignature: "",
            mediaAlbumId: 0,
            effectId: 0,
            restrictionInfo: nil,
            summaryLanguageCode: "",
            content: .messageText(.init(
                linkPreview: nil,
                linkPreviewOptions: nil,
                text: .init(entities: [], text: "accepted"),
            )),
            ephemeralContent: nil,
            replyMarkup: nil,
            ephemeralMessageId: 0,
            chatInstance: 0,
        )
    }
}
#endif

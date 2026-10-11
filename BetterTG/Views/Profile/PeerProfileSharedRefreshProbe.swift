// PeerProfileSharedRefreshProbe.swift

#if DEBUG
import Combine
import TDLibKit
import UIKit

@MainActor enum PeerProfileSharedRefreshProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }
    @MainActor private final class Gate {
        var pending = [Int64: CheckedContinuation<Message, any Swift.Error>]()
        var calls = [Int64]()
        var maximum = 0

        func read(_ id: Int64) async throws -> Message {
            calls.append(id)
            return try await withCheckedThrowingContinuation {
                precondition(pending[id] == nil)
                pending[id] = $0
                maximum = max(maximum, pending.count)
            }
        }

        func finish(_ id: Int64, _ result: Result<Message, any Swift.Error>) {
            pending.removeValue(forKey: id)?.resume(with: result)
        }

        func close() {
            let values = pending.values
            pending.removeAll()
            values.forEach { $0.resume(throwing: CancellationError()) }
        }
    }

    @MainActor private final class Fixture {
        let source = TdUpdateSource(accountID: UUID(), clientID: 811)
        var current: TdUpdateSource?
        var actor = 77
        var attached = true
        var tab = PeerProfileViewController.SharedTab.media
        let gate = Gate()
        var values = [Int64: Message]()
        var changes = [PeerProfileSharedMessageRefresh.Change]()
        var onQuarantine: ((Set<Int64>) -> Void)?
        var refresh: PeerProfileSharedMessageRefresh!

        init(ids: [Int64] = [1], topic: MessageTopic? = nil) {
            self.current = source
            let source = source
            self.refresh = PeerProfileSharedMessageRefresh(
                source: source, location: .init(
                    accountID: source.accountID,
                    chatID: 8,
                    clientID: source.clientID,
                    topic: topic,
                ),
                tab: .media, seedIDs: ids, visibleIDs: [ids.last].compactMap(\.self),
                accepts: { [weak self] in
                    self?.current == source && self?.actor == 77 && self?.attached == true && self?.tab == .media
                }, read: { [gate] in try await gate.read($0) },
            )
            refresh.onChange = { [weak self] change in
                guard let self else { return }
                changes.append(change)
                switch change {
                case .message(let value): values[value.id] = value
                case .remove(let id): values[id] = nil
                case .quarantine(let ids): onQuarantine?(ids)
                case .retry: break
                }
            }
        }

        func close() {
            refresh.stop()
            gate.close()
        }
    }

    static let coverage = "A38-real-ledger/four-read-limit/seed-quarantine/delete/edit-spoiler/page-revision=true; "
        + "A38-exact-404/offline/permission/filter-unknown/explicit-retry=true; "
        + "A38-source/tab/actor/root-detach/cancel=fenced; "
        + "A38-actual-pending/grid/row/viewport/permit/late-transition=true; raw-thumbnail-loads=1; "
        + "A38-bootstrap=production-helper; gallery/PiP-teardown/raw-cursor-owner=source-reviewed; "
        + "actual-PeerProfile/TDLib/system-PiP=unverified"

    static func verify() async throws {
        try await verifyReads()
        try await verifyPageAndScopes()
        try await verifyAttachmentAndBootstrap()
        try await verifyGeometry()
        try await verifyCells()
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-profile-shared-refresh") else { return }
        Task {
            let result: String
            do {
                try await verify()
                result = "Profile shared refresh probe passed: " + coverage + "; server-reads/writes=0"
            } catch { result = "Profile shared refresh probe failed: \(error)" }
            log(result)
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("profile-shared-refresh-probe.txt"),
                    options: .atomic,
                )
            }
        }
    }

    private static func require(_ value: Bool, _ reason: String) throws {
        if !value { throw Failure(description: reason) }
    }

    private static func until(_ reason: String, _ test: () -> Bool) async throws {
        for _ in 0..<300 {
            if test() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure(description: "timeout: \(reason)")
    }

    private static func settle(_ task: Task<Void, Never>?, _ reason: String) async throws {
        guard let task else { return }
        var finished = false
        let waiter = Task {
            await task.value
            finished = true
        }
        defer { waiter.cancel() }
        try await until("driver completion: \(reason)") { finished }
    }

    private static func verifyReads() async throws {
        let f = Fixture(ids: [1, 2, 3, 4, 5, 6])
        defer { f.close() }
        f.refresh.start()
        try await until("first bounded batch") { f.gate.pending.count == 4 }
        try require(Set(f.gate.calls) == [6, 1, 2, 3] && f.gate.maximum == 4, "visible priority or read bound")
        try require((1...6).allSatisfy { !f.refresh.allows(Int64($0)) }, "seed authorized before response")
        f.refresh.delete(.init(chatId: 8, fromCache: false, isPermanent: true, messageIds: [6]), source: f.source)
        f.refresh.invalidate(id: 1, chatID: 8, source: f.source)
        for id in Array(f.gate.pending.keys) {
            f.gate.finish(id, .success(message(id)))
        }
        try await until("second batch and edit reread") { f.gate.pending[1] != nil && f.gate.pending[5] != nil }
        try require(
            f.values[6] == nil && !f.refresh.allows(6) && !f.refresh.allows(1),
            "stale delete/edit body admitted",
        )
        for id in Array(f.gate.pending.keys) {
            f.gate.finish(id, .success(message(id, spoiler: id == 1)))
        }
        try await until("fresh spoiler accepted") { f.refresh.allows(1) }
        if case .messagePhoto(let photo) = f.values[1]?
            .content { try require(photo.hasSpoiler, "old spoiler flag won") }
        else { throw Failure(description: "fresh photo missing") }
        f.refresh.retry()
        try await settle(f.refresh.debugRefreshTask, "tombstone retry")
        try require(!f.gate.calls.dropFirst(4).contains(6) && f.gate.maximum == 4, "tombstone reread or bound exceeded")

        for error in [
            TDLibError(code: 404, message: "Not Found"),
            .init(code: 404, message: "offline"),
            .init(code: 403, message: "CHAT_ACCESS_DENIED"),
            .init(code: 500, message: "offline"),
        ] {
            let e = Fixture()
            defer { e.close() }
            e.values[1] = message(1)
            e.refresh.start()
            try await until("error read") { e.gate.pending[1] != nil }
            e.gate.finish(1, .failure(error))
            if error.code == 404, error.message == "Not Found" {
                try await until("exact not-found delivery") { e.values[1] == nil }
                try await settle(e.refresh.debugRefreshTask, "exact not-found")
                try require(e.values[1] == nil && !e.refresh.allows(1), "exact not-found kept stale seed")
            } else {
                try await until("retry delivery \(error.code) \(error.message)") { e.refresh.state(for: 1) == .retry }
                try await settle(e.refresh.debugRefreshTask, "retry \(error.code) \(error.message)")
                try require(
                    e.values[1] != nil && e.refresh.state(for: 1) == .retry && e.gate.calls.count == 1,
                    "error \(error.code) \(error.message) disappeared or auto-spun",
                )
                e.refresh.retry()
                try await until("explicit retry") { e.gate.pending[1] != nil }
                e.gate.finish(1, .success(message(1)))
                try await until("retry admission") { e.refresh.allows(1) }
            }
        }
        let filtered = Fixture()
        defer { filtered.close() }
        filtered.values[1] = message(1)
        filtered.refresh.start()
        try await until("filter read") { filtered.gate.pending[1] != nil }
        filtered.gate.finish(1, .success(message(1, text: true)))
        try await until("confirmed filter removal") { filtered.values[1] == nil }
        try require(!filtered.refresh.allows(1), "changed filter retained media authority")

        let unknown = Fixture()
        defer { unknown.close() }
        unknown.values[1] = message(1)
        unknown.refresh.start()
        try await until("unknown rich read") { unknown.gate.pending[1] != nil }
        unknown.gate.finish(1, .success(message(1, rich: true)))
        try await until("unknown filter retry") { unknown.refresh.state(for: 1) == .retry }
        try require(
            unknown.values[1] != nil && !unknown.refresh.allows(1),
            "unknown rich mask removed seed or granted authority",
        )
        unknown.refresh.retry()
        try await until("unknown explicit retry") { unknown.gate.pending[1] != nil }
        unknown.gate.finish(1, .success(message(1)))
        try await until("unknown recovered") { unknown.refresh.allows(1) }
    }

    private static func verifyPageAndScopes() async throws {
        let f = Fixture(ids: [])
        defer { f.close() }
        guard let token = f.refresh.beginPage() else { throw Failure(description: "page token") }
        f.refresh.delete(.init(chatId: 8, fromCache: false, isPermanent: true, messageIds: [1]), source: f.source)
        f.refresh.invalidate(id: 2, chatID: 8, source: f.source)
        let accepted = f.refresh.acceptPage([message(1), message(2), message(3)], token: token)
        accepted.install(into: &f.values)
        try require(
            accepted.accepted.map(\.id) == [3] && accepted.quarantined.map(\.id) == [2]
            && f.values[1] == nil && !f.refresh.allows(1) && !f.refresh.allows(2),
            "page resurrected newer delete/edit",
        )
        try await until("page edit reread") { f.gate.pending[2] != nil }
        f.gate.finish(2, .failure(TDLibError(code: 500, message: "offline")))
        try await until("page unresolved retry") { f.refresh.state(for: 2) == .retry }
        let pending = SharedMediaPendingCell()
        pending.configure(state: f.refresh.state(for: 2))
        try require(
            f.values[2] != nil && pending.accessibilityLabel?.contains("Tap to retry") == true,
            "rejected page ID lost local retry row",
        )
        var actions = 0
        f.refresh.perform(id: 2) { actions += 1 }
        try require(actions == 0, "unresolved page action escaped")
        f.refresh.retry()
        try await until("page explicit retry read") { f.gate.pending[2] != nil }
        f.gate.finish(2, .success(message(2, spoiler: true)))
        try await until("page current body") { f.refresh.allows(2) }

        for boundary in 0..<5 {
            let e = Fixture()
            defer { e.close() }
            e.refresh.start()
            try await until("scope read") { e.gate.pending[1] != nil }
            switch boundary {
            case 0: e.current = .init(accountID: e.source.accountID, clientID: 812)
            case 1: e.current = .init(accountID: UUID(), clientID: 812)
            case 2: e.tab = .files
            case 3: e.attached = false
            default: e.actor = 78
            }
            e.gate.finish(1, .success(message(1)))
            try await settle(e.refresh.debugRefreshTask, "scope \(boundary)")
            try require(e.values.isEmpty && !e.refresh.allows(1), "scope \(boundary) admitted late result")
        }
        let canceled = Fixture()
        defer { canceled.close() }
        canceled.refresh.start()
        let canceledTask = canceled.refresh.debugRefreshTask
        try require(canceledTask != nil, "predispatch fixture lacked a driver")
        canceled.refresh.stop()
        try await settle(canceledTask, "predispatch cancellation")
        try require(canceled.gate.calls.isEmpty, "predispatch stop issued a read")
        let topic = Fixture(topic: .messageTopicForum(.init(forumTopicId: 12)))
        defer { topic.close() }
        topic.values[1] = message(1)
        topic.refresh.start()
        try await until("topic read") { topic.gate.pending[1] != nil }
        topic.gate.finish(1, .success(message(1)))
        try await until("topic removal") { topic.values[1] == nil }
    }

    private static func verifyAttachmentAndBootstrap() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw Failure(description: "missing bootstrap scene")
        }
        let owner = UIViewController()
        let navigation = UINavigationController(rootViewController: owner)
        navigation.loadViewIfNeeded()
        owner.loadViewIfNeeded()
        let source = TdUpdateSource(accountID: UUID(), clientID: 813)
        var viewportPending = true
        var unexpectedReads = 0
        let refresh = PeerProfileSharedMessageRefresh(
            source: source, location: .init(
                accountID: source.accountID,
                chatID: 8,
                clientID: source.clientID,
                topic: nil,
            ),
            tab: .media, seedIDs: [], visibleIDs: [],
            accepts: { owner.chatListActionOwnerIsAttached }, canStart: { !viewportPending },
            read: { id in
                unexpectedReads += 1
                return message(id)
            },
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
        defer {
            refresh.stop()
            window.isHidden = true
            window.rootViewController = nil
        }
        var request = PeerProfileHistoryRequest()
        var pages = 0
        let load: () -> Void = {
            guard request.currentID == nil, refresh.beginPage() != nil else { return }
            _ = request.begin()
            pages += 1
        }
        refresh.resume(needsPage: true, hasError: false, loadPage: load)
        try require(pages == 0 && !refresh.canRead, "detached initial view dispatched")
        window.rootViewController = navigation
        window.isHidden = false
        navigation.view.layoutIfNeeded()
        refresh.resume(needsPage: true, hasError: false, loadPage: load)
        try require(pages == 0 && refresh.canRead, "pending viewport did not defer initial read")
        viewportPending = false
        refresh.resume(needsPage: true, hasError: false, loadPage: load)
        refresh.resume(needsPage: true, hasError: false, loadPage: load)
        try require(pages == 1 && request.currentID != nil, "attached appearance failed or duplicated initial page")
        if let id = request.currentID { _ = request.finish(id, settled: true) }
        refresh.finishPage()
        refresh.resume(needsPage: true, hasError: true, loadPage: load)
        try require(pages == 1, "handled page error auto-retried")
        window.rootViewController = UIViewController()
        window.addSubview(navigation.view)
        try require(
            owner.view.window === window && !owner.chatListActionOwnerIsAttached,
            "detached navigation fixture lacks residual pixels",
        )
        refresh.resume(needsPage: true, hasError: false, loadPage: load)
        try await settle(refresh.debugRefreshTask, "detached bootstrap")
        try require(
            pages == 1 && !refresh.canRead && unexpectedReads == 0,
            "detached navigation issued page or seed read",
        )
        navigation.view.removeFromSuperview()
    }

    private static func verifyGeometry() async throws {
        let row = SharedMediaRowCell(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
        func height() -> CGFloat {
            row.contentView
.systemLayoutSizeFitting(
    CGSize(width: 320, height: 0), withHorizontalFittingPriority: .required,
    verticalFittingPriority: .fittingSizeLevel,
)
.height
        }
        row.configure(message: message(1, text: true))
        let readyHeight = height()
        row.configurePending(state: .loading)
        let loadingHeight = height()
        row.configurePending(state: .retry)
        try require(
            readyHeight > 0 && abs(readyHeight - loadingHeight) < 0.5 && abs(readyHeight - height()) < 0.5,
            "pending/retry row changed fitted geometry",
        )
        try require(row.accessibilityLabel == "Couldn't refresh. Tap to retry", "row leaked seed caption")

        let narrow = SharedMediaPendingCell(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        narrow.configure(state: .loading)
        narrow.layoutIfNeeded()
        try require(
            narrow.bounds.height == 40 && narrow.contentView.bounds.height == 40,
            "narrow pending grid imposed minimum height",
        )

        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: readyHeight)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 320),
            collectionViewLayout: layout,
        )
        collection.contentInsetAdjustmentBehavior = .never
        collection.register(SharedMediaRowCell.self, forCellWithReuseIdentifier: SharedMediaRowCell.reuseIdentifier)
        var pending = true
        let dataSource = UICollectionViewDiffableDataSource<
            Int,
            Int64,
        >(collectionView: collection) { collection, path, id in
            let cell = collection.dequeueReusableCell(
                withReuseIdentifier: SharedMediaRowCell.reuseIdentifier,
                for: path,
            ) as! SharedMediaRowCell
            if pending { cell.configurePending(state: .loading) }
            else { cell.configure(message: message(id, text: true)) }
            return cell
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int64>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(Int64(1)...40))
        await withCheckedContinuation { continuation in
            dataSource.apply(snapshot, animatingDifferences: false) { continuation.resume() }
        }
        collection.layoutIfNeeded()
        collection.contentOffset.y = 413
        collection.layoutIfNeeded()
        let anchor = PeerProfileViewport.capture(collection, messageID: { dataSource.itemIdentifier(for: $0) })
        guard let id = anchor.messageID else { throw Failure(description: "quarantine row anchor unavailable") }
        pending = false
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        await withCheckedContinuation { continuation in
            dataSource.apply(snapshot, animatingDifferences: false) { continuation.resume() }
        }
        try require(
            anchor.restore(collection, indexPath: { dataSource.indexPath(for: $0) }),
            "ready row anchor restore rejected",
        )
        guard let path = dataSource.indexPath(for: id),
              let attributes = collection.layoutAttributesForItem(at: path)
        else {
            throw Failure(description: "ready row anchor missing")
        }
        try require(
            abs(attributes.frame.minY - collection.contentOffset.y - anchor.minY) < 0.5,
            "quarantine-to-ready changed row pixel anchor",
        )
    }

    private static func verifyCells() async throws {
        let f = Fixture()
        defer { f.close() }
        let backend = TDLibVODProbeBackend(
            fileURL: URL(fileURLWithPath: "/nonexistent-profile-probe"),
            fileSize: 1,
            network: TDLibVODProbeNetwork(available: false),
        )
        let context = MediaGalleryPlaybackContext(
            probeLocation: f.refresh.location,
            vodRanges: TDLibVODRangeCoordinator(accountID: f.source.accountID.uuidString, client: backend.client),
            currentClientMatches: { f.current == f.source },
        )
        let session = MediaRevealSession(context: context)
        let pending = SharedMediaPendingCell(frame: CGRect(x: 0, y: 0, width: 110, height: 110))
        pending.configure(state: f.refresh.state(for: 1))
        try require(
            pending.accessibilityLabel == "Loading message…" && pending.accessibilityTraits == .staticText,
            "pending cell leaked seed text",
        )
        pending.configure(state: .retry)
        try require(
            pending.accessibilityLabel == "Couldn't refresh.\nTap to retry" && pending.accessibilityTraits == .button,
            "retry cell semantics",
        )
        let grid = SharedMediaGridCell(frame: CGRect(x: 0, y: 0, width: 110, height: 110))
        var loads = 0
        grid.debugThumbnailLoader = { _, imageView in
            loads += 1
            imageView.image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { renderer in
                UIColor.red.setFill()
                renderer.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
        }
        grid.configure(message: message(1), context: context, permit: nil)
        try require(
            loads == 0 && !grid.debugHasRawImage && session.permit(for: message(1)) == nil && !f.refresh.allows(1),
            "seed reached media/action authority",
        )
        f.refresh.start()
        try await until("cell read") { f.gate.pending[1] != nil }
        f.gate.finish(1, .success(message(1)))
        try await until("cell admission") { f.refresh.allows(1) }
        session.reconcile([message(1)])
        let permit = session.permit(for: message(1))
        grid.configure(message: message(1), context: context, permit: permit)
        try require(loads == 1 && grid.debugHasRawImage && permit?.allowsPixels == true, "accepted cell did not render")
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw Failure(description: "missing scene")
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        host.view.addSubview(grid)
        host.view.layoutIfNeeded()
        grid.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let target = grid.transitionTarget(for: 1, validation: { f.refresh.allows(1) })
        try require(target?.snapshotView != nil, "accepted attached transition snapshot unavailable")
        let gallery = MediaGalleryViewController(
            messages: [message(1)],
            selection: 1,
            sourceLocation: context.location,
            playbackContext: context,
            mediaRevealSession: session,
        )
        gallery.loadViewIfNeeded()
        _ = gallery.debugRevealCell(at: 0)
        f.onQuarantine = { ids in
            session.revoke(messageIDs: ids)
            grid.prepareForReuse()
            gallery.invalidateForContextChange(revokePlaybackContext: false, completion: {})
        }
        f.refresh.invalidate(id: 1, chatID: 8, source: f.source)
        try require(
            !f.refresh.allows(1) && permit?.isCurrent == false && !grid.debugHasRawImage && target?
                .snapshotView == nil && context.isCurrent,
            "revoke left old pixels/permit or revoked profile context",
        )
        try await until("cell newer read") { f.gate.pending[1] != nil }
        f.gate.finish(1, .success(message(1, spoiler: true)))
        try await until("cell newer admission") { f.refresh.allows(1) }
        guard let updated = f.values[1] else { throw Failure(description: "updated cell") }
        session.reconcile([updated])
        grid.configure(message: updated, context: context, permit: session.permit(for: updated))
        try require(loads == 1 && !grid.debugHasRawImage && grid.debugHasCover, "new spoiler loaded old pixels")
        let downloads = await backend.downloadCalls
        try require(downloads.isEmpty, "probe unexpectedly downloaded media")
    }

    private static func message(_ id: Int64, spoiler: Bool = false, text: Bool = false, rich: Bool = false) -> Message {
        let file = File(
            expectedSize: 1,
            id: 81,
            local: .init(
                canBeDeleted: false,
                canBeDownloaded: true,
                downloadOffset: 0,
                downloadedPrefixSize: 0,
                downloadedSize: 0,
                isDownloadingActive: false,
                isDownloadingCompleted: false,
                path: "",
            ),
            remote: .init(
                id: "probe",
                isUploadingActive: false,
                isUploadingCompleted: true,
                uniqueId: "probe",
                uploadedSize: 1,
            ),
            size: 1,
        )
        let caption = FormattedText(entities: [], text: "private seed caption")
        let content: MessageContent =
 if rich {
            .messageRichMessage(.init(message: .init(blocks: [], isRtl: false, isFull: false)))
        } else if text {
            .messageText(.init(linkPreview: nil, linkPreviewOptions: nil, text: caption))
        } else {
            .messagePhoto(.init(
                photo: .init(hasStickers: false, minithumbnail: nil, sizes: [.init(
                    height: 24,
                    photo: file,
                    progressiveSizes: [],
                    type: "y",
                    width: 24,
                )]),
                video: nil,
                caption: caption,
                showCaptionAboveMedia: false,
                hasSpoiler: spoiler,
                isSecret: false,
            ))
        }
        return Message(
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
            editDate: spoiler ? 1 : 0,
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
            content: content,
            ephemeralContent: nil,
            replyMarkup: nil,
            ephemeralMessageId: 0,
            chatInstance: 0,
        )
    }
}
#endif

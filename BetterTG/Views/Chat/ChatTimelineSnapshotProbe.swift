// ChatTimelineSnapshotProbe.swift

#if DEBUG
import TDLibKit
import UIKit

/// Native cells and the production transaction owner; no ChatVM or transport fixture.
@MainActor enum ChatTimelineSnapshotProbe {
    private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

    @MainActor private final class Receipts {
        var held = [() -> Void]()
        var native = 0
        var ownerlessReleases = 0
        var cleaningUp = false
    }

    @MainActor private final class Rows {
        let state = ChatTimelineSnapshotState()
        let client = TDLib.shared.activeClient
        let source: TdUpdateSource
        let location: ChatLocation
        let polls = MessagePollInteractionStore()
        let chat = RootChatInsertionProbe.chat(
            .init(isPinned: false, list: .chatListMain, order: 1, source: nil), id: 100,
        )
        let collection: UICollectionView
        var data: UICollectionViewDiffableDataSource<Int, ChatTimelineItemID>!
        var models = [CustomMessage]()
        var selecting = true
        var selected = Set<DisplayedMessageID>()
        var viewport = ChatViewportRestorationAuthority()
        let receipts = Receipts()
        var starts = 0
        var releases = 0
        var depth = 0
        var maximumDepth = 0
        var restorationTickets = 0
        var finishingWasBusy = true
        var finishingRetainedDeletion = true
        var finishingRetainedCommitted = true
        var deletingBinding: (DisplayedMessageID, UUID)?
        weak var deletingCell: MessageCell?
        var deletingProviderDiagnostics = [String]()
        var deletingPresentation: (alpha: CGFloat, transform: CGAffineTransform)?
        var preservedInnerPresentation = true
        var preserved = 0
        var beforeProvider: (() -> Void)?
        var authorities = [DisplayedMessageID: ChatMessageActionAuthority]()
        var selectionCalls = 0
        var permitsStructuralDispatch = true

        var held: [() -> Void] { receipts.held }
        var nativeReceipts: Int { receipts.native }

        init() {
            self.source = .init(accountID: UUID(), clientID: client.id)
            self.location = .init(accountID: source.accountID, chatID: 100, clientID: client.id, topic: nil)
            let layout = UICollectionViewFlowLayout()
            layout.itemSize = .init(width: 350, height: 100)
            self.collection = UICollectionView(
                frame: .init(x: 0, y: 0, width: 390, height: 550), collectionViewLayout: layout,
            )
            collection.register(MessageCell.self, forCellWithReuseIdentifier: "snapshot-probe")
            self.data = UICollectionViewDiffableDataSource<Int, ChatTimelineItemID>(collectionView: collection) {
                [weak self] collection, path, item in
                let hook = self?.beforeProvider
                self?.beforeProvider = nil
                hook?()
                let returned = ChatTimelineCellProvider.dequeue(
                    MessageCell.self, from: collection, at: path, reuseIdentifier: "snapshot-probe",
                    preserve: { [weak self] cell in
                        guard let self, let id = item.displayedMessageID else { return false }
                        let decision = state.canPreserveDeletingCell(cell, id: id)
                        if id == deletingBinding?.0 {
                            deletingProviderDiagnostics.append(deletionReceipt("preserve=\(decision)", cell: cell))
                            self
                                .preservedInnerPresentation = preservedInnerPresentation &&
                                deletionPresentationMatches(cell)
                        }
                        guard decision else { return false }
                        preserved += 1
                        return true
                    },
                    configure: { [weak self] cell in
                        guard let self, let id = item.displayedMessageID, !state.deleting.contains(id),
                              let row = state.row(for: item)?.message else { return false }
                        let authority = ChatMessageActionAuthority(
                            message: row.canonical, cell: cell, source: row.source, location: row.location,
                            selected: row.inputs.selected, renderValue: row.value,
                        )
                        authorities[id] = authority
                        cell.configure(
                            message: row.renderedMessage, chat: chat, highlighted: row.inputs.highlighted,
                            client: row.client, pollInteractionStore: row.polls, canAddReactions: false,
                            selectionActive: row.inputs.selectionActive, selected: row.inputs.selected,
                            onSwipeToReply: nil,
                            onSelectionToggle: { [weak self] in
                                guard let self, resolve(authority) != nil else { return }
                                selectionCalls += 1
                            },
                            onReactionTap: { _ in }, onMetadataNavigate: { _ in }, onReplyQuoteExpand: {},
                            onContentAction: { _ in }, onMediaTap: { _, _ in },
                            actionBindingID: authority.bindingID, timelineRowID: row.id,
                            showsProfileImage: row.inputs.showsProfileImage,
                        )
                        return true
                    },
                    unavailable: { $0.resetUnavailableContent() },
                )
                if let owner = self, item.displayedMessageID == owner.deletingBinding?.0 {
                    owner.deletingProviderDiagnostics.append(owner.deletionReceipt(
                        "returned",
                        cell: returned as? MessageCell,
                    ))
                    owner.preservedInnerPresentation = owner.preservedInnerPresentation
                        && owner.deletionPresentationMatches(returned as? MessageCell)
                }
                return returned
            }
        }

        func deletionReceipt(_ phase: String, cell: MessageCell?) -> String {
            guard let cell else { return "\(phase):cell=nil" }
            let transform = cell.transform
            let innerTransform = cell.contentView.transform
            let lease = deletingBinding.map { state.ownsDeletingBinding($0.1, id: $0.0) } ?? false
            return "\(phase):same-cell=\(cell === deletingCell),binding=\(cell.timelineRowID == deletingBinding?.1),"
                + "displayed=\(cell.timelineDisplayedID == deletingBinding?.0),interaction=\(cell.isUserInteractionEnabled),"
                + "alpha=\(cell.alpha),transform=(\(transform.a),\(transform.b),\(transform.c),\(transform.d),\(transform.tx),\(transform.ty)),"
                + "inner-alpha=\(cell.contentView.alpha),inner-transform=(\(innerTransform.a),\(innerTransform.b),\(innerTransform.c),\(innerTransform.d),\(innerTransform.tx),\(innerTransform.ty)),"
                + "reuse=\(cell.probeReuseCount),lease=\(lease),preserved=\(preserved)"
        }

        func deletionPresentationMatches(_ cell: MessageCell?) -> Bool {
            guard let cell, let deletingPresentation else { return false }
            return cell === deletingCell && cell.timelineRowID == deletingBinding?.1
                && !cell.isUserInteractionEnabled && !cell.isAccessibilityElement && cell.accessibilityElementsHidden
                && cell.contentView.alpha == deletingPresentation.alpha
                && cell.contentView.transform == deletingPresentation.transform
        }

        func resolve(
            _ authority: ChatMessageActionAuthority,
            intent: ChatMessageActionAuthority.Intent = .selection,
        ) -> CustomMessage? {
            authority.resolve(
                intent, current: models.first { $0.displayedID == authority.displayedID },
                source: source, location: location, ownerIsCurrent: !state.retired, rowIsCurrent: !state.retired,
                state: .init(
                    isFull: true,
                    isSelecting: selecting,
                    isReadOnly: false,
                    canAddReactions: false,
                    isSelected: selected.contains(authority.displayedID),
                ),
            )
        }

        func enqueue(_ demand: ChatTimelineSnapshotState.Demand) {
            state.enqueue(demand)
            drain()
        }

        func drain() {
            guard depth == 0, state.canBegin,
                  permitsStructuralDispatch || state.pending?.structural != true else { return }
            guard let batch = state.begin(makeContent: { demand in
                if demand.restoresViewport, demand.permitsRestoration(at: viewport.invalidationRevision) {
                    _ = viewport.begin()
                    restorationTickets += 1
                }
                let ids = demand.structural
                    ? models.filter { !state.deleting.contains($0.displayedID) }
                    .map { ChatTimelineItemID.message($0.displayedID) }
                    : state.committed.ids
                var rows = [ChatTimelineItemID: ChatTimelineRenderRow]()
                for item in ids {
                    guard let id = item.displayedMessageID else { continue }
                    if state.deleting.contains(id) {
                        rows[item] = state.committed.rows[item]
                    } else if let model = models.first(where: { $0.displayedID == id }) {
                        rows[item] = .message(ChatTimelineMessageRow(
                            canonical: model, value: .init(model),
                            inputs: .init(
                                highlighted: demand.highlight,
                                selectionActive: selecting,
                                selected: selected.contains(id),
                                showsProfileImage: false,
                                canAddReactions: false,
                                canReply: false,
                            ),
                            client: client, source: source, location: location, polls: polls,
                            mediaRevealSession: nil, videoOwners: [:],
                        ))
                    }
                }
                return .init(ids: ids, rows: rows, reconfigure: Set(ids.filter {
                    $0.displayedMessageID.map { !state.deleting.contains($0) } ?? true
                }))
            }) else { return }
            starts += 1
            depth += 1
            maximumDepth = max(maximumDepth, depth)
            var snapshot = NSDiffableDataSourceSnapshot<Int, ChatTimelineItemID>()
            snapshot.appendSections([0])
            snapshot.appendItems(batch.content.ids)
            snapshot.reconfigureItems(Array(batch.content.reconfigure))
            let id = batch.id
            let viewportRevision = batch.demand.viewportRevision
            data.apply(snapshot, animatingDifferences: false) { [weak self, state, receipts] in
                receipts.native += 1
                let completion = { [weak self, state, receipts] in
                    guard let owner = self else {
                        state.retire()
                        if state.complete(id, finish: { _ in }) { receipts.ownerlessReleases += 1 }
                        return
                    }
                    var removedDeletionIDs = Set<DisplayedMessageID>()
                    guard state.complete(id, finish: { exact in
                        removedDeletionIDs = state.deleting
                            .subtracting(exact.content.ids.compactMap(\.displayedMessageID))
                        owner.finishingWasBusy = owner.finishingWasBusy && state.isBusy && !state.canBegin && exact
                            .id == id
                        owner.finishingRetainedCommitted = owner.finishingRetainedCommitted && exact.outgoing
                            .allSatisfy { item, row in
                            row.message?.id == state.committed.rows[item]?.message?.id
                        }
                        let removed = Set(exact.outgoing.keys).subtracting(exact.content.ids)
                        owner.finishingRetainedDeletion = owner.finishingRetainedDeletion && removed.allSatisfy {
                            $0.displayedMessageID.map { state.deleting.contains($0) } ?? true
                        }
                        if let (deletedID, binding) = owner.deletingBinding, removed.contains(.message(deletedID)) {
                            owner.finishingRetainedDeletion = owner.finishingRetainedDeletion
                                && state.ownsDeletingBinding(binding, id: deletedID)
                        }
                        owner.collection.layoutIfNeeded()
                        _ = ChatViewportRestorationAuthority.finishLayoutMutation(depth: &owner.depth)
                        owner.releases += 1
                    }) else { return }
                    if !state.retired {
                        state.reconcileRemovedRows(
                            removedDeletionIDs,
                            current: Set(owner.models.map(\.displayedID)),
                            viewportRevision: viewportRevision,
                        )
                    }
                    owner.drain()
                }
                if receipts.cleaningUp { completion() } else { receipts.held.append(completion) }
            }
        }

        @discardableResult func release() -> () -> Void {
            let completion = receipts.held.removeFirst()
            completion()
            return completion
        }

        func cleanup() {
            receipts.cleaningUp = true
            state.retire()
            while !held.isEmpty {
                release()
            }
        }
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-chat-timeline-snapshots") else { return }
        Task { @MainActor in
            let result: String
            do {
                try await verify()
                try await verifyReleasedOwner()
                result = "Chat timeline snapshot probe passed: shared-production-scheduler/native-MessageCell=true; "
                    + "five-demand-coalescing/exact-completion/outgoing-value-client-source/maximum-active-one=true; "
                    + "in-place-album/new-wrapper/frozen-action-baseline/committed-raw-member=true; "
                    + "pre-drag-buffer-no-new-ticket/delete-late-provider/same-album-reappearance/selection-exit=true; "
                    + "duplicate-completion/source-retirement/released-owner-lease/fresh-restoration/exact-depth-cleanup=true; "
                    + "actual-ChatView-producers/physical-gesture/live-client-switch/delete-timing/media-player=unverified; RPC/sends=0"
            } catch { result = "Chat timeline snapshot probe failed: \(error)" }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("chat-timeline-snapshot-probe.txt"), options: .atomic,
                )
            }
            log(result)
        }
    }

    private static func verify() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { throw Failure(description: "missing native scene") }
        let rows = Rows()
        let window = UIWindow(windowScene: scene)
        window.frame = .init(x: -10000, y: 0, width: 390, height: 844)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(rows.collection)
        window.isHidden = false
        defer {
            rows.cleanup()
            window.isHidden = true
            window.rootViewController = nil
        }
        func model(_ id: Int64, album: Int64 = 0, text: String) -> CustomMessage {
            CustomMessage(
                message: MessageDeliveryProbe.fixture(id: id, album: album),
                formattedText: .init(entities: [], text: text),
                properties: .default,
            )
        }
        let album = model(10, album: 77, text: "frozen album")
        let outgoing = model(20, text: "outgoing")
        let albumID = album.displayedID
        let outgoingID = outgoing.displayedID
        rows.models = [album, outgoing]
        rows.selected = [albumID]
        rows.enqueue(.init(structural: true, restoresViewport: true, viewportRevision: 0))
        try await until("initial native completion") { rows.held.count == 1 }
        try require(rows.depth == 1 && rows.state.committed.ids.isEmpty, "initial completion was not held whole")
        rows.release()
        rows.collection.layoutIfNeeded()
        guard let oldRow = rows.state.committed.rows[.message(albumID)]?.message,
              let oldOutgoing = rows.state.committed.rows[.message(outgoingID)]?.message,
              let oldAuthority = rows.authorities[albumID], rows.resolve(oldAuthority) === album,
              let cell = rows.collection.cellForItem(at: .init(item: 0, section: 0)) as? MessageCell
        else { throw Failure(description: "unarmed initial frozen rows or action") }
        try require(
            oldRow.client.id == rows.client.id && oldRow.source == rows.source && oldRow.location == rows.location,
            "row lost its exact client/source/location",
        )
        rows.enqueue(.init(ids: [albumID], restoresViewport: true, viewportRevision: 0))
        try await until("first held reconfigure") { rows.held.count == 1 }
        let heldID = rows.state.active?.id
        let secondAuthority = rows.authorities[albumID]
        album.message = MessageDeliveryProbe.fixture(id: 11, album: 77)
        album.album = [album.message, MessageDeliveryProbe.fixture(id: 12, album: 77)]
        album.formattedText = .init(entities: [], text: "promoted album")
        album.isReplyQuoteExpanded = true
        if let secondAuthority {
            try require(rows.resolve(secondAuthority) == nil, "old frozen action admitted promoted canonical payload")
        } else { throw Failure(description: "missing held reconfigure action") }
        let replacement = model(20, text: "replacement")
        rows.models = [album, replacement]
        if let authority = rows.authorities[outgoingID] {
            try require(rows.resolve(authority) == nil, "old frozen action admitted replacement wrapper")
        } else { throw Failure(description: "missing replacement baseline action") }
        rows.selecting = false
        rows.selected.removeAll()
        rows.enqueue(.init(structural: true, animated: true, restoresViewport: true, viewportRevision: 0))
        rows.enqueue(.init(ids: [albumID], restoresViewport: true, viewportRevision: 0))
        rows.enqueue(.init(ids: [albumID, outgoingID], restoresViewport: true, viewportRevision: 0))
        rows.viewport.invalidate()
        rows.enqueue(.init(ids: [albumID], highlight: true, viewportRevision: rows.viewport.invalidationRevision))
        rows.enqueue(.init(ids: [albumID], quoteID: albumID, viewportRevision: rows.viewport.invalidationRevision))
        try require(
            rows.starts == 2 && rows.depth == 1 && rows.state.active?.id == heldID,
            "producer overlapped the held native transaction",
        )
        guard let demand = rows.state.pending else { throw Failure(description: "coalesced demand absent") }
        try require(
            demand.structural && demand.animated && demand.highlight && demand.quoteID == albumID
            && demand.ids == [albumID, outgoingID] && demand.viewportRevision == 0,
            "five producer demands lost intent or refreshed pre-drag revision",
        )
        try require(
            oldRow.value.message.id == 10 && oldRow.renderedMessage.message.id == 10
            && oldOutgoing.value.formattedText?.text == "outgoing"
            && rows.state.active?.outgoing[.message(outgoingID)]?.message === oldOutgoing,
            "live mutation rewrote outgoing rendering values",
        )
        try require(
            !rows.state.committedContains(rawID: 12, displayedID: albumID),
            "new album member became ready before committed native completion",
        )
        let ticketCount = rows.restorationTickets
        let duplicate = rows.release()
        try await until("coalesced five-demand native completion") { rows.held.count == 1 }
        try require(
            rows.starts == 3 && rows.maximumDepth == 1 && rows.restorationTickets == ticketCount,
            "pre-drag pending content minted a new ticket or overlapped apply",
        )
        try require(
            !rows.state.committedContains(rawID: 12, displayedID: albumID),
            "incoming provider payload was mistaken for committed raw membership",
        )
        duplicate()
        try require(rows.depth == 1 && rows.releases == 2, "duplicate completion released the newer batch")
        rows.release()
        try require(
            rows.state.committedContains(rawID: 12, displayedID: albumID)
            && rows.state.committed.rows[.message(outgoingID)]?.message?.canonical === replacement
            && rows.depth == 0 && !rows.state.isBusy,
            "latest content did not commit on its exact native completion",
        )
        guard let freshAuthority = rows.authorities[albumID], rows.resolve(freshAuthority, intent: .media) === album
        else { throw Failure(description: "fresh frozen baseline did not recover current action authority") }
        try require(
            rows.collection.cellForItem(at: .init(item: 0, section: 0)) === cell
            && cell.accessibilityCustomActions?
                .contains(where: { $0.name == "Select Message" || $0.name == "Deselect Message" }) != true
            && rows.state.committed.rows.values.compactMap(\.message).allSatisfy { !$0.inputs.selectionActive },
            "same-cell selection exit retained selection actions",
        )
        let freshTickets = rows.restorationTickets
        rows.enqueue(.init(
            ids: [albumID],
            restoresViewport: true,
            viewportRevision: rows.viewport.invalidationRevision,
        ))
        try await until("fresh post-drag restoration") { rows.held.count == 1 }
        try require(rows.restorationTickets == freshTickets + 1, "fresh post-drag demand could not capture restoration")
        rows.release()
        try await verifyNormalDeletionReset(rows)
        try await verifyDeletion(rows)
        try await verifyDeletion(rows, queuesFreshHighlight: true)
        try await verifyRetirement(rows)
        try require(
            rows.maximumDepth == 1 && rows.nativeReceipts == rows.releases
            && rows.depth == 0 && rows.finishingWasBusy && rows.finishingRetainedDeletion
            && rows.finishingRetainedCommitted && !rows.state.isBusy,
            "unbalanced exact receipt/release/depth or finishing ownership",
        )
    }

    private static func verifyNormalDeletionReset(_ rows: Rows) async throws {
        guard let cell = rows.collection.cellForItem(at: .init(item: 0, section: 0)) as? MessageCell,
              let id = cell.timelineDisplayedID else { throw Failure(description: "missing deletion reset cell") }
        let reuse = cell.probeReuseCount
        cell.setDeletionPresentation(alpha: 0.375, transform: .init(translationX: 8, y: -3))
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0.375
        animation.duration = 60
        cell.contentView.layer.add(animation, forKey: "probe-normal-deletion-reset")
        try require(
            cell.contentView.layer.animationKeys()?.isEmpty == false && !cell.isUserInteractionEnabled
            && !cell.isAccessibilityElement && cell.accessibilityElementsHidden,
            "normal reset was not armed",
        )
        rows.enqueue(.init(ids: [id], viewportRevision: rows.viewport.invalidationRevision))
        try await until("native same-cell deletion presentation reset") { rows.held.count == 1 }
        try require(
            rows.collection.cellForItem(at: .init(item: 0, section: 0)) === cell
            && cell.probeReuseCount == reuse && cell.contentView.alpha == 1
            && cell.contentView.transform == CGAffineTransform(scaleX: 1, y: -1)
            && cell.contentView.layer.animationKeys()?.isEmpty != false && cell.isUserInteractionEnabled
            && cell.isAccessibilityElement && !cell.accessibilityElementsHidden,
            "normal same-cell configure failed to reset inner deletion presentation and AX",
        )
        rows.release()
    }

    private static func verifyDeletion(_ rows: Rows, queuesFreshHighlight: Bool = false) async throws {
        guard let canonical = rows.models.first,
              let cell = rows.collection.cellForItem(at: .init(item: 0, section: 0)) as? MessageCell,
              let binding = cell.timelineRowID else { throw Failure(description: "missing deleting cell") }
        let id = canonical.displayedID
        rows.deletingBinding = (id, binding)
        rows.deletingCell = cell
        rows.deletingProviderDiagnostics.removeAll()
        rows.preservedInnerPresentation = true
        let preservedBefore = rows.preserved
        let reuseBefore = cell.probeReuseCount
        let deletionTransform = CGAffineTransform(translationX: 8, y: -3).scaledBy(x: 0.875, y: 0.875)
        let expectedContentTransform = CGAffineTransform(scaleX: 1, y: -1).concatenating(deletionTransform)
        var armed = false
        rows.beforeProvider = { [weak rows, weak cell] in
            guard let rows, let cell else { return }
            rows.state.markDeleting([id])
            cell.setDeletionPresentation(alpha: 0.375, transform: deletionTransform)
            rows.deletingPresentation = (cell.contentView.alpha, cell.contentView.transform)
            armed = true
            rows.deletingProviderDiagnostics.append(rows.deletionReceipt("armed", cell: cell))
        }
        rows.enqueue(.init(ids: [id], viewportRevision: rows.viewport.invalidationRevision))
        try await until("late deleting native provider") { rows.held.count == 1 }
        try require(
            armed && rows.preserved == preservedBefore + 1 && cell.timelineRowID == binding
            && !cell.isUserInteractionEnabled && cell.contentView.alpha == 0.375
            && cell.contentView.transform == expectedContentTransform
            && rows.preservedInnerPresentation && rows.deletionPresentationMatches(cell)
            && rows.collection.cellForItem(at: .init(item: 0, section: 0)) === cell
            && cell.probeReuseCount == reuseBefore && rows.state.ownsDeletingBinding(binding, id: id),
            "late provider resurrected or rebound the exact deleting cell: armed=\(armed),preserved-delta=\(rows.preserved - preservedBefore); "
                + rows.deletingProviderDiagnostics.joined(separator: "; ") + "; "
                + rows.deletionReceipt("native-receipt", cell: cell),
        )
        let other = MessageCell(frame: .zero)
        try require(
            !rows.state.canPreserveDeletingCell(other, id: id),
            "unbound deleting cell was allowed to expose content",
        )
        other.setDeletionPresentation(alpha: 0.375, transform: deletionTransform)
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0.375
        animation.duration = 60
        other.contentView.layer.add(animation, forKey: "probe-deletion")
        try require(other.contentView.layer.animationKeys()?.isEmpty == false, "inner deletion animation was not armed")
        other.resetUnavailableContent()
        try require(
            other.contentView.alpha == 1
            && other.contentView.transform == CGAffineTransform(scaleX: 1, y: -1)
            && other.contentView.layer.animationKeys()?.isEmpty != false,
            "unavailable reset retained inner deletion animation or lost content flip",
        )
        rows.permitsStructuralDispatch = false
        rows.models.removeAll { $0.displayedID == id }
        let reappearedRawID = (canonical.sourceMessages.map(\.id).max() ?? canonical.id) + 1
        let reappearing = CustomMessage(
            message: MessageDeliveryProbe.fixture(id: reappearedRawID, album: canonical.message.mediaAlbumId),
            formattedText: .init(entities: [], text: "new album incarnation"), properties: .default,
        )
        rows.models.insert(reappearing, at: 0)
        rows.enqueue(.init(structural: true, ids: [id], viewportRevision: rows.viewport.invalidationRevision))
        let starts = rows.starts
        rows.release()
        try require(
            rows.starts == starts && rows.state.deleting.contains(id) && rows.state.isBusy,
            "pending removal crossed the controlled deletion dispatch barrier",
        )
        try require(
            rows.state.canPreserveDeletingCell(cell, id: id),
            "intermediate commit lost the exact old deleting cell binding",
        )
        rows.permitsStructuralDispatch = true
        rows.drain()
        try await until("exact deleting row removal") { rows.held.count == 1 }
        try require(
            rows.state.deleting.contains(id) && rows.state.active?.content.ids.contains(.message(id)) == false,
            "new same-album member bypassed the exact removal transaction",
        )
        rows.viewport.invalidate()
        if queuesFreshHighlight {
            rows.enqueue(.init(ids: [id], highlight: true, viewportRevision: rows.viewport.invalidationRevision))
            try require(rows.state.pending?.restoresViewport == false, "fresh highlight unexpectedly owned restoration")
        }
        let ticketsBeforeRecovery = rows.restorationTickets
        rows.release()
        try require(
            !rows.state.deleting.contains(id) && !rows.state.committed.ids.contains(.message(id))
            && !rows.state.ownsDeletingBinding(binding, id: id),
            "exact removal failed to clear tombstone and membership",
        )
        try await until("reappearing same-album native receipt") { rows.held.count == 1 }
        try require(
            rows.restorationTickets == ticketsBeforeRecovery
            && !rows.state.committedContains(rawID: reappearedRawID, displayedID: id),
            "reappearance refreshed stale viewport epoch or became ready before commit",
        )
        rows.release()
        guard let authority = rows.authorities[id], rows.resolve(authority, intent: .media) === reappearing else {
            throw Failure(description: "reappearing same-album row did not regain fresh action authority")
        }
        guard let restoredCell = rows.collection.cellForItem(at: .init(item: 0, section: 0)) as? MessageCell else {
            throw Failure(description: "missing reinserted deletion presentation cell")
        }
        try require(
            restoredCell.contentView.alpha == 1
            && restoredCell.contentView.transform == CGAffineTransform(scaleX: 1, y: -1)
            && restoredCell.isUserInteractionEnabled && restoredCell.isAccessibilityElement
            && !restoredCell.accessibilityElementsHidden,
            "normal reinsert configure retained deletion presentation or lost content flip",
        )
        try require(
            rows.state.committedContains(rawID: reappearedRawID, displayedID: id) && !rows.state.deleting.contains(id),
            "new same-album member remained under the deleted incarnation tombstone",
        )
    }

    private static func verifyRetirement(_ rows: Rows) async throws {
        guard let model = rows.models.first,
              let outgoing = rows.state.committed.rows[.message(model.displayedID)]?.message
        else { throw Failure(description: "missing retirement outgoing row") }
        rows.enqueue(.init(ids: [model.displayedID], viewportRevision: rows.viewport.invalidationRevision))
        try await until("retiring native completion") { rows.held.count == 1 }
        rows.enqueue(.init(structural: true, viewportRevision: rows.viewport.invalidationRevision))
        let starts = rows.starts
        rows.state.markDeleting([model.displayedID])
        rows.state.retire()
        try require(
            rows.state.pending == nil && rows.state.row(for: .message(model.displayedID)) == nil
            && rows.state.active?.outgoing[.message(model.displayedID)]?.message === outgoing
            && rows.state.active?.outgoing[.message(model.displayedID)]?.message?.client.id == rows.client.id,
            "retirement exposed rows or released active originating owners early",
        )
        try require(
            rows.state.ownsDeletingBinding(outgoing.id, id: model.displayedID),
            "source retirement released tombstone owner before exact receipt",
        )
        rows.enqueue(.init(structural: true, viewportRevision: rows.viewport.invalidationRevision))
        let duplicate = rows.release()
        duplicate()
        try require(
            rows.starts == starts && rows.state.active == nil && rows.state.committed.ids.isEmpty
            && rows.state.pending == nil && rows.depth == 0
            && !rows.state.ownsDeletingBinding(outgoing.id, id: model.displayedID),
            "retired source restarted work or missed exact native cleanup",
        )
    }

    private static func verifyReleasedOwner() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { throw Failure(description: "missing owner-release scene") }
        var owner: Rows? = Rows()
        guard let collection = owner?.collection, let receipts = owner?.receipts
        else { throw Failure(description: "missing owner-release fixture") }
        let window = UIWindow(windowScene: scene)
        window.frame = .init(x: -10000, y: 0, width: 390, height: 844)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(collection)
        window.isHidden = false
        defer {
            owner?.cleanup()
            receipts.cleaningUp = true
            while !receipts.held.isEmpty {
                receipts.held.removeFirst()()
            }
            window.isHidden = true
            window.rootViewController = nil
        }
        let model = CustomMessage(
            message: MessageDeliveryProbe.fixture(id: 50),
            formattedText: .init(entities: [], text: "owner release"),
            properties: .default,
        )
        owner?.models = [model]
        owner?.enqueue(.init(structural: true, viewportRevision: 0))
        try await until("owner-release initial native apply") { receipts.held.count == 1 }
        owner?.release()
        let outgoingExists = { [weak row = owner?.state.committed.rows[.message(model.displayedID)]?.message] in
            row != nil
        }
        let schedulerIsActive = { [weak state = owner?.state] in state?.active != nil }
        let schedulerIsRetired = { [weak state = owner?.state] in
            state?.retired == true && state?.active == nil && state?.committed.ids.isEmpty == true && state?
                .pending == nil
        }
        owner?.enqueue(.init(ids: [model.displayedID], viewportRevision: 0))
        try await until("owner-release held native receipt") { receipts.held.count == 1 }
        let ownerWasReleased = { [weak owner] in owner == nil }
        owner = nil
        try require(
            ownerWasReleased() && outgoingExists() && schedulerIsActive(),
            "native completion retained owner or released outgoing lease early",
        )
        let duplicate = receipts.held.removeFirst()
        duplicate()
        duplicate()
        try require(
            !outgoingExists() && schedulerIsRetired() && receipts.ownerlessReleases == 1,
            "ownerless exact native completion leaked outgoing rows or released twice",
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    private static func until(_ label: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(condition(), "timed out: \(label)")
    }
}
#endif

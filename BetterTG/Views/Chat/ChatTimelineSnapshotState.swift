// ChatTimelineSnapshotState.swift

import TDLibKit
import UIKit

// MARK: - ChatTimelineMessageRow

@MainActor final class ChatTimelineMessageRow {
    struct Inputs: Equatable {
        /// The highlighted source message, so an album highlights only that item.
        let highlightedMessageID: Int64?
        let selectionActive: Bool
        let selected: Bool
        let showsProfileImage: Bool
        let canAddReactions: Bool
        let canReply: Bool
        /// The items of a media album that are selected, while selection is on; an album can be partly selected.
        var selectedAlbumItemIDs: Set<Int64>?
        /// The last bubble of a run from one author carries the avatar; the others keep its room.
        var showsAvatarImage = true
        /// The first bubble of a run from one author in a group carries the author's name, with this rank.
        var showsSenderName = false
        var senderRank: MessageSenderName.Rank?
    }

    let id = UUID()
    let canonical: CustomMessage
    let value: ChatMessageRenderValue
    /// The canonical revision this row's value is known to match; equal-content reuse advances it.
    var revision: UInt64
    let inputs: Inputs
    let client: TDLibClient
    let source: TdUpdateSource?
    let location: ChatLocation
    let polls: MessagePollInteractionStore
    let mediaRevealSession: MediaRevealSession?
    var videoOwners: [Int64: GalleryVideoPlaybackOwner]
    lazy var renderedMessage = value.makeRenderOnlyMessage()

    init(
        canonical: CustomMessage, value: ChatMessageRenderValue, inputs: Inputs, client: TDLibClient,
        source: TdUpdateSource?, location: ChatLocation, polls: MessagePollInteractionStore,
        mediaRevealSession: MediaRevealSession?, videoOwners: [Int64: GalleryVideoPlaybackOwner],
    ) {
        self.canonical = canonical
        self.value = value
        self.revision = canonical.renderRevision
        self.inputs = inputs
        self.client = client
        self.source = source
        self.location = location
        self.polls = polls
        self.mediaRevealSession = mediaRevealSession
        self.videoOwners = videoOwners
    }
}

// MARK: - ChatTimelineRenderRow

@MainActor enum ChatTimelineRenderRow {
    case message(ChatTimelineMessageRow)
    case topic(ForumTopicRunHeaderID, ForumTopicInfo?, TDLibClient, TdUpdateSource?)
    case date(ChatDateHeaderID)
    case notice(String)
    case botInfo(TDNativeBotInfo, TDLibClient)

    var message: ChatTimelineMessageRow? {
        if case .message(let row) = self {
            row
        } else {
            nil
        }
    }
}

// MARK: - ChatTimelineSnapshotState

/// The only diffable apply owner. Pending work is intent, never a stale snapshot.
@MainActor final class ChatTimelineSnapshotState {
    struct Demand {
        var structural = false
        var animated = false
        var ids = Set<DisplayedMessageID>()
        var restoresViewport = false
        var quoteID: DisplayedMessageID?
        var highlight = false
        let viewportRevision: UInt64

        func permitsRestoration(at revision: UInt64) -> Bool { viewportRevision == revision }

        mutating func merge(_ newer: Self) {
            structural = structural || newer.structural
            animated = animated || newer.animated
            ids.formUnion(newer.ids)
            restoresViewport = restoresViewport || newer.restoresViewport
            quoteID = newer.quoteID ?? quoteID
            highlight = highlight || newer.highlight
            // Keep the first stamp: later events cannot revive a pre-gesture buffer.
        }
    }

    struct Content {
        let ids: [ChatTimelineItemID]
        let rows: [ChatTimelineItemID: ChatTimelineRenderRow]
        let reconfigure: Set<ChatTimelineItemID>
    }

    struct Batch {
        let id = UUID()
        let demand: Demand
        let content: Content
        let outgoing: [ChatTimelineItemID: ChatTimelineRenderRow]
    }

    private(set) var pending: Demand?
    private(set) var active: Batch?
    private(set) var committed = Content(ids: [], rows: [:], reconfigure: [])
    private(set) var deleting = Set<DisplayedMessageID>()
    private(set) var retired = false

    private var finishing = false
    private var deletingRows = [UUID: ChatTimelineMessageRow]()

    var isBusy: Bool { active != nil || pending != nil || finishing }
    var canBegin: Bool { !retired && active == nil && !finishing && pending != nil }

    func enqueue(_ demand: Demand) {
        guard !retired else { return }
        if pending != nil { pending?.merge(demand) } else { pending = demand }
    }

    func reconcileRemovedRows(
        _ removed: Set<DisplayedMessageID>,
        current: Set<DisplayedMessageID>,
        viewportRevision: UInt64,
    ) {
        guard !removed.isDisjoint(with: current) else { return }
        let ownsPendingRevision = pending == nil || pending?.viewportRevision == viewportRevision
        enqueue(.init(structural: true, restoresViewport: ownsPendingRevision, viewportRevision: viewportRevision))
    }

    func begin(makeContent: (Demand) -> Content?) -> Batch? {
        guard canBegin, let demand = pending else { return nil }
        pending = nil
        finishing = true
        defer { finishing = false }
        guard let content = makeContent(demand), !retired else { return nil }
        let batch = Batch(demand: demand, content: content, outgoing: committed.rows)
        active = batch
        return batch
    }

    /// Keep both generations through the whole native completion, including layout
    /// and depth release. Reentrant producers may only fill the pending buffer.
    @discardableResult func complete(_ id: UUID, finish: (Batch) -> Void) -> Bool {
        guard !finishing, let batch = active, batch.id == id else { return false }
        finishing = true
        finish(batch)
        if !retired {
            committed = batch.content
            deleting.formIntersection(Set(committed.ids.compactMap(\.displayedMessageID)))
            deletingRows = deletingRows.filter { deleting.contains($0.value.value.displayedID) }
        }
        active = nil
        if retired {
            committed = Content(ids: [], rows: [:], reconfigure: [])
            deletingRows.removeAll()
        }
        finishing = false
        return true
    }

    func row(for id: ChatTimelineItemID) -> ChatTimelineRenderRow? {
        guard !retired else { return nil }
        return active?.content.rows[id] ?? active?.outgoing[id] ?? committed.rows[id]
    }

    func markDeleting(_ ids: Set<DisplayedMessageID>) {
        guard !retired else { return }
        deleting.formUnion(ids)
        for rows in [active?.content.rows ?? [:], active?.outgoing ?? [:], committed.rows] {
            for row in rows.values.compactMap(\.message) where ids.contains(row.value.displayedID) {
                deletingRows[row.id] = row
            }
        }
    }

    func ownsDeletingBinding(_ binding: UUID, id: DisplayedMessageID) -> Bool {
        deletingRows[binding]?.value.displayedID == id
    }

    func canPreserveDeletingCell(_ cell: MessageCell, id: DisplayedMessageID) -> Bool {
        guard !retired, deleting.contains(id), cell.timelineDisplayedID == id,
              let binding = cell.timelineRowID, !cell.isUserInteractionEnabled else { return false }
        if ownsDeletingBinding(binding, id: id) { return true }
        let key = ChatTimelineItemID.message(id)
        return [active?.content.rows[key], active?.outgoing[key], committed.rows[key]]
            .contains { $0?.message?.id == binding }
    }

    func boundRow(for cell: MessageCell) -> ChatTimelineMessageRow? {
        guard !retired, let id = cell.timelineDisplayedID, let binding = cell.timelineRowID else { return nil }
        let key = ChatTimelineItemID.message(id)
        return [active?.content.rows[key], active?.outgoing[key], committed.rows[key]]
            .compactMap { $0?.message }
            .first { $0.id == binding } ?? deletingRows[binding]
    }

    func committedContains(rawID: Int64, displayedID: DisplayedMessageID) -> Bool {
        !retired && !deleting.contains(displayedID)
            && committed.rows[.message(displayedID)]?
            .message?
            .value
            .sourceMessages
            .contains(where: { $0.id == rawID }) == true
    }

    func retire() {
        retired = true
        pending = nil
        deleting.removeAll()
        if active == nil {
            committed = Content(ids: [], rows: [:], reconfigure: [])
            deletingRows.removeAll()
        }
    }
}

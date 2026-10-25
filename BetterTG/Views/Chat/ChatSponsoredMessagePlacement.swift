// ChatSponsoredMessagePlacement.swift

import UIKit

// MARK: - ChatSponsoredMessagePlacement

/// ChatHistoryListNode's ad management (`beginAdMessageManagement`, `maybeInsertPendingAdMessage`, `markAdAsSeen`):
/// TDLib's first ad goes after the newest message; when TDLib gives `messages_between`, the ads also go into the
/// history as the user scrolls through that many messages and a screen of them, each just after a message beyond
/// the screen in the scroll direction.
struct ChatSponsoredMessagePlacement {
    struct Placed: Equatable {
        let id: Int64
        /// The message the ad follows; it shows just below it.
        let anchor: DisplayedMessageID
    }

    /// `allAdMessages.fixed`: the ad after the newest message.
    private(set) var fixedID: Int64?
    /// `allAdMessages.opportunistic`: the ads placed in the history.
    private(set) var placed = [Placed]()

    /// `pendingDynamicAdMessages`: the ads still to place, in TDLib's order.
    private var pending = [Int64]()
    private var interval: Int?
    private var remainingInterval: Int?
    private var remainingDistance: CGFloat?
    /// `seenMessageIds`: the messages already counted toward the next ad.
    private var countedMessageIDs = Set<DisplayedMessageID>()

    /// beginAdMessageManagement for a new list of ads: the first is the fixed one and, with `messages_between`,
    /// all of them wait to be placed; the count toward the next one carries on.
    mutating func reset(ids: [Int64], messagesBetween: Int, viewportHeight: CGFloat) {
        fixedID = ids.first
        placed = []
        if messagesBetween > 0 {
            pending = ids
            interval = messagesBetween
            if remainingInterval == nil { remainingInterval = messagesBetween }
            if remainingDistance == nil { remainingDistance = viewportHeight }
        } else {
            pending = []
            interval = nil
        }
    }

    /// processDisplayedItemRangeChanged: each message seen for the first time counts once with its height. True when
    /// the next ad is due; the count then starts over.
    mutating func count(_ visible: [(id: DisplayedMessageID, height: CGFloat)], viewportHeight: CGFloat) -> Bool {
        guard let interval, var remainingInterval, var remainingDistance else { return false }
        var due = false
        for message in visible where countedMessageIDs.insert(message.id).inserted {
            remainingInterval -= 1
            remainingDistance -= message.height
            if remainingInterval <= 0, remainingDistance <= 0 {
                remainingInterval = interval
                remainingDistance = viewportHeight
                due = true
            }
        }
        self.remainingInterval = remainingInterval
        self.remainingDistance = remainingDistance
        return due && !pending.isEmpty
    }

    /// maybeInsertPendingAdMessage: the next ad follows `anchor`. When it is the fixed one, the fixed place takes
    /// the ad after it.
    mutating func place(after anchor: DisplayedMessageID) {
        guard !pending.isEmpty else { return }
        let id = pending.removeFirst()
        if fixedID == id { fixedID = pending.first }
        placed.append(Placed(id: id, anchor: anchor))
    }

    /// markAdAsSeen: a seen ad is not placed again.
    mutating func noteSeen(_ id: Int64) {
        pending.removeAll { $0 == id }
    }

    func isPlaced(_ id: Int64) -> Bool {
        placed.contains { $0.id == id }
    }
}

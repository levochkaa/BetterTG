// ForumTopicState.swift

import Foundation
import TDLibKit

// MARK: - ForumTopicPageCursor

struct ForumTopicPageCursor: Hashable {
    static let zero = ForumTopicPageCursor(
        date: 0,
        forumTopicID: 0,
        messageID: 0,
    )

    let date: Int
    let forumTopicID: Int
    let messageID: Int64

    init(
        date: Int,
        forumTopicID: Int,
        messageID: Int64,
    ) {
        self.date = date
        self.forumTopicID = forumTopicID
        self.messageID = messageID
    }

    init(response: ForumTopics) {
        self.init(
            date: response.nextOffsetDate,
            forumTopicID: response.nextOffsetForumTopicId,
            messageID: response.nextOffsetMessageId,
        )
    }
}

// MARK: - ForumTopicLiveUpdateState

/// A getForumTopic response itself emits updateForumTopic. Consume that payload
/// directly; only a changed inbox edge requires the omitted unread count again.
struct ForumTopicLiveUpdateState {
    struct Read {
        fileprivate let id: UUID
        fileprivate let revision: UInt64
    }

    struct Change {
        let metadataChanged: Bool
        let draftChanged: Bool
        let refreshUnreadCount: Bool
    }

    let location: ChatLocation

    private var latest: UpdateForumTopic?
    private var revision = UInt64.zero
    private var readID: UUID?
    private var retired = false

    init(location: ChatLocation) { self.location = location }

    private static func payload(_ topic: ForumTopic) -> UpdateForumTopic {
        UpdateForumTopic(
            chatId: topic.info.chatId, draftMessage: topic.draftMessage, forumTopicId: topic.info.forumTopicId,
            isPinned: topic.isPinned, lastReadInboxMessageId: topic.lastReadInboxMessageId,
            lastReadOutboxMessageId: topic.lastReadOutboxMessageId, notificationSettings: topic.notificationSettings,
            unreadMentionCount: topic.unreadMentionCount, unreadPollVoteCount: topic.unreadPollVoteCount,
            unreadReactionCount: topic.unreadReactionCount,
        )
    }

    mutating func beginRead(source: TdUpdateSource?) -> Read? {
        guard permits(source) else { return nil }
        let id = UUID()
        readID = id
        return Read(id: id, revision: revision)
    }

    mutating func receive(_ update: UpdateForumTopic, current: ForumTopic?, source: TdUpdateSource?) -> Change? {
        guard permits(source), update.chatId == location.chatID,
              update.forumTopicId == location.forumTopicID else { return nil }
        let previous = latest ?? current.flatMap { matches($0) ? Self.payload($0) : nil }
        revision &+= 1
        latest = update
        return Change(
            metadataChanged: previous != update,
            draftChanged: previous?.draftMessage != update.draftMessage,
            refreshUnreadCount: previous.map { $0.lastReadInboxMessageId != update.lastReadInboxMessageId } ?? false,
        )
    }

    func applyingLatest(to topic: ForumTopic) -> ForumTopic {
        guard matches(topic), let update = latest else { return topic }
        return topic.applying(update: update)
    }

    @discardableResult mutating func finishRead(
        _ read: Read,
        topic: ForumTopic?,
        source: TdUpdateSource?,
    ) -> ForumTopic? {
        guard permits(source), readID == read.id else { return nil }
        readID = nil
        guard let topic, matches(topic) else { return nil }
        if revision == read.revision { latest = Self.payload(topic) }
        return applyingLatest(to: topic)
    }

    mutating func retire() {
        retired = true
        latest = nil
        readID = nil
    }

    private func permits(_ source: TdUpdateSource?) -> Bool {
        !retired && (location.forumTopicID ?? 0) > 0 && source?.matches(location) == true
    }

    private func matches(_ topic: ForumTopic) -> Bool {
        topic.info.chatId == location.chatID && topic.info.forumTopicId == location.forumTopicID
    }
}

extension ForumTopic {
    func applying(update: UpdateForumTopic) -> ForumTopic {
        guard info.chatId == update.chatId, info.forumTopicId == update.forumTopicId else { return self }
        return ForumTopic(
            draftMessage: update.draftMessage, info: info, isPinned: update.isPinned,
            lastMessage: lastMessage, lastReadInboxMessageId: update.lastReadInboxMessageId,
            lastReadOutboxMessageId: update.lastReadOutboxMessageId, notificationSettings: update.notificationSettings,
            order: order, unreadCount: unreadCount, unreadMentionCount: update.unreadMentionCount,
            unreadPollVoteCount: update.unreadPollVoteCount, unreadReactionCount: update.unreadReactionCount,
        )
    }

    var updatePayload: UpdateForumTopic {
        UpdateForumTopic(
            chatId: info.chatId, draftMessage: draftMessage, forumTopicId: info.forumTopicId,
            isPinned: isPinned, lastReadInboxMessageId: lastReadInboxMessageId,
            lastReadOutboxMessageId: lastReadOutboxMessageId, notificationSettings: notificationSettings,
            unreadMentionCount: unreadMentionCount, unreadPollVoteCount: unreadPollVoteCount,
            unreadReactionCount: unreadReactionCount,
        )
    }
}

extension ForumTopicInfo {
    /// TDLib hides only General, which Telegram keeps above the topic list (ChatListNodeEntries, the hidden General
    /// thread); any other hidden topic leaves the list.
    var leavesTopicList: Bool {
        isHidden && !isGeneral
    }
}

// MARK: - ForumTopicPinnedOrder

/// Only a server head supplies pin positions. Unknown/new pins keep ordinary
/// chronology until the head read a pin change requests; membership is not a rank.
struct ForumTopicPinnedOrder {
    private(set) var ids = [Int]()
    private(set) var revision = UInt64.zero

    private var changedAt = [Int: UInt64]()

    init(ids: [Int] = []) {
        var seen = Set<Int>()
        self.ids = ids.filter { $0 > 0 && seen.insert($0).inserted }
    }

    mutating func reset(keepingRanks: Bool) {
        if !keepingRanks { ids.removeAll() }
        changedAt.removeAll()
    }

    /// Returns whether the pin changed; the caller re-reads the head for the new rank.
    @discardableResult mutating func observeMembership(id: Int, previous: Bool?, pinned: Bool) -> Bool {
        guard id > 0, let previous, previous != pinned else { return false }
        revision &+= 1
        changedAt[id] = revision
        ids.removeAll { $0 == id }
        return true
    }

    mutating func acceptHead(_ raw: [ForumTopic], eligible: Set<Int>, chatID: Int64, after version: UInt64) {
        var seen = Set<Int>()
        ids = raw.compactMap { topic in
            let id = topic.info.forumTopicId
            guard topic.info.chatId == chatID, id > 0, topic.isPinned, !topic.info.isHidden,
                  eligible.contains(id), (changedAt[id] ?? 0) <= version,
                  seen.insert(id).inserted else { return nil }
            return id
        }
    }

    func applying(to chronological: [ForumTopic]) -> [ForumTopic] {
        let byID = Dictionary(uniqueKeysWithValues: chronological.map { ($0.info.forumTopicId, $0) })
        // A hidden General sits above everything, pins included, revealed by pulling the list down.
        let hidden = chronological.filter(\.info.isHidden)
        let pinned = ids.compactMap { id in
            byID[id].flatMap { $0.isPinned && !$0.info.isHidden ? $0 : nil }
        }
        let placed = Set((hidden + pinned).map(\.info.forumTopicId))
        return hidden + pinned + chronological.filter { !placed.contains($0.info.forumTopicId) }
    }
}

// MARK: - ForumTopicPageState

enum ForumTopicPageState {
    static func merging(
        existing: [ForumTopic],
        incoming: [ForumTopic],
    ) -> [ForumTopic] {
        var byID = Dictionary(uniqueKeysWithValues: existing.map {
            ($0.info.forumTopicId, $0)
        })
        for topic in incoming {
            byID[topic.info.forumTopicId] =
                if topic.info.leavesTopicList {
                    nil
                } else {
                    topic
                }
        }
        return byID.values.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order > rhs.order
            }
            return lhs.info.forumTopicId < rhs.info.forumTopicId
        }
    }

    static func hasMore(
        response: ForumTopics,
        requestedCursor: ForumTopicPageCursor,
    ) -> Bool {
        let nextCursor = ForumTopicPageCursor(response: response)
        return !response.topics.isEmpty
            && nextCursor != .zero
            && nextCursor != requestedCursor
    }
}

// ForumTopicState.swift

import Foundation
import TDLibKitDynamic

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
        return ForumTopic(
            draftMessage: update.draftMessage, info: topic.info, isPinned: update.isPinned,
            lastMessage: topic.lastMessage, lastReadInboxMessageId: update.lastReadInboxMessageId,
            lastReadOutboxMessageId: update.lastReadOutboxMessageId, notificationSettings: update.notificationSettings,
            order: topic.order, unreadCount: topic.unreadCount, unreadMentionCount: update.unreadMentionCount,
            unreadPollVoteCount: update.unreadPollVoteCount, unreadReactionCount: update.unreadReactionCount,
        )
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
                if topic.info.isHidden {
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

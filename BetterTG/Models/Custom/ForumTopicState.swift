// ForumTopicState.swift

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

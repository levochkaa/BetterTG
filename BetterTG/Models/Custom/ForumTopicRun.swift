// ForumTopicRun.swift

import TDLibKitDynamic

// MARK: - ForumTopicRunHeaderID

struct ForumTopicRunHeaderID: Hashable {
    let topicID: Int
    let runStartMessageID: Int64
}

// MARK: - DisplayedMessageID

enum DisplayedMessageID: Hashable {
    case album(Int64)
    case message(Int64)
}

// MARK: - ChatTimelineItemID

enum ChatTimelineItemID: Hashable {
    case message(DisplayedMessageID)
    case topicHeader(ForumTopicRunHeaderID)

    var displayedMessageID: DisplayedMessageID? {
        guard case .message(let id) = self else { return nil }
        return id
    }
}

// MARK: - ForumTopicTimelineProjection

@MainActor enum ForumTopicTimelineProjection {
    static func items(
        messages: [CustomMessage],
        includesTopicHeaders: Bool,
    ) -> [ChatTimelineItemID] {
        guard includesTopicHeaders else {
            return messages.map { .message($0.displayedID) }
        }
        var result = [ChatTimelineItemID]()
        result.reserveCapacity(messages.count * 2)
        for index in messages.indices {
            let message = messages[index]
            result.append(.message(message.displayedID))
            guard let topicID = message.forumTopicID else { continue }
            let olderTopicID = messages.indices.contains(index + 1)
                ? messages[index + 1].forumTopicID
                : nil
            if olderTopicID != topicID {
                result.append(.topicHeader(ForumTopicRunHeaderID(
                    topicID: topicID,
                    runStartMessageID: message.oldestSourceMessageID,
                )))
            }
        }
        return result
    }
}

extension CustomMessage {
    var displayedID: DisplayedMessageID {
        message.mediaAlbumId == 0
            ? .message(id)
            : .album(message.mediaAlbumId.rawValue)
    }

    var oldestSourceMessageID: Int64 {
        sourceMessages.min { lhs, rhs in
            lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date < rhs.date
        }?.id ?? id
    }

    var newestSourceMessage: Message {
        sourceMessages.max { lhs, rhs in
            lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date < rhs.date
        } ?? message
    }

    var forumTopicID: Int? {
        let topicIDs = Set(sourceMessages.compactMap { message -> Int? in
            if case .messageTopicForum(let topic) = message.topicId {
                topic.forumTopicId
            } else {
                nil
            }
        })
        assert(topicIDs.count <= 1, "A media album must not span forum topics")
        return topicIDs.first
    }

    var sourceMessages: [Message] {
        if album.isEmpty {
            [message]
        } else if album.contains(where: { $0.id == message.id }) {
            album
        } else {
            [message] + album
        }
    }
}

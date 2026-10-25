// ForumTopicRun.swift

import Foundation
import TDLibKit

// MARK: - ForumTopicRunHeaderID

struct ForumTopicRunHeaderID: Hashable {
    let topicID: Int
    let runStartMessageID: Int64
}

// MARK: - ChatDateHeaderID

struct ChatDateHeaderID: Hashable {
    let dayTimestamp: Int
}

// MARK: - DisplayedMessageID

enum DisplayedMessageID: Hashable {
    case album(Int64)
    case message(Int64)
}

// MARK: - ChatTimelineItemID

enum ChatTimelineItemID: Hashable {
    case dateHeader(ChatDateHeaderID)
    case message(DisplayedMessageID)
    case topicHeader(ForumTopicRunHeaderID)
    /// Telegram's ChatReplyCountItem, between a reply thread's root and its first reply.
    case threadStart
    /// Telegram's ChatBotInfoItem, above a bot chat's first message once the history reaches its start.
    case botInfo
    /// Telegram's ChatUnreadItem, above the first message that was unread when the chat opened.
    case unreadDivider
    /// A channel's sponsored message by its TDLib identifier: after the newest message, or after the message
    /// ChatHistoryListNode placed it at (ChatHistoryEntriesForView's `adMessage` and `dynamicAdMessages`).
    case sponsored(Int64)

    var displayedMessageID: DisplayedMessageID? {
        guard case .message(let id) = self else { return nil }
        return id
    }
}

// MARK: - ChatTimelineProjection

@MainActor enum ChatTimelineProjection {
    static func items(
        messages: [CustomMessage],
        includesTopicHeaders: Bool,
        threadHeadID: DisplayedMessageID? = nil,
        includesBotInfo: Bool = false,
        unreadAfterMessageID: Int64? = nil,
    ) -> [ChatTimelineItemID] {
        var result = [ChatTimelineItemID]()
        result.reserveCapacity(messages.count * (includesTopicHeaders ? 3 : 2))
        for index in messages.indices {
            let message = messages[index]
            // Rows run newest first: the notice goes just before the root, so it shows under it, as Telegram puts the
            // ReplyCountEntry right after the thread head (ChatHistoryEntriesForView).
            if message.displayedID == threadHeadID { result.append(.threadStart) }
            result.append(.message(message.displayedID))
            // ChatHistoryEntriesForView's UnreadEntry at the read state the chat opened with: above the oldest
            // message past it, whose older neighbour (if loaded) was read.
            if let lastRead = unreadAfterMessageID, message.newestSourceMessage.id > lastRead,
               messages.indices.contains(index + 1), messages[index + 1].newestSourceMessage.id <= lastRead
            {
                result.append(.unreadDivider)
            }
            if includesTopicHeaders, let topicID = message.forumTopicID {
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
            let dayTimestamp = message.dayTimestamp
            let olderDayTimestamp = messages.indices.contains(index + 1)
                ? messages[index + 1].dayTimestamp
                : nil
            if olderDayTimestamp != dayTimestamp {
                result.append(.dateHeader(ChatDateHeaderID(dayTimestamp: dayTimestamp)))
            }
        }
        // Rows run newest first, so the last row shows at the top, above the first message's date
        // (ChatHistoryEntriesForView inserts the ChatInfoEntry at index 0).
        if includesBotInfo { result.append(.botInfo) }
        return result
    }
}

extension CustomMessage {
    var displayedID: DisplayedMessageID {
        if message.mediaAlbumId == 0 {
            .message(id)
        } else {
            .album(message.mediaAlbumId)
        }
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

    var dayTimestamp: Int {
        Int(Calendar.autoupdatingCurrent.startOfDay(for: date).timeIntervalSince1970)
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

// ChatVM+UnreadJumps.swift

import Foundation
import TDLibKit

/// Telegram's mention and reaction navigation buttons (ChatHistoryNavigationButtons): TDLib reads a message's mention
/// and reactions when it is viewed in the chat, so the counts fall as the user reaches them; the buttons jump to the
/// earliest unread one, and their menus clear the rest.
extension ChatVM {
    var unreadMentionCount: Int {
        if location.forumTopicID != nil {
            forumTopic?.unreadMentionCount ?? 0
        } else if location.isTopicScoped {
            0
        } else {
            chatUnreadMentionCount
        }
    }

    var unreadReactionCount: Int {
        if location.forumTopicID != nil {
            forumTopic?.unreadReactionCount ?? 0
        } else if location.isTopicScoped {
            0
        } else {
            chatUnreadReactionCount
        }
    }

    var unreadPollVoteCount: Int {
        #if DEBUG
            // `-ui-probe-poll-votes-button`: three unread poll votes, to look at the button.
            if ProcessInfo.processInfo.arguments.contains("-ui-probe-poll-votes-button") { return 3 }
        #endif
        if location.forumTopicID != nil { return forumTopic?.unreadPollVoteCount ?? 0 }
        return location.isTopicScoped ? 0 : chatUnreadPollVoteCount
    }

    /// The navigation buttons' kinds of unread messages.
    enum UnreadJumpKind {
        case mention
        case reaction
        case pollVote
    }

    /// `earliestUnseenPersonalMentionMessage`, `earliestUnseenPersonalReactionMessage` and
    /// `earliestUnseenPollVoteMessage`: the oldest of the newest hundred unread ones in this chat or forum topic.
    func earliestUnreadMessageID(_ kind: UnreadJumpKind) async -> Int64? {
        guard location.messageThreadID == nil, locationContextIsCurrent else { return nil }
        let client = client
        let topic = location.forumTopicID.map { MessageTopic.messageTopicForum(MessageTopicForum(forumTopicId: $0)) }
        let filter: SearchMessagesFilter =
            switch kind {
            case .mention: .searchMessagesFilterUnreadMention
            case .reaction: .searchMessagesFilterUnreadReaction
            case .pollVote: .searchMessagesFilterUnreadPollVote
            }
        guard let found = try? await client.searchChatMessages(
            chatId: chatID,
            filter: filter,
            fromMessageId: 0,
            limit: 100,
            offset: 0,
            query: "",
            senderId: nil,
            topicId: topic,
        ), locationContextIsCurrent else { return nil }
        return found.messages.map(\.id).min()
    }

    /// The poll votes button's Read All Poll Votes (`clearPeerUnseenReactionsAndPollVotesInteractively`).
    func readAllPollVotes() {
        guard location.messageThreadID == nil, locationContextIsCurrent else { return }
        let client = client
        let chatID = chatID
        let forumTopicID = location.forumTopicID
        Task {
            _ =
                if let forumTopicID {
                    try? await client.send(
                        TDNativeRequests.readAllForumTopicPollVotes(chatId: chatID, forumTopicId: forumTopicID),
                    )
                } else {
                    try? await client.send(TDNativeRequests.readAllChatPollVotes(chatId: chatID))
                }
        }
    }

    /// The mentions button's Clear (`clearPeerUnseenPersonalMessagesInteractively`).
    func readAllMentions() {
        guard location.messageThreadID == nil, locationContextIsCurrent else { return }
        let client = client
        let chatID = chatID
        let forumTopicID = location.forumTopicID
        Task {
            _ =
                if let forumTopicID {
                    try? await client.send(
                        TDNativeRequests.readAllForumTopicMentions(chatId: chatID, forumTopicId: forumTopicID),
                    )
                } else {
                    try? await client.send(TDNativeRequests.readAllChatMentions(chatId: chatID))
                }
        }
    }
}

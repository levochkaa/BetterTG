// ChatLocation.swift

import Foundation
import TDLibKit

struct ChatLocation: Hashable {
    let accountID: UUID?
    let chatID: Int64
    let clientID: Int32
    let topic: MessageTopic?

    var forumTopicID: Int? {
        if case .messageTopicForum(let forumTopic) = topic {
            forumTopic.forumTopicId
        } else {
            nil
        }
    }

    /// A reply thread of a non-forum supergroup, Telegram's `ChatLocation.replyThread`: a channel post's comments
    /// in its discussion group, or the replies to a group message. The identifier is the thread's root message.
    var messageThreadID: Int64? {
        if case .messageTopicThread(let thread) = topic {
            thread.messageThreadId
        } else {
            nil
        }
    }

    var isTopicScoped: Bool {
        topic != nil
    }

    /// The account comes from the same published snapshot as the active client. During an account switch the
    /// selected account changes before TDLibKit 2 has created its client, so pairing `activeAccountID` with the
    /// client would mix two epochs; a client that is not the active one gets no account.
    @MainActor static func current(
        chatID: Int64,
        topic: MessageTopic? = nil,
        client: TDLibClient = TDLib.shared.activeClient,
    ) -> ChatLocation {
        let source = TDLib.shared.activeUpdateSource
        return ChatLocation(
            accountID: source?.clientID == client.id ? source?.accountID : nil,
            chatID: chatID,
            clientID: client.id,
            topic: topic,
        )
    }

    func withForumTopic(id: Int) -> ChatLocation {
        ChatLocation(
            accountID: accountID,
            chatID: chatID,
            clientID: clientID,
            topic: .messageTopicForum(MessageTopicForum(forumTopicId: id)),
        )
    }

    func withMessageThread(chatID: Int64, id: Int64) -> ChatLocation {
        ChatLocation(
            accountID: accountID,
            chatID: chatID,
            clientID: clientID,
            topic: .messageTopicThread(MessageTopicThread(messageThreadId: id)),
        )
    }

    func matches(message: Message) -> Bool {
        guard message.chatId == chatID else { return false }
        guard let topic else { return true }
        return message.topicId == topic
    }
}

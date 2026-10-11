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

    func matches(message: Message) -> Bool {
        guard message.chatId == chatID else { return false }
        guard let topic else { return true }
        return message.topicId == topic
    }
}

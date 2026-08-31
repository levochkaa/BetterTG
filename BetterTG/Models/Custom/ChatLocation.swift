// ChatLocation.swift

import Foundation
import TDLibKitDynamic

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

    @MainActor static func current(
        chatID: Int64,
        topic: MessageTopic? = nil,
        client: TDLibClient = TDLib.shared.activeClient,
    ) -> ChatLocation {
        ChatLocation(
            accountID: TDLib.shared.activeAccountID,
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
            topic: .messageTopicForum(.init(forumTopicId: id)),
        )
    }

    func matches(message: Message) -> Bool {
        guard message.chatId == chatID else { return false }
        guard let topic else { return true }
        return message.topicId == topic
    }
}

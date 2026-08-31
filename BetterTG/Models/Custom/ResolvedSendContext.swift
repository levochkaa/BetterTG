// ResolvedSendContext.swift

import Foundation
import TDLibKitDynamic

// MARK: - ChatSendContentKind

enum ChatSendContentKind {
    case photo
    case text
    case videoNote
    case voiceNote
}

// MARK: - ResolvedSendContext

struct ResolvedSendContext {
    let accountID: UUID
    let chatID: Int64
    let clientID: Int32
    let destinationTopic: MessageTopic?
    let draftTopic: MessageTopic?
    let replyTo: InputMessageReplyTo?

    var draftKey: ChatDraftKey {
        ChatDraftKey(
            accountID: accountID,
            chatID: chatID,
            topic: draftTopic,
        )
    }

    func matches(message: Message) -> Bool {
        message.chatId == chatID && message.topicId == destinationTopic
    }
}

// MARK: - ChatSendContextError

enum ChatSendContextError: LocalizedError {
    case accountUnavailable
    case chatPermissionDenied
    case crossTopicReply
    case forumTopicRequired
    case partialAlbum(sent: Int, expected: Int)
    case topicMetadataUnavailable
    case topicReadOnly
    case unexpectedDestination

    var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            "The active Telegram account changed."
        case .chatPermissionDenied:
            "You can't send this kind of message in the chat."
        case .crossTopicReply:
            "Open the replied message's topic before replying."
        case .forumTopicRequired:
            "Choose a forum topic before sending."
        case .partialAlbum(let sent, let expected):
            "Telegram accepted \(sent) of \(expected) photos. The selection was kept to avoid losing anything."
        case .topicMetadataUnavailable:
            "The topic couldn't be checked yet."
        case .topicReadOnly:
            "Only the topic creator or an administrator can post in this closed topic."
        case .unexpectedDestination:
            "Telegram returned the message in a different topic."
        }
    }
}

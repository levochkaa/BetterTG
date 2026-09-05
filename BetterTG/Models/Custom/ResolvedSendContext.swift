// ResolvedSendContext.swift

import Foundation
import TDLibKit

// MARK: - ChatSendContentKind

enum ChatSendContentKind {
    case animation
    case document
    case photo
    case sticker
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
    var allowsSavedMessagesTopic = false

    var draftKey: ChatDraftKey {
        ChatDraftKey(
            accountID: accountID,
            chatID: chatID,
            topic: draftTopic,
        )
    }

    func matches(message: Message) -> Bool {
        guard message.chatId == chatID else { return false }
        if message.topicId == destinationTopic { return true }
        // TDLib assigns a Saved Messages topic even when sendMessage was called
        // from the unscoped self chat. This is an accepted send, not a retry.
        if destinationTopic == nil, allowsSavedMessagesTopic,
           case .messageTopicSavedMessages = message.topicId { return true }
        return false
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
            "Telegram accepted \(sent) of \(expected) attachments. The selection was kept to avoid losing anything."
        case .topicMetadataUnavailable:
            "The topic couldn't be checked yet."
        case .topicReadOnly:
            "Only the topic creator or an administrator can post in this closed topic."
        case .unexpectedDestination:
            "Telegram returned the message in a different topic."
        }
    }
}

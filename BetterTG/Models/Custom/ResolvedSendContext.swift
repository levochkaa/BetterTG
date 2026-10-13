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
    case video
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
            L10n.betterTG("Error.AccountChanged")
        case .chatPermissionDenied:
            L10n.betterTG("Composer.MessageTypeNotAllowed")
        case .crossTopicReply:
            L10n.betterTG("Composer.CrossTopicReply")
        case .forumTopicRequired:
            L10n.betterTG("Composer.ChooseTopic")
        case .partialAlbum(let sent, let expected):
            L10n.betterTG("Composer.PartialAlbum", sent, expected)
        case .topicMetadataUnavailable:
            L10n.betterTG("Composer.TopicCheckPending")
        case .topicReadOnly:
            L10n.betterTG("Composer.ClosedTopicPostRestriction")
        case .unexpectedDestination:
            L10n.betterTG("Composer.UnexpectedTopic")
        }
    }
}

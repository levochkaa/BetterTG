// MessageForwardingService.swift

import Foundation
import TDLibKitDynamic

// MARK: - MessageForwardRequest

struct MessageForwardRequest: Equatable {
    let sourceChatID: Int64
    let messageIDs: [Int64]

    init(sourceChatID: Int64, messageIDs: [Int64]) throws {
        let normalizedIDs = Array(Set(messageIDs)).sorted()
        guard !normalizedIDs.isEmpty else {
            throw MessageForwardingError.emptySelection
        }
        guard normalizedIDs.count <= 100 else {
            throw MessageForwardingError.tooManyMessages(normalizedIDs.count)
        }
        self.sourceChatID = sourceChatID
        self.messageIDs = normalizedIDs
    }
}

// MARK: - MessageForwardMode

enum MessageForwardMode: Equatable {
    case copy(removeCaption: Bool)
    case forward

    var removesSender: Bool {
        if case .copy = self {
            true
        } else {
            false
        }
    }

    var removesCaption: Bool {
        if case .copy(let removeCaption) = self {
            removeCaption
        } else {
            false
        }
    }
}

// MARK: - PreparedMessageForward

struct PreparedMessageForward: Equatable {
    let request: MessageForwardRequest
    let canForward: Bool
    let canCopy: Bool
    let canCopyToSecretChat: Bool
    let contentRequirements: Set<MessageForwardContentRequirement>
    let hasCaptions: Bool

    var defaultMode: MessageForwardMode {
        canForward ? .forward : .copy(removeCaption: false)
    }

    func supports(_ mode: MessageForwardMode) -> Bool {
        switch mode {
        case .forward:
            canForward
        case .copy:
            canCopy
        }
    }
}

// MARK: - MessageForwardContentRequirement

enum MessageForwardContentRequirement: Hashable {
    case audio
    case basic
    case document
    case other
    case photo
    case poll
    case video
    case videoNote
    case voiceNote
}

// MARK: - MessageForwardDestinationEligibility

struct MessageForwardDestinationEligibility: Equatable {
    static let allowed = MessageForwardDestinationEligibility(
        isAllowed: true,
        reason: nil,
        forcedMode: nil,
    )

    let isAllowed: Bool
    let reason: String?
    let forcedMode: MessageForwardMode?
}

// MARK: - MessageForwardingError

enum MessageForwardingError: LocalizedError, Equatable {
    case accountChanged
    case destinationUnavailable(String)
    case emptySelection
    case excludedProduct
    case partialDelivery(sent: Int, expected: Int)
    case protectedMessages
    case tooManyMessages(Int)
    case unsupportedMode

    var errorDescription: String? {
        switch self {
        case .accountChanged:
            "The active Telegram account changed. Open Forward again in the current account."
        case .destinationUnavailable(let reason):
            reason
        case .emptySelection:
            "Select at least one message to forward."
        case .excludedProduct:
            "Paid media forwarding isn't supported."
        case .partialDelivery(let sent, let expected):
            "TDLib forwarded \(sent) of \(expected) selected messages."
        case .protectedMessages:
            "One or more selected messages can't be forwarded or copied."
        case .tooManyMessages(let count):
            "Select no more than 100 messages. \(count) are currently selected."
        case .unsupportedMode:
            "The selected messages don't support this forwarding option."
        }
    }
}

// MARK: - MessageForwardingService

@MainActor enum MessageForwardingService {
    static func prepare(
        request: MessageForwardRequest,
        client: TDLibClient,
    ) async throws -> PreparedMessageForward {
        var canForward = true
        var canCopy = true
        var canCopyToSecretChat = true
        var contentRequirements = Set<MessageForwardContentRequirement>()
        var hasCaptions = false
        for messageID in request.messageIDs {
            try Task.checkCancellation()
            async let properties = client.getMessageProperties(
                chatId: request.sourceChatID,
                messageId: messageID,
            )
            async let message = client.getMessage(
                chatId: request.sourceChatID,
                messageId: messageID,
            )
            let (resolvedProperties, resolvedMessage) = try await (properties, message)
            if case .messagePaidMedia = resolvedMessage.content {
                throw MessageForwardingError.excludedProduct
            }
            canForward = canForward && resolvedProperties.canBeForwarded
            canCopy = canCopy && resolvedProperties.canBeCopied
            canCopyToSecretChat = canCopyToSecretChat && resolvedProperties.canBeCopiedToSecretChat
            contentRequirements.insert(requirement(for: resolvedMessage.content))
            hasCaptions = hasCaptions || contentHasCaption(resolvedMessage.content)
        }
        guard canForward || canCopy else {
            throw MessageForwardingError.protectedMessages
        }
        return PreparedMessageForward(
            request: request,
            canForward: canForward,
            canCopy: canCopy,
            canCopyToSecretChat: canCopyToSecretChat,
            contentRequirements: contentRequirements,
            hasCaptions: hasCaptions,
        )
    }

    static func eligibility(
        of chat: Chat,
        for prepared: PreparedMessageForward,
        client: TDLibClient,
    ) async -> MessageForwardDestinationEligibility {
        let localEligibility = localEligibility(of: chat, for: prepared)
        guard localEligibility.isAllowed else {
            return localEligibility
        }

        if case .chatTypeSupergroup(let supergroupChat) = chat.type {
            do {
                let supergroup = try await client.getSupergroup(
                    supergroupId: supergroupChat.supergroupId,
                )
                if supergroup.isForum {
                    return unavailable("Choose a forum topic before forwarding.")
                }
            } catch {
                return unavailable("This chat couldn't be checked.")
            }
        }

        if case .chatTypePrivate(let privateChat) = chat.type {
            do {
                switch try await client.canSendMessageToUser(onlyLocal: false, userId: privateChat.userId) {
                case .canSendMessageToUserResultOk:
                    break
                case .canSendMessageToUserResultUserHasPaidMessages:
                    return unavailable("Paid messages aren't supported.")
                case .canSendMessageToUserResultUserIsDeleted:
                    return unavailable("This user is no longer available.")
                case .canSendMessageToUserResultUserRestrictsNewChats:
                    return unavailable("This user doesn't accept new chats.")
                }
            } catch {
                return unavailable("This chat couldn't be checked.")
            }
        }
        return localEligibility
    }

    static func localEligibility(
        of chat: Chat,
        for prepared: PreparedMessageForward,
    ) -> MessageForwardDestinationEligibility {
        if chat.viewAsTopics {
            return unavailable("Choose a topic before forwarding.")
        }
        if case .chatTypeSecret = chat.type {
            guard prepared.canCopyToSecretChat else {
                return unavailable("One or more selected messages can't be copied to a Secret Chat.")
            }
            return MessageForwardDestinationEligibility(
                isAllowed: true,
                reason: nil,
                forcedMode: .copy(removeCaption: false),
            )
        }
        let permissions = chat.permissions
        for requirement in prepared.contentRequirements {
            let allowed =
                switch requirement {
                case .audio: permissions.canSendAudios
                case .basic: permissions.canSendBasicMessages
                case .document: permissions.canSendDocuments
                case .other: permissions.canSendOtherMessages
                case .photo: permissions.canSendPhotos
                case .poll: permissions.canSendPolls
                case .video: permissions.canSendVideos
                case .videoNote: permissions.canSendVideoNotes
                case .voiceNote: permissions.canSendVoiceNotes
                }
            if !allowed {
                return unavailable("You don't have permission to send this message type here.")
            }
        }
        return .allowed
    }

    @discardableResult static func send(
        _ prepared: PreparedMessageForward,
        to destinationChatID: Int64,
        mode: MessageForwardMode,
        client: TDLibClient,
        accountID: UUID,
    ) async throws -> Int {
        guard prepared.supports(mode) else {
            throw MessageForwardingError.unsupportedMode
        }
        guard TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else {
            throw MessageForwardingError.accountChanged
        }
        try Task.checkCancellation()
        let destination = try await client.getChat(chatId: destinationChatID)
        let eligibility = await eligibility(of: destination, for: prepared, client: client)
        guard eligibility.isAllowed else {
            throw MessageForwardingError.destinationUnavailable(
                eligibility.reason ?? "This chat can't receive the selected messages.",
            )
        }
        let effectiveMode =
            if eligibility.forcedMode != nil {
                MessageForwardMode.copy(removeCaption: mode.removesCaption)
            } else {
                mode
            }
        let supportsEffectiveMode =
            if case .chatTypeSecret = destination.type {
                prepared.canCopyToSecretChat
            } else {
                prepared.supports(effectiveMode)
            }
        guard supportsEffectiveMode else {
            throw MessageForwardingError.unsupportedMode
        }
        guard TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else {
            throw MessageForwardingError.accountChanged
        }
        let result = try await client.forwardMessages(
            chatId: destinationChatID,
            fromChatId: prepared.request.sourceChatID,
            messageIds: prepared.request.messageIDs,
            options: nil,
            removeCaption: effectiveMode.removesCaption,
            sendCopy: effectiveMode.removesSender,
            topicId: nil,
        )
        let sentCount = result.messages?.count ?? 0
        guard sentCount == prepared.request.messageIDs.count else {
            throw MessageForwardingError.partialDelivery(
                sent: sentCount,
                expected: prepared.request.messageIDs.count,
            )
        }
        return sentCount
    }

    private static func unavailable(_ reason: String) -> MessageForwardDestinationEligibility {
        MessageForwardDestinationEligibility(
            isAllowed: false,
            reason: reason,
            forcedMode: nil,
        )
    }

    private static func requirement(for content: MessageContent) -> MessageForwardContentRequirement {
        switch content {
        case .messageAnimatedEmoji, .messageAnimation, .messageDice, .messageGame, .messageStakeDice,
             .messageSticker:
            .other
        case .messageAudio:
            .audio
        case .messageDocument:
            .document
        case .messagePhoto:
            .photo
        case .messageChecklist, .messagePoll:
            .poll
        case .messageVideo:
            .video
        case .messageVideoNote:
            .videoNote
        case .messageVoiceNote:
            .voiceNote
        default:
            .basic
        }
    }

    private static func contentHasCaption(_ content: MessageContent) -> Bool {
        switch content {
        case .messageAnimation(let animation):
            !animation.caption.text.isEmpty
        case .messageAudio(let audio):
            !audio.caption.text.isEmpty
        case .messageDocument(let document):
            !document.caption.text.isEmpty
        case .messagePaidMedia(let media):
            !media.caption.text.isEmpty
        case .messagePhoto(let photo):
            !photo.caption.text.isEmpty
        case .messageVideo(let video):
            !video.caption.text.isEmpty
        case .messageVoiceNote(let voiceNote):
            !voiceNote.caption.text.isEmpty
        default:
            false
        }
    }
}

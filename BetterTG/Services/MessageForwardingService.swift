// MessageForwardingService.swift

import Foundation
import TDLibKit

// MARK: - MessageForwardRequest

struct MessageForwardRequest: Equatable {
    let sourceLocation: ChatLocation?
    let messageIDs: [Int64]

    private let legacySourceChatID: Int64

    var sourceChatID: Int64 {
        sourceLocation?.chatID ?? legacySourceChatID
    }

    init(sourceChatID: Int64, messageIDs: [Int64]) throws {
        try self.init(
            sourceLocation: nil,
            legacySourceChatID: sourceChatID,
            messageIDs: messageIDs,
        )
    }

    init(sourceLocation: ChatLocation, messageIDs: [Int64]) throws {
        try self.init(
            sourceLocation: sourceLocation,
            legacySourceChatID: sourceLocation.chatID,
            messageIDs: messageIDs,
        )
    }

    private init(
        sourceLocation: ChatLocation?,
        legacySourceChatID: Int64,
        messageIDs: [Int64],
    ) throws {
        let normalizedIDs = Array(Set(messageIDs)).sorted()
        guard !normalizedIDs.isEmpty else {
            throw MessageForwardingError.emptySelection
        }
        guard normalizedIDs.count <= 100 else {
            throw MessageForwardingError.tooManyMessages(normalizedIDs.count)
        }
        self.sourceLocation = sourceLocation
        self.legacySourceChatID = legacySourceChatID
        self.messageIDs = normalizedIDs
    }
}

// MARK: - MessageForwardDestination

struct MessageForwardDestination: Hashable {
    let chatID: Int64
    let topic: MessageTopic?

    var forumTopicID: Int? {
        if case .messageTopicForum(let topic) = topic {
            topic.forumTopicId
        } else {
            nil
        }
    }

    /// TDLib files a message sent to the unscoped self chat under a Saved Messages topic; that is the
    /// requested destination, as in a regular send.
    @MainActor func accepts(_ message: Message) -> Bool {
        guard message.chatId == chatID else { return false }
        if message.topicId == topic { return true }
        guard topic == nil, chatID == TDLib.shared.activeAccount?.userID else { return false }
        if case .messageTopicSavedMessages = message.topicId { return true }
        return false
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

// MARK: - PendingMessageForward

/// The destination composer owns this until the user sends or cancels it.
struct PendingMessageForward: Equatable {
    let id = UUID()
    let prepared: PreparedMessageForward
    let mode: MessageForwardMode
    let summary: String

    var title: String {
        prepared.request.messageIDs.count == 1
            ? L10n.telegram("Conversation.ForwardOptions.ForwardTitleSingle")
            : L10n.telegramPlural("Conversation.ForwardOptions.ForwardTitle", count: prepared.request.messageIDs.count)
    }

    /// The same forward through the account's renewed client. Message IDs belong to the account, so only the source
    /// location's client changes; another account's forward is dropped.
    func renewed(for destination: ChatLocation) -> PendingMessageForward? {
        guard let source = prepared.request.sourceLocation else { return self }
        guard let accountID = destination.accountID, source.accountID == accountID,
              let request = try? MessageForwardRequest(
                  sourceLocation: ChatLocation(
                      accountID: accountID, chatID: source.chatID, clientID: destination.clientID, topic: source.topic,
                  ),
                  messageIDs: prepared.request.messageIDs,
              ) else { return nil }
        return PendingMessageForward(
            prepared: PreparedMessageForward(
                request: request, canForward: prepared.canForward, canCopy: prepared.canCopy,
                canCopyToSecretChat: prepared.canCopyToSecretChat,
                contentRequirements: prepared.contentRequirements, hasCaptions: prepared.hasCaptions,
            ),
            mode: mode,
            summary: summary,
        )
    }
}

// MARK: - MessageForwardContentRequirement

enum MessageForwardContentRequirement: Hashable {
    case audio
    case basic
    /// A checklist; Telegram doesn't forward checklists to channels.
    case checklist
    case document
    case other
    case photo
    case poll
    /// A non-anonymous poll or quiz; Telegram doesn't forward public polls to channels.
    case publicPoll
    case video
    case videoNote
    case voiceNote
}

// MARK: - MessageForwardDestinationStanding

/// The user's own standing in a destination. Telegram's send check (`canSendMessagesToPeer`) needs it besides the
/// chat's default permissions: owners and admins aren't bound by the defaults, channels take posts only from admins
/// who may post, and a secret chat takes messages only once it is active.
enum MessageForwardDestinationStanding {
    case direct
    case group(MessageForwardGroupStanding)
    case secret(isReady: Bool)

    var isForum: Bool {
        if case .group(let group) = self {
            group.isForum
        } else {
            false
        }
    }
}

// MARK: - MessageForwardGroupStanding

struct MessageForwardGroupStanding {
    let status: ChatMemberStatus
    /// A channel or broadcast group.
    let isBroadcast: Bool
    let isForum: Bool
    /// Non-admin members pay Stars for each message, which BetterTG doesn't support.
    let chargesStars: Bool

    var canManageTopics: Bool {
        switch status {
        case .chatMemberStatusCreator:
            true
        case .chatMemberStatusAdministrator(let administrator):
            administrator.rights.canManageTopics
        default:
            false
        }
    }

    var paysForMessages: Bool {
        guard chargesStars else { return false }
        return switch status {
        case .chatMemberStatusAdministrator, .chatMemberStatusCreator:
            false
        default:
            true
        }
    }
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
    case sourceMismatch
    case tooManyMessages(Int)
    case unsupportedMode

    var errorDescription: String? {
        switch self {
        case .accountChanged:
            L10n.betterTG("Forward.AccountChanged")
        case .destinationUnavailable(let reason):
            reason
        case .emptySelection:
            L10n.betterTG("Forward.EmptySelection")
        case .excludedProduct:
            L10n.betterTG("Forward.PaidMediaUnsupported")
        case .partialDelivery(let sent, let expected):
            L10n.betterTG("Forward.PartialDelivery", sent, expected)
        case .protectedMessages:
            L10n.betterTG("Forward.ProtectedMessages")
        case .sourceMismatch:
            L10n.betterTG("Forward.SourceMismatch")
        case .tooManyMessages(let count):
            L10n.betterTG("Forward.TooManyMessages", count)
        case .unsupportedMode:
            L10n.betterTG("Forward.UnsupportedMode")
        }
    }
}

// MARK: - MessageForwardingService

@MainActor enum MessageForwardingService {
    static func prepare(
        request: MessageForwardRequest,
        client: TDLibClient,
    ) async throws -> PreparedMessageForward {
        if let sourceLocation = request.sourceLocation {
            guard TDLib.shared.activeAccountID == sourceLocation.accountID,
                  TDLib.shared.activeClient.id == sourceLocation.clientID,
                  client.id == sourceLocation.clientID
            else { throw MessageForwardingError.accountChanged }
        }
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
            if let sourceLocation = request.sourceLocation {
                guard TDLib.shared.activeAccountID == sourceLocation.accountID,
                      TDLib.shared.activeClient.id == sourceLocation.clientID,
                      client.id == sourceLocation.clientID
                else { throw MessageForwardingError.accountChanged }
                guard sourceLocation.matches(message: resolvedMessage) else {
                    throw MessageForwardingError.sourceMismatch
                }
            }
            if case .messagePaidMedia = resolvedMessage.content {
                throw MessageForwardingError.excludedProduct
            }
            canForward = canForward && resolvedProperties.canBeForwarded
            canCopy = canCopy && resolvedProperties.canBeCopied
            canCopyToSecretChat = canCopyToSecretChat && resolvedProperties.canBeCopiedToSecretChat
            contentRequirements.insert(requirement(for: resolvedMessage.content))
            switch resolvedMessage.content {
            case .messageChecklist:
                contentRequirements.insert(.checklist)
            case .messagePoll(let poll) where !poll.poll.isAnonymous:
                contentRequirements.insert(.publicPoll)
            default:
                break
            }
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

    /// The user's standing in `chat`, read from TDLib's local supergroup, basic group or secret chat.
    static func standing(
        of chat: Chat,
        client: TDLibClient,
    ) async throws -> MessageForwardDestinationStanding {
        switch chat.type {
        case .chatTypePrivate:
            return .direct
        case .chatTypeSecret(let secretChat):
            let secret = try await client.send(TDNativeRequests.getSecretChat(secretChatId: secretChat.secretChatId))
            if case .secretChatStateReady = secret.state {
                return .secret(isReady: true)
            }
            return .secret(isReady: false)
        case .chatTypeBasicGroup(let basicGroupChat):
            let group = try await client.getBasicGroup(basicGroupId: basicGroupChat.basicGroupId)
            return .group(MessageForwardGroupStanding(
                status: group.status, isBroadcast: false, isForum: false, chargesStars: false,
            ))
        case .chatTypeSupergroup(let supergroupChat):
            let group = try await client.getSupergroup(supergroupId: supergroupChat.supergroupId)
            return .group(MessageForwardGroupStanding(
                status: group.status,
                isBroadcast: group.isChannel || group.isBroadcastGroup,
                isForum: group.isForum,
                chargesStars: group.paidMessageStarCount > 0,
            ))
        }
    }

    static func localEligibility(
        of chat: Chat,
        standing: MessageForwardDestinationStanding,
        for prepared: PreparedMessageForward,
    ) -> MessageForwardDestinationEligibility {
        let requirements = prepared.contentRequirements
        switch standing {
        case .secret(let isReady):
            guard isReady else { return unavailable(L10n.betterTG("Forward.DestinationUnavailable")) }
            guard prepared.canCopyToSecretChat else {
                return unavailable(L10n.betterTG("Forward.SecretChatCopyUnavailable"))
            }
            return MessageForwardDestinationEligibility(
                isAllowed: true,
                reason: nil,
                forcedMode: .copy(removeCaption: false),
            )
        case .direct:
            for requirement in requirements where !chat.permissions[keyPath: permission(for: requirement)] {
                return unavailable(L10n.betterTG("Forward.NoPermission"))
            }
            return .allowed
        case .group(let group):
            // ChatControllerForwardMessages: public polls and checklists never go to a channel.
            if group.isBroadcast, requirements.contains(.publicPoll) {
                return unavailable(L10n.telegram("Forward.ErrorPublicPollDisabledInChannels"))
            }
            if group.isBroadcast, requirements.contains(.checklist) {
                return unavailable(L10n.telegram("Forward.ErrorTodoDisabledInChannels"))
            }
            if group.paysForMessages {
                return unavailable(L10n.betterTG("Forward.PaidMessagesUnsupported"))
            }
            for requirement in requirements {
                let allowed = CustomChat.allowsSending(
                    permission(for: requirement),
                    defaults: chat.permissions,
                    status: group.status,
                    postsOnly: group.isBroadcast,
                    joinToSend: true,
                )
                if !allowed {
                    return unavailable(L10n.betterTG("Forward.NoPermission"))
                }
            }
            return .allowed
        }
    }

    @discardableResult static func send(
        _ prepared: PreparedMessageForward,
        to destination: MessageForwardDestination,
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
        let destinationChat = try await client.getChat(chatId: destination.chatID)
        let eligibility = await eligibility(
            of: destinationChat,
            topic: destination.topic,
            for: prepared,
            client: client,
        )
        guard eligibility.isAllowed else {
            throw MessageForwardingError.destinationUnavailable(
                eligibility.reason ?? L10n.betterTG("Forward.ChatCantReceive"),
            )
        }
        let effectiveMode =
            if eligibility.forcedMode != nil {
                MessageForwardMode.copy(removeCaption: mode.removesCaption)
            } else {
                mode
            }
        let supportsEffectiveMode =
            if case .chatTypeSecret = destinationChat.type {
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
        if let sourceLocation = prepared.request.sourceLocation {
            for messageID in prepared.request.messageIDs {
                let message = try await client.getMessage(
                    chatId: sourceLocation.chatID,
                    messageId: messageID,
                )
                guard TDLib.shared.activeAccountID == sourceLocation.accountID,
                      TDLib.shared.activeClient.id == sourceLocation.clientID,
                      client.id == sourceLocation.clientID
                else { throw MessageForwardingError.accountChanged }
                guard sourceLocation.matches(message: message) else {
                    throw MessageForwardingError.sourceMismatch
                }
            }
        }
        let result = try await client.forwardMessages(
            chatId: destination.chatID,
            fromChatId: prepared.request.sourceChatID,
            messageIds: prepared.request.messageIDs,
            options: nil,
            removeCaption: effectiveMode.removesCaption,
            sendCopy: effectiveMode.removesSender,
            topicId: destination.topic,
        )
        let messages = result.messages
        let sentCount = messages.count
        guard sentCount == prepared.request.messageIDs.count else {
            throw MessageForwardingError.partialDelivery(
                sent: sentCount,
                expected: prepared.request.messageIDs.count,
            )
        }
        guard messages.allSatisfy({ destination.accepts($0) })
        else { throw MessageForwardingError.destinationUnavailable(L10n.betterTG("Forward.DifferentTopic")) }
        return sentCount
    }

    @discardableResult static func sendComment(
        _ comment: FormattedText,
        prepared: PreparedMessageForward,
        to destination: MessageForwardDestination,
        client: TDLibClient,
        accountID: UUID,
    ) async throws -> Message {
        guard !comment.text.isEmpty else {
            throw MessageForwardingError.emptySelection
        }
        guard TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else { throw MessageForwardingError.accountChanged }
        let destinationChat = try await client.getChat(chatId: destination.chatID)
        guard destinationChat.permissions.canSendBasicMessages else {
            throw MessageForwardingError.destinationUnavailable(L10n.betterTG("Forward.CommentNotAllowed"))
        }
        let commentPrepared = PreparedMessageForward(
            request: prepared.request,
            canForward: true,
            canCopy: true,
            canCopyToSecretChat: true,
            contentRequirements: [.basic],
            hasCaptions: false,
        )
        let commentEligibility = await eligibility(
            of: destinationChat,
            topic: destination.topic,
            for: commentPrepared,
            client: client,
        )
        guard commentEligibility.isAllowed else {
            throw MessageForwardingError.destinationUnavailable(
                commentEligibility.reason ?? L10n.betterTG("Forward.CommentDestinationUnavailable"),
            )
        }
        guard TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else { throw MessageForwardingError.accountChanged }
        let message = try await client.sendMessage(
            chatId: destination.chatID,
            inputMessageContent: .inputMessageText(InputMessageText(
                clearDraft: false,
                linkPreviewOptions: nil,
                text: comment,
            )),
            options: nil,
            replyMarkup: nil,
            replyTo: nil,
            topicId: destination.topic,
        )
        guard destination.accepts(message)
        else { throw MessageForwardingError.destinationUnavailable(L10n.betterTG("Forward.DifferentTopic")) }
        return message
    }

    static func eligibility(
        of chat: Chat,
        topic: MessageTopic?,
        for prepared: PreparedMessageForward,
        client: TDLibClient,
    ) async -> MessageForwardDestinationEligibility {
        let standing: MessageForwardDestinationStanding
        do {
            standing = try await self.standing(of: chat, client: client)
        } catch {
            return unavailable(L10n.betterTG("Forward.ChatCheckFailed"))
        }
        let localEligibility = localEligibility(of: chat, standing: standing, for: prepared)
        guard localEligibility.isAllowed else { return localEligibility }

        if case .group(let group) = standing, group.isForum {
            guard case .messageTopicForum(let forumTopic) = topic else {
                return unavailable(L10n.betterTG("Forward.ChooseTopic"))
            }
            do {
                let resolvedTopic = try await client.getForumTopic(
                    chatId: chat.id,
                    forumTopicId: forumTopic.forumTopicId,
                )
                let restricted = resolvedTopic.info.isClosed || resolvedTopic.info.isHidden
                guard !restricted || resolvedTopic.info.isOutgoing || group.canManageTopics else {
                    return unavailable(L10n.betterTG("Forward.TopicClosed"))
                }
            } catch {
                return unavailable(L10n.betterTG("Forward.ChatCheckFailed"))
            }
        } else if topic != nil {
            return unavailable(L10n.betterTG("Forward.TopicsUnsupported"))
        }

        if case .chatTypePrivate(let privateChat) = chat.type {
            do {
                switch try await client.canSendMessageToUser(onlyLocal: false, userId: privateChat.userId) {
                case .canSendMessageToUserResultOk:
                    break
                case .canSendMessageToUserResultUserHasPaidMessages:
                    return unavailable(L10n.betterTG("Forward.PaidMessagesUnsupported"))
                case .canSendMessageToUserResultUserIsDeleted:
                    return unavailable(L10n.betterTG("Forward.UserUnavailable"))
                case .canSendMessageToUserResultUserRestrictsNewChats:
                    return unavailable(L10n.betterTG("Forward.UserRestrictsNewChats"))
                }
            } catch {
                return unavailable(L10n.betterTG("Forward.ChatCheckFailed"))
            }
        }
        return localEligibility
    }

    private static func permission(
        for requirement: MessageForwardContentRequirement,
    ) -> KeyPath<ChatPermissions, Bool> {
        switch requirement {
        case .audio: \.canSendAudios
        case .basic: \.canSendBasicMessages
        case .document: \.canSendDocuments
        case .other: \.canSendOtherMessages
        case .photo: \.canSendPhotos
        case .checklist, .poll, .publicPoll: \.canSendPolls
        case .video: \.canSendVideos
        case .videoNote: \.canSendVideoNotes
        case .voiceNote: \.canSendVoiceNotes
        }
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

// MessageMetadataPresentation.swift

import Foundation
import TDLibKit

// MARK: - MessageQuoteHighlight

struct MessageQuoteHighlight: Hashable {
    let length: Int
    let position: Int
    /// Navigation looks the text up again in the current message, which an edit may have changed.
    let text: String

    init?(text: String, position: Int) {
        guard !text.isEmpty else { return nil }
        self.init(range: NSRange(location: max(0, position), length: text.utf16.count), text: text)
    }

    private init(range: NSRange, text: String) {
        self.length = range.length
        self.position = range.location
        self.text = text
    }

    private static func sourceText(for content: MessageContent) -> String? {
        switch content {
        case .messageText(let message):
            message.text.text
        case .messageAnimation(let message):
            message.caption.text
        case .messageAudio(let message):
            message.caption.text
        case .messageDocument(let message):
            message.caption.text
        case .messagePhoto(let message):
            message.caption.text
        case .messageVideo(let message):
            message.caption.text
        case .messageVoiceNote(let message):
            message.caption.text
        default:
            nil
        }
    }

    /// ChatMessageTextBubbleContentNode.findQuoteRange: the occurrence nearest the recorded position, or nil when the
    /// message no longer contains the quoted text.
    func resolved(in content: MessageContent) -> MessageQuoteHighlight? {
        guard let source = Self.sourceText(for: content) else { return nil }
        let string = source as NSString
        var nearest: NSRange?
        var start = 0
        while start < string.length {
            let range = string.range(of: text, range: NSRange(location: start, length: string.length - start))
            guard range.location != NSNotFound, range.length > 0 else { break }
            if let nearest, abs(range.location - position) > abs(nearest.location - position) { break }
            nearest = range
            start = NSMaxRange(range)
        }
        return nearest.map { MessageQuoteHighlight(range: $0, text: text) }
    }
}

// MARK: - MessageMetadataNavigationTarget

enum MessageMetadataNavigationTarget: Hashable {
    case chat(chatID: Int64)
    case message(chatID: Int64, messageID: Int64, quote: MessageQuoteHighlight?)
    case unavailable
    case user(userID: Int64)
}

// MARK: - MessageQuoteBuilder

enum MessageQuoteBuilder {
    static func make(
        from formattedText: FormattedText, maximumLength: Int, range selectedRange: NSRange? = nil,
    ) -> InputTextQuote? {
        let source = formattedText.text
        let totalLength = source.utf16.count
        let nativeText = source as NSString
        func isCharacterBoundary(_ offset: Int) -> Bool {
            offset == totalLength || nativeText.rangeOfComposedCharacterSequence(at: offset).location == offset
        }
        let requested = selectedRange ?? NSRange(location: 0, length: totalLength)
        guard requested.location != NSNotFound, requested.location >= 0,
              requested.length > 0, requested.location < totalLength,
              requested.length <= totalLength - requested.location,
              isCharacterBoundary(requested.location),
              isCharacterBoundary(NSMaxRange(requested))
        else { return nil }
        // trimStringWithEntities: spaces and line feeds around the selection are not quoted, before the length limit.
        func isTrimmed(_ offset: Int) -> Bool {
            let unit = nativeText.character(at: offset)
            return (unit == 0x20 || unit == 0x0A) && nativeText.rangeOfComposedCharacterSequence(at: offset).length == 1
        }
        var lowerBound = requested.location
        var upperBound = NSMaxRange(requested)
        while lowerBound < upperBound, isTrimmed(lowerBound) {
            lowerBound += 1
        }
        while upperBound > lowerBound, isTrimmed(upperBound - 1) {
            upperBound -= 1
        }
        guard upperBound > lowerBound else { return nil }
        var range = NSRange(location: lowerBound, length: min(max(1, maximumLength), upperBound - lowerBound))
        while range.length > 0, !isCharacterBoundary(NSMaxRange(range)) {
            range.length -= 1
        }
        guard range.length > 0 else { return nil }
        let entities = formattedText.entities.compactMap { entity -> TextEntity? in
            guard entity.offset >= 0, entity.length > 0, entity.offset <= totalLength,
                  entity.length <= totalLength - entity.offset, isAllowed(entity.type)
            else { return nil }
            let original = NSRange(location: entity.offset, length: entity.length)
            let overlap = NSIntersectionRange(range, original)
            guard overlap.length > 0 else { return nil }
            switch entity.type {
            case .textEntityTypeCustomEmoji, .textEntityTypeDateTime:
                guard overlap == original else { return nil }
            default: break
            }
            return TextEntity(length: overlap.length, offset: overlap.location - range.location, type: entity.type)
        }
        return InputTextQuote(
            position: range.location,
            text: FormattedText(entities: entities, text: nativeText.substring(with: range)),
        )
    }

    private static func isAllowed(_ type: TextEntityType) -> Bool {
        switch type {
        case .textEntityTypeBold, .textEntityTypeCustomEmoji, .textEntityTypeDateTime,
             .textEntityTypeItalic, .textEntityTypeSpoiler, .textEntityTypeStrikethrough,
             .textEntityTypeUnderline:
            true
        default:
            false
        }
    }
}

// MARK: - MessageReplyInputBuilder

enum MessageReplyInputBuilder {
    static func make(
        currentChatID: Int64,
        target: Message,
        override: InputMessageReplyTo?,
        quote: InputTextQuote?,
    ) -> InputMessageReplyTo {
        if let override {
            return override
        }
        if target.chatId == currentChatID {
            return .inputMessageReplyToMessage(InputMessageReplyToMessage(
                checklistTaskId: 0,
                messageId: target.id,
                pollOptionId: "",
                quote: quote,
            ))
        }
        return .inputMessageReplyToExternalMessage(InputMessageReplyToExternalMessage(
            chatId: target.chatId,
            checklistTaskId: 0,
            messageId: target.id,
            pollOptionId: "",
            quote: quote,
        ))
    }

    static func navigationTarget(
        for input: InputMessageReplyTo?,
        currentChatID: Int64,
    ) -> MessageMetadataNavigationTarget? {
        switch input {
        case .inputMessageReplyToMessage(let message):
            .message(
                chatID: currentChatID,
                messageID: message.messageId,
                quote: message.quote.flatMap { MessageQuoteHighlight(text: $0.text.text, position: $0.position) },
            )
        case .inputMessageReplyToExternalMessage(let message):
            .message(
                chatID: message.chatId,
                messageID: message.messageId,
                quote: message.quote.flatMap { MessageQuoteHighlight(text: $0.text.text, position: $0.position) },
            )
        case .inputMessageReplyToEphemeralMessage, .inputMessageReplyToStory:
            .unavailable
        case nil:
            nil
        }
    }
}

// MARK: - MessageMetadataAvatar

struct MessageMetadataAvatar: Equatable {
    let file: File?
    let initials: String
    let minithumbnailData: Data?
}

// MARK: - MessageReplyThumbnail

struct MessageReplyThumbnail: Equatable {
    let file: File
    let isRound: Bool
    let minithumbnailData: Data?

    static func make(for content: MessageContent) -> MessageReplyThumbnail? {
        switch content {
        case .messagePhoto(let message) where !message.isSecret && !message.hasSpoiler:
            guard let size = message.photo.sizes.getSize(.sBox) ?? message.photo.sizes.first else { return nil }
            return MessageReplyThumbnail(
                file: size.photo,
                isRound: false,
                minithumbnailData: message.photo.minithumbnail?.data,
            )
        case .messageAnimation(let message) where !message.isSecret && !message.hasSpoiler:
            guard let thumbnail = message.animation.thumbnail else { return nil }
            return MessageReplyThumbnail(
                file: thumbnail.file,
                isRound: false,
                minithumbnailData: message.animation.minithumbnail?.data,
            )
        case .messageAudio(let message):
            guard let thumbnail = message.audio.albumCoverThumbnail else { return nil }
            return MessageReplyThumbnail(
                file: thumbnail.file,
                isRound: false,
                minithumbnailData: message.audio.albumCoverMinithumbnail?.data,
            )
        case .messageDocument(let message):
            guard let thumbnail = message.document.thumbnail else { return nil }
            return MessageReplyThumbnail(
                file: thumbnail.file,
                isRound: false,
                minithumbnailData: message.document.minithumbnail?.data,
            )
        case .messageSticker(let message):
            guard let thumbnail = message.sticker.thumbnail else { return nil }
            return MessageReplyThumbnail(file: thumbnail.file, isRound: false, minithumbnailData: nil)
        case .messageVideo(let message) where !message.isSecret && !message.hasSpoiler:
            guard let thumbnail = message.video.thumbnail else { return nil }
            return MessageReplyThumbnail(
                file: thumbnail.file,
                isRound: false,
                minithumbnailData: message.video.minithumbnail?.data,
            )
        case .messageVideoNote(let message) where !message.isSecret:
            guard let thumbnail = message.videoNote.thumbnail else { return nil }
            return MessageReplyThumbnail(
                file: thumbnail.file,
                isRound: true,
                minithumbnailData: message.videoNote.minithumbnail?.data,
            )
        default:
            return nil
        }
    }
}

// MARK: - MessageReplyAvailability

enum MessageReplyAvailability: Equatable {
    case inline
    case resolved
    case story
    case unavailable
}

// MARK: - MessageReplyPresentation

struct MessageReplyPresentation: Equatable {
    let availability: MessageReplyAvailability
    let body: FormattedText
    let navigationTarget: MessageMetadataNavigationTarget?
    let quote: TextQuote?
    let referencedChatID: Int64?
    let referencedUserID: Int64?
    let targetChatID: Int64?
    let targetMessageID: Int64?
    let thumbnail: MessageReplyThumbnail?
    let title: String
    /// A reply to a checklist task shows the task's text after its check, done or not (ChatMessageReplyInfoNode).
    var checklistTaskIsDone: Bool?

    var isManualQuote: Bool { quote?.isManual == true }

    var quoteHighlight: MessageQuoteHighlight? {
        quote.flatMap { MessageQuoteHighlight(text: $0.text.text, position: $0.position) }
    }

    var accessibilityDescription: String {
        L10n.betterTG("Accessibility.ReplyFrom", title, MessageTextSpoilerPresentation(body).accessibilityText())
    }
}

extension MessageReplyPresentation {
    static func fallback(
        for input: InputMessageReplyTo,
        currentChatID: Int64,
    ) -> Self {
        let quote: InputTextQuote?
        let title: String
        let targetChatID: Int64?
        let targetMessageID: Int64?
        switch input {
        case .inputMessageReplyToMessage(let message):
            quote = message.quote
            title = L10n.betterTG("Chat.Reply")
            targetChatID = currentChatID
            targetMessageID = message.messageId
        case .inputMessageReplyToExternalMessage(let message):
            quote = message.quote
            title = L10n.betterTG("Chat.ExternalReply")
            targetChatID = message.chatId
            targetMessageID = message.messageId
        case .inputMessageReplyToStory(let story):
            quote = nil
            title = L10n.telegram("Message.Story")
            targetChatID = story.storyPosterChatId
            targetMessageID = nil
        case .inputMessageReplyToEphemeralMessage:
            quote = nil
            title = L10n.betterTG("Chat.EphemeralMessage")
            targetChatID = nil
            targetMessageID = nil
        }
        let textQuote = quote.map { TextQuote(isManual: true, position: $0.position, text: $0.text) }
        return Self(
            availability: quote == nil ? .unavailable : .inline,
            body: quote?.text ?? FormattedText(entities: [], text: L10n.betterTG("Chat.OriginalMessageUnavailable")),
            navigationTarget: .unavailable,
            quote: textQuote,
            referencedChatID: targetChatID,
            referencedUserID: nil,
            targetChatID: targetChatID,
            targetMessageID: targetMessageID,
            thumbnail: nil,
            title: title,
        )
    }
}

// MARK: - MessageForwardPresentation

struct MessageForwardPresentation: Equatable {
    let avatar: MessageMetadataAvatar?
    let headline: String
    let navigationTarget: MessageMetadataNavigationTarget?
    let originalSourceTitle: String
    let publicServiceAnnouncementType: String?
    let referencedChatIDs: Set<Int64>
    let referencedUserIDs: Set<Int64>
    let sourceTitle: String
    let targetChatID: Int64?
    let targetMessageID: Int64?

    var accessibilityDescription: String {
        L10n.telegram("VoiceOver.Chat.ForwardedFrom", sourceTitle)
    }

    func removingNavigationTarget() -> Self {
        Self(
            avatar: avatar,
            headline: headline,
            navigationTarget: nil,
            originalSourceTitle: originalSourceTitle,
            publicServiceAnnouncementType: publicServiceAnnouncementType,
            referencedChatIDs: referencedChatIDs,
            referencedUserIDs: referencedUserIDs,
            sourceTitle: sourceTitle,
            targetChatID: targetChatID,
            targetMessageID: targetMessageID,
        )
    }
}

// MARK: - MessageMetadataResolver

@MainActor final class MessageMetadataResolver {
    private struct ResolvedPeer {
        let avatar: MessageMetadataAvatar?
        let chatID: Int64?
        let navigationTarget: MessageMetadataNavigationTarget?
        let title: String
        let userID: Int64?
    }

    private let client: TDLibClient
    private var chats = [Int64: Chat]()
    private var missingChatIDs = Set<Int64>()
    private var missingUserIDs = Set<Int64>()
    private var users = [Int64: User]()

    init(client: TDLibClient) {
        self.client = client
    }

    func replyPresentation(for message: Message) async -> MessageReplyPresentation? {
        guard let replyTo = message.replyTo else { return nil }
        switch replyTo {
        case .messageReplyToMessage(let reply):
            return await messageReplyPresentation(reply, parent: message)
        case .messageReplyToStory(let story):
            let chat = await chat(id: story.storyPosterChatId)
            let title = nonEmpty(chat?.title) ?? L10n.telegram("Message.Story")
            return MessageReplyPresentation(
                availability: .story,
                body: plainText(L10n.telegram("Message.Story")),
                navigationTarget: .unavailable,
                quote: nil,
                referencedChatID: story.storyPosterChatId == 0 ? nil : story.storyPosterChatId,
                referencedUserID: nil,
                targetChatID: story.storyPosterChatId == 0 ? nil : story.storyPosterChatId,
                targetMessageID: nil,
                thumbnail: nil,
                title: title,
            )
        }
    }

    func forwardPresentation(for info: MessageForwardInfo?) async -> MessageForwardPresentation? {
        guard let info else { return nil }
        let origin = await resolve(origin: info.origin)
        let source: ResolvedPeer? =
            if let forwardSource = info.source {
                await resolve(source: forwardSource)
            } else {
                nil
            }
        let displayed = source ?? origin
        let sourceTitle =
            if let source, normalized(source.title) != normalized(origin.title) {
                "\(source.title) • \(origin.title)"
            } else {
                displayed.title
            }
        let navigationTarget =
            if info.source != nil {
                source?.navigationTarget
            } else {
                origin.navigationTarget
            }
        let psa = nonEmpty(info.publicServiceAnnouncementType)
        let peers = [source, origin].compactMap(\.self)
        let targetKey: (chatID: Int64?, messageID: Int64?) =
            if let navigationTarget, case .message(let chatID, let messageID, _) = navigationTarget {
                (chatID, messageID)
            } else {
                (nil, nil)
            }
        return MessageForwardPresentation(
            avatar: displayed.avatar,
            headline: psa == nil
                ? L10n.telegramPlural("ForwardedMessages", count: 1)
                : L10n.betterTG("Chat.PublicServiceAnnouncement"),
            navigationTarget: navigationTarget,
            originalSourceTitle: origin.title,
            publicServiceAnnouncementType: psa,
            referencedChatIDs: Set(peers.compactMap(\.chatID)),
            referencedUserIDs: Set(peers.compactMap(\.userID)),
            sourceTitle: sourceTitle,
            targetChatID: targetKey.chatID,
            targetMessageID: targetKey.messageID,
        )
    }

    func update(user: User) {
        users[user.id] = user
        missingUserIDs.remove(user.id)
    }

    func invalidateChat(id: Int64) {
        chats[id] = nil
        missingChatIDs.remove(id)
    }

    private func messageReplyPresentation(
        _ reply: MessageReplyToMessage,
        parent: Message,
    ) async -> MessageReplyPresentation {
        let declaredChatID: Int64? = reply.chatId == 0 ? nil : reply.chatId
        let target = await resolveTargetMessage(
            parent: parent,
            declaredChatID: declaredChatID,
            targetMessageID: reply.messageId,
        )
        let targetChatID = target?.chatId ?? declaredChatID
        let targetMessageID = target?.id ?? (reply.messageId == 0 ? nil : reply.messageId)
        let content = target?.content ?? reply.content
        let originPeer = await reply.origin.asyncMap(resolve(origin:))
        let authorPeer: ResolvedPeer? =
            if let originPeer {
                originPeer
            } else if let target, let forwardInfo = target.forwardInfo {
                await resolve(origin: forwardInfo.origin)
            } else if let target {
                await resolve(sender: target.senderId, authorSignature: target.authorSignature)
            } else {
                nil
            }
        let crossChat = targetChatID.map { $0 != parent.chatId } == true
        let contextChat: Chat? =
            if crossChat, let targetChatID {
                await chat(id: targetChatID)
            } else {
                nil
            }
        let authorTitle = authorPeer?.title ?? nonEmpty(contextChat?.title) ?? L10n.betterTG("Chat.Reply")
        let title =
            if let contextTitle = nonEmpty(contextChat?.title), normalized(contextTitle) != normalized(authorTitle) {
                "\(authorTitle) • \(contextTitle)"
            } else {
                authorTitle
            }
        let checklistTask: ChecklistTask? =
            if reply.checklistTaskId != 0, case .messageChecklist(let checklist)? = content {
                checklist.list.tasks.first { $0.id == reply.checklistTaskId }
            } else {
                nil
            }
        let body =
            if let quote = reply.quote, !quote.text.text.isEmpty {
                quote.text
            } else if let checklistTask {
                checklistTask.text
            } else if let content {
                previewText(for: content)
            } else {
                plainText(L10n.betterTG("Chat.OriginalMessageUnavailable"))
            }
        // The chat resolves the quote against the message it opens (MessageQuoteHighlight.resolved).
        let quoteHighlight = reply.quote.flatMap { MessageQuoteHighlight(text: $0.text.text, position: $0.position) }
        let navigationTarget: MessageMetadataNavigationTarget? =
            if let target {
                .message(chatID: target.chatId, messageID: target.id, quote: quoteHighlight)
            } else if reply.messageId == 0 {
                authorPeer?.navigationTarget
            } else {
                .unavailable
            }
        return MessageReplyPresentation(
            availability: target != nil ? .resolved : (content != nil || reply.quote != nil ? .inline : .unavailable),
            body: body,
            navigationTarget: navigationTarget,
            quote: reply.quote,
            referencedChatID: authorPeer?.chatID ?? targetChatID,
            referencedUserID: authorPeer?.userID,
            targetChatID: targetChatID,
            targetMessageID: targetMessageID,
            thumbnail: content.flatMap(MessageReplyThumbnail.make(for:)),
            title: title,
            checklistTaskIsDone: checklistTask.map { $0.completedBy != nil },
        )
    }

    private func resolveTargetMessage(
        parent: Message,
        declaredChatID: Int64?,
        targetMessageID: Int64,
    ) async -> Message? {
        guard targetMessageID != 0 else { return nil }
        if let replied = try? await client.getRepliedMessage(chatId: parent.chatId, messageId: parent.id) {
            return replied
        }
        guard let declaredChatID else { return nil }
        if let local = try? await client.getMessageLocally(chatId: declaredChatID, messageId: targetMessageID) {
            return local
        }
        return try? await client.getMessage(chatId: declaredChatID, messageId: targetMessageID)
    }

    private func resolve(source: ForwardSource) async -> ResolvedPeer? {
        let sourceMessageTarget: MessageMetadataNavigationTarget? =
            if source.chatId != 0, source.messageId != 0 {
                .message(chatID: source.chatId, messageID: source.messageId, quote: nil)
            } else {
                nil
            }
        let sourceChat = source.chatId == 0 ? nil : await chat(id: source.chatId)
        let senderPeer: ResolvedPeer? =
            if let senderID = source.senderId {
                await resolve(sender: senderID, authorSignature: "")
            } else if let senderName = nonEmpty(source.senderName) {
                ResolvedPeer(
                    avatar: avatar(initialsFor(senderName)),
                    chatID: nil,
                    navigationTarget: nil,
                    title: senderName,
                    userID: nil,
                )
            } else {
                nil
            }
        if let sourceChat {
            let title =
                if let senderPeer, normalized(senderPeer.title) != normalized(sourceChat.title) {
                    "\(sourceChat.title) • \(senderPeer.title)"
                } else {
                    sourceChat.title
                }
            return ResolvedPeer(
                avatar: avatar(for: sourceChat),
                chatID: sourceChat.id,
                navigationTarget: sourceMessageTarget ?? .chat(chatID: sourceChat.id),
                title: title,
                userID: senderPeer?.userID,
            )
        }
        if let senderPeer {
            return ResolvedPeer(
                avatar: senderPeer.avatar,
                chatID: source.chatId == 0 ? nil : source.chatId,
                navigationTarget: sourceMessageTarget ?? senderPeer.navigationTarget,
                title: senderPeer.title,
                userID: senderPeer.userID,
            )
        }
        return nil
    }

    private func resolve(origin: MessageOrigin) async -> ResolvedPeer {
        switch origin {
        case .messageOriginUser(let origin):
            if let user = await user(id: origin.senderUserId) {
                return resolved(user: user)
            }
            return ResolvedPeer(
                avatar: nil,
                chatID: nil,
                navigationTarget: .user(userID: origin.senderUserId),
                title: L10n.telegram("User.DeletedAccount"),
                userID: origin.senderUserId,
            )
        case .messageOriginHiddenUser(let origin):
            let title = nonEmpty(origin.senderName) ?? L10n.betterTG("Chat.HiddenAccount")
            return ResolvedPeer(
                avatar: avatar(initialsFor(title)),
                chatID: nil,
                navigationTarget: nil,
                title: title,
                userID: nil,
            )
        case .messageOriginChat(let origin):
            let chat = await chat(id: origin.senderChatId)
            let base = nonEmpty(chat?.title) ?? nonEmpty(origin.authorSignature) ?? L10n
                .betterTG("Chat.FallbackChatTitle")
            return ResolvedPeer(
                avatar: chat.map(avatar(for:)),
                chatID: origin.senderChatId,
                navigationTarget: .chat(chatID: origin.senderChatId),
                title: signedTitle(base, signature: origin.authorSignature),
                userID: nil,
            )
        case .messageOriginChannel(let origin):
            let chat = await chat(id: origin.chatId)
            let base = nonEmpty(chat?.title) ?? nonEmpty(origin.authorSignature) ?? L10n
                .betterTG("Chat.FallbackChannelTitle")
            let navigation: MessageMetadataNavigationTarget = origin.messageId == 0
                ? .chat(chatID: origin.chatId)
                : .message(chatID: origin.chatId, messageID: origin.messageId, quote: nil)
            return ResolvedPeer(
                avatar: chat.map(avatar(for:)),
                chatID: origin.chatId,
                navigationTarget: navigation,
                title: signedTitle(base, signature: origin.authorSignature),
                userID: nil,
            )
        }
    }

    private func resolve(sender: MessageSender, authorSignature: String) async -> ResolvedPeer {
        switch sender {
        case .messageSenderUser(let sender):
            if let user = await user(id: sender.userId) {
                return resolved(user: user)
            }
            return ResolvedPeer(
                avatar: nil,
                chatID: nil,
                navigationTarget: .user(userID: sender.userId),
                title: L10n.telegram("User.DeletedAccount"),
                userID: sender.userId,
            )
        case .messageSenderChat(let sender):
            let chat = await chat(id: sender.chatId)
            let base = nonEmpty(chat?.title) ?? nonEmpty(authorSignature) ?? L10n.betterTG("Chat.FallbackChatTitle")
            return ResolvedPeer(
                avatar: chat.map(avatar(for:)),
                chatID: sender.chatId,
                navigationTarget: .chat(chatID: sender.chatId),
                title: signedTitle(base, signature: authorSignature),
                userID: nil,
            )
        }
    }

    private func resolved(user: User) -> ResolvedPeer {
        let title = userDisplayName(user)
        return ResolvedPeer(
            avatar: MessageMetadataAvatar(
                file: user.profilePhoto?.small,
                initials: initialsFor(title),
                minithumbnailData: user.profilePhoto?.minithumbnail?.data,
            ),
            chatID: nil,
            navigationTarget: .user(userID: user.id),
            title: title,
            userID: user.id,
        )
    }

    private func user(id: Int64) async -> User? {
        if let user = users[id] { return user }
        guard !missingUserIDs.contains(id), let user = try? await client.getUser(userId: id) else {
            missingUserIDs.insert(id)
            return nil
        }
        users[id] = user
        return user
    }

    private func chat(id: Int64) async -> Chat? {
        guard id != 0 else { return nil }
        if let chat = chats[id] { return chat }
        guard !missingChatIDs.contains(id), let chat = try? await client.getChat(chatId: id) else {
            missingChatIDs.insert(id)
            return nil
        }
        chats[id] = chat
        return chat
    }

    private func previewText(for content: MessageContent) -> FormattedText {
        switch content {
        case .messageText(let message):
            message.text
        case .messageAnimation(let message):
            nonEmpty(message.caption.text) == nil ? plainText(L10n.telegram("Message.Animation")) : message.caption
        case .messageAudio(let message):
            nonEmpty(message.caption.text) == nil
                ? plainText(MessageContentPresentation.make(content).summary)
                : message.caption
        case .messageDocument(let message):
            nonEmpty(message.caption.text) == nil
                ? plainText(MessageContentPresentation.make(content).summary)
                : message.caption
        case .messagePhoto(let message):
            nonEmpty(message.caption.text) == nil
                ? plainText(L10n.telegram(message.video == nil ? "Message.Photo" : "Message.LivePhoto"))
                : message.caption
        case .messageVideo(let message):
            nonEmpty(message.caption.text) == nil ? plainText(L10n.telegram("Message.Video")) : message.caption
        case .messageVoiceNote(let message):
            nonEmpty(message.caption.text) == nil ? plainText(L10n.telegram("Message.Audio")) : message.caption
        case .messagePoll(let message):
            message.poll.question
        default:
            plainText(MessageContentPresentation.make(content).summary)
        }
    }

    private func avatar(for chat: Chat) -> MessageMetadataAvatar {
        MessageMetadataAvatar(
            file: chat.photo?.small,
            initials: initialsFor(chat.title),
            minithumbnailData: chat.photo?.minithumbnail?.data,
        )
    }

    private func avatar(_ initials: String) -> MessageMetadataAvatar {
        MessageMetadataAvatar(file: nil, initials: initials, minithumbnailData: nil)
    }

    private func userDisplayName(_ user: User) -> String {
        if case .userTypeDeleted = user.type { return L10n.telegram("User.DeletedAccount") }
        let value = [user.firstName, user.lastName]
            .compactMap(nonEmpty)
            .joined(separator: " ")
        return value.isEmpty ? L10n.telegram("User.DeletedAccount") : value
    }

    private func signedTitle(_ title: String, signature: String) -> String {
        guard let signature = nonEmpty(signature), normalized(signature) != normalized(title) else { return title }
        return "\(title) (\(signature))"
    }

    private func initialsFor(_ title: String) -> String {
        let initials = title
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        return initials.isEmpty ? "•" : initials
    }

    private func plainText(_ text: String) -> FormattedText {
        FormattedText(entities: [], text: text)
    }

    private func nonEmpty(_ string: String?) -> String? {
        guard let value = string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func normalized(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}

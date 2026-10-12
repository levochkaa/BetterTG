// ServiceMessageText.swift

import Foundation
import TDLibKit

/// Telegram's service-message wording with actor names (TelegramStringFormatting ServiceMessageStrings.swift,
/// universalServiceMessageString) for the actions BetterTG shows. Names are resolved before the row is built, so
/// the bubble has its final height on first layout; other actions keep MessageContentPresentation's title.
enum ServiceMessageText {
    struct Context {
        let author: String
        let isOutgoing: Bool
        let isChannel: Bool
        let senderUserID: Int64?
        let names: [Int64: String]
        let pinned: Message?
    }

    static func resolve(
        _ message: Message,
        senderUser: User?,
        isChannel: Bool,
        client: TDLibClient,
    ) async -> String? {
        guard handles(message.content) else { return nil }
        var author = ""
        var senderUserID: Int64?
        switch message.senderId {
        case .messageSenderUser(let sender):
            senderUserID = sender.userId
            let user: User? =
                if let senderUser, senderUser.id == sender.userId {
                    senderUser
                } else {
                    try? await client.getUser(userId: sender.userId)
                }
            author = user.map(displayTitle) ?? ""
        case .messageSenderChat(let sender):
            author = await (try? client.getChat(chatId: sender.chatId))?.title ?? ""
        }
        var names = [Int64: String]()
        for id in memberIDs(message.content) where names[id] == nil {
            if let user = try? await client.getUser(userId: id) { names[id] = displayTitle(user) }
        }
        var pinned: Message?
        if case .messagePinMessage(let value) = message.content {
            pinned = try? await client.getMessage(chatId: message.chatId, messageId: value.messageId)
        }
        return make(message.content, context: Context(
            author: author, isOutgoing: message.isOutgoing, isChannel: isChannel,
            senderUserID: senderUserID, names: names, pinned: pinned,
        ))
    }

    static func make(_ content: MessageContent, context: Context) -> String? {
        let author = context.author
        let hasAuthor = !author.isEmpty && !context.isChannel
        let text: String? =
            switch content {
            case .messageBasicGroupChatCreate(let value):
                hasAuthor ? telegram("Notification.CreatedChatWithTitle", author, value.title) : nil
            case .messageSupergroupChatCreate(let value):
                context.isChannel
                    ? telegram("Notification.CreatedChannel")
                    : hasAuthor ? telegram("Notification.CreatedChatWithTitle", author, value.title) : nil
            case .messageChatChangeTitle(let value):
                hasAuthor
                    ? telegram("Notification.ChangedGroupName", author, value.title)
                    : telegram("Channel.MessageTitleUpdated", value.title)
            case .messageChatChangePhoto(let value):
                switch (hasAuthor, value.photo.animation != nil) {
                case (true, true): telegram("Notification.ChangedGroupVideo", author)
                case (true, false): telegram("Notification.ChangedGroupPhoto", author)
                case (false, true): telegram("Channel.MessageVideoUpdated")
                case (false, false): telegram("Channel.MessagePhotoUpdated")
                }
            case .messageChatDeletePhoto:
                hasAuthor ? telegram("Notification.RemovedGroupPhoto", author) : telegram("Channel.MessagePhotoRemoved")
            case .messageChatAddMembers(let value):
                addedMembers(value.memberUserIds, context: context)
            case .messageChatDeleteMember(let value):
                removedMember(value.userId, context: context)
            case .messageChatJoinByLink:
                context.isOutgoing
                    ? telegram("Notification.JoinedGroupByLinkYou")
                    : author.isEmpty ? nil : telegram("Notification.JoinedGroupByLink", author)
            case .messageChatJoinByRequest:
                if context.isOutgoing {
                    telegram(context.isChannel
                        ? "Notification.JoinedChannelByRequestYou"
                        : "Notification.JoinedGroupByRequestYou")
                } else {
                    author.isEmpty ? nil : telegram("Notification.JoinedGroupByRequest", author)
                }
            case .messagePinMessage:
                author.isEmpty ? nil : pinnedMessage(context.pinned, author: author)
            case .messageScreenshotTaken:
                context.isOutgoing
                    ? telegram("Notification.SecretChatMessageScreenshotSelf")
                    : author.isEmpty ? nil : telegram("Notification.SecretChatMessageScreenshot", author)
            case .messageContactRegistered:
                author.isEmpty ? nil : telegram("Notification.Joined", author)
            case .messageVideoChatStarted:
                hasAuthor
                    ? telegram("Notification.VoiceChatStarted", author)
                    : telegram("Notification.VoiceChatStartedChannel")
            case .messageForumTopicCreated:
                telegram("Notification.ForumTopicCreated")
            case .messageForumTopicIsClosedToggled(let value):
                author.isEmpty
                    ? telegram(value.isClosed ? "Notification.ForumTopicClosed" : "Notification.ForumTopicReopened")
                    : telegram(
                        value
                            .isClosed ? "Notification.ForumTopicClosedAuthor" : "Notification.ForumTopicReopenedAuthor",
                        author,
                    )
            case .messageForumTopicEdited(let value) where !value.name.isEmpty:
                author.isEmpty
                    ? telegram("Notification.ForumTopicRenamed", value.name)
                    : telegram("Notification.ForumTopicRenamedAuthor", author, value.name)
            default:
                nil
            }
        return text?.trimmingCharacters(in: .whitespaces)
    }

    /// Telegram's EnginePeer.displayTitle for users: the full name, or Deleted Account.
    static func displayTitle(_ user: User) -> String {
        let name = [user.firstName, user.lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? L10n.telegram("User.DeletedAccount") : name
    }

    static func memberIDs(_ content: MessageContent) -> [Int64] {
        switch content {
        case .messageChatAddMembers(let value): value.memberUserIds
        case .messageChatDeleteMember(let value): [value.userId]
        default: []
        }
    }

    private static func handles(_ content: MessageContent) -> Bool {
        switch content {
        case .messageBasicGroupChatCreate, .messageChatAddMembers, .messageChatChangePhoto,
             .messageChatChangeTitle, .messageChatDeleteMember, .messageChatDeletePhoto, .messageChatJoinByLink,
             .messageChatJoinByRequest, .messageContactRegistered, .messageForumTopicCreated, .messageForumTopicEdited,
             .messageForumTopicIsClosedToggled, .messagePinMessage, .messageScreenshotTaken,
             .messageSupergroupChatCreate, .messageVideoChatStarted:
            true
        default:
            false
        }
    }

    private static func addedMembers(_ ids: [Int64], context: Context) -> String? {
        let author = context.author
        guard !author.isEmpty else { return nil }
        if ids.first == context.senderUserID {
            return telegram(context.isChannel ? "Notification.JoinedChannel" : "Notification.JoinedChat", author)
        }
        let names = ids.compactMap { context.names[$0] }
        guard !names.isEmpty else { return nil }
        return telegram(
            ids.count == 1 ? "Notification.Invited" : "Notification.InvitedMultiple",
            author,
            names.joined(separator: ", "),
        )
    }

    private static func removedMember(_ id: Int64, context: Context) -> String? {
        let author = context.author
        guard !author.isEmpty else { return nil }
        if id == context.senderUserID {
            return telegram(context.isChannel ? "Notification.LeftChannel" : "Notification.LeftChat", author)
        }
        return context.names[id].map { telegram("Notification.Kicked", author, $0) }
    }

    private static func pinnedMessage(_ pinned: Message?, author: String) -> String {
        guard let pinned else { return telegram("Message.PinnedGenericMessage", author) }
        let key: String? =
            switch pinned.content {
            case .messagePhoto: "Notification.PinnedPhotoMessage"
            case .messageVideo: "Notification.PinnedVideoMessage"
            case .messageVideoNote: "Notification.PinnedRoundMessage"
            case .messageVoiceNote: "Notification.PinnedAudioMessage"
            case .messageAudio, .messageDocument: "Notification.PinnedDocumentMessage"
            case .messageAnimation: "Notification.PinnedAnimationMessage"
            case .messageSticker: "Notification.PinnedStickerMessage"
            case .messageLiveLocation, .messageLocation, .messageVenue: "Notification.PinnedLocationMessage"
            case .messageContact: "Notification.PinnedContactMessage"
            case .messageGame: "Message.AuthorPinnedGame"
            case .messagePoll(let value):
                if case .pollTypeQuiz = value.poll.type {
                    "Notification.PinnedQuizMessage"
                } else {
                    "Notification.PinnedPollMessage"
                }
            default: nil
            }
        if let key { return telegram(key, author) }
        guard case .messageText(let value) = pinned.content else {
            return telegram("Message.PinnedGenericMessage", author)
        }
        // Telegram clips the quoted text to fifteen characters on one line.
        var clipped = value.text.text.replacingOccurrences(of: "\n", with: " ")
        if clipped.count > 14 { clipped = String(clipped.prefix(15)) + "..." }
        return clipped.isEmpty
            ? telegram("Message.PinnedGenericMessage", author)
            : telegram("Notification.PinnedTextMessage", author, clipped)
    }

    private static func telegram(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.shared.telegramString(key, arguments: arguments)
    }
}

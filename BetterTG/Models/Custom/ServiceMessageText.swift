// ServiceMessageText.swift

import Foundation
import MapKit
import TDLibKit

/// Telegram's service-message wording with actor names (TelegramStringFormatting ServiceMessageStrings.swift,
/// universalServiceMessageString) for the actions BetterTG shows. Names are resolved before the row is built, so
/// the bubble has its final height on first layout; other actions keep MessageContentPresentation's title.
enum ServiceMessageText {
    enum ChatKind {
        case privateChat
        case secretChat
        case basicGroup
        case supergroup
        case channel
        case unknown
    }

    struct Context {
        let author: String
        let isOutgoing: Bool
        let isChannel: Bool
        let senderUserID: Int64?
        /// Display names by user ID, and by chat ID for chats named as senders.
        var names: [Int64: String]
        let pinned: Message?
        var accountUserID: Int64?
        var chatKind = ChatKind.unknown
        var chatTitle = ""
        var gameTitle: String?
        /// The checklist whose tasks were marked or added, while its message is still there.
        var checklist: Checklist?
        /// EnginePeer.compactDisplayTitle of the chat (a user's first name), which sharing and Passport notices name.
        var chatCompactTitle = ""
        /// The community the chat was added to, named by TDLib's updateCommunity.
        var communityName: String?
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
        var context = Context(
            author: author, isOutgoing: message.isOutgoing, isChannel: isChannel,
            senderUserID: senderUserID, names: names, pinned: pinned,
        )
        if needsAccount(message.content) {
            context.accountUserID = try? await client.getMe().id
        }
        if needsChat(message.content), let chat = try? await client.getChat(chatId: message.chatId) {
            context.chatTitle = chat.title
            context.chatKind = chatKind(chat.type)
            context.chatCompactTitle = await compactTitle(chat, client: client)
        }
        switch message.content {
        case .messageGameScore(let value) where value.gameMessageId != 0:
            if let game = try? await client.getMessage(chatId: message.chatId, messageId: value.gameMessageId),
               case .messageGame(let content) = game.content
            {
                context.gameTitle = content.game.title
            }
        case .messageChecklistTasksDone(let value) where value.checklistMessageId != 0:
            context.checklist = await checklist(in: message.chatId, messageID: value.checklistMessageId, client: client)
        case .messageChecklistTasksAdded(let value) where value.checklistMessageId != 0:
            context.checklist = await checklist(in: message.chatId, messageID: value.checklistMessageId, client: client)
        case .messageChatShared(let value) where context.names[value.chat.chatId] == nil:
            let title = await (try? client.getChat(chatId: value.chat.chatId))?.title ?? value.chat.title
            if !title.isEmpty { context.names[value.chat.chatId] = title }
        case .messageChatAddedToCommunity(let value):
            context.communityName = await TelegramChatListStore.shared.communityName(
                value.communityId,
                clientID: client.id,
            )
        case .messageProximityAlertTriggered(let value):
            for sender in [value.travelerId, value.watcherId] {
                guard case .messageSenderChat(let chat) = sender, context.names[chat.chatId] == nil else { continue }
                if let title = try? await client.getChat(chatId: chat.chatId)
                    .title { context.names[chat.chatId] = title }
            }
        default:
            break
        }
        return make(message.content, context: context)
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
                context.senderUserID == nil || author.isEmpty
                    ? telegram(context.isChannel
                        ? "Notification.LiveStreamStarted"
                        : "Notification.VoiceChatStartedChannel")
                    : telegram("Notification.VoiceChatStarted", author)
            case .messageVideoChatEnded(let value):
                videoChatEnded(duration: value.duration, context: context)
            case .messageVideoChatScheduled(let value):
                videoChatScheduled(startDate: value.startDate, context: context)
            case .messageInviteVideoChatParticipants(let value):
                videoChatInvitation(value.userIds, context: context)
            case .messageCall(let value):
                callTitle(value.discardReason, isOutgoing: context.isOutgoing)
            case .messageGroupCall(let value):
                telegram(
                    value.wasMissed
                        ? "Chat.CallMessage.DeclinedGroupCall"
                        : !value.isActive && value.duration == 0
                            ? "Chat.CallMessage.MissedGroupCall"
                            : context.isOutgoing
                                ? "Chat.CallMessage.OutgoingGroupCall"
                                : "Chat.CallMessage.IncomingGroupCall",
                )
            case .messageChatSetMessageAutoDeleteTime(let value):
                autoDeleteTimer(value.messageAutoDeleteTime, fromUserID: value.fromUserId, context: context)
            case .messageGameScore(let value):
                gameScore(value.score, context: context)
            case .messageChecklistTasksDone(let value):
                checklistTasksDone(
                    done: value.markedAsDoneTaskIds,
                    notDone: value.markedAsNotDoneTaskIds,
                    context: context,
                )
            case .messageChecklistTasksAdded(let value):
                checklistTasksAdded(value.tasks, context: context)
            case .messageProximityAlertTriggered(let value):
                proximityAlert(traveler: value.travelerId, watcher: value.watcherId, distance: value.distance, context)
            case .messageWebAppDataSent(let value):
                telegram("Notification.WebAppSentData", value.buttonText)
            case .messageChatSetTheme(let value):
                chatTheme(value.theme, context: context)
            case .messageChatSetBackground(let value):
                chatBackground(onlyForSelf: value.onlyForSelf, isSame: value.oldBackgroundMessageId != 0, context)
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
            case .messageForumTopicIsHiddenToggled(let value):
                context.senderUserID == nil || author.isEmpty
                    ? telegram(value.isHidden ? "Notification.ForumTopicHidden" : "Notification.ForumTopicUnhidden")
                    : telegram(
                        value
                            .isHidden ? "Notification.ForumTopicHiddenAuthor" : "Notification.ForumTopicUnhiddenAuthor",
                        author,
                    )
            case .messageChatOwnerLeft(let value):
                ownerChange(to: value.newOwnerUserId, applied: false, context: context)
            case .messageChatOwnerChanged(let value):
                ownerChange(to: value.newOwnerUserId, applied: true, context: context)
            case .messageChatHasProtectedContentToggled(let value):
                copyProtection(old: value.oldHasProtectedContent, new: value.newHasProtectedContent, context: context)
            case .messageChatHasProtectedContentDisableRequested:
                context.isOutgoing
                    ? telegram("Notification.CopyProtection.RequestYou")
                    : context.chatCompactTitle.isEmpty
                        ? nil
                        : telegram("Notification.CopyProtection.Request", context.chatCompactTitle)
            case .messageSuggestProfilePhoto(let value):
                telegram(
                    value.photo.animation == nil && value.photo.smallAnimation == nil
                        ? "Notification.SuggestedProfilePhoto"
                        : "Notification.SuggestedProfileVideo",
                )
            case .messageSuggestBirthdate:
                telegram("Notification.SuggestBirthdate")
            case .messageBotWriteAccessAllowed(let value):
                botWriteAccess(value.reason)
            case .messageUsersShared(let value):
                sharedPeers(value.users.map(\.userId), context: context)
            case .messageChatShared(let value):
                sharedPeers([value.chat.chatId], context: context)
            case .messagePassportDataSent(let value):
                passportValues(value.types, context: context)
            case .messagePollOptionAdded(let value):
                pollOption(value.text.text, added: true, context: context)
            case .messagePollOptionDeleted(let value):
                pollOption(value.text.text, added: false, context: context)
            case .messageSuggestedPostApproved:
                telegram(
                    context.isOutgoing
                        ? "Chat.PostApproval.Status.AdminApproved"
                        : "Chat.PostApproval.Status.UserApproved",
                )
            case .messageSuggestedPostApprovalFailed,
                 .messageSuggestedPostDeclined:
                // Telegram words a rejection for a low balance as any rejection.
                telegram(
                    context.isOutgoing
                        ? "Chat.PostApproval.Status.AdminRejected"
                        : "Chat.PostApproval.Status.UserRejected",
                )
            case .messageManagedBotCreated(let value):
                context.names[value.botUserId].map { telegram("Notification.ManagedBotCreated", $0) }
            case .messageChatAddedToCommunity:
                community(added: true, context: context)
            case .messageChatRemovedFromCommunity:
                community(added: false, context: context)
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
        case .messageInviteVideoChatParticipants(let value): value.userIds
        case .messageChatOwnerLeft(let value): value.newOwnerUserId == 0 ? [] : [value.newOwnerUserId]
        case .messageChatOwnerChanged(let value): [value.newOwnerUserId]
        case .messageUsersShared(let value): value.users.map(\.userId)
        case .messageManagedBotCreated(let value): [value.botUserId]
        case .messageProximityAlertTriggered(let value):
            [value.travelerId, value.watcherId].compactMap { sender in
                if case .messageSenderUser(let user) = sender { user.userId } else { nil }
            }
        default: []
        }
    }

    /// Service messages whose wording needs more than their author's and members' names: their checklist or game,
    /// the chat, its community or the account. Chat and topic lists resolve them in the background, as Telegram's
    /// lists read them with the message's associated messages and peers.
    static func needsResolvedContext(_ content: MessageContent) -> Bool {
        if needsAccount(content) || needsChat(content) { return true }
        switch content {
        case .messageChecklistTasksAdded,
             .messageChecklistTasksDone,
             .messageGameScore:
            return true
        default:
            return false
        }
    }

    private static func handles(_ content: MessageContent) -> Bool {
        switch content {
        case .messageBasicGroupChatCreate,
             .messageBotWriteAccessAllowed,
             .messageCall,
             .messageChatAddedToCommunity,
             .messageChatAddMembers,
             .messageChatChangePhoto,
             .messageChatChangeTitle,
             .messageChatDeleteMember,
             .messageChatDeletePhoto,
             .messageChatHasProtectedContentDisableRequested,
             .messageChatHasProtectedContentToggled,
             .messageChatJoinByLink,
             .messageChatJoinByRequest,
             .messageChatOwnerChanged,
             .messageChatOwnerLeft,
             .messageChatRemovedFromCommunity,
             .messageChatSetBackground,
             .messageChatSetMessageAutoDeleteTime,
             .messageChatSetTheme,
             .messageChatShared,
             .messageChecklistTasksAdded,
             .messageChecklistTasksDone,
             .messageContactRegistered,
             .messageForumTopicCreated,
             .messageForumTopicEdited,
             .messageForumTopicIsClosedToggled,
             .messageForumTopicIsHiddenToggled,
             .messageGameScore,
             .messageGroupCall,
             .messageInviteVideoChatParticipants,
             .messageManagedBotCreated,
             .messagePassportDataSent,
             .messagePinMessage,
             .messagePollOptionAdded,
             .messagePollOptionDeleted,
             .messageProximityAlertTriggered,
             .messageScreenshotTaken,
             .messageSuggestBirthdate,
             .messageSuggestedPostApprovalFailed,
             .messageSuggestedPostApproved,
             .messageSuggestedPostDeclined,
             .messageSuggestProfilePhoto,
             .messageSupergroupChatCreate,
             .messageUsersShared,
             .messageVideoChatEnded,
             .messageVideoChatScheduled,
             .messageVideoChatStarted,
             .messageWebAppDataSent:
            true
        default:
            false
        }
    }

    private static func needsAccount(_ content: MessageContent) -> Bool {
        switch content {
        case .messageChatSetMessageAutoDeleteTime,
             .messageInviteVideoChatParticipants,
             .messageProximityAlertTriggered:
            true
        default:
            false
        }
    }

    private static func needsChat(_ content: MessageContent) -> Bool {
        switch content {
        case .messageChatAddedToCommunity,
             .messageChatHasProtectedContentDisableRequested,
             .messageChatHasProtectedContentToggled,
             .messageChatRemovedFromCommunity,
             .messageChatSetBackground,
             .messageChatSetMessageAutoDeleteTime,
             .messageChatShared,
             .messagePassportDataSent,
             .messageUsersShared:
            true
        default: false
        }
    }

    /// EnginePeer.compactDisplayTitle: a user's first name, else the last name; a group's or channel's title.
    private static func compactTitle(_ chat: Chat, client: TDLibClient) async -> String {
        let userID: Int64? =
            switch chat.type {
            case .chatTypePrivate(let value): value.userId
            case .chatTypeSecret(let value): value.userId
            default: nil
            }
        guard let userID, let user = try? await client.getUser(userId: userID) else { return chat.title }
        return [user.firstName, user.lastName].first { !$0.isEmpty } ?? displayTitle(user)
    }

    /// groupCreatorChange: the owner left and the member becomes the owner in 7 days unless they return, or the
    /// owner handed the group over.
    private static func ownerChange(to userID: Int64, applied: Bool, context: Context) -> String? {
        guard !context.author.isEmpty, let target = context.names[userID] else { return nil }
        return telegram(
            applied ? "Notification.GroupCreatorChangeApplied" : "Notification.GroupCreatorChangePending",
            context.author,
            target,
        )
    }

    /// copyProtectionToggle, which names the chat rather than its author. A toggle that keeps protection on is a
    /// declined request to enable sharing.
    private static func copyProtection(old: Bool, new: Bool, context: Context) -> String? {
        if old, new { return telegram("Notification.CopyProtection.StillEnabled") }
        if context.isOutgoing {
            return telegram(new ? "Notification.CopyProtection.EnabledYou" : "Notification.CopyProtection.DisabledYou")
        }
        guard !context.chatCompactTitle.isEmpty else { return nil }
        return telegram(
            new ? "Notification.CopyProtection.Enabled" : "Notification.CopyProtection.Disabled",
            context.chatCompactTitle,
        )
    }

    /// botDomainAccessGranted and botAppAccessGranted.
    private static func botWriteAccess(_ reason: TDNativeBotWriteAccessAllowReason) -> String {
        switch reason {
        case .botWriteAccessAllowReasonConnectedWebsite(let value):
            telegram("AuthSessions.Message", value.domainName)
        case .botWriteAccessAllowReasonAddedToAttachmentMenu:
            telegram("Notification.BotWriteAllowedMenu")
        case .botWriteAccessAllowReasonLaunchedWebApp(let value):
            telegram("AuthSessions.MessageApp", value.webApp.title)
        case .botWriteAccessAllowReasonAcceptedRequest:
            telegram("Notification.BotWriteAllowedRequest")
        }
    }

    /// requestedPeer: the users or the chat shared with the bot whose chat this is.
    private static func sharedPeers(_ ids: [Int64], context: Context) -> String? {
        let names = ids.compactMap { context.names[$0] }
        guard !ids.isEmpty, names.count == ids.count, !context.chatTitle.isEmpty else { return nil }
        return telegram(
            ids.count == 1 ? "Notification.RequestedPeer" : "Notification.RequestedPeerMultiple",
            names.joined(separator: ", "),
            context.chatTitle,
        )
    }

    /// botSentSecureValues: the bot and the kinds of documents it received, each proof of identity or address once.
    private static func passportValues(_ types: [TDNativePassportElementType], context: Context) -> String? {
        guard !context.chatCompactTitle.isEmpty else { return nil }
        var values = [String]()
        var hasIdentity = false
        var hasAddress = false
        for type in types {
            switch type {
            case .passportElementTypePersonalDetails:
                values.append(telegram("Notification.PassportValuePersonalDetails"))
            case .passportElementTypeDriverLicense,
                 .passportElementTypeIdentityCard,
                 .passportElementTypeInternalPassport,
                 .passportElementTypePassport:
                guard !hasIdentity else { continue }
                hasIdentity = true
                values.append(telegram("Notification.PassportValueProofOfIdentity"))
            case .passportElementTypeAddress:
                values.append(telegram("Notification.PassportValueAddress"))
            case .passportElementTypeBankStatement,
                 .passportElementTypePassportRegistration,
                 .passportElementTypeRentalAgreement,
                 .passportElementTypeTemporaryRegistration,
                 .passportElementTypeUtilityBill:
                guard !hasAddress else { continue }
                hasAddress = true
                values.append(telegram("Notification.PassportValueProofOfAddress"))
            case .passportElementTypePhoneNumber:
                values.append(telegram("Notification.PassportValuePhone"))
            case .passportElementTypeEmailAddress:
                values.append(telegram("Notification.PassportValueEmail"))
            }
        }
        return telegram(
            "Notification.PassportValuesSentMessage",
            context.chatCompactTitle,
            values.joined(separator: ", "),
        )
    }

    /// pollOptionAppended and pollOptionDeleted, with the option cut after 20 characters.
    private static func pollOption(_ text: String, added: Bool, context: Context) -> String? {
        let option = shortened(text)
        if context.isOutgoing {
            return telegram(added ? "Notification.PollAddedOptionYou" : "Notification.PollDeletedOptionYou", option)
        }
        guard !context.author.isEmpty else { return nil }
        return telegram(
            added ? "Notification.PollAddedOption" : "Notification.PollDeletedOption",
            context.author,
            option,
        )
    }

    /// communityChanged: a bot's, a channel's or a group's community. A community TDLib hasn't named keeps the
    /// generic title.
    private static func community(added: Bool, context: Context) -> String? {
        let name = context.communityName ?? ""
        if added, name.isEmpty { return nil }
        switch context.chatKind {
        case .privateChat:
            return added
                ? telegram("Notification.CommunityAddedBot", name)
                : telegram("Notification.CommunityRemovedBot")
        case .channel:
            return added
                ? telegram("Notification.CommunityAddedChannel", name)
                : telegram("Notification.CommunityRemovedChannel")
        case .basicGroup,
             .supergroup:
            if context.isOutgoing {
                return added
                    ? telegram("Notification.CommunityAddedGroupYou", name)
                    : telegram("Notification.CommunityRemovedGroupYou")
            }
            if added, context.senderUserID == nil { return telegram("Notification.CommunityAddedGroupUnknown", name) }
            guard !context.author.isEmpty else { return nil }
            return added
                ? telegram("Notification.CommunityAddedGroup", context.author, name)
                : telegram("Notification.CommunityRemovedGroup", context.author)
        case .secretChat,
             .unknown:
            return nil
        }
    }

    private static func chatKind(_ type: ChatType) -> ChatKind {
        switch type {
        case .chatTypePrivate: .privateChat
        case .chatTypeSecret: .secretChat
        case .chatTypeBasicGroup: .basicGroup
        case .chatTypeSupergroup(let value): value.isChannel ? .channel : .supergroup
        }
    }

    /// Telegram's phoneCall wording. TDLib's declined is Telegram's busy and disconnected its disconnect.
    private static func callTitle(_ reason: CallDiscardReason, isOutgoing: Bool) -> String {
        switch reason {
        case .callDiscardReasonDisconnected:
            telegram("Notification.CallCanceled")
        case .callDiscardReasonDeclined,
             .callDiscardReasonMissed:
            telegram(isOutgoing ? "Notification.CallCanceled" : "Notification.CallMissed")
        default:
            telegram(isOutgoing ? "Notification.CallOutgoing" : "Notification.CallIncoming")
        }
    }

    /// A chat author (a channel or an anonymous admin) gets the impersonal wording, as Telegram does for a channel
    /// author; a broadcast channel's call is a live stream.
    private static func videoChatEnded(duration: Int, context: Context) -> String {
        let value = callDuration(duration)
        guard context.senderUserID != nil, !context.author.isEmpty else {
            return telegram(context.isChannel ? "Notification.LiveStreamEnded" : "Notification.VoiceChatEnded", value)
        }
        return telegram("Notification.VoiceChatEndedGroup", context.author, value)
    }

    /// humanReadableStringForTimestamp with the time always shown and no "yesterday".
    private static func videoChatScheduled(startDate: Int, context: Context) -> String {
        let date = Foundation.Date(timeIntervalSince1970: TimeInterval(startDate))
        let day =
            if Calendar.current.isDateInToday(date) {
                "Today"
            } else if Calendar.current.isDateInTomorrow(date) {
                "Tomorrow"
            } else {
                ""
            }
        let value = day.isEmpty
            ? date.formatted(date: .abbreviated, time: .shortened)
            : date.formatted(date: .omitted, time: .shortened)
        guard context.senderUserID != nil, !context.author.isEmpty else {
            return telegram(
                context.isChannel
                    ? "Notification.LiveStreamScheduled\(day)"
                    : "Notification.VoiceChatScheduled\(day)Channel",
                value,
            )
        }
        return telegram("Notification.VoiceChatScheduled\(day)", context.author, value)
    }

    private static func videoChatInvitation(_ ids: [Int64], context: Context) -> String? {
        let author = context.author
        guard !author.isEmpty else { return nil }
        if ids.count == 1, let accountUserID = context.accountUserID, ids[0] == accountUserID {
            return telegram("Notification.VoiceChatInvitationForYou", author)
        }
        let names = ids.compactMap { context.names[$0] }
        guard !names.isEmpty else { return nil }
        return telegram("Notification.VoiceChatInvitation", author, names.joined(separator: ", "))
    }

    /// messageAutoremoveTimeoutUpdated: the wording depends on the chat type; secret chats keep the self-destruct
    /// timer strings. A chat whose type isn't known keeps the generic title.
    private static func autoDeleteTimer(_ timeout: Int, fromUserID: Int64, context: Context) -> String? {
        let author = context.author
        let isYou = context.isOutgoing
        let time = timeInterval(timeout)
        func byAuthor(_ key: String, _ arguments: CVarArg...) -> String? {
            if author.isEmpty {
                nil
            } else {
                AppLocalization.shared.telegramString(key, arguments: [author as CVarArg] + arguments)
            }
        }
        switch context.chatKind {
        case .privateChat:
            if timeout > 0 {
                if fromUserID != 0 {
                    return fromUserID == context.accountUserID
                        ? telegram("Conversation.AutoremoveTimerSetUserGlobalYou", time)
                        : byAuthor("Conversation.AutoremoveTimerSetUserGlobal", time)
                }
                return isYou
                    ? telegram("Conversation.AutoremoveTimerSetUserYou", time)
                    : byAuthor("Conversation.AutoremoveTimerSetUser", time)
            }
            return isYou
                ? telegram("Conversation.AutoremoveTimerRemovedUserYou")
                : byAuthor("Conversation.AutoremoveTimerRemovedUser")
        case .basicGroup,
             .supergroup:
            if isYou {
                return timeout > 0
                    ? telegram("Conversation.AutoremoveTimerSetUserYou", time)
                    : telegram("Conversation.AutoremoveTimerRemovedUserYou")
            }
            return timeout > 0
                ? telegram("Conversation.AutoremoveTimerSetGroup", time)
                : telegram("Conversation.AutoremoveTimerRemovedGroup")
        case .channel:
            guard timeout > 0 else { return telegram("Conversation.AutoremoveTimerRemovedChannel") }
            return isYou
                ? telegram("Conversation.AutoremoveTimerSetUserYou", time)
                : telegram("Conversation.AutoremoveTimerSetChannel", time)
        case .secretChat:
            if timeout > 0 {
                return isYou
                    ? telegram("Notification.MessageLifetimeChangedOutgoing", time)
                    : byAuthor("Notification.MessageLifetimeChanged", time)
            }
            return isYou
                ? telegram("Notification.MessageLifetimeRemovedOutgoing")
                : byAuthor("Notification.MessageLifetimeRemoved")
        case .unknown:
            return nil
        }
    }

    private static func gameScore(_ score: Int, context: Context) -> String? {
        guard context.isOutgoing || !context.author.isEmpty else { return nil }
        let form = context.gameTitle == nil ? "Simple" : "Extended"
        let key = context.isOutgoing ? "ServiceMessage.GameScoreSelf\(form)" : "ServiceMessage.GameScore\(form)"
        return AppLocalization.shared
            .telegramPluralString(key, count: score)
            .replacing("{name}", with: context.author)
            .replacing("{game}", with: context.gameTitle ?? "")
    }

    private static func checklist(in chatID: Int64, messageID: Int64, client: TDLibClient) async -> Checklist? {
        guard let message = try? await client.getMessage(chatId: chatID, messageId: messageID),
              case .messageChecklist(let content) = message.content
        else { return nil }
        return content.list
    }

    /// ServiceMessageStrings' todoCompletions: the task's name while one task was marked and is still in the
    /// checklist, or the number of tasks, by the author or You.
    private static func checklistTasksDone(done: [Int], notDone: [Int], context: Context) -> String? {
        let author = context.author
        let isYou = context.isOutgoing
        guard isYou || !author.isEmpty else { return nil }
        let tasks = context.checklist?.tasks ?? []
        func name(_ id: Int) -> String? {
            tasks.first { $0.id == id }.map { shortened($0.text.text) }
        }
        let title = done.first.flatMap(name) ?? notDone.first.flatMap(name)
        func counted(_ key: String, _ count: Int) -> String {
            let tasksText = AppLocalization.shared.telegramPluralString(key, count: count)
            return isYou
                ? telegram("Notification.TodoMultipleYou", tasksText)
                : telegram("Notification.TodoMultiple", author, tasksText)
        }
        func named(_ youKey: String, _ key: String) -> String {
            isYou ? telegram(youKey, title ?? "") : telegram(key, author, title ?? "")
        }
        if done.count > 1 || (done.count == 1 && title == nil) {
            return counted("Notification.TodoTasksDone", done.count)
        }
        if !done.isEmpty { return named("Notification.TodoCompletedYou", "Notification.TodoCompleted") }
        if notDone.count > 1 || (notDone.count == 1 && title == nil) {
            return counted("Notification.TodoTasksUndone", notDone.count)
        }
        if !notDone.isEmpty { return named("Notification.TodoIncompletedYou", "Notification.TodoIncompleted") }
        return named("Notification.TodoCompletedYou", "Notification.TodoCompleted")
    }

    /// ServiceMessageStrings' todoAppendTasks: the task's name for one task or the number of tasks, and the
    /// checklist's title, DELETED once its message is gone.
    private static func checklistTasksAdded(_ tasks: [ChecklistTask], context: Context) -> String? {
        let author = context.author
        guard context.isOutgoing || !author.isEmpty else { return nil }
        let checklistTitle = shortened(context.checklist?.title.text ?? "DELETED")
        if tasks.count == 1, let task = tasks.first {
            let title = shortened(task.text.text)
            return context.isOutgoing
                ? telegram("Notification.TodoAddedTaskYou", title, checklistTitle)
                : telegram("Notification.TodoAddedTask", author, title, checklistTitle)
        }
        let count = AppLocalization.shared.telegramPluralString("Notification.TodoAddedTasks", count: tasks.count)
        return context.isOutgoing
            ? telegram("Notification.TodoAddedMultipleTasksYou", count, checklistTitle)
            : telegram("Notification.TodoAddedMultipleTasks", author, count, checklistTitle)
    }

    /// Telegram cuts a task's or a checklist's name after 20 characters.
    private static func shortened(_ text: String) -> String {
        text.count > 20 ? String(text.prefix(20)) + "…" : text
    }

    private static func proximityAlert(
        traveler: MessageSender,
        watcher: MessageSender,
        distance: Int,
        _ context: Context,
    ) -> String? {
        // Telegram's stringForDistance.
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .full
        let distance = formatter.string(fromDistance: CLLocationDistance(distance))
        let travelerID = senderID(traveler)
        let watcherID = senderID(watcher)
        if let accountUserID = context.accountUserID, travelerID == accountUserID {
            return context.names[watcherID].map { telegram("Notification.ProximityYouReached", distance, $0) }
        }
        if let accountUserID = context.accountUserID, watcherID == accountUserID {
            return context.names[travelerID].map { telegram("Notification.ProximityReachedYou", $0, distance) }
        }
        guard let from = context.names[travelerID], let to = context.names[watcherID] else { return nil }
        return telegram("Notification.ProximityReached", from, distance, to)
    }

    private static func chatTheme(_ theme: ChatTheme?, context: Context) -> String? {
        let byChat = context.senderUserID == nil
        guard let theme else {
            if byChat { return telegram("Notification.ChannelDisabledTheme") }
            if context.isOutgoing { return telegram("Notification.YouDisabledTheme") }
            return context.author.isEmpty ? nil : telegram("Notification.DisabledTheme", context.author)
        }
        var emoji = ""
        var giftTitle: String?
        switch theme {
        case .chatThemeEmoji(let value):
            emoji = value.name
        case .chatThemeGift(let value):
            let gift = value.giftTheme.gift
            giftTitle = "\(gift.title) #\(gift.number.formatted())"
        }
        if byChat { return telegram("Notification.ChannelChangedTheme", giftTitle ?? emoji) }
        if context.isOutgoing {
            return giftTitle.map { telegram("Notification.YouChangedThemeGift", $0) }
                ?? telegram("Notification.YouChangedTheme", emoji)
        }
        guard !context.author.isEmpty else { return nil }
        return giftTitle.map { telegram("Notification.ChangedThemeGift", context.author, $0) }
            ?? telegram("Notification.ChangedTheme", context.author, emoji)
    }

    /// setChatWallpaper and setSameChatWallpaper. TDLib marks a repeated background with the earlier message's ID;
    /// "for both" applies only to private chats.
    private static func chatBackground(onlyForSelf: Bool, isSame: Bool, _ context: Context) -> String? {
        if isSame {
            if context.isOutgoing { return telegram("Notification.YouChangedToSameWallpaper") }
            return context.author.isEmpty ? nil : telegram("Notification.ChangedToSameWallpaper", context.author)
        }
        let isGroup = context.chatKind == .basicGroup || context.chatKind == .supergroup
        if context.isOutgoing {
            if context.chatKind == .privateChat, !onlyForSelf, !context.chatTitle.isEmpty {
                return telegram("Notification.YouChangedWallpaperBoth", context.chatTitle)
            }
            return telegram(isGroup ? "Notification.YouChangedGroupWallpaper" : "Notification.YouChangedWallpaper")
        }
        switch context.chatKind {
        case .basicGroup,
             .supergroup:
            return telegram("Notification.GroupChangedWallpaper")
        case .channel:
            return telegram("Notification.ChannelChangedWallpaper")
        case .privateChat,
             .secretChat:
            return context.author.isEmpty ? nil : telegram("Notification.ChangedWallpaper", context.author)
        case .unknown:
            return nil
        }
    }

    private static func senderID(_ sender: MessageSender) -> Int64 {
        switch sender {
        case .messageSenderUser(let user): user.userId
        case .messageSenderChat(let chat): chat.chatId
        }
    }

    /// Telegram's timeIntervalString (generic usage).
    private static func timeInterval(_ seconds: Int) -> String {
        let day = 24 * 60 * 60
        let (key, count): (String, Int) =
            if seconds < 60 {
                ("MessageTimer.Seconds", max(1, seconds))
            } else if seconds < 60 * 60 {
                ("MessageTimer.Minutes", seconds / 60)
            } else if seconds < day {
                ("MessageTimer.Hours", seconds / (60 * 60))
            } else if seconds < day * 7 {
                ("MessageTimer.Days", seconds / day)
            } else if seconds < day * 30 {
                ("MessageTimer.Weeks", seconds / (day * 7))
            } else if seconds < day * 365 {
                ("MessageTimer.Months", seconds / (day * 30))
            } else {
                ("MessageTimer.Years", seconds / (day * 365))
            }
        return AppLocalization.shared.telegramPluralString(key, count: max(1, count))
    }

    /// Telegram's callDurationString.
    private static func callDuration(_ seconds: Int) -> String {
        let (key, count): (String, Int) =
            if seconds < 60 {
                ("Call.Seconds", seconds)
            } else if seconds < 60 * 60 {
                ("Call.Minutes", seconds / 60)
            } else if seconds < 24 * 60 * 60 {
                ("Call.Hours", seconds / (60 * 60))
            } else {
                ("Call.Days", seconds / (24 * 60 * 60))
            }
        return AppLocalization.shared.telegramPluralString(key, count: max(1, count))
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
            case .messageAudio,
                 .messageDocument: "Notification.PinnedDocumentMessage"
            case .messageAnimation: "Notification.PinnedAnimationMessage"
            case .messageSticker: "Notification.PinnedStickerMessage"
            case .messageLiveLocation,
                 .messageLocation,
                 .messageVenue: "Notification.PinnedLocationMessage"
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
        // Telegram clips the quoted text to fifteen characters on one line. Swift's replacing sees "\r\n" as one
        // character and would keep that line break.
        // swiftformat:disable:next preferSwiftStringAPI
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

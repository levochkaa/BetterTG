// ChatListRecord.swift

import TDLibKit

/// Mutable application cache for TDLib's immutable native chat views. All fields survive partial updates.
struct ChatListRecord {
    var id: Int64
    var type: TDNativeChatType
    var title: String
    var photo: TDNativeChatPhotoInfo?
    var accentColorId: Int
    var backgroundCustomEmojiId: Int64
    var upgradedGiftColors: TDNativeUpgradedGiftColors?
    var profileAccentColorId: Int
    var profileBackgroundCustomEmojiId: Int64
    var permissions: TDNativeChatPermissions
    var lastMessage: TDNativeMessage?
    var positions: [TDNativeChatPosition]
    var chatLists: [TDNativeChatList]
    var messageSenderId: TDNativeMessageSender?
    var blockList: TDNativeBlockList?
    var hasProtectedContent: Bool
    var isTranslatable: Bool
    var isMarkedAsUnread: Bool
    var viewAsTopics: Bool
    var hasScheduledMessages: Bool
    var hasWelcomeMessages: Bool
    var canBeDeletedOnlyForSelf: Bool
    var canBeDeletedForAllUsers: Bool
    var canBeReported: Bool
    var defaultDisableNotification: Bool
    var unreadCount: Int
    var lastReadInboxMessageId: Int64
    var lastReadOutboxMessageId: Int64
    var unreadMentionCount: Int
    var unreadReactionCount: Int
    var unreadPollVoteCount: Int
    var notificationSettings: TDNativeChatNotificationSettings
    var availableReactions: TDNativeChatAvailableReactions
    var messageAutoDeleteTime: Int
    var emojiStatus: TDNativeEmojiStatus?
    var background: TDNativeChatBackground?
    var theme: TDNativeChatTheme?
    var actionBar: TDNativeChatActionBar?
    var businessBotManageBar: TDNativeBusinessBotManageBar?
    var videoChat: TDNativeVideoChat
    var pendingJoinRequests: TDNativeChatJoinRequestsInfo?
    var replyMarkupMessageId: Int64
    var draftMessage: TDNativeDraftMessage?
    var clientData: String

    var snapshot: Chat {
        Chat(
            id: id,
            type: type,
            title: title,
            photo: photo,
            accentColorId: accentColorId,
            backgroundCustomEmojiId: backgroundCustomEmojiId,
            upgradedGiftColors: upgradedGiftColors,
            profileAccentColorId: profileAccentColorId,
            profileBackgroundCustomEmojiId: profileBackgroundCustomEmojiId,
            permissions: permissions,
            lastMessage: lastMessage,
            positions: positions,
            chatLists: chatLists,
            messageSenderId: messageSenderId,
            blockList: blockList,
            hasProtectedContent: hasProtectedContent,
            isTranslatable: isTranslatable,
            isMarkedAsUnread: isMarkedAsUnread,
            viewAsTopics: viewAsTopics,
            hasScheduledMessages: hasScheduledMessages,
            hasWelcomeMessages: hasWelcomeMessages,
            canBeDeletedOnlyForSelf: canBeDeletedOnlyForSelf,
            canBeDeletedForAllUsers: canBeDeletedForAllUsers,
            canBeReported: canBeReported,
            defaultDisableNotification: defaultDisableNotification,
            unreadCount: unreadCount,
            lastReadInboxMessageId: lastReadInboxMessageId,
            lastReadOutboxMessageId: lastReadOutboxMessageId,
            unreadMentionCount: unreadMentionCount,
            unreadReactionCount: unreadReactionCount,
            unreadPollVoteCount: unreadPollVoteCount,
            notificationSettings: notificationSettings,
            availableReactions: availableReactions,
            messageAutoDeleteTime: messageAutoDeleteTime,
            emojiStatus: emojiStatus,
            background: background,
            theme: theme,
            actionBar: actionBar,
            businessBotManageBar: businessBotManageBar,
            videoChat: videoChat,
            pendingJoinRequests: pendingJoinRequests,
            replyMarkupMessageId: replyMarkupMessageId,
            draftMessage: draftMessage,
            clientData: clientData,
        )
    }

    init(_ chat: Chat) {
        self.id = chat.id
        self.type = chat.type
        self.title = chat.title
        self.photo = chat.photo
        self.accentColorId = chat.accentColorId
        self.backgroundCustomEmojiId = chat.backgroundCustomEmojiId
        self.upgradedGiftColors = chat.upgradedGiftColors
        self.profileAccentColorId = chat.profileAccentColorId
        self.profileBackgroundCustomEmojiId = chat.profileBackgroundCustomEmojiId
        self.permissions = chat.permissions
        self.lastMessage = chat.lastMessage
        self.positions = chat.positions
        self.chatLists = chat.chatLists
        self.messageSenderId = chat.messageSenderId
        self.blockList = chat.blockList
        self.hasProtectedContent = chat.hasProtectedContent
        self.isTranslatable = chat.isTranslatable
        self.isMarkedAsUnread = chat.isMarkedAsUnread
        self.viewAsTopics = chat.viewAsTopics
        self.hasScheduledMessages = chat.hasScheduledMessages
        self.hasWelcomeMessages = chat.hasWelcomeMessages
        self.canBeDeletedOnlyForSelf = chat.canBeDeletedOnlyForSelf
        self.canBeDeletedForAllUsers = chat.canBeDeletedForAllUsers
        self.canBeReported = chat.canBeReported
        self.defaultDisableNotification = chat.defaultDisableNotification
        self.unreadCount = chat.unreadCount
        self.lastReadInboxMessageId = chat.lastReadInboxMessageId
        self.lastReadOutboxMessageId = chat.lastReadOutboxMessageId
        self.unreadMentionCount = chat.unreadMentionCount
        self.unreadReactionCount = chat.unreadReactionCount
        self.unreadPollVoteCount = chat.unreadPollVoteCount
        self.notificationSettings = chat.notificationSettings
        self.availableReactions = chat.availableReactions
        self.messageAutoDeleteTime = chat.messageAutoDeleteTime
        self.emojiStatus = chat.emojiStatus
        self.background = chat.background
        self.theme = chat.theme
        self.actionBar = chat.actionBar
        self.businessBotManageBar = chat.businessBotManageBar
        self.videoChat = chat.videoChat
        self.pendingJoinRequests = chat.pendingJoinRequests
        self.replyMarkupMessageId = chat.replyMarkupMessageId
        self.draftMessage = chat.draftMessage
        self.clientData = chat.clientData
    }

    mutating func setPosition(_ position: ChatPosition) {
        positions.removeAll { $0.list == position.list }
        if position.order != 0 { positions.append(position) }
    }
}

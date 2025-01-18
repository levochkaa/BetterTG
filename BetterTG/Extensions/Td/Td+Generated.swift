// Td+Generated.swift

// This file is generated from td.py
// Any modifications will be overwritten

import SwiftUI
import TDLibKit

func update(_ update: Update) {
    switch update {
        case .updateAuthorizationState(let updateAuthorizationState):
            TDLib.shared.UpdateAuthorizationState(updateAuthorizationState.authorizationState)
        case .updateNewMessage(let updateNewMessage):
            nc.post(name: .updateNewMessage, object: updateNewMessage)
        case .updateMessageSendAcknowledged(let updateMessageSendAcknowledged):
            nc.post(name: .updateMessageSendAcknowledged, object: updateMessageSendAcknowledged)
        case .updateMessageSendSucceeded(let updateMessageSendSucceeded):
            nc.post(name: .updateMessageSendSucceeded, object: updateMessageSendSucceeded)
        case .updateMessageSendFailed(let updateMessageSendFailed):
            nc.post(name: .updateMessageSendFailed, object: updateMessageSendFailed)
        case .updateMessageContent(let updateMessageContent):
            nc.post(name: .updateMessageContent, object: updateMessageContent)
        case .updateMessageEdited(let updateMessageEdited):
            nc.post(name: .updateMessageEdited, object: updateMessageEdited)
        case .updateMessageIsPinned(let updateMessageIsPinned):
            nc.post(name: .updateMessageIsPinned, object: updateMessageIsPinned)
        case .updateMessageInteractionInfo(let updateMessageInteractionInfo):
            nc.post(name: .updateMessageInteractionInfo, object: updateMessageInteractionInfo)
        case .updateMessageContentOpened(let updateMessageContentOpened):
            nc.post(name: .updateMessageContentOpened, object: updateMessageContentOpened)
        case .updateMessageMentionRead(let updateMessageMentionRead):
            nc.post(name: .updateMessageMentionRead, object: updateMessageMentionRead)
        case .updateMessageUnreadReactions(let updateMessageUnreadReactions):
            nc.post(name: .updateMessageUnreadReactions, object: updateMessageUnreadReactions)
        case .updateMessageFactCheck(let updateMessageFactCheck):
            nc.post(name: .updateMessageFactCheck, object: updateMessageFactCheck)
        case .updateMessageLiveLocationViewed(let updateMessageLiveLocationViewed):
            nc.post(name: .updateMessageLiveLocationViewed, object: updateMessageLiveLocationViewed)
        case .updateVideoPublished(let updateVideoPublished):
            nc.post(name: .updateVideoPublished, object: updateVideoPublished)
        case .updateNewChat(let updateNewChat):
            nc.post(name: .updateNewChat, object: updateNewChat)
        case .updateChatTitle(let updateChatTitle):
            nc.post(name: .updateChatTitle, object: updateChatTitle)
        case .updateChatPhoto(let updateChatPhoto):
            nc.post(name: .updateChatPhoto, object: updateChatPhoto)
        case .updateChatAccentColors(let updateChatAccentColors):
            nc.post(name: .updateChatAccentColors, object: updateChatAccentColors)
        case .updateChatPermissions(let updateChatPermissions):
            nc.post(name: .updateChatPermissions, object: updateChatPermissions)
        case .updateChatLastMessage(let updateChatLastMessage):
            nc.post(name: .updateChatLastMessage, object: updateChatLastMessage)
        case .updateChatPosition(let updateChatPosition):
            nc.post(name: .updateChatPosition, object: updateChatPosition)
        case .updateChatAddedToList(let updateChatAddedToList):
            nc.post(name: .updateChatAddedToList, object: updateChatAddedToList)
        case .updateChatRemovedFromList(let updateChatRemovedFromList):
            nc.post(name: .updateChatRemovedFromList, object: updateChatRemovedFromList)
        case .updateChatReadInbox(let updateChatReadInbox):
            nc.post(name: .updateChatReadInbox, object: updateChatReadInbox)
        case .updateChatReadOutbox(let updateChatReadOutbox):
            nc.post(name: .updateChatReadOutbox, object: updateChatReadOutbox)
        case .updateChatActionBar(let updateChatActionBar):
            nc.post(name: .updateChatActionBar, object: updateChatActionBar)
        case .updateChatBusinessBotManageBar(let updateChatBusinessBotManageBar):
            nc.post(name: .updateChatBusinessBotManageBar, object: updateChatBusinessBotManageBar)
        case .updateChatAvailableReactions(let updateChatAvailableReactions):
            nc.post(name: .updateChatAvailableReactions, object: updateChatAvailableReactions)
        case .updateChatDraftMessage(let updateChatDraftMessage):
            nc.post(name: .updateChatDraftMessage, object: updateChatDraftMessage)
        case .updateChatEmojiStatus(let updateChatEmojiStatus):
            nc.post(name: .updateChatEmojiStatus, object: updateChatEmojiStatus)
        case .updateChatMessageSender(let updateChatMessageSender):
            nc.post(name: .updateChatMessageSender, object: updateChatMessageSender)
        case .updateChatMessageAutoDeleteTime(let updateChatMessageAutoDeleteTime):
            nc.post(name: .updateChatMessageAutoDeleteTime, object: updateChatMessageAutoDeleteTime)
        case .updateChatNotificationSettings(let updateChatNotificationSettings):
            nc.post(name: .updateChatNotificationSettings, object: updateChatNotificationSettings)
        case .updateChatPendingJoinRequests(let updateChatPendingJoinRequests):
            nc.post(name: .updateChatPendingJoinRequests, object: updateChatPendingJoinRequests)
        case .updateChatReplyMarkup(let updateChatReplyMarkup):
            nc.post(name: .updateChatReplyMarkup, object: updateChatReplyMarkup)
        case .updateChatBackground(let updateChatBackground):
            nc.post(name: .updateChatBackground, object: updateChatBackground)
        case .updateChatTheme(let updateChatTheme):
            nc.post(name: .updateChatTheme, object: updateChatTheme)
        case .updateChatUnreadMentionCount(let updateChatUnreadMentionCount):
            nc.post(name: .updateChatUnreadMentionCount, object: updateChatUnreadMentionCount)
        case .updateChatUnreadReactionCount(let updateChatUnreadReactionCount):
            nc.post(name: .updateChatUnreadReactionCount, object: updateChatUnreadReactionCount)
        case .updateChatVideoChat(let updateChatVideoChat):
            nc.post(name: .updateChatVideoChat, object: updateChatVideoChat)
        case .updateChatDefaultDisableNotification(let updateChatDefaultDisableNotification):
            nc.post(name: .updateChatDefaultDisableNotification, object: updateChatDefaultDisableNotification)
        case .updateChatHasProtectedContent(let updateChatHasProtectedContent):
            nc.post(name: .updateChatHasProtectedContent, object: updateChatHasProtectedContent)
        case .updateChatIsTranslatable(let updateChatIsTranslatable):
            nc.post(name: .updateChatIsTranslatable, object: updateChatIsTranslatable)
        case .updateChatIsMarkedAsUnread(let updateChatIsMarkedAsUnread):
            nc.post(name: .updateChatIsMarkedAsUnread, object: updateChatIsMarkedAsUnread)
        case .updateChatViewAsTopics(let updateChatViewAsTopics):
            nc.post(name: .updateChatViewAsTopics, object: updateChatViewAsTopics)
        case .updateChatBlockList(let updateChatBlockList):
            nc.post(name: .updateChatBlockList, object: updateChatBlockList)
        case .updateChatHasScheduledMessages(let updateChatHasScheduledMessages):
            nc.post(name: .updateChatHasScheduledMessages, object: updateChatHasScheduledMessages)
        case .updateChatFolders(let updateChatFolders):
            nc.post(name: .updateChatFolders, object: updateChatFolders)
        case .updateChatOnlineMemberCount(let updateChatOnlineMemberCount):
            nc.post(name: .updateChatOnlineMemberCount, object: updateChatOnlineMemberCount)
        case .updateSavedMessagesTopic(let updateSavedMessagesTopic):
            nc.post(name: .updateSavedMessagesTopic, object: updateSavedMessagesTopic)
        case .updateSavedMessagesTopicCount(let updateSavedMessagesTopicCount):
            nc.post(name: .updateSavedMessagesTopicCount, object: updateSavedMessagesTopicCount)
        case .updateQuickReplyShortcut(let updateQuickReplyShortcut):
            nc.post(name: .updateQuickReplyShortcut, object: updateQuickReplyShortcut)
        case .updateQuickReplyShortcutDeleted(let updateQuickReplyShortcutDeleted):
            nc.post(name: .updateQuickReplyShortcutDeleted, object: updateQuickReplyShortcutDeleted)
        case .updateQuickReplyShortcuts(let updateQuickReplyShortcuts):
            nc.post(name: .updateQuickReplyShortcuts, object: updateQuickReplyShortcuts)
        case .updateQuickReplyShortcutMessages(let updateQuickReplyShortcutMessages):
            nc.post(name: .updateQuickReplyShortcutMessages, object: updateQuickReplyShortcutMessages)
        case .updateForumTopicInfo(let updateForumTopicInfo):
            nc.post(name: .updateForumTopicInfo, object: updateForumTopicInfo)
        case .updateScopeNotificationSettings(let updateScopeNotificationSettings):
            nc.post(name: .updateScopeNotificationSettings, object: updateScopeNotificationSettings)
        case .updateReactionNotificationSettings(let updateReactionNotificationSettings):
            nc.post(name: .updateReactionNotificationSettings, object: updateReactionNotificationSettings)
        case .updateNotification(let updateNotification):
            nc.post(name: .updateNotification, object: updateNotification)
        case .updateNotificationGroup(let updateNotificationGroup):
            nc.post(name: .updateNotificationGroup, object: updateNotificationGroup)
        case .updateActiveNotifications(let updateActiveNotifications):
            nc.post(name: .updateActiveNotifications, object: updateActiveNotifications)
        case .updateHavePendingNotifications(let updateHavePendingNotifications):
            nc.post(name: .updateHavePendingNotifications, object: updateHavePendingNotifications)
        case .updateDeleteMessages(let updateDeleteMessages):
            nc.post(name: .updateDeleteMessages, object: updateDeleteMessages)
        case .updateChatAction(let updateChatAction):
            nc.post(name: .updateChatAction, object: updateChatAction)
        case .updateUserStatus(let updateUserStatus):
            nc.post(name: .updateUserStatus, object: updateUserStatus)
        case .updateUser(let updateUser):
            nc.post(name: .updateUser, object: updateUser)
        case .updateBasicGroup(let updateBasicGroup):
            nc.post(name: .updateBasicGroup, object: updateBasicGroup)
        case .updateSupergroup(let updateSupergroup):
            nc.post(name: .updateSupergroup, object: updateSupergroup)
        case .updateSecretChat(let updateSecretChat):
            nc.post(name: .updateSecretChat, object: updateSecretChat)
        case .updateUserFullInfo(let updateUserFullInfo):
            nc.post(name: .updateUserFullInfo, object: updateUserFullInfo)
        case .updateBasicGroupFullInfo(let updateBasicGroupFullInfo):
            nc.post(name: .updateBasicGroupFullInfo, object: updateBasicGroupFullInfo)
        case .updateSupergroupFullInfo(let updateSupergroupFullInfo):
            nc.post(name: .updateSupergroupFullInfo, object: updateSupergroupFullInfo)
        case .updateServiceNotification(let updateServiceNotification):
            nc.post(name: .updateServiceNotification, object: updateServiceNotification)
        case .updateFile(let updateFile):
            nc.post(name: .updateFile, object: updateFile)
        case .updateFileGenerationStart(let updateFileGenerationStart):
            nc.post(name: .updateFileGenerationStart, object: updateFileGenerationStart)
        case .updateFileGenerationStop(let updateFileGenerationStop):
            nc.post(name: .updateFileGenerationStop, object: updateFileGenerationStop)
        case .updateFileDownloads(let updateFileDownloads):
            nc.post(name: .updateFileDownloads, object: updateFileDownloads)
        case .updateFileAddedToDownloads(let updateFileAddedToDownloads):
            nc.post(name: .updateFileAddedToDownloads, object: updateFileAddedToDownloads)
        case .updateFileDownload(let updateFileDownload):
            nc.post(name: .updateFileDownload, object: updateFileDownload)
        case .updateFileRemovedFromDownloads(let updateFileRemovedFromDownloads):
            nc.post(name: .updateFileRemovedFromDownloads, object: updateFileRemovedFromDownloads)
        case .updateApplicationVerificationRequired(let updateApplicationVerificationRequired):
            nc.post(name: .updateApplicationVerificationRequired, object: updateApplicationVerificationRequired)
        case .updateCall(let updateCall):
            nc.post(name: .updateCall, object: updateCall)
        case .updateGroupCall(let updateGroupCall):
            nc.post(name: .updateGroupCall, object: updateGroupCall)
        case .updateGroupCallParticipant(let updateGroupCallParticipant):
            nc.post(name: .updateGroupCallParticipant, object: updateGroupCallParticipant)
        case .updateNewCallSignalingData(let updateNewCallSignalingData):
            nc.post(name: .updateNewCallSignalingData, object: updateNewCallSignalingData)
        case .updateUserPrivacySettingRules(let updateUserPrivacySettingRules):
            nc.post(name: .updateUserPrivacySettingRules, object: updateUserPrivacySettingRules)
        case .updateUnreadMessageCount(let updateUnreadMessageCount):
            nc.post(name: .updateUnreadMessageCount, object: updateUnreadMessageCount)
        case .updateUnreadChatCount(let updateUnreadChatCount):
            nc.post(name: .updateUnreadChatCount, object: updateUnreadChatCount)
        case .updateStory(let updateStory):
            nc.post(name: .updateStory, object: updateStory)
        case .updateStoryDeleted(let updateStoryDeleted):
            nc.post(name: .updateStoryDeleted, object: updateStoryDeleted)
        case .updateStorySendSucceeded(let updateStorySendSucceeded):
            nc.post(name: .updateStorySendSucceeded, object: updateStorySendSucceeded)
        case .updateStorySendFailed(let updateStorySendFailed):
            nc.post(name: .updateStorySendFailed, object: updateStorySendFailed)
        case .updateChatActiveStories(let updateChatActiveStories):
            nc.post(name: .updateChatActiveStories, object: updateChatActiveStories)
        case .updateStoryListChatCount(let updateStoryListChatCount):
            nc.post(name: .updateStoryListChatCount, object: updateStoryListChatCount)
        case .updateStoryStealthMode(let updateStoryStealthMode):
            nc.post(name: .updateStoryStealthMode, object: updateStoryStealthMode)
        case .updateOption(let updateOption):
            nc.post(name: .updateOption, object: updateOption)
        case .updateStickerSet(let updateStickerSet):
            nc.post(name: .updateStickerSet, object: updateStickerSet)
        case .updateInstalledStickerSets(let updateInstalledStickerSets):
            nc.post(name: .updateInstalledStickerSets, object: updateInstalledStickerSets)
        case .updateTrendingStickerSets(let updateTrendingStickerSets):
            nc.post(name: .updateTrendingStickerSets, object: updateTrendingStickerSets)
        case .updateRecentStickers(let updateRecentStickers):
            nc.post(name: .updateRecentStickers, object: updateRecentStickers)
        case .updateFavoriteStickers(let updateFavoriteStickers):
            nc.post(name: .updateFavoriteStickers, object: updateFavoriteStickers)
        case .updateSavedAnimations(let updateSavedAnimations):
            nc.post(name: .updateSavedAnimations, object: updateSavedAnimations)
        case .updateSavedNotificationSounds(let updateSavedNotificationSounds):
            nc.post(name: .updateSavedNotificationSounds, object: updateSavedNotificationSounds)
        case .updateDefaultBackground(let updateDefaultBackground):
            nc.post(name: .updateDefaultBackground, object: updateDefaultBackground)
        case .updateChatThemes(let updateChatThemes):
            nc.post(name: .updateChatThemes, object: updateChatThemes)
        case .updateAccentColors(let updateAccentColors):
            nc.post(name: .updateAccentColors, object: updateAccentColors)
        case .updateProfileAccentColors(let updateProfileAccentColors):
            nc.post(name: .updateProfileAccentColors, object: updateProfileAccentColors)
        case .updateLanguagePackStrings(let updateLanguagePackStrings):
            nc.post(name: .updateLanguagePackStrings, object: updateLanguagePackStrings)
        case .updateConnectionState(let updateConnectionState):
            nc.post(name: .updateConnectionState, object: updateConnectionState)
        case .updateTermsOfService(let updateTermsOfService):
            nc.post(name: .updateTermsOfService, object: updateTermsOfService)
        case .updateUnconfirmedSession(let updateUnconfirmedSession):
            nc.post(name: .updateUnconfirmedSession, object: updateUnconfirmedSession)
        case .updateAttachmentMenuBots(let updateAttachmentMenuBots):
            nc.post(name: .updateAttachmentMenuBots, object: updateAttachmentMenuBots)
        case .updateWebAppMessageSent(let updateWebAppMessageSent):
            nc.post(name: .updateWebAppMessageSent, object: updateWebAppMessageSent)
        case .updateActiveEmojiReactions(let updateActiveEmojiReactions):
            nc.post(name: .updateActiveEmojiReactions, object: updateActiveEmojiReactions)
        case .updateAvailableMessageEffects(let updateAvailableMessageEffects):
            nc.post(name: .updateAvailableMessageEffects, object: updateAvailableMessageEffects)
        case .updateDefaultReactionType(let updateDefaultReactionType):
            nc.post(name: .updateDefaultReactionType, object: updateDefaultReactionType)
        case .updateSavedMessagesTags(let updateSavedMessagesTags):
            nc.post(name: .updateSavedMessagesTags, object: updateSavedMessagesTags)
        case .updateActiveLiveLocationMessages(let updateActiveLiveLocationMessages):
            nc.post(name: .updateActiveLiveLocationMessages, object: updateActiveLiveLocationMessages)
        case .updateOwnedStarCount(let updateOwnedStarCount):
            nc.post(name: .updateOwnedStarCount, object: updateOwnedStarCount)
        case .updateChatRevenueAmount(let updateChatRevenueAmount):
            nc.post(name: .updateChatRevenueAmount, object: updateChatRevenueAmount)
        case .updateStarRevenueStatus(let updateStarRevenueStatus):
            nc.post(name: .updateStarRevenueStatus, object: updateStarRevenueStatus)
        case .updateSpeechRecognitionTrial(let updateSpeechRecognitionTrial):
            nc.post(name: .updateSpeechRecognitionTrial, object: updateSpeechRecognitionTrial)
        case .updateDiceEmojis(let updateDiceEmojis):
            nc.post(name: .updateDiceEmojis, object: updateDiceEmojis)
        case .updateAnimatedEmojiMessageClicked(let updateAnimatedEmojiMessageClicked):
            nc.post(name: .updateAnimatedEmojiMessageClicked, object: updateAnimatedEmojiMessageClicked)
        case .updateAnimationSearchParameters(let updateAnimationSearchParameters):
            nc.post(name: .updateAnimationSearchParameters, object: updateAnimationSearchParameters)
        case .updateSuggestedActions(let updateSuggestedActions):
            nc.post(name: .updateSuggestedActions, object: updateSuggestedActions)
        case .updateSpeedLimitNotification(let updateSpeedLimitNotification):
            nc.post(name: .updateSpeedLimitNotification, object: updateSpeedLimitNotification)
        case .updateContactCloseBirthdays(let updateContactCloseBirthdays):
            nc.post(name: .updateContactCloseBirthdays, object: updateContactCloseBirthdays)
        case .updateAutosaveSettings(let updateAutosaveSettings):
            nc.post(name: .updateAutosaveSettings, object: updateAutosaveSettings)
        case .updateBusinessConnection(let updateBusinessConnection):
            nc.post(name: .updateBusinessConnection, object: updateBusinessConnection)
        case .updateNewBusinessMessage(let updateNewBusinessMessage):
            nc.post(name: .updateNewBusinessMessage, object: updateNewBusinessMessage)
        case .updateBusinessMessageEdited(let updateBusinessMessageEdited):
            nc.post(name: .updateBusinessMessageEdited, object: updateBusinessMessageEdited)
        case .updateBusinessMessagesDeleted(let updateBusinessMessagesDeleted):
            nc.post(name: .updateBusinessMessagesDeleted, object: updateBusinessMessagesDeleted)
        case .updateNewInlineQuery(let updateNewInlineQuery):
            nc.post(name: .updateNewInlineQuery, object: updateNewInlineQuery)
        case .updateNewChosenInlineResult(let updateNewChosenInlineResult):
            nc.post(name: .updateNewChosenInlineResult, object: updateNewChosenInlineResult)
        case .updateNewCallbackQuery(let updateNewCallbackQuery):
            nc.post(name: .updateNewCallbackQuery, object: updateNewCallbackQuery)
        case .updateNewInlineCallbackQuery(let updateNewInlineCallbackQuery):
            nc.post(name: .updateNewInlineCallbackQuery, object: updateNewInlineCallbackQuery)
        case .updateNewBusinessCallbackQuery(let updateNewBusinessCallbackQuery):
            nc.post(name: .updateNewBusinessCallbackQuery, object: updateNewBusinessCallbackQuery)
        case .updateNewShippingQuery(let updateNewShippingQuery):
            nc.post(name: .updateNewShippingQuery, object: updateNewShippingQuery)
        case .updateNewPreCheckoutQuery(let updateNewPreCheckoutQuery):
            nc.post(name: .updateNewPreCheckoutQuery, object: updateNewPreCheckoutQuery)
        case .updateNewCustomEvent(let updateNewCustomEvent):
            nc.post(name: .updateNewCustomEvent, object: updateNewCustomEvent)
        case .updateNewCustomQuery(let updateNewCustomQuery):
            nc.post(name: .updateNewCustomQuery, object: updateNewCustomQuery)
        case .updatePoll(let updatePoll):
            nc.post(name: .updatePoll, object: updatePoll)
        case .updatePollAnswer(let updatePollAnswer):
            nc.post(name: .updatePollAnswer, object: updatePollAnswer)
        case .updateChatMember(let updateChatMember):
            nc.post(name: .updateChatMember, object: updateChatMember)
        case .updateNewChatJoinRequest(let updateNewChatJoinRequest):
            nc.post(name: .updateNewChatJoinRequest, object: updateNewChatJoinRequest)
        case .updateChatBoost(let updateChatBoost):
            nc.post(name: .updateChatBoost, object: updateChatBoost)
        case .updateMessageReaction(let updateMessageReaction):
            nc.post(name: .updateMessageReaction, object: updateMessageReaction)
        case .updateMessageReactions(let updateMessageReactions):
            nc.post(name: .updateMessageReactions, object: updateMessageReactions)
        case .updatePaidMediaPurchased(let updatePaidMediaPurchased):
            nc.post(name: .updatePaidMediaPurchased, object: updatePaidMediaPurchased)
    }
}

extension TdNotification {
    static var updateAuthorizationState: TdNotification<UpdateAuthorizationState> { .init(.updateAuthorizationState) }
    static var updateNewMessage: TdNotification<UpdateNewMessage> { .init(.updateNewMessage) }
    static var updateMessageSendAcknowledged: TdNotification<UpdateMessageSendAcknowledged> { .init(.updateMessageSendAcknowledged) }
    static var updateMessageSendSucceeded: TdNotification<UpdateMessageSendSucceeded> { .init(.updateMessageSendSucceeded) }
    static var updateMessageSendFailed: TdNotification<UpdateMessageSendFailed> { .init(.updateMessageSendFailed) }
    static var updateMessageContent: TdNotification<UpdateMessageContent> { .init(.updateMessageContent) }
    static var updateMessageEdited: TdNotification<UpdateMessageEdited> { .init(.updateMessageEdited) }
    static var updateMessageIsPinned: TdNotification<UpdateMessageIsPinned> { .init(.updateMessageIsPinned) }
    static var updateMessageInteractionInfo: TdNotification<UpdateMessageInteractionInfo> { .init(.updateMessageInteractionInfo) }
    static var updateMessageContentOpened: TdNotification<UpdateMessageContentOpened> { .init(.updateMessageContentOpened) }
    static var updateMessageMentionRead: TdNotification<UpdateMessageMentionRead> { .init(.updateMessageMentionRead) }
    static var updateMessageUnreadReactions: TdNotification<UpdateMessageUnreadReactions> { .init(.updateMessageUnreadReactions) }
    static var updateMessageFactCheck: TdNotification<UpdateMessageFactCheck> { .init(.updateMessageFactCheck) }
    static var updateMessageLiveLocationViewed: TdNotification<UpdateMessageLiveLocationViewed> { .init(.updateMessageLiveLocationViewed) }
    static var updateVideoPublished: TdNotification<UpdateVideoPublished> { .init(.updateVideoPublished) }
    static var updateNewChat: TdNotification<UpdateNewChat> { .init(.updateNewChat) }
    static var updateChatTitle: TdNotification<UpdateChatTitle> { .init(.updateChatTitle) }
    static var updateChatPhoto: TdNotification<UpdateChatPhoto> { .init(.updateChatPhoto) }
    static var updateChatAccentColors: TdNotification<UpdateChatAccentColors> { .init(.updateChatAccentColors) }
    static var updateChatPermissions: TdNotification<UpdateChatPermissions> { .init(.updateChatPermissions) }
    static var updateChatLastMessage: TdNotification<UpdateChatLastMessage> { .init(.updateChatLastMessage) }
    static var updateChatPosition: TdNotification<UpdateChatPosition> { .init(.updateChatPosition) }
    static var updateChatAddedToList: TdNotification<UpdateChatAddedToList> { .init(.updateChatAddedToList) }
    static var updateChatRemovedFromList: TdNotification<UpdateChatRemovedFromList> { .init(.updateChatRemovedFromList) }
    static var updateChatReadInbox: TdNotification<UpdateChatReadInbox> { .init(.updateChatReadInbox) }
    static var updateChatReadOutbox: TdNotification<UpdateChatReadOutbox> { .init(.updateChatReadOutbox) }
    static var updateChatActionBar: TdNotification<UpdateChatActionBar> { .init(.updateChatActionBar) }
    static var updateChatBusinessBotManageBar: TdNotification<UpdateChatBusinessBotManageBar> { .init(.updateChatBusinessBotManageBar) }
    static var updateChatAvailableReactions: TdNotification<UpdateChatAvailableReactions> { .init(.updateChatAvailableReactions) }
    static var updateChatDraftMessage: TdNotification<UpdateChatDraftMessage> { .init(.updateChatDraftMessage) }
    static var updateChatEmojiStatus: TdNotification<UpdateChatEmojiStatus> { .init(.updateChatEmojiStatus) }
    static var updateChatMessageSender: TdNotification<UpdateChatMessageSender> { .init(.updateChatMessageSender) }
    static var updateChatMessageAutoDeleteTime: TdNotification<UpdateChatMessageAutoDeleteTime> { .init(.updateChatMessageAutoDeleteTime) }
    static var updateChatNotificationSettings: TdNotification<UpdateChatNotificationSettings> { .init(.updateChatNotificationSettings) }
    static var updateChatPendingJoinRequests: TdNotification<UpdateChatPendingJoinRequests> { .init(.updateChatPendingJoinRequests) }
    static var updateChatReplyMarkup: TdNotification<UpdateChatReplyMarkup> { .init(.updateChatReplyMarkup) }
    static var updateChatBackground: TdNotification<UpdateChatBackground> { .init(.updateChatBackground) }
    static var updateChatTheme: TdNotification<UpdateChatTheme> { .init(.updateChatTheme) }
    static var updateChatUnreadMentionCount: TdNotification<UpdateChatUnreadMentionCount> { .init(.updateChatUnreadMentionCount) }
    static var updateChatUnreadReactionCount: TdNotification<UpdateChatUnreadReactionCount> { .init(.updateChatUnreadReactionCount) }
    static var updateChatVideoChat: TdNotification<UpdateChatVideoChat> { .init(.updateChatVideoChat) }
    static var updateChatDefaultDisableNotification: TdNotification<UpdateChatDefaultDisableNotification> { .init(.updateChatDefaultDisableNotification) }
    static var updateChatHasProtectedContent: TdNotification<UpdateChatHasProtectedContent> { .init(.updateChatHasProtectedContent) }
    static var updateChatIsTranslatable: TdNotification<UpdateChatIsTranslatable> { .init(.updateChatIsTranslatable) }
    static var updateChatIsMarkedAsUnread: TdNotification<UpdateChatIsMarkedAsUnread> { .init(.updateChatIsMarkedAsUnread) }
    static var updateChatViewAsTopics: TdNotification<UpdateChatViewAsTopics> { .init(.updateChatViewAsTopics) }
    static var updateChatBlockList: TdNotification<UpdateChatBlockList> { .init(.updateChatBlockList) }
    static var updateChatHasScheduledMessages: TdNotification<UpdateChatHasScheduledMessages> { .init(.updateChatHasScheduledMessages) }
    static var updateChatFolders: TdNotification<UpdateChatFolders> { .init(.updateChatFolders) }
    static var updateChatOnlineMemberCount: TdNotification<UpdateChatOnlineMemberCount> { .init(.updateChatOnlineMemberCount) }
    static var updateSavedMessagesTopic: TdNotification<UpdateSavedMessagesTopic> { .init(.updateSavedMessagesTopic) }
    static var updateSavedMessagesTopicCount: TdNotification<UpdateSavedMessagesTopicCount> { .init(.updateSavedMessagesTopicCount) }
    static var updateQuickReplyShortcut: TdNotification<UpdateQuickReplyShortcut> { .init(.updateQuickReplyShortcut) }
    static var updateQuickReplyShortcutDeleted: TdNotification<UpdateQuickReplyShortcutDeleted> { .init(.updateQuickReplyShortcutDeleted) }
    static var updateQuickReplyShortcuts: TdNotification<UpdateQuickReplyShortcuts> { .init(.updateQuickReplyShortcuts) }
    static var updateQuickReplyShortcutMessages: TdNotification<UpdateQuickReplyShortcutMessages> { .init(.updateQuickReplyShortcutMessages) }
    static var updateForumTopicInfo: TdNotification<UpdateForumTopicInfo> { .init(.updateForumTopicInfo) }
    static var updateScopeNotificationSettings: TdNotification<UpdateScopeNotificationSettings> { .init(.updateScopeNotificationSettings) }
    static var updateReactionNotificationSettings: TdNotification<UpdateReactionNotificationSettings> { .init(.updateReactionNotificationSettings) }
    static var updateNotification: TdNotification<UpdateNotification> { .init(.updateNotification) }
    static var updateNotificationGroup: TdNotification<UpdateNotificationGroup> { .init(.updateNotificationGroup) }
    static var updateActiveNotifications: TdNotification<UpdateActiveNotifications> { .init(.updateActiveNotifications) }
    static var updateHavePendingNotifications: TdNotification<UpdateHavePendingNotifications> { .init(.updateHavePendingNotifications) }
    static var updateDeleteMessages: TdNotification<UpdateDeleteMessages> { .init(.updateDeleteMessages) }
    static var updateChatAction: TdNotification<UpdateChatAction> { .init(.updateChatAction) }
    static var updateUserStatus: TdNotification<UpdateUserStatus> { .init(.updateUserStatus) }
    static var updateUser: TdNotification<UpdateUser> { .init(.updateUser) }
    static var updateBasicGroup: TdNotification<UpdateBasicGroup> { .init(.updateBasicGroup) }
    static var updateSupergroup: TdNotification<UpdateSupergroup> { .init(.updateSupergroup) }
    static var updateSecretChat: TdNotification<UpdateSecretChat> { .init(.updateSecretChat) }
    static var updateUserFullInfo: TdNotification<UpdateUserFullInfo> { .init(.updateUserFullInfo) }
    static var updateBasicGroupFullInfo: TdNotification<UpdateBasicGroupFullInfo> { .init(.updateBasicGroupFullInfo) }
    static var updateSupergroupFullInfo: TdNotification<UpdateSupergroupFullInfo> { .init(.updateSupergroupFullInfo) }
    static var updateServiceNotification: TdNotification<UpdateServiceNotification> { .init(.updateServiceNotification) }
    static var updateFile: TdNotification<UpdateFile> { .init(.updateFile) }
    static var updateFileGenerationStart: TdNotification<UpdateFileGenerationStart> { .init(.updateFileGenerationStart) }
    static var updateFileGenerationStop: TdNotification<UpdateFileGenerationStop> { .init(.updateFileGenerationStop) }
    static var updateFileDownloads: TdNotification<UpdateFileDownloads> { .init(.updateFileDownloads) }
    static var updateFileAddedToDownloads: TdNotification<UpdateFileAddedToDownloads> { .init(.updateFileAddedToDownloads) }
    static var updateFileDownload: TdNotification<UpdateFileDownload> { .init(.updateFileDownload) }
    static var updateFileRemovedFromDownloads: TdNotification<UpdateFileRemovedFromDownloads> { .init(.updateFileRemovedFromDownloads) }
    static var updateApplicationVerificationRequired: TdNotification<UpdateApplicationVerificationRequired> { .init(.updateApplicationVerificationRequired) }
    static var updateCall: TdNotification<UpdateCall> { .init(.updateCall) }
    static var updateGroupCall: TdNotification<UpdateGroupCall> { .init(.updateGroupCall) }
    static var updateGroupCallParticipant: TdNotification<UpdateGroupCallParticipant> { .init(.updateGroupCallParticipant) }
    static var updateNewCallSignalingData: TdNotification<UpdateNewCallSignalingData> { .init(.updateNewCallSignalingData) }
    static var updateUserPrivacySettingRules: TdNotification<UpdateUserPrivacySettingRules> { .init(.updateUserPrivacySettingRules) }
    static var updateUnreadMessageCount: TdNotification<UpdateUnreadMessageCount> { .init(.updateUnreadMessageCount) }
    static var updateUnreadChatCount: TdNotification<UpdateUnreadChatCount> { .init(.updateUnreadChatCount) }
    static var updateStory: TdNotification<UpdateStory> { .init(.updateStory) }
    static var updateStoryDeleted: TdNotification<UpdateStoryDeleted> { .init(.updateStoryDeleted) }
    static var updateStorySendSucceeded: TdNotification<UpdateStorySendSucceeded> { .init(.updateStorySendSucceeded) }
    static var updateStorySendFailed: TdNotification<UpdateStorySendFailed> { .init(.updateStorySendFailed) }
    static var updateChatActiveStories: TdNotification<UpdateChatActiveStories> { .init(.updateChatActiveStories) }
    static var updateStoryListChatCount: TdNotification<UpdateStoryListChatCount> { .init(.updateStoryListChatCount) }
    static var updateStoryStealthMode: TdNotification<UpdateStoryStealthMode> { .init(.updateStoryStealthMode) }
    static var updateOption: TdNotification<UpdateOption> { .init(.updateOption) }
    static var updateStickerSet: TdNotification<UpdateStickerSet> { .init(.updateStickerSet) }
    static var updateInstalledStickerSets: TdNotification<UpdateInstalledStickerSets> { .init(.updateInstalledStickerSets) }
    static var updateTrendingStickerSets: TdNotification<UpdateTrendingStickerSets> { .init(.updateTrendingStickerSets) }
    static var updateRecentStickers: TdNotification<UpdateRecentStickers> { .init(.updateRecentStickers) }
    static var updateFavoriteStickers: TdNotification<UpdateFavoriteStickers> { .init(.updateFavoriteStickers) }
    static var updateSavedAnimations: TdNotification<UpdateSavedAnimations> { .init(.updateSavedAnimations) }
    static var updateSavedNotificationSounds: TdNotification<UpdateSavedNotificationSounds> { .init(.updateSavedNotificationSounds) }
    static var updateDefaultBackground: TdNotification<UpdateDefaultBackground> { .init(.updateDefaultBackground) }
    static var updateChatThemes: TdNotification<UpdateChatThemes> { .init(.updateChatThemes) }
    static var updateAccentColors: TdNotification<UpdateAccentColors> { .init(.updateAccentColors) }
    static var updateProfileAccentColors: TdNotification<UpdateProfileAccentColors> { .init(.updateProfileAccentColors) }
    static var updateLanguagePackStrings: TdNotification<UpdateLanguagePackStrings> { .init(.updateLanguagePackStrings) }
    static var updateConnectionState: TdNotification<UpdateConnectionState> { .init(.updateConnectionState) }
    static var updateTermsOfService: TdNotification<UpdateTermsOfService> { .init(.updateTermsOfService) }
    static var updateUnconfirmedSession: TdNotification<UpdateUnconfirmedSession> { .init(.updateUnconfirmedSession) }
    static var updateAttachmentMenuBots: TdNotification<UpdateAttachmentMenuBots> { .init(.updateAttachmentMenuBots) }
    static var updateWebAppMessageSent: TdNotification<UpdateWebAppMessageSent> { .init(.updateWebAppMessageSent) }
    static var updateActiveEmojiReactions: TdNotification<UpdateActiveEmojiReactions> { .init(.updateActiveEmojiReactions) }
    static var updateAvailableMessageEffects: TdNotification<UpdateAvailableMessageEffects> { .init(.updateAvailableMessageEffects) }
    static var updateDefaultReactionType: TdNotification<UpdateDefaultReactionType> { .init(.updateDefaultReactionType) }
    static var updateSavedMessagesTags: TdNotification<UpdateSavedMessagesTags> { .init(.updateSavedMessagesTags) }
    static var updateActiveLiveLocationMessages: TdNotification<UpdateActiveLiveLocationMessages> { .init(.updateActiveLiveLocationMessages) }
    static var updateOwnedStarCount: TdNotification<UpdateOwnedStarCount> { .init(.updateOwnedStarCount) }
    static var updateChatRevenueAmount: TdNotification<UpdateChatRevenueAmount> { .init(.updateChatRevenueAmount) }
    static var updateStarRevenueStatus: TdNotification<UpdateStarRevenueStatus> { .init(.updateStarRevenueStatus) }
    static var updateSpeechRecognitionTrial: TdNotification<UpdateSpeechRecognitionTrial> { .init(.updateSpeechRecognitionTrial) }
    static var updateDiceEmojis: TdNotification<UpdateDiceEmojis> { .init(.updateDiceEmojis) }
    static var updateAnimatedEmojiMessageClicked: TdNotification<UpdateAnimatedEmojiMessageClicked> { .init(.updateAnimatedEmojiMessageClicked) }
    static var updateAnimationSearchParameters: TdNotification<UpdateAnimationSearchParameters> { .init(.updateAnimationSearchParameters) }
    static var updateSuggestedActions: TdNotification<UpdateSuggestedActions> { .init(.updateSuggestedActions) }
    static var updateSpeedLimitNotification: TdNotification<UpdateSpeedLimitNotification> { .init(.updateSpeedLimitNotification) }
    static var updateContactCloseBirthdays: TdNotification<UpdateContactCloseBirthdays> { .init(.updateContactCloseBirthdays) }
    static var updateAutosaveSettings: TdNotification<UpdateAutosaveSettings> { .init(.updateAutosaveSettings) }
    static var updateBusinessConnection: TdNotification<UpdateBusinessConnection> { .init(.updateBusinessConnection) }
    static var updateNewBusinessMessage: TdNotification<UpdateNewBusinessMessage> { .init(.updateNewBusinessMessage) }
    static var updateBusinessMessageEdited: TdNotification<UpdateBusinessMessageEdited> { .init(.updateBusinessMessageEdited) }
    static var updateBusinessMessagesDeleted: TdNotification<UpdateBusinessMessagesDeleted> { .init(.updateBusinessMessagesDeleted) }
    static var updateNewInlineQuery: TdNotification<UpdateNewInlineQuery> { .init(.updateNewInlineQuery) }
    static var updateNewChosenInlineResult: TdNotification<UpdateNewChosenInlineResult> { .init(.updateNewChosenInlineResult) }
    static var updateNewCallbackQuery: TdNotification<UpdateNewCallbackQuery> { .init(.updateNewCallbackQuery) }
    static var updateNewInlineCallbackQuery: TdNotification<UpdateNewInlineCallbackQuery> { .init(.updateNewInlineCallbackQuery) }
    static var updateNewBusinessCallbackQuery: TdNotification<UpdateNewBusinessCallbackQuery> { .init(.updateNewBusinessCallbackQuery) }
    static var updateNewShippingQuery: TdNotification<UpdateNewShippingQuery> { .init(.updateNewShippingQuery) }
    static var updateNewPreCheckoutQuery: TdNotification<UpdateNewPreCheckoutQuery> { .init(.updateNewPreCheckoutQuery) }
    static var updateNewCustomEvent: TdNotification<UpdateNewCustomEvent> { .init(.updateNewCustomEvent) }
    static var updateNewCustomQuery: TdNotification<UpdateNewCustomQuery> { .init(.updateNewCustomQuery) }
    static var updatePoll: TdNotification<UpdatePoll> { .init(.updatePoll) }
    static var updatePollAnswer: TdNotification<UpdatePollAnswer> { .init(.updatePollAnswer) }
    static var updateChatMember: TdNotification<UpdateChatMember> { .init(.updateChatMember) }
    static var updateNewChatJoinRequest: TdNotification<UpdateNewChatJoinRequest> { .init(.updateNewChatJoinRequest) }
    static var updateChatBoost: TdNotification<UpdateChatBoost> { .init(.updateChatBoost) }
    static var updateMessageReaction: TdNotification<UpdateMessageReaction> { .init(.updateMessageReaction) }
    static var updateMessageReactions: TdNotification<UpdateMessageReactions> { .init(.updateMessageReactions) }
    static var updatePaidMediaPurchased: TdNotification<UpdatePaidMediaPurchased> { .init(.updatePaidMediaPurchased) }
}

extension Foundation.Notification.Name {
    static let updateAuthorizationState = Self("updateAuthorizationState")
    static let updateNewMessage = Self("updateNewMessage")
    static let updateMessageSendAcknowledged = Self("updateMessageSendAcknowledged")
    static let updateMessageSendSucceeded = Self("updateMessageSendSucceeded")
    static let updateMessageSendFailed = Self("updateMessageSendFailed")
    static let updateMessageContent = Self("updateMessageContent")
    static let updateMessageEdited = Self("updateMessageEdited")
    static let updateMessageIsPinned = Self("updateMessageIsPinned")
    static let updateMessageInteractionInfo = Self("updateMessageInteractionInfo")
    static let updateMessageContentOpened = Self("updateMessageContentOpened")
    static let updateMessageMentionRead = Self("updateMessageMentionRead")
    static let updateMessageUnreadReactions = Self("updateMessageUnreadReactions")
    static let updateMessageFactCheck = Self("updateMessageFactCheck")
    static let updateMessageLiveLocationViewed = Self("updateMessageLiveLocationViewed")
    static let updateVideoPublished = Self("updateVideoPublished")
    static let updateNewChat = Self("updateNewChat")
    static let updateChatTitle = Self("updateChatTitle")
    static let updateChatPhoto = Self("updateChatPhoto")
    static let updateChatAccentColors = Self("updateChatAccentColors")
    static let updateChatPermissions = Self("updateChatPermissions")
    static let updateChatLastMessage = Self("updateChatLastMessage")
    static let updateChatPosition = Self("updateChatPosition")
    static let updateChatAddedToList = Self("updateChatAddedToList")
    static let updateChatRemovedFromList = Self("updateChatRemovedFromList")
    static let updateChatReadInbox = Self("updateChatReadInbox")
    static let updateChatReadOutbox = Self("updateChatReadOutbox")
    static let updateChatActionBar = Self("updateChatActionBar")
    static let updateChatBusinessBotManageBar = Self("updateChatBusinessBotManageBar")
    static let updateChatAvailableReactions = Self("updateChatAvailableReactions")
    static let updateChatDraftMessage = Self("updateChatDraftMessage")
    static let updateChatEmojiStatus = Self("updateChatEmojiStatus")
    static let updateChatMessageSender = Self("updateChatMessageSender")
    static let updateChatMessageAutoDeleteTime = Self("updateChatMessageAutoDeleteTime")
    static let updateChatNotificationSettings = Self("updateChatNotificationSettings")
    static let updateChatPendingJoinRequests = Self("updateChatPendingJoinRequests")
    static let updateChatReplyMarkup = Self("updateChatReplyMarkup")
    static let updateChatBackground = Self("updateChatBackground")
    static let updateChatTheme = Self("updateChatTheme")
    static let updateChatUnreadMentionCount = Self("updateChatUnreadMentionCount")
    static let updateChatUnreadReactionCount = Self("updateChatUnreadReactionCount")
    static let updateChatVideoChat = Self("updateChatVideoChat")
    static let updateChatDefaultDisableNotification = Self("updateChatDefaultDisableNotification")
    static let updateChatHasProtectedContent = Self("updateChatHasProtectedContent")
    static let updateChatIsTranslatable = Self("updateChatIsTranslatable")
    static let updateChatIsMarkedAsUnread = Self("updateChatIsMarkedAsUnread")
    static let updateChatViewAsTopics = Self("updateChatViewAsTopics")
    static let updateChatBlockList = Self("updateChatBlockList")
    static let updateChatHasScheduledMessages = Self("updateChatHasScheduledMessages")
    static let updateChatFolders = Self("updateChatFolders")
    static let updateChatOnlineMemberCount = Self("updateChatOnlineMemberCount")
    static let updateSavedMessagesTopic = Self("updateSavedMessagesTopic")
    static let updateSavedMessagesTopicCount = Self("updateSavedMessagesTopicCount")
    static let updateQuickReplyShortcut = Self("updateQuickReplyShortcut")
    static let updateQuickReplyShortcutDeleted = Self("updateQuickReplyShortcutDeleted")
    static let updateQuickReplyShortcuts = Self("updateQuickReplyShortcuts")
    static let updateQuickReplyShortcutMessages = Self("updateQuickReplyShortcutMessages")
    static let updateForumTopicInfo = Self("updateForumTopicInfo")
    static let updateScopeNotificationSettings = Self("updateScopeNotificationSettings")
    static let updateReactionNotificationSettings = Self("updateReactionNotificationSettings")
    static let updateNotification = Self("updateNotification")
    static let updateNotificationGroup = Self("updateNotificationGroup")
    static let updateActiveNotifications = Self("updateActiveNotifications")
    static let updateHavePendingNotifications = Self("updateHavePendingNotifications")
    static let updateDeleteMessages = Self("updateDeleteMessages")
    static let updateChatAction = Self("updateChatAction")
    static let updateUserStatus = Self("updateUserStatus")
    static let updateUser = Self("updateUser")
    static let updateBasicGroup = Self("updateBasicGroup")
    static let updateSupergroup = Self("updateSupergroup")
    static let updateSecretChat = Self("updateSecretChat")
    static let updateUserFullInfo = Self("updateUserFullInfo")
    static let updateBasicGroupFullInfo = Self("updateBasicGroupFullInfo")
    static let updateSupergroupFullInfo = Self("updateSupergroupFullInfo")
    static let updateServiceNotification = Self("updateServiceNotification")
    static let updateFile = Self("updateFile")
    static let updateFileGenerationStart = Self("updateFileGenerationStart")
    static let updateFileGenerationStop = Self("updateFileGenerationStop")
    static let updateFileDownloads = Self("updateFileDownloads")
    static let updateFileAddedToDownloads = Self("updateFileAddedToDownloads")
    static let updateFileDownload = Self("updateFileDownload")
    static let updateFileRemovedFromDownloads = Self("updateFileRemovedFromDownloads")
    static let updateApplicationVerificationRequired = Self("updateApplicationVerificationRequired")
    static let updateCall = Self("updateCall")
    static let updateGroupCall = Self("updateGroupCall")
    static let updateGroupCallParticipant = Self("updateGroupCallParticipant")
    static let updateNewCallSignalingData = Self("updateNewCallSignalingData")
    static let updateUserPrivacySettingRules = Self("updateUserPrivacySettingRules")
    static let updateUnreadMessageCount = Self("updateUnreadMessageCount")
    static let updateUnreadChatCount = Self("updateUnreadChatCount")
    static let updateStory = Self("updateStory")
    static let updateStoryDeleted = Self("updateStoryDeleted")
    static let updateStorySendSucceeded = Self("updateStorySendSucceeded")
    static let updateStorySendFailed = Self("updateStorySendFailed")
    static let updateChatActiveStories = Self("updateChatActiveStories")
    static let updateStoryListChatCount = Self("updateStoryListChatCount")
    static let updateStoryStealthMode = Self("updateStoryStealthMode")
    static let updateOption = Self("updateOption")
    static let updateStickerSet = Self("updateStickerSet")
    static let updateInstalledStickerSets = Self("updateInstalledStickerSets")
    static let updateTrendingStickerSets = Self("updateTrendingStickerSets")
    static let updateRecentStickers = Self("updateRecentStickers")
    static let updateFavoriteStickers = Self("updateFavoriteStickers")
    static let updateSavedAnimations = Self("updateSavedAnimations")
    static let updateSavedNotificationSounds = Self("updateSavedNotificationSounds")
    static let updateDefaultBackground = Self("updateDefaultBackground")
    static let updateChatThemes = Self("updateChatThemes")
    static let updateAccentColors = Self("updateAccentColors")
    static let updateProfileAccentColors = Self("updateProfileAccentColors")
    static let updateLanguagePackStrings = Self("updateLanguagePackStrings")
    static let updateConnectionState = Self("updateConnectionState")
    static let updateTermsOfService = Self("updateTermsOfService")
    static let updateUnconfirmedSession = Self("updateUnconfirmedSession")
    static let updateAttachmentMenuBots = Self("updateAttachmentMenuBots")
    static let updateWebAppMessageSent = Self("updateWebAppMessageSent")
    static let updateActiveEmojiReactions = Self("updateActiveEmojiReactions")
    static let updateAvailableMessageEffects = Self("updateAvailableMessageEffects")
    static let updateDefaultReactionType = Self("updateDefaultReactionType")
    static let updateSavedMessagesTags = Self("updateSavedMessagesTags")
    static let updateActiveLiveLocationMessages = Self("updateActiveLiveLocationMessages")
    static let updateOwnedStarCount = Self("updateOwnedStarCount")
    static let updateChatRevenueAmount = Self("updateChatRevenueAmount")
    static let updateStarRevenueStatus = Self("updateStarRevenueStatus")
    static let updateSpeechRecognitionTrial = Self("updateSpeechRecognitionTrial")
    static let updateDiceEmojis = Self("updateDiceEmojis")
    static let updateAnimatedEmojiMessageClicked = Self("updateAnimatedEmojiMessageClicked")
    static let updateAnimationSearchParameters = Self("updateAnimationSearchParameters")
    static let updateSuggestedActions = Self("updateSuggestedActions")
    static let updateSpeedLimitNotification = Self("updateSpeedLimitNotification")
    static let updateContactCloseBirthdays = Self("updateContactCloseBirthdays")
    static let updateAutosaveSettings = Self("updateAutosaveSettings")
    static let updateBusinessConnection = Self("updateBusinessConnection")
    static let updateNewBusinessMessage = Self("updateNewBusinessMessage")
    static let updateBusinessMessageEdited = Self("updateBusinessMessageEdited")
    static let updateBusinessMessagesDeleted = Self("updateBusinessMessagesDeleted")
    static let updateNewInlineQuery = Self("updateNewInlineQuery")
    static let updateNewChosenInlineResult = Self("updateNewChosenInlineResult")
    static let updateNewCallbackQuery = Self("updateNewCallbackQuery")
    static let updateNewInlineCallbackQuery = Self("updateNewInlineCallbackQuery")
    static let updateNewBusinessCallbackQuery = Self("updateNewBusinessCallbackQuery")
    static let updateNewShippingQuery = Self("updateNewShippingQuery")
    static let updateNewPreCheckoutQuery = Self("updateNewPreCheckoutQuery")
    static let updateNewCustomEvent = Self("updateNewCustomEvent")
    static let updateNewCustomQuery = Self("updateNewCustomQuery")
    static let updatePoll = Self("updatePoll")
    static let updatePollAnswer = Self("updatePollAnswer")
    static let updateChatMember = Self("updateChatMember")
    static let updateNewChatJoinRequest = Self("updateNewChatJoinRequest")
    static let updateChatBoost = Self("updateChatBoost")
    static let updateMessageReaction = Self("updateMessageReaction")
    static let updateMessageReactions = Self("updateMessageReactions")
    static let updatePaidMediaPurchased = Self("updatePaidMediaPurchased")
}

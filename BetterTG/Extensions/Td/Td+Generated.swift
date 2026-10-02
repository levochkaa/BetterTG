// Td+Generated.swift

// This file is generated from td.py
// Any modifications will be overwritten

import Foundation
import TDLibKitDynamic

func update(
    _ update: Update,
    source: TdUpdateSource? = nil,
    notificationCenter: NotificationCenter = nc
) {
    switch update {
        case .updateAuthorizationState(let updateAuthorizationState):
            notificationCenter.postTdUpdate(name: .updateAuthorizationState, object: updateAuthorizationState, source: source)
        case .updateNewMessage(let updateNewMessage):
            notificationCenter.postTdUpdate(name: .updateNewMessage, object: updateNewMessage, source: source)
        case .updateMessageSendAcknowledged(let updateMessageSendAcknowledged):
            notificationCenter.postTdUpdate(name: .updateMessageSendAcknowledged, object: updateMessageSendAcknowledged, source: source)
        case .updateMessageSendSucceeded(let updateMessageSendSucceeded):
            notificationCenter.postTdUpdate(name: .updateMessageSendSucceeded, object: updateMessageSendSucceeded, source: source)
        case .updateMessageSendFailed(let updateMessageSendFailed):
            notificationCenter.postTdUpdate(name: .updateMessageSendFailed, object: updateMessageSendFailed, source: source)
        case .updateMessageContent(let updateMessageContent):
            notificationCenter.postTdUpdate(name: .updateMessageContent, object: updateMessageContent, source: source)
        case .updateMessageEdited(let updateMessageEdited):
            notificationCenter.postTdUpdate(name: .updateMessageEdited, object: updateMessageEdited, source: source)
        case .updateMessageIsPinned(let updateMessageIsPinned):
            notificationCenter.postTdUpdate(name: .updateMessageIsPinned, object: updateMessageIsPinned, source: source)
        case .updateMessageInteractionInfo(let updateMessageInteractionInfo):
            notificationCenter.postTdUpdate(name: .updateMessageInteractionInfo, object: updateMessageInteractionInfo, source: source)
        case .updateMessageContentOpened(let updateMessageContentOpened):
            notificationCenter.postTdUpdate(name: .updateMessageContentOpened, object: updateMessageContentOpened, source: source)
        case .updateMessageMentionRead(let updateMessageMentionRead):
            notificationCenter.postTdUpdate(name: .updateMessageMentionRead, object: updateMessageMentionRead, source: source)
        case .updateMessageUnreadReactions(let updateMessageUnreadReactions):
            notificationCenter.postTdUpdate(name: .updateMessageUnreadReactions, object: updateMessageUnreadReactions, source: source)
        case .updateMessageContainsUnreadPollVotes(let updateMessageContainsUnreadPollVotes):
            notificationCenter.postTdUpdate(name: .updateMessageContainsUnreadPollVotes, object: updateMessageContainsUnreadPollVotes, source: source)
        case .updateMessageFactCheck(let updateMessageFactCheck):
            notificationCenter.postTdUpdate(name: .updateMessageFactCheck, object: updateMessageFactCheck, source: source)
        case .updateMessageSuggestedPostInfo(let updateMessageSuggestedPostInfo):
            notificationCenter.postTdUpdate(name: .updateMessageSuggestedPostInfo, object: updateMessageSuggestedPostInfo, source: source)
        case .updateMessageLiveLocationViewed(let updateMessageLiveLocationViewed):
            notificationCenter.postTdUpdate(name: .updateMessageLiveLocationViewed, object: updateMessageLiveLocationViewed, source: source)
        case .updateVideoPublished(let updateVideoPublished):
            notificationCenter.postTdUpdate(name: .updateVideoPublished, object: updateVideoPublished, source: source)
        case .updateNewChat(let updateNewChat):
            notificationCenter.postTdUpdate(name: .updateNewChat, object: updateNewChat, source: source)
        case .updateChatTitle(let updateChatTitle):
            notificationCenter.postTdUpdate(name: .updateChatTitle, object: updateChatTitle, source: source)
        case .updateChatPhoto(let updateChatPhoto):
            notificationCenter.postTdUpdate(name: .updateChatPhoto, object: updateChatPhoto, source: source)
        case .updateChatAccentColors(let updateChatAccentColors):
            notificationCenter.postTdUpdate(name: .updateChatAccentColors, object: updateChatAccentColors, source: source)
        case .updateChatPermissions(let updateChatPermissions):
            notificationCenter.postTdUpdate(name: .updateChatPermissions, object: updateChatPermissions, source: source)
        case .updateChatLastMessage(let updateChatLastMessage):
            notificationCenter.postTdUpdate(name: .updateChatLastMessage, object: updateChatLastMessage, source: source)
        case .updateChatPosition(let updateChatPosition):
            notificationCenter.postTdUpdate(name: .updateChatPosition, object: updateChatPosition, source: source)
        case .updateChatAddedToList(let updateChatAddedToList):
            notificationCenter.postTdUpdate(name: .updateChatAddedToList, object: updateChatAddedToList, source: source)
        case .updateChatRemovedFromList(let updateChatRemovedFromList):
            notificationCenter.postTdUpdate(name: .updateChatRemovedFromList, object: updateChatRemovedFromList, source: source)
        case .updateChatReadInbox(let updateChatReadInbox):
            notificationCenter.postTdUpdate(name: .updateChatReadInbox, object: updateChatReadInbox, source: source)
        case .updateChatReadOutbox(let updateChatReadOutbox):
            notificationCenter.postTdUpdate(name: .updateChatReadOutbox, object: updateChatReadOutbox, source: source)
        case .updateChatActionBar(let updateChatActionBar):
            notificationCenter.postTdUpdate(name: .updateChatActionBar, object: updateChatActionBar, source: source)
        case .updateChatBusinessBotManageBar(let updateChatBusinessBotManageBar):
            notificationCenter.postTdUpdate(name: .updateChatBusinessBotManageBar, object: updateChatBusinessBotManageBar, source: source)
        case .updateChatAvailableReactions(let updateChatAvailableReactions):
            notificationCenter.postTdUpdate(name: .updateChatAvailableReactions, object: updateChatAvailableReactions, source: source)
        case .updateChatDraftMessage(let updateChatDraftMessage):
            notificationCenter.postTdUpdate(name: .updateChatDraftMessage, object: updateChatDraftMessage, source: source)
        case .updateChatEmojiStatus(let updateChatEmojiStatus):
            notificationCenter.postTdUpdate(name: .updateChatEmojiStatus, object: updateChatEmojiStatus, source: source)
        case .updateChatMessageSender(let updateChatMessageSender):
            notificationCenter.postTdUpdate(name: .updateChatMessageSender, object: updateChatMessageSender, source: source)
        case .updateChatMessageAutoDeleteTime(let updateChatMessageAutoDeleteTime):
            notificationCenter.postTdUpdate(name: .updateChatMessageAutoDeleteTime, object: updateChatMessageAutoDeleteTime, source: source)
        case .updateChatNotificationSettings(let updateChatNotificationSettings):
            notificationCenter.postTdUpdate(name: .updateChatNotificationSettings, object: updateChatNotificationSettings, source: source)
        case .updateChatPendingJoinRequests(let updateChatPendingJoinRequests):
            notificationCenter.postTdUpdate(name: .updateChatPendingJoinRequests, object: updateChatPendingJoinRequests, source: source)
        case .updateChatReplyMarkup(let updateChatReplyMarkup):
            notificationCenter.postTdUpdate(name: .updateChatReplyMarkup, object: updateChatReplyMarkup, source: source)
        case .updateChatBackground(let updateChatBackground):
            notificationCenter.postTdUpdate(name: .updateChatBackground, object: updateChatBackground, source: source)
        case .updateChatTheme(let updateChatTheme):
            notificationCenter.postTdUpdate(name: .updateChatTheme, object: updateChatTheme, source: source)
        case .updateChatUnreadMentionCount(let updateChatUnreadMentionCount):
            notificationCenter.postTdUpdate(name: .updateChatUnreadMentionCount, object: updateChatUnreadMentionCount, source: source)
        case .updateChatUnreadReactionCount(let updateChatUnreadReactionCount):
            notificationCenter.postTdUpdate(name: .updateChatUnreadReactionCount, object: updateChatUnreadReactionCount, source: source)
        case .updateChatUnreadPollVoteCount(let updateChatUnreadPollVoteCount):
            notificationCenter.postTdUpdate(name: .updateChatUnreadPollVoteCount, object: updateChatUnreadPollVoteCount, source: source)
        case .updateChatVideoChat(let updateChatVideoChat):
            notificationCenter.postTdUpdate(name: .updateChatVideoChat, object: updateChatVideoChat, source: source)
        case .updateChatDefaultDisableNotification(let updateChatDefaultDisableNotification):
            notificationCenter.postTdUpdate(name: .updateChatDefaultDisableNotification, object: updateChatDefaultDisableNotification, source: source)
        case .updateChatHasProtectedContent(let updateChatHasProtectedContent):
            notificationCenter.postTdUpdate(name: .updateChatHasProtectedContent, object: updateChatHasProtectedContent, source: source)
        case .updateChatIsTranslatable(let updateChatIsTranslatable):
            notificationCenter.postTdUpdate(name: .updateChatIsTranslatable, object: updateChatIsTranslatable, source: source)
        case .updateChatIsMarkedAsUnread(let updateChatIsMarkedAsUnread):
            notificationCenter.postTdUpdate(name: .updateChatIsMarkedAsUnread, object: updateChatIsMarkedAsUnread, source: source)
        case .updateChatViewAsTopics(let updateChatViewAsTopics):
            notificationCenter.postTdUpdate(name: .updateChatViewAsTopics, object: updateChatViewAsTopics, source: source)
        case .updateChatBlockList(let updateChatBlockList):
            notificationCenter.postTdUpdate(name: .updateChatBlockList, object: updateChatBlockList, source: source)
        case .updateChatHasScheduledMessages(let updateChatHasScheduledMessages):
            notificationCenter.postTdUpdate(name: .updateChatHasScheduledMessages, object: updateChatHasScheduledMessages, source: source)
        case .updateChatFolders(let updateChatFolders):
            notificationCenter.postTdUpdate(name: .updateChatFolders, object: updateChatFolders, source: source)
        case .updateChatOnlineMemberCount(let updateChatOnlineMemberCount):
            notificationCenter.postTdUpdate(name: .updateChatOnlineMemberCount, object: updateChatOnlineMemberCount, source: source)
        case .updateSavedMessagesTopic(let updateSavedMessagesTopic):
            notificationCenter.postTdUpdate(name: .updateSavedMessagesTopic, object: updateSavedMessagesTopic, source: source)
        case .updateSavedMessagesTopicCount(let updateSavedMessagesTopicCount):
            notificationCenter.postTdUpdate(name: .updateSavedMessagesTopicCount, object: updateSavedMessagesTopicCount, source: source)
        case .updateDirectMessagesChatTopic(let updateDirectMessagesChatTopic):
            notificationCenter.postTdUpdate(name: .updateDirectMessagesChatTopic, object: updateDirectMessagesChatTopic, source: source)
        case .updateTopicMessageCount(let updateTopicMessageCount):
            notificationCenter.postTdUpdate(name: .updateTopicMessageCount, object: updateTopicMessageCount, source: source)
        case .updateQuickReplyShortcut(let updateQuickReplyShortcut):
            notificationCenter.postTdUpdate(name: .updateQuickReplyShortcut, object: updateQuickReplyShortcut, source: source)
        case .updateQuickReplyShortcutDeleted(let updateQuickReplyShortcutDeleted):
            notificationCenter.postTdUpdate(name: .updateQuickReplyShortcutDeleted, object: updateQuickReplyShortcutDeleted, source: source)
        case .updateQuickReplyShortcuts(let updateQuickReplyShortcuts):
            notificationCenter.postTdUpdate(name: .updateQuickReplyShortcuts, object: updateQuickReplyShortcuts, source: source)
        case .updateQuickReplyShortcutMessages(let updateQuickReplyShortcutMessages):
            notificationCenter.postTdUpdate(name: .updateQuickReplyShortcutMessages, object: updateQuickReplyShortcutMessages, source: source)
        case .updateForumTopicInfo(let updateForumTopicInfo):
            notificationCenter.postTdUpdate(name: .updateForumTopicInfo, object: updateForumTopicInfo, source: source)
        case .updateForumTopic(let updateForumTopic):
            notificationCenter.postTdUpdate(name: .updateForumTopic, object: updateForumTopic, source: source)
        case .updateScopeNotificationSettings(let updateScopeNotificationSettings):
            notificationCenter.postTdUpdate(name: .updateScopeNotificationSettings, object: updateScopeNotificationSettings, source: source)
        case .updateReactionNotificationSettings(let updateReactionNotificationSettings):
            notificationCenter.postTdUpdate(name: .updateReactionNotificationSettings, object: updateReactionNotificationSettings, source: source)
        case .updateNotification(let updateNotification):
            notificationCenter.postTdUpdate(name: .updateNotification, object: updateNotification, source: source)
        case .updateNotificationGroup(let updateNotificationGroup):
            notificationCenter.postTdUpdate(name: .updateNotificationGroup, object: updateNotificationGroup, source: source)
        case .updateActiveNotifications(let updateActiveNotifications):
            notificationCenter.postTdUpdate(name: .updateActiveNotifications, object: updateActiveNotifications, source: source)
        case .updateHavePendingNotifications(let updateHavePendingNotifications):
            notificationCenter.postTdUpdate(name: .updateHavePendingNotifications, object: updateHavePendingNotifications, source: source)
        case .updateDeleteMessages(let updateDeleteMessages):
            notificationCenter.postTdUpdate(name: .updateDeleteMessages, object: updateDeleteMessages, source: source)
        case .updateChatAction(let updateChatAction):
            notificationCenter.postTdUpdate(name: .updateChatAction, object: updateChatAction, source: source)
        case .updatePendingMessage(let updatePendingMessage):
            notificationCenter.postTdUpdate(name: .updatePendingMessage, object: updatePendingMessage, source: source)
        case .updateCommunity(let updateCommunity):
            notificationCenter.postTdUpdate(name: .updateCommunity, object: updateCommunity, source: source)
        case .updateUserStatus(let updateUserStatus):
            notificationCenter.postTdUpdate(name: .updateUserStatus, object: updateUserStatus, source: source)
        case .updateUser(let updateUser):
            notificationCenter.postTdUpdate(name: .updateUser, object: updateUser, source: source)
        case .updateBasicGroup(let updateBasicGroup):
            notificationCenter.postTdUpdate(name: .updateBasicGroup, object: updateBasicGroup, source: source)
        case .updateSupergroup(let updateSupergroup):
            notificationCenter.postTdUpdate(name: .updateSupergroup, object: updateSupergroup, source: source)
        case .updateSecretChat(let updateSecretChat):
            notificationCenter.postTdUpdate(name: .updateSecretChat, object: updateSecretChat, source: source)
        case .updateUserFullInfo(let updateUserFullInfo):
            notificationCenter.postTdUpdate(name: .updateUserFullInfo, object: updateUserFullInfo, source: source)
        case .updateBasicGroupFullInfo(let updateBasicGroupFullInfo):
            notificationCenter.postTdUpdate(name: .updateBasicGroupFullInfo, object: updateBasicGroupFullInfo, source: source)
        case .updateSupergroupFullInfo(let updateSupergroupFullInfo):
            notificationCenter.postTdUpdate(name: .updateSupergroupFullInfo, object: updateSupergroupFullInfo, source: source)
        case .updateServiceNotification(let updateServiceNotification):
            notificationCenter.postTdUpdate(name: .updateServiceNotification, object: updateServiceNotification, source: source)
        case .updateNewOauthRequest(let updateNewOauthRequest):
            notificationCenter.postTdUpdate(name: .updateNewOauthRequest, object: updateNewOauthRequest, source: source)
        case .updateFile(let updateFile):
            notificationCenter.postTdUpdate(name: .updateFile, object: updateFile, source: source)
        case .updateFileGenerationStart(let updateFileGenerationStart):
            notificationCenter.postTdUpdate(name: .updateFileGenerationStart, object: updateFileGenerationStart, source: source)
        case .updateFileGenerationStop(let updateFileGenerationStop):
            notificationCenter.postTdUpdate(name: .updateFileGenerationStop, object: updateFileGenerationStop, source: source)
        case .updateFileDownloads(let updateFileDownloads):
            notificationCenter.postTdUpdate(name: .updateFileDownloads, object: updateFileDownloads, source: source)
        case .updateFileAddedToDownloads(let updateFileAddedToDownloads):
            notificationCenter.postTdUpdate(name: .updateFileAddedToDownloads, object: updateFileAddedToDownloads, source: source)
        case .updateFileDownload(let updateFileDownload):
            notificationCenter.postTdUpdate(name: .updateFileDownload, object: updateFileDownload, source: source)
        case .updateFileRemovedFromDownloads(let updateFileRemovedFromDownloads):
            notificationCenter.postTdUpdate(name: .updateFileRemovedFromDownloads, object: updateFileRemovedFromDownloads, source: source)
        case .updateApplicationVerificationRequired(let updateApplicationVerificationRequired):
            notificationCenter.postTdUpdate(name: .updateApplicationVerificationRequired, object: updateApplicationVerificationRequired, source: source)
        case .updateApplicationRecaptchaVerificationRequired(let updateApplicationRecaptchaVerificationRequired):
            notificationCenter.postTdUpdate(name: .updateApplicationRecaptchaVerificationRequired, object: updateApplicationRecaptchaVerificationRequired, source: source)
        case .updateCall(let updateCall):
            notificationCenter.postTdUpdate(name: .updateCall, object: updateCall, source: source)
        case .updateGroupCall(let updateGroupCall):
            notificationCenter.postTdUpdate(name: .updateGroupCall, object: updateGroupCall, source: source)
        case .updateGroupCallParticipant(let updateGroupCallParticipant):
            notificationCenter.postTdUpdate(name: .updateGroupCallParticipant, object: updateGroupCallParticipant, source: source)
        case .updateGroupCallParticipants(let updateGroupCallParticipants):
            notificationCenter.postTdUpdate(name: .updateGroupCallParticipants, object: updateGroupCallParticipants, source: source)
        case .updateGroupCallVerificationState(let updateGroupCallVerificationState):
            notificationCenter.postTdUpdate(name: .updateGroupCallVerificationState, object: updateGroupCallVerificationState, source: source)
        case .updateNewGroupCallMessage(let updateNewGroupCallMessage):
            notificationCenter.postTdUpdate(name: .updateNewGroupCallMessage, object: updateNewGroupCallMessage, source: source)
        case .updateNewGroupCallPaidReaction(let updateNewGroupCallPaidReaction):
            notificationCenter.postTdUpdate(name: .updateNewGroupCallPaidReaction, object: updateNewGroupCallPaidReaction, source: source)
        case .updateGroupCallMessageSendFailed(let updateGroupCallMessageSendFailed):
            notificationCenter.postTdUpdate(name: .updateGroupCallMessageSendFailed, object: updateGroupCallMessageSendFailed, source: source)
        case .updateGroupCallMessagesDeleted(let updateGroupCallMessagesDeleted):
            notificationCenter.postTdUpdate(name: .updateGroupCallMessagesDeleted, object: updateGroupCallMessagesDeleted, source: source)
        case .updateLiveStoryTopDonors(let updateLiveStoryTopDonors):
            notificationCenter.postTdUpdate(name: .updateLiveStoryTopDonors, object: updateLiveStoryTopDonors, source: source)
        case .updateNewCallSignalingData(let updateNewCallSignalingData):
            notificationCenter.postTdUpdate(name: .updateNewCallSignalingData, object: updateNewCallSignalingData, source: source)
        case .updateGiftAuctionState(let updateGiftAuctionState):
            notificationCenter.postTdUpdate(name: .updateGiftAuctionState, object: updateGiftAuctionState, source: source)
        case .updateActiveGiftAuctions(let updateActiveGiftAuctions):
            notificationCenter.postTdUpdate(name: .updateActiveGiftAuctions, object: updateActiveGiftAuctions, source: source)
        case .updateUserPrivacySettingRules(let updateUserPrivacySettingRules):
            notificationCenter.postTdUpdate(name: .updateUserPrivacySettingRules, object: updateUserPrivacySettingRules, source: source)
        case .updateUnreadMessageCount(let updateUnreadMessageCount):
            notificationCenter.postTdUpdate(name: .updateUnreadMessageCount, object: updateUnreadMessageCount, source: source)
        case .updateUnreadChatCount(let updateUnreadChatCount):
            notificationCenter.postTdUpdate(name: .updateUnreadChatCount, object: updateUnreadChatCount, source: source)
        case .updateChatJoinResult(let updateChatJoinResult):
            notificationCenter.postTdUpdate(name: .updateChatJoinResult, object: updateChatJoinResult, source: source)
        case .updateStory(let updateStory):
            notificationCenter.postTdUpdate(name: .updateStory, object: updateStory, source: source)
        case .updateStoryDeleted(let updateStoryDeleted):
            notificationCenter.postTdUpdate(name: .updateStoryDeleted, object: updateStoryDeleted, source: source)
        case .updateStoryPostSucceeded(let updateStoryPostSucceeded):
            notificationCenter.postTdUpdate(name: .updateStoryPostSucceeded, object: updateStoryPostSucceeded, source: source)
        case .updateStoryPostFailed(let updateStoryPostFailed):
            notificationCenter.postTdUpdate(name: .updateStoryPostFailed, object: updateStoryPostFailed, source: source)
        case .updateChatActiveStories(let updateChatActiveStories):
            notificationCenter.postTdUpdate(name: .updateChatActiveStories, object: updateChatActiveStories, source: source)
        case .updateStoryListChatCount(let updateStoryListChatCount):
            notificationCenter.postTdUpdate(name: .updateStoryListChatCount, object: updateStoryListChatCount, source: source)
        case .updateStoryStealthMode(let updateStoryStealthMode):
            notificationCenter.postTdUpdate(name: .updateStoryStealthMode, object: updateStoryStealthMode, source: source)
        case .updateTrustedMiniAppBots(let updateTrustedMiniAppBots):
            notificationCenter.postTdUpdate(name: .updateTrustedMiniAppBots, object: updateTrustedMiniAppBots, source: source)
        case .updateOption(let updateOption):
            notificationCenter.postTdUpdate(name: .updateOption, object: updateOption, source: source)
        case .updateStickerSet(let updateStickerSet):
            notificationCenter.postTdUpdate(name: .updateStickerSet, object: updateStickerSet, source: source)
        case .updateInstalledStickerSets(let updateInstalledStickerSets):
            notificationCenter.postTdUpdate(name: .updateInstalledStickerSets, object: updateInstalledStickerSets, source: source)
        case .updateTrendingStickerSets(let updateTrendingStickerSets):
            notificationCenter.postTdUpdate(name: .updateTrendingStickerSets, object: updateTrendingStickerSets, source: source)
        case .updateRecentStickers(let updateRecentStickers):
            notificationCenter.postTdUpdate(name: .updateRecentStickers, object: updateRecentStickers, source: source)
        case .updateFavoriteStickers(let updateFavoriteStickers):
            notificationCenter.postTdUpdate(name: .updateFavoriteStickers, object: updateFavoriteStickers, source: source)
        case .updateSavedAnimations(let updateSavedAnimations):
            notificationCenter.postTdUpdate(name: .updateSavedAnimations, object: updateSavedAnimations, source: source)
        case .updateSavedNotificationSounds(let updateSavedNotificationSounds):
            notificationCenter.postTdUpdate(name: .updateSavedNotificationSounds, object: updateSavedNotificationSounds, source: source)
        case .updateDefaultBackground(let updateDefaultBackground):
            notificationCenter.postTdUpdate(name: .updateDefaultBackground, object: updateDefaultBackground, source: source)
        case .updateEmojiChatThemes(let updateEmojiChatThemes):
            notificationCenter.postTdUpdate(name: .updateEmojiChatThemes, object: updateEmojiChatThemes, source: source)
        case .updateAccentColors(let updateAccentColors):
            notificationCenter.postTdUpdate(name: .updateAccentColors, object: updateAccentColors, source: source)
        case .updateProfileAccentColors(let updateProfileAccentColors):
            notificationCenter.postTdUpdate(name: .updateProfileAccentColors, object: updateProfileAccentColors, source: source)
        case .updateWebBrowserSettings(let updateWebBrowserSettings):
            notificationCenter.postTdUpdate(name: .updateWebBrowserSettings, object: updateWebBrowserSettings, source: source)
        case .updateLanguagePackStrings(let updateLanguagePackStrings):
            notificationCenter.postTdUpdate(name: .updateLanguagePackStrings, object: updateLanguagePackStrings, source: source)
        case .updateConnectionState(let updateConnectionState):
            notificationCenter.postTdUpdate(name: .updateConnectionState, object: updateConnectionState, source: source)
        case .updateFreezeState(let updateFreezeState):
            notificationCenter.postTdUpdate(name: .updateFreezeState, object: updateFreezeState, source: source)
        case .updateAgeVerificationParameters(let updateAgeVerificationParameters):
            notificationCenter.postTdUpdate(name: .updateAgeVerificationParameters, object: updateAgeVerificationParameters, source: source)
        case .updateTermsOfService(let updateTermsOfService):
            notificationCenter.postTdUpdate(name: .updateTermsOfService, object: updateTermsOfService, source: source)
        case .updateUnconfirmedSession(let updateUnconfirmedSession):
            notificationCenter.postTdUpdate(name: .updateUnconfirmedSession, object: updateUnconfirmedSession, source: source)
        case .updateAttachmentMenuBots(let updateAttachmentMenuBots):
            notificationCenter.postTdUpdate(name: .updateAttachmentMenuBots, object: updateAttachmentMenuBots, source: source)
        case .updateWebAppMessageSent(let updateWebAppMessageSent):
            notificationCenter.postTdUpdate(name: .updateWebAppMessageSent, object: updateWebAppMessageSent, source: source)
        case .updateActiveEmojiReactions(let updateActiveEmojiReactions):
            notificationCenter.postTdUpdate(name: .updateActiveEmojiReactions, object: updateActiveEmojiReactions, source: source)
        case .updateAvailableMessageEffects(let updateAvailableMessageEffects):
            notificationCenter.postTdUpdate(name: .updateAvailableMessageEffects, object: updateAvailableMessageEffects, source: source)
        case .updateDefaultReactionType(let updateDefaultReactionType):
            notificationCenter.postTdUpdate(name: .updateDefaultReactionType, object: updateDefaultReactionType, source: source)
        case .updateDefaultPaidReactionType(let updateDefaultPaidReactionType):
            notificationCenter.postTdUpdate(name: .updateDefaultPaidReactionType, object: updateDefaultPaidReactionType, source: source)
        case .updateSavedMessagesTags(let updateSavedMessagesTags):
            notificationCenter.postTdUpdate(name: .updateSavedMessagesTags, object: updateSavedMessagesTags, source: source)
        case .updateActiveLiveLocationMessages(let updateActiveLiveLocationMessages):
            notificationCenter.postTdUpdate(name: .updateActiveLiveLocationMessages, object: updateActiveLiveLocationMessages, source: source)
        case .updateOwnedStarCount(let updateOwnedStarCount):
            notificationCenter.postTdUpdate(name: .updateOwnedStarCount, object: updateOwnedStarCount, source: source)
        case .updateOwnedGramCount(let updateOwnedGramCount):
            notificationCenter.postTdUpdate(name: .updateOwnedGramCount, object: updateOwnedGramCount, source: source)
        case .updateChatRevenueAmount(let updateChatRevenueAmount):
            notificationCenter.postTdUpdate(name: .updateChatRevenueAmount, object: updateChatRevenueAmount, source: source)
        case .updateStarRevenueStatus(let updateStarRevenueStatus):
            notificationCenter.postTdUpdate(name: .updateStarRevenueStatus, object: updateStarRevenueStatus, source: source)
        case .updateGramRevenueStatus(let updateGramRevenueStatus):
            notificationCenter.postTdUpdate(name: .updateGramRevenueStatus, object: updateGramRevenueStatus, source: source)
        case .updateSpeechRecognitionTrial(let updateSpeechRecognitionTrial):
            notificationCenter.postTdUpdate(name: .updateSpeechRecognitionTrial, object: updateSpeechRecognitionTrial, source: source)
        case .updateGroupCallMessageLevels(let updateGroupCallMessageLevels):
            notificationCenter.postTdUpdate(name: .updateGroupCallMessageLevels, object: updateGroupCallMessageLevels, source: source)
        case .updateDiceEmojis(let updateDiceEmojis):
            notificationCenter.postTdUpdate(name: .updateDiceEmojis, object: updateDiceEmojis, source: source)
        case .updateStakeDiceState(let updateStakeDiceState):
            notificationCenter.postTdUpdate(name: .updateStakeDiceState, object: updateStakeDiceState, source: source)
        case .updateAnimatedEmojiMessageClicked(let updateAnimatedEmojiMessageClicked):
            notificationCenter.postTdUpdate(name: .updateAnimatedEmojiMessageClicked, object: updateAnimatedEmojiMessageClicked, source: source)
        case .updateAnimationSearchParameters(let updateAnimationSearchParameters):
            notificationCenter.postTdUpdate(name: .updateAnimationSearchParameters, object: updateAnimationSearchParameters, source: source)
        case .updateTextCompositionStyles(let updateTextCompositionStyles):
            notificationCenter.postTdUpdate(name: .updateTextCompositionStyles, object: updateTextCompositionStyles, source: source)
        case .updateSuggestedActions(let updateSuggestedActions):
            notificationCenter.postTdUpdate(name: .updateSuggestedActions, object: updateSuggestedActions, source: source)
        case .updateSpeedLimitNotification(let updateSpeedLimitNotification):
            notificationCenter.postTdUpdate(name: .updateSpeedLimitNotification, object: updateSpeedLimitNotification, source: source)
        case .updateContactCloseBirthdays(let updateContactCloseBirthdays):
            notificationCenter.postTdUpdate(name: .updateContactCloseBirthdays, object: updateContactCloseBirthdays, source: source)
        case .updateAutosaveSettings(let updateAutosaveSettings):
            notificationCenter.postTdUpdate(name: .updateAutosaveSettings, object: updateAutosaveSettings, source: source)
        case .updateBusinessConnection(let updateBusinessConnection):
            notificationCenter.postTdUpdate(name: .updateBusinessConnection, object: updateBusinessConnection, source: source)
        case .updateNewBusinessMessage(let updateNewBusinessMessage):
            notificationCenter.postTdUpdate(name: .updateNewBusinessMessage, object: updateNewBusinessMessage, source: source)
        case .updateBusinessMessageEdited(let updateBusinessMessageEdited):
            notificationCenter.postTdUpdate(name: .updateBusinessMessageEdited, object: updateBusinessMessageEdited, source: source)
        case .updateBusinessMessagesDeleted(let updateBusinessMessagesDeleted):
            notificationCenter.postTdUpdate(name: .updateBusinessMessagesDeleted, object: updateBusinessMessagesDeleted, source: source)
        case .updateNewInlineQuery(let updateNewInlineQuery):
            notificationCenter.postTdUpdate(name: .updateNewInlineQuery, object: updateNewInlineQuery, source: source)
        case .updateNewChosenInlineResult(let updateNewChosenInlineResult):
            notificationCenter.postTdUpdate(name: .updateNewChosenInlineResult, object: updateNewChosenInlineResult, source: source)
        case .updateNewGuestQuery(let updateNewGuestQuery):
            notificationCenter.postTdUpdate(name: .updateNewGuestQuery, object: updateNewGuestQuery, source: source)
        case .updateNewCallbackQuery(let updateNewCallbackQuery):
            notificationCenter.postTdUpdate(name: .updateNewCallbackQuery, object: updateNewCallbackQuery, source: source)
        case .updateNewInlineCallbackQuery(let updateNewInlineCallbackQuery):
            notificationCenter.postTdUpdate(name: .updateNewInlineCallbackQuery, object: updateNewInlineCallbackQuery, source: source)
        case .updateNewBusinessCallbackQuery(let updateNewBusinessCallbackQuery):
            notificationCenter.postTdUpdate(name: .updateNewBusinessCallbackQuery, object: updateNewBusinessCallbackQuery, source: source)
        case .updateNewShippingQuery(let updateNewShippingQuery):
            notificationCenter.postTdUpdate(name: .updateNewShippingQuery, object: updateNewShippingQuery, source: source)
        case .updateNewPreCheckoutQuery(let updateNewPreCheckoutQuery):
            notificationCenter.postTdUpdate(name: .updateNewPreCheckoutQuery, object: updateNewPreCheckoutQuery, source: source)
        case .updateNewCustomEvent(let updateNewCustomEvent):
            notificationCenter.postTdUpdate(name: .updateNewCustomEvent, object: updateNewCustomEvent, source: source)
        case .updateNewCustomQuery(let updateNewCustomQuery):
            notificationCenter.postTdUpdate(name: .updateNewCustomQuery, object: updateNewCustomQuery, source: source)
        case .updateUserSubscription(let updateUserSubscription):
            notificationCenter.postTdUpdate(name: .updateUserSubscription, object: updateUserSubscription, source: source)
        case .updatePoll(let updatePoll):
            notificationCenter.postTdUpdate(name: .updatePoll, object: updatePoll, source: source)
        case .updatePollAnswer(let updatePollAnswer):
            notificationCenter.postTdUpdate(name: .updatePollAnswer, object: updatePollAnswer, source: source)
        case .updateManagedBot(let updateManagedBot):
            notificationCenter.postTdUpdate(name: .updateManagedBot, object: updateManagedBot, source: source)
        case .updateChatMember(let updateChatMember):
            notificationCenter.postTdUpdate(name: .updateChatMember, object: updateChatMember, source: source)
        case .updateNewChatJoinRequest(let updateNewChatJoinRequest):
            notificationCenter.postTdUpdate(name: .updateNewChatJoinRequest, object: updateNewChatJoinRequest, source: source)
        case .updateChatBoost(let updateChatBoost):
            notificationCenter.postTdUpdate(name: .updateChatBoost, object: updateChatBoost, source: source)
        case .updateMessageReaction(let updateMessageReaction):
            notificationCenter.postTdUpdate(name: .updateMessageReaction, object: updateMessageReaction, source: source)
        case .updateMessageReactions(let updateMessageReactions):
            notificationCenter.postTdUpdate(name: .updateMessageReactions, object: updateMessageReactions, source: source)
        case .updatePaidMediaPurchased(let updatePaidMediaPurchased):
            notificationCenter.postTdUpdate(name: .updatePaidMediaPurchased, object: updatePaidMediaPurchased, source: source)
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
    static var updateMessageContainsUnreadPollVotes: TdNotification<UpdateMessageContainsUnreadPollVotes> { .init(.updateMessageContainsUnreadPollVotes) }
    static var updateMessageFactCheck: TdNotification<UpdateMessageFactCheck> { .init(.updateMessageFactCheck) }
    static var updateMessageSuggestedPostInfo: TdNotification<UpdateMessageSuggestedPostInfo> { .init(.updateMessageSuggestedPostInfo) }
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
    static var updateChatUnreadPollVoteCount: TdNotification<UpdateChatUnreadPollVoteCount> { .init(.updateChatUnreadPollVoteCount) }
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
    static var updateDirectMessagesChatTopic: TdNotification<UpdateDirectMessagesChatTopic> { .init(.updateDirectMessagesChatTopic) }
    static var updateTopicMessageCount: TdNotification<UpdateTopicMessageCount> { .init(.updateTopicMessageCount) }
    static var updateQuickReplyShortcut: TdNotification<UpdateQuickReplyShortcut> { .init(.updateQuickReplyShortcut) }
    static var updateQuickReplyShortcutDeleted: TdNotification<UpdateQuickReplyShortcutDeleted> { .init(.updateQuickReplyShortcutDeleted) }
    static var updateQuickReplyShortcuts: TdNotification<UpdateQuickReplyShortcuts> { .init(.updateQuickReplyShortcuts) }
    static var updateQuickReplyShortcutMessages: TdNotification<UpdateQuickReplyShortcutMessages> { .init(.updateQuickReplyShortcutMessages) }
    static var updateForumTopicInfo: TdNotification<UpdateForumTopicInfo> { .init(.updateForumTopicInfo) }
    static var updateForumTopic: TdNotification<UpdateForumTopic> { .init(.updateForumTopic) }
    static var updateScopeNotificationSettings: TdNotification<UpdateScopeNotificationSettings> { .init(.updateScopeNotificationSettings) }
    static var updateReactionNotificationSettings: TdNotification<UpdateReactionNotificationSettings> { .init(.updateReactionNotificationSettings) }
    static var updateNotification: TdNotification<UpdateNotification> { .init(.updateNotification) }
    static var updateNotificationGroup: TdNotification<UpdateNotificationGroup> { .init(.updateNotificationGroup) }
    static var updateActiveNotifications: TdNotification<UpdateActiveNotifications> { .init(.updateActiveNotifications) }
    static var updateHavePendingNotifications: TdNotification<UpdateHavePendingNotifications> { .init(.updateHavePendingNotifications) }
    static var updateDeleteMessages: TdNotification<UpdateDeleteMessages> { .init(.updateDeleteMessages) }
    static var updateChatAction: TdNotification<UpdateChatAction> { .init(.updateChatAction) }
    static var updatePendingMessage: TdNotification<UpdatePendingMessage> { .init(.updatePendingMessage) }
    static var updateCommunity: TdNotification<UpdateCommunity> { .init(.updateCommunity) }
    static var updateUserStatus: TdNotification<UpdateUserStatus> { .init(.updateUserStatus) }
    static var updateUser: TdNotification<UpdateUser> { .init(.updateUser) }
    static var updateBasicGroup: TdNotification<UpdateBasicGroup> { .init(.updateBasicGroup) }
    static var updateSupergroup: TdNotification<UpdateSupergroup> { .init(.updateSupergroup) }
    static var updateSecretChat: TdNotification<UpdateSecretChat> { .init(.updateSecretChat) }
    static var updateUserFullInfo: TdNotification<UpdateUserFullInfo> { .init(.updateUserFullInfo) }
    static var updateBasicGroupFullInfo: TdNotification<UpdateBasicGroupFullInfo> { .init(.updateBasicGroupFullInfo) }
    static var updateSupergroupFullInfo: TdNotification<UpdateSupergroupFullInfo> { .init(.updateSupergroupFullInfo) }
    static var updateServiceNotification: TdNotification<UpdateServiceNotification> { .init(.updateServiceNotification) }
    static var updateNewOauthRequest: TdNotification<UpdateNewOauthRequest> { .init(.updateNewOauthRequest) }
    static var updateFile: TdNotification<UpdateFile> { .init(.updateFile) }
    static var updateFileGenerationStart: TdNotification<UpdateFileGenerationStart> { .init(.updateFileGenerationStart) }
    static var updateFileGenerationStop: TdNotification<UpdateFileGenerationStop> { .init(.updateFileGenerationStop) }
    static var updateFileDownloads: TdNotification<UpdateFileDownloads> { .init(.updateFileDownloads) }
    static var updateFileAddedToDownloads: TdNotification<UpdateFileAddedToDownloads> { .init(.updateFileAddedToDownloads) }
    static var updateFileDownload: TdNotification<UpdateFileDownload> { .init(.updateFileDownload) }
    static var updateFileRemovedFromDownloads: TdNotification<UpdateFileRemovedFromDownloads> { .init(.updateFileRemovedFromDownloads) }
    static var updateApplicationVerificationRequired: TdNotification<UpdateApplicationVerificationRequired> { .init(.updateApplicationVerificationRequired) }
    static var updateApplicationRecaptchaVerificationRequired: TdNotification<UpdateApplicationRecaptchaVerificationRequired> { .init(.updateApplicationRecaptchaVerificationRequired) }
    static var updateCall: TdNotification<UpdateCall> { .init(.updateCall) }
    static var updateGroupCall: TdNotification<UpdateGroupCall> { .init(.updateGroupCall) }
    static var updateGroupCallParticipant: TdNotification<UpdateGroupCallParticipant> { .init(.updateGroupCallParticipant) }
    static var updateGroupCallParticipants: TdNotification<UpdateGroupCallParticipants> { .init(.updateGroupCallParticipants) }
    static var updateGroupCallVerificationState: TdNotification<UpdateGroupCallVerificationState> { .init(.updateGroupCallVerificationState) }
    static var updateNewGroupCallMessage: TdNotification<UpdateNewGroupCallMessage> { .init(.updateNewGroupCallMessage) }
    static var updateNewGroupCallPaidReaction: TdNotification<UpdateNewGroupCallPaidReaction> { .init(.updateNewGroupCallPaidReaction) }
    static var updateGroupCallMessageSendFailed: TdNotification<UpdateGroupCallMessageSendFailed> { .init(.updateGroupCallMessageSendFailed) }
    static var updateGroupCallMessagesDeleted: TdNotification<UpdateGroupCallMessagesDeleted> { .init(.updateGroupCallMessagesDeleted) }
    static var updateLiveStoryTopDonors: TdNotification<UpdateLiveStoryTopDonors> { .init(.updateLiveStoryTopDonors) }
    static var updateNewCallSignalingData: TdNotification<UpdateNewCallSignalingData> { .init(.updateNewCallSignalingData) }
    static var updateGiftAuctionState: TdNotification<UpdateGiftAuctionState> { .init(.updateGiftAuctionState) }
    static var updateActiveGiftAuctions: TdNotification<UpdateActiveGiftAuctions> { .init(.updateActiveGiftAuctions) }
    static var updateUserPrivacySettingRules: TdNotification<UpdateUserPrivacySettingRules> { .init(.updateUserPrivacySettingRules) }
    static var updateUnreadMessageCount: TdNotification<UpdateUnreadMessageCount> { .init(.updateUnreadMessageCount) }
    static var updateUnreadChatCount: TdNotification<UpdateUnreadChatCount> { .init(.updateUnreadChatCount) }
    static var updateChatJoinResult: TdNotification<UpdateChatJoinResult> { .init(.updateChatJoinResult) }
    static var updateStory: TdNotification<UpdateStory> { .init(.updateStory) }
    static var updateStoryDeleted: TdNotification<UpdateStoryDeleted> { .init(.updateStoryDeleted) }
    static var updateStoryPostSucceeded: TdNotification<UpdateStoryPostSucceeded> { .init(.updateStoryPostSucceeded) }
    static var updateStoryPostFailed: TdNotification<UpdateStoryPostFailed> { .init(.updateStoryPostFailed) }
    static var updateChatActiveStories: TdNotification<UpdateChatActiveStories> { .init(.updateChatActiveStories) }
    static var updateStoryListChatCount: TdNotification<UpdateStoryListChatCount> { .init(.updateStoryListChatCount) }
    static var updateStoryStealthMode: TdNotification<UpdateStoryStealthMode> { .init(.updateStoryStealthMode) }
    static var updateTrustedMiniAppBots: TdNotification<UpdateTrustedMiniAppBots> { .init(.updateTrustedMiniAppBots) }
    static var updateOption: TdNotification<UpdateOption> { .init(.updateOption) }
    static var updateStickerSet: TdNotification<UpdateStickerSet> { .init(.updateStickerSet) }
    static var updateInstalledStickerSets: TdNotification<UpdateInstalledStickerSets> { .init(.updateInstalledStickerSets) }
    static var updateTrendingStickerSets: TdNotification<UpdateTrendingStickerSets> { .init(.updateTrendingStickerSets) }
    static var updateRecentStickers: TdNotification<UpdateRecentStickers> { .init(.updateRecentStickers) }
    static var updateFavoriteStickers: TdNotification<UpdateFavoriteStickers> { .init(.updateFavoriteStickers) }
    static var updateSavedAnimations: TdNotification<UpdateSavedAnimations> { .init(.updateSavedAnimations) }
    static var updateSavedNotificationSounds: TdNotification<UpdateSavedNotificationSounds> { .init(.updateSavedNotificationSounds) }
    static var updateDefaultBackground: TdNotification<UpdateDefaultBackground> { .init(.updateDefaultBackground) }
    static var updateEmojiChatThemes: TdNotification<UpdateEmojiChatThemes> { .init(.updateEmojiChatThemes) }
    static var updateAccentColors: TdNotification<UpdateAccentColors> { .init(.updateAccentColors) }
    static var updateProfileAccentColors: TdNotification<UpdateProfileAccentColors> { .init(.updateProfileAccentColors) }
    static var updateWebBrowserSettings: TdNotification<UpdateWebBrowserSettings> { .init(.updateWebBrowserSettings) }
    static var updateLanguagePackStrings: TdNotification<UpdateLanguagePackStrings> { .init(.updateLanguagePackStrings) }
    static var updateConnectionState: TdNotification<UpdateConnectionState> { .init(.updateConnectionState) }
    static var updateFreezeState: TdNotification<UpdateFreezeState> { .init(.updateFreezeState) }
    static var updateAgeVerificationParameters: TdNotification<UpdateAgeVerificationParameters> { .init(.updateAgeVerificationParameters) }
    static var updateTermsOfService: TdNotification<UpdateTermsOfService> { .init(.updateTermsOfService) }
    static var updateUnconfirmedSession: TdNotification<UpdateUnconfirmedSession> { .init(.updateUnconfirmedSession) }
    static var updateAttachmentMenuBots: TdNotification<UpdateAttachmentMenuBots> { .init(.updateAttachmentMenuBots) }
    static var updateWebAppMessageSent: TdNotification<UpdateWebAppMessageSent> { .init(.updateWebAppMessageSent) }
    static var updateActiveEmojiReactions: TdNotification<UpdateActiveEmojiReactions> { .init(.updateActiveEmojiReactions) }
    static var updateAvailableMessageEffects: TdNotification<UpdateAvailableMessageEffects> { .init(.updateAvailableMessageEffects) }
    static var updateDefaultReactionType: TdNotification<UpdateDefaultReactionType> { .init(.updateDefaultReactionType) }
    static var updateDefaultPaidReactionType: TdNotification<UpdateDefaultPaidReactionType> { .init(.updateDefaultPaidReactionType) }
    static var updateSavedMessagesTags: TdNotification<UpdateSavedMessagesTags> { .init(.updateSavedMessagesTags) }
    static var updateActiveLiveLocationMessages: TdNotification<UpdateActiveLiveLocationMessages> { .init(.updateActiveLiveLocationMessages) }
    static var updateOwnedStarCount: TdNotification<UpdateOwnedStarCount> { .init(.updateOwnedStarCount) }
    static var updateOwnedGramCount: TdNotification<UpdateOwnedGramCount> { .init(.updateOwnedGramCount) }
    static var updateChatRevenueAmount: TdNotification<UpdateChatRevenueAmount> { .init(.updateChatRevenueAmount) }
    static var updateStarRevenueStatus: TdNotification<UpdateStarRevenueStatus> { .init(.updateStarRevenueStatus) }
    static var updateGramRevenueStatus: TdNotification<UpdateGramRevenueStatus> { .init(.updateGramRevenueStatus) }
    static var updateSpeechRecognitionTrial: TdNotification<UpdateSpeechRecognitionTrial> { .init(.updateSpeechRecognitionTrial) }
    static var updateGroupCallMessageLevels: TdNotification<UpdateGroupCallMessageLevels> { .init(.updateGroupCallMessageLevels) }
    static var updateDiceEmojis: TdNotification<UpdateDiceEmojis> { .init(.updateDiceEmojis) }
    static var updateStakeDiceState: TdNotification<UpdateStakeDiceState> { .init(.updateStakeDiceState) }
    static var updateAnimatedEmojiMessageClicked: TdNotification<UpdateAnimatedEmojiMessageClicked> { .init(.updateAnimatedEmojiMessageClicked) }
    static var updateAnimationSearchParameters: TdNotification<UpdateAnimationSearchParameters> { .init(.updateAnimationSearchParameters) }
    static var updateTextCompositionStyles: TdNotification<UpdateTextCompositionStyles> { .init(.updateTextCompositionStyles) }
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
    static var updateNewGuestQuery: TdNotification<UpdateNewGuestQuery> { .init(.updateNewGuestQuery) }
    static var updateNewCallbackQuery: TdNotification<UpdateNewCallbackQuery> { .init(.updateNewCallbackQuery) }
    static var updateNewInlineCallbackQuery: TdNotification<UpdateNewInlineCallbackQuery> { .init(.updateNewInlineCallbackQuery) }
    static var updateNewBusinessCallbackQuery: TdNotification<UpdateNewBusinessCallbackQuery> { .init(.updateNewBusinessCallbackQuery) }
    static var updateNewShippingQuery: TdNotification<UpdateNewShippingQuery> { .init(.updateNewShippingQuery) }
    static var updateNewPreCheckoutQuery: TdNotification<UpdateNewPreCheckoutQuery> { .init(.updateNewPreCheckoutQuery) }
    static var updateNewCustomEvent: TdNotification<UpdateNewCustomEvent> { .init(.updateNewCustomEvent) }
    static var updateNewCustomQuery: TdNotification<UpdateNewCustomQuery> { .init(.updateNewCustomQuery) }
    static var updateUserSubscription: TdNotification<UpdateUserSubscription> { .init(.updateUserSubscription) }
    static var updatePoll: TdNotification<UpdatePoll> { .init(.updatePoll) }
    static var updatePollAnswer: TdNotification<UpdatePollAnswer> { .init(.updatePollAnswer) }
    static var updateManagedBot: TdNotification<UpdateManagedBot> { .init(.updateManagedBot) }
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
    static let updateMessageContainsUnreadPollVotes = Self("updateMessageContainsUnreadPollVotes")
    static let updateMessageFactCheck = Self("updateMessageFactCheck")
    static let updateMessageSuggestedPostInfo = Self("updateMessageSuggestedPostInfo")
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
    static let updateChatUnreadPollVoteCount = Self("updateChatUnreadPollVoteCount")
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
    static let updateDirectMessagesChatTopic = Self("updateDirectMessagesChatTopic")
    static let updateTopicMessageCount = Self("updateTopicMessageCount")
    static let updateQuickReplyShortcut = Self("updateQuickReplyShortcut")
    static let updateQuickReplyShortcutDeleted = Self("updateQuickReplyShortcutDeleted")
    static let updateQuickReplyShortcuts = Self("updateQuickReplyShortcuts")
    static let updateQuickReplyShortcutMessages = Self("updateQuickReplyShortcutMessages")
    static let updateForumTopicInfo = Self("updateForumTopicInfo")
    static let updateForumTopic = Self("updateForumTopic")
    static let updateScopeNotificationSettings = Self("updateScopeNotificationSettings")
    static let updateReactionNotificationSettings = Self("updateReactionNotificationSettings")
    static let updateNotification = Self("updateNotification")
    static let updateNotificationGroup = Self("updateNotificationGroup")
    static let updateActiveNotifications = Self("updateActiveNotifications")
    static let updateHavePendingNotifications = Self("updateHavePendingNotifications")
    static let updateDeleteMessages = Self("updateDeleteMessages")
    static let updateChatAction = Self("updateChatAction")
    static let updatePendingMessage = Self("updatePendingMessage")
    static let updateCommunity = Self("updateCommunity")
    static let updateUserStatus = Self("updateUserStatus")
    static let updateUser = Self("updateUser")
    static let updateBasicGroup = Self("updateBasicGroup")
    static let updateSupergroup = Self("updateSupergroup")
    static let updateSecretChat = Self("updateSecretChat")
    static let updateUserFullInfo = Self("updateUserFullInfo")
    static let updateBasicGroupFullInfo = Self("updateBasicGroupFullInfo")
    static let updateSupergroupFullInfo = Self("updateSupergroupFullInfo")
    static let updateServiceNotification = Self("updateServiceNotification")
    static let updateNewOauthRequest = Self("updateNewOauthRequest")
    static let updateFile = Self("updateFile")
    static let updateFileGenerationStart = Self("updateFileGenerationStart")
    static let updateFileGenerationStop = Self("updateFileGenerationStop")
    static let updateFileDownloads = Self("updateFileDownloads")
    static let updateFileAddedToDownloads = Self("updateFileAddedToDownloads")
    static let updateFileDownload = Self("updateFileDownload")
    static let updateFileRemovedFromDownloads = Self("updateFileRemovedFromDownloads")
    static let updateApplicationVerificationRequired = Self("updateApplicationVerificationRequired")
    static let updateApplicationRecaptchaVerificationRequired = Self("updateApplicationRecaptchaVerificationRequired")
    static let updateCall = Self("updateCall")
    static let updateGroupCall = Self("updateGroupCall")
    static let updateGroupCallParticipant = Self("updateGroupCallParticipant")
    static let updateGroupCallParticipants = Self("updateGroupCallParticipants")
    static let updateGroupCallVerificationState = Self("updateGroupCallVerificationState")
    static let updateNewGroupCallMessage = Self("updateNewGroupCallMessage")
    static let updateNewGroupCallPaidReaction = Self("updateNewGroupCallPaidReaction")
    static let updateGroupCallMessageSendFailed = Self("updateGroupCallMessageSendFailed")
    static let updateGroupCallMessagesDeleted = Self("updateGroupCallMessagesDeleted")
    static let updateLiveStoryTopDonors = Self("updateLiveStoryTopDonors")
    static let updateNewCallSignalingData = Self("updateNewCallSignalingData")
    static let updateGiftAuctionState = Self("updateGiftAuctionState")
    static let updateActiveGiftAuctions = Self("updateActiveGiftAuctions")
    static let updateUserPrivacySettingRules = Self("updateUserPrivacySettingRules")
    static let updateUnreadMessageCount = Self("updateUnreadMessageCount")
    static let updateUnreadChatCount = Self("updateUnreadChatCount")
    static let updateChatJoinResult = Self("updateChatJoinResult")
    static let updateStory = Self("updateStory")
    static let updateStoryDeleted = Self("updateStoryDeleted")
    static let updateStoryPostSucceeded = Self("updateStoryPostSucceeded")
    static let updateStoryPostFailed = Self("updateStoryPostFailed")
    static let updateChatActiveStories = Self("updateChatActiveStories")
    static let updateStoryListChatCount = Self("updateStoryListChatCount")
    static let updateStoryStealthMode = Self("updateStoryStealthMode")
    static let updateTrustedMiniAppBots = Self("updateTrustedMiniAppBots")
    static let updateOption = Self("updateOption")
    static let updateStickerSet = Self("updateStickerSet")
    static let updateInstalledStickerSets = Self("updateInstalledStickerSets")
    static let updateTrendingStickerSets = Self("updateTrendingStickerSets")
    static let updateRecentStickers = Self("updateRecentStickers")
    static let updateFavoriteStickers = Self("updateFavoriteStickers")
    static let updateSavedAnimations = Self("updateSavedAnimations")
    static let updateSavedNotificationSounds = Self("updateSavedNotificationSounds")
    static let updateDefaultBackground = Self("updateDefaultBackground")
    static let updateEmojiChatThemes = Self("updateEmojiChatThemes")
    static let updateAccentColors = Self("updateAccentColors")
    static let updateProfileAccentColors = Self("updateProfileAccentColors")
    static let updateWebBrowserSettings = Self("updateWebBrowserSettings")
    static let updateLanguagePackStrings = Self("updateLanguagePackStrings")
    static let updateConnectionState = Self("updateConnectionState")
    static let updateFreezeState = Self("updateFreezeState")
    static let updateAgeVerificationParameters = Self("updateAgeVerificationParameters")
    static let updateTermsOfService = Self("updateTermsOfService")
    static let updateUnconfirmedSession = Self("updateUnconfirmedSession")
    static let updateAttachmentMenuBots = Self("updateAttachmentMenuBots")
    static let updateWebAppMessageSent = Self("updateWebAppMessageSent")
    static let updateActiveEmojiReactions = Self("updateActiveEmojiReactions")
    static let updateAvailableMessageEffects = Self("updateAvailableMessageEffects")
    static let updateDefaultReactionType = Self("updateDefaultReactionType")
    static let updateDefaultPaidReactionType = Self("updateDefaultPaidReactionType")
    static let updateSavedMessagesTags = Self("updateSavedMessagesTags")
    static let updateActiveLiveLocationMessages = Self("updateActiveLiveLocationMessages")
    static let updateOwnedStarCount = Self("updateOwnedStarCount")
    static let updateOwnedGramCount = Self("updateOwnedGramCount")
    static let updateChatRevenueAmount = Self("updateChatRevenueAmount")
    static let updateStarRevenueStatus = Self("updateStarRevenueStatus")
    static let updateGramRevenueStatus = Self("updateGramRevenueStatus")
    static let updateSpeechRecognitionTrial = Self("updateSpeechRecognitionTrial")
    static let updateGroupCallMessageLevels = Self("updateGroupCallMessageLevels")
    static let updateDiceEmojis = Self("updateDiceEmojis")
    static let updateStakeDiceState = Self("updateStakeDiceState")
    static let updateAnimatedEmojiMessageClicked = Self("updateAnimatedEmojiMessageClicked")
    static let updateAnimationSearchParameters = Self("updateAnimationSearchParameters")
    static let updateTextCompositionStyles = Self("updateTextCompositionStyles")
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
    static let updateNewGuestQuery = Self("updateNewGuestQuery")
    static let updateNewCallbackQuery = Self("updateNewCallbackQuery")
    static let updateNewInlineCallbackQuery = Self("updateNewInlineCallbackQuery")
    static let updateNewBusinessCallbackQuery = Self("updateNewBusinessCallbackQuery")
    static let updateNewShippingQuery = Self("updateNewShippingQuery")
    static let updateNewPreCheckoutQuery = Self("updateNewPreCheckoutQuery")
    static let updateNewCustomEvent = Self("updateNewCustomEvent")
    static let updateNewCustomQuery = Self("updateNewCustomQuery")
    static let updateUserSubscription = Self("updateUserSubscription")
    static let updatePoll = Self("updatePoll")
    static let updatePollAnswer = Self("updatePollAnswer")
    static let updateManagedBot = Self("updateManagedBot")
    static let updateChatMember = Self("updateChatMember")
    static let updateNewChatJoinRequest = Self("updateNewChatJoinRequest")
    static let updateChatBoost = Self("updateChatBoost")
    static let updateMessageReaction = Self("updateMessageReaction")
    static let updateMessageReactions = Self("updateMessageReactions")
    static let updatePaidMediaPurchased = Self("updatePaidMediaPurchased")
}

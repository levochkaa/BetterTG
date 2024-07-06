// NotificationName.swift

import SwiftUI

extension Foundation.Notification.Name {
    static let updateNewMessage = Self("updateNewMessage")
    static let updateMessageSendAcknowledged = Self("updateMessageSendAcknowledged")
    static let updateMessageSendSucceeded = Self("updateMessageSendSucceeded")
    static let updateMessageSendFailed = Self("updateMessageSendFailed")
    static let updateMessageContent = Self("updateMessageContent")
    static let updateMessageSendContent = Self("updateMessageSendContent")
    static let updateMessageEdited = Self("updateMessageEdited")
    static let updateMessageIsPinned = Self("updateMessageIsPinned")
    static let updateMessageInteractionInfo = Self("updateMessageInteractionInfo")
    static let updateMessageContentOpened = Self("updateMessageContentOpened")
    static let updateMessageMentionRead = Self("updateMessageContentOpened")
    static let updateMessageUnreadReactions = Self("updateMessageUnreadReactions")
    static let updateMessageFactCheck = Self("updateMessageFactCheck")
    static let updateMessageLiveLocationViewed = Self("updateMessageLiveLocationViewed")
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
    static let updateChatMessageTtl = Self("updateChatMessageTtl")
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
    static let updateChatHasScheduledMessages = Self("updateChatHasScheduledMessages")
    static let updateChatFolders = Self("updateChatFolders")
    static let updateChatIsMarkedAsUnread = Self("updateChatIsMarkedAsUnread")
    static let updateChatViewAsTopics = Self("updateChatViewAsTopics")
    static let updateChatBlockList = Self("updateChatBlockList")
    static let updateChatOnlineMemberCount = Self("updateChatFilters")
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
    static let updateUsersNearby = Self("updateUsersNearby")
    static let updateUnconfirmedSession = Self("updateUnconfirmedSession")
    static let updateAttachmentMenuBots = Self("updateAttachmentMenuBots")
    static let updateWebAppMessageSent = Self("updateWebAppMessageSent")
    static let updateActiveEmojiReactions = Self("updateActiveEmojiReactions")
    static let updateAvailableMessageEffects = Self("updateAvailableMessageEffects")
    static let updateDefaultReactionType = Self("updateDefaultReactionType")
    static let updateSavedMessagesTags = Self("updateSavedMessagesTags")
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
    
    static let authorizationStateWaitTdlibParameters = Self("authorizationStateWaitTdlibParameters")
    static let authorizationStateWaitPhoneNumber = Self("authorizationStateWaitPhoneNumber")
    static let authorizationStateWaitEmailAddress = Self("authorizationStateWaitEmailAddress")
    static let authorizationStateWaitEmailCode = Self("authorizationStateWaitEmailCode")
    static let authorizationStateWaitCode = Self("authorizationStateWaitCode")
    static let authorizationStateWaitOtherDeviceConfirmation = Self("authorizationStateWaitOtherDeviceConfirmation")
    static let authorizationStateWaitRegistration = Self("authorizationStateWaitRegistration")
    static let authorizationStateWaitPassword = Self("authorizationStateWaitPassword")
    static let authorizationStateReady = Self("authorizationStateReady")
    static let authorizationStateLoggingOut = Self("authorizationStateLoggingOut")
    static let authorizationStateClosing = Self("authorizationStateClosing")
    static let authorizationStateClosed = Self("authorizationStateClosed")
    
    static let localScrollToLastOnFocus = Self("localScrollToLastOnFocus")
    static let localPasteImages = Self("localPasteImages")
    static let localOnSelectedImagesDrop = Self("localOnSelectedImagesDrop")
}

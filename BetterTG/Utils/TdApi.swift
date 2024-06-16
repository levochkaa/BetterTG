// TdApi.swift

import SwiftUI
import TDLibKit
import Combine

private var cancellables = Set<AnyCancellable>()
private let manager = TDLibClientManager()

var td: TDLibClient!

func startTdLibUpdateHandler() {
    td = manager.createClient { data, client in
        do {
            update(try client.decoder.decode(Update.self, from: data))
        } catch {
            log("Error TdLibUpdateHandler: \(error)")
        }
    }
    // Xcode 15 is unable to handle so many logs
    try? td.setLogStream(logStream: .logStreamEmpty) { _ in }
    
    nc.publisher(&cancellables, for: .authorizationStateWaitTdlibParameters) { _ in
        Task.background {
            let dir = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appending(path: "td").path()
            
            try await td.setTdlibParameters(
                apiHash: Secret.apiHash,
                apiId: Secret.apiId,
                applicationVersion: Utils.applicationVersion,
                databaseDirectory: dir,
                databaseEncryptionKey: Data(),
                deviceModel: Utils.modelName,
                filesDirectory: dir,
                systemLanguageCode: "en-US",
                systemVersion: UIDevice.current.systemVersion,
                useChatInfoDatabase: true,
                useFileDatabase: true,
                useMessageDatabase: true,
                useSecretChats: true,
                useTestDc: false
            )
        }
    }
    
    nc.publisher(&cancellables, for: UIApplication.willTerminateNotification) { _ in
        manager.closeClients()
    }
}

// swiftlint:disable:next function_body_length
private func update(_ update: Update) {
    switch update {
        case .updateAuthorizationState(let updateAuthorizationState):
            Task.main { UpdateAuthorizationState(updateAuthorizationState.authorizationState) }
        case .updateNewMessage(let updateNewMessage):
            Task.main { nc.post(name: .updateNewMessage, object: updateNewMessage) }
        case .updateMessageSendAcknowledged(let updateMessageSendAcknowledged):
            nc.post(name: .updateMessageSendAcknowledged, object: updateMessageSendAcknowledged)
        case .updateMessageSendSucceeded(let updateMessageSendSucceeded):
            nc.post(name: .updateMessageSendSucceeded, object: updateMessageSendSucceeded)
        case .updateMessageSendFailed(let updateMessageSendFailed):
            nc.post(name: .updateMessageSendFailed, object: updateMessageSendFailed)
        case .updateMessageContent(let updateMessageContent):
            nc.post(name: .updateMessageContent, object: updateMessageContent)
        case .updateMessageEdited(let updateMessageEdited):
            Task.main { nc.post(name: .updateMessageEdited, object: updateMessageEdited) }
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
        case .updateMessageLiveLocationViewed(let updateMessageLiveLocationViewed):
            nc.post(name: .updateMessageLiveLocationViewed, object: updateMessageLiveLocationViewed)
        case .updateNewChat(let updateNewChat):
            Task.main { nc.post(name: .updateNewChat, object: updateNewChat) }
        case .updateChatTitle(let updateChatTitle):
            nc.post(name: .updateChatTitle, object: updateChatTitle)
        case .updateChatPhoto(let updateChatPhoto):
            nc.post(name: .updateChatPhoto, object: updateChatPhoto)
        case .updateChatAccentColors(let updateChatAccentColors):
            nc.post(name: .updateChatAccentColors, object: updateChatAccentColors)
        case .updateChatPermissions(let updateChatPermissions):
            nc.post(name: .updateChatPermissions, object: updateChatPermissions)
        case .updateChatLastMessage(let updateChatLastMessage):
            Task.main { nc.post(name: .updateChatLastMessage, object: updateChatLastMessage) }
        case .updateChatPosition(let updateChatPosition):
            Task.main { nc.post(name: .updateChatPosition, object: updateChatPosition) }
        case .updateChatAddedToList(let updateChatAddedToList):
            nc.post(name: .updateChatAddedToList, object: updateChatAddedToList)
        case .updateChatRemovedFromList(let updateChatRemovedFromList):
            nc.post(name: .updateChatRemovedFromList, object: updateChatRemovedFromList)
        case .updateChatReadInbox(let updateChatReadInbox):
            Task.main { nc.post(name: .updateChatReadInbox, object: updateChatReadInbox) }
        case .updateChatReadOutbox(let updateChatReadOutbox):
            nc.post(name: .updateChatReadOutbox, object: updateChatReadOutbox)
        case .updateChatActionBar(let updateChatActionBar):
            nc.post(name: .updateChatActionBar, object: updateChatActionBar)
        case .updateChatBusinessBotManageBar(let updateChatBusinessBotManageBar):
            nc.post(name: .updateChatBusinessBotManageBar, object: updateChatBusinessBotManageBar)
        case .updateChatAvailableReactions(let updateChatAvailableReactions):
            nc.post(name: .updateChatAvailableReactions, object: updateChatAvailableReactions)
        case .updateChatDraftMessage(let updateChatDraftMessage):
            Task.main { nc.post(name: .updateChatDraftMessage, object: updateChatDraftMessage) }
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
            Task.main { nc.post(name: .updateFile, object: updateFile) }
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
        case .updateUsersNearby(let updateUsersNearby):
            nc.post(name: .updateUsersNearby, object: updateUsersNearby)
        case .updateUnconfirmedSession(let updateUnconfirmedSession):
            nc.post(name: .updateUnconfirmedSession, object: updateUnconfirmedSession)
        case .updateAttachmentMenuBots(let updateAttachmentMenuBots):
            nc.post(name: .updateAttachmentMenuBots, object: updateAttachmentMenuBots)
        case .updateWebAppMessageSent(let updateWebAppMessageSent):
            nc.post(name: .updateWebAppMessageSent, object: updateWebAppMessageSent)
        case .updateActiveEmojiReactions(let updateActiveEmojiReactions):
            nc.post(name: .updateActiveEmojiReactions, object: updateActiveEmojiReactions)
        case .updateDefaultReactionType(let updateDefaultReactionType):
            nc.post(name: .updateDefaultReactionType, object: updateDefaultReactionType)
        case .updateSavedMessagesTags(let updateSavedMessagesTags):
            nc.post(name: .updateSavedMessagesTags, object: updateSavedMessagesTags)
        case .updateChatRevenueAmount:
            nc.post(name: .updateChatRevenueAmount)
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
    }
}

private func UpdateAuthorizationState(_ updateAuthorizationState: AuthorizationState) {
    switch updateAuthorizationState {
        case .authorizationStateWaitTdlibParameters:
            nc.post(name: .authorizationStateWaitTdlibParameters)
        case .authorizationStateWaitPhoneNumber:
            Task.main { nc.post(name: .authorizationStateWaitPhoneNumber) }
        case .authorizationStateWaitEmailAddress(let authorizationStateWaitEmailAddress):
            nc.post(name: .authorizationStateWaitEmailAddress, object: authorizationStateWaitEmailAddress)
        case .authorizationStateWaitEmailCode(let authorizationStateWaitEmailCode):
            nc.post(name: .authorizationStateWaitEmailCode, object: authorizationStateWaitEmailCode)
        case .authorizationStateWaitCode(let authorizationStateWaitCode):
            Task.main { nc.post(name: .authorizationStateWaitCode, object: authorizationStateWaitCode) }
        case .authorizationStateWaitOtherDeviceConfirmation(let authorizationStateWaitOtherDeviceConfirmation):
            nc.post(
                name: .authorizationStateWaitOtherDeviceConfirmation,
                object: authorizationStateWaitOtherDeviceConfirmation
            )
        case .authorizationStateWaitRegistration(let authorizationStateWaitRegistration):
            nc.post(name: .authorizationStateWaitRegistration, object: authorizationStateWaitRegistration)
        case .authorizationStateWaitPassword(let authorizationStateWaitPassword):
            Task.main { nc.post(name: .authorizationStateWaitPassword, object: authorizationStateWaitPassword) }
        case .authorizationStateReady:
            Task.main { nc.post(name: .authorizationStateReady) }
        case .authorizationStateLoggingOut:
            Task.main { nc.post(name: .authorizationStateLoggingOut) }
        case .authorizationStateClosing:
            Task.main { nc.post(name: .authorizationStateClosing) }
        case .authorizationStateClosed:
            Task.main { nc.post(name: .authorizationStateClosed) }
    }
}

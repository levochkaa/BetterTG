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
    
    nc.publisher(&cancellables, for: .waitTdlibParameters) { _ in
        Task {
            let dir = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appending(path: "td").path()
            
            try await td.setTdlibParameters(
                apiHash: Secret.apiHash,
                apiId: Secret.apiId,
                applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                databaseDirectory: dir,
                databaseEncryptionKey: Data(),
                deviceModel: Utils.modelName,
                enableStorageOptimizer: true,
                filesDirectory: dir,
                ignoreFileNames: false,
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
}

// swiftlint:disable:next function_body_length
private func update(_ update: Update) {
    switch update {
        case .updateAuthorizationState(let authorizationState):
            Task.main { updateAuthorizationState(authorizationState.authorizationState) }
        case .updateNewMessage(let updateNewMessage):
            Task.main { nc.post(name: .newMessage, object: updateNewMessage) }
        case .updateMessageSendAcknowledged(let updateMessageSendAcknowledged):
            nc.post(name: .messageSendAcknowledged, object: updateMessageSendAcknowledged)
        case .updateMessageSendSucceeded(let updateMessageSendSucceeded):
            nc.post(name: .messageSendSucceeded, object: updateMessageSendSucceeded)
        case .updateMessageSendFailed(let updateMessageSendFailed):
            nc.post(name: .messageSendFailed, object: updateMessageSendFailed)
        case .updateMessageContent(let updateMessageContent):
            nc.post(name: .messageSendContent, object: updateMessageContent)
        case .updateMessageEdited(let updateMessageEdited):
            Task.main { nc.post(name: .messageEdited, object: updateMessageEdited) }
        case .updateMessageIsPinned(let updateMessageIsPinned):
            nc.post(name: .messageIsPinned, object: updateMessageIsPinned)
        case .updateMessageInteractionInfo(let updateMessageInteractionInfo):
            nc.post(name: .messageInteractionInfo, object: updateMessageInteractionInfo)
        case .updateMessageContentOpened(let updateMessageContentOpened):
            nc.post(name: .messageContentOpened, object: updateMessageContentOpened)
        case .updateMessageMentionRead(let updateMessageMentionRead):
            nc.post(name: .messageMentionRead, object: updateMessageMentionRead)
        case .updateMessageUnreadReactions(let updateMessageUnreadReactions):
            nc.post(name: .messageUnreadReactions, object: updateMessageUnreadReactions)
        case .updateMessageLiveLocationViewed(let updateMessageLiveLocationViewed):
            nc.post(name: .messageLiveLocationViewed, object: updateMessageLiveLocationViewed)
        case .updateNewChat(let updateNewChat):
            nc.post(name: .newChat, object: updateNewChat)
        case .updateChatTitle(let updateChatTitle):
            nc.post(name: .chatTitle, object: updateChatTitle)
        case .updateChatPhoto(let updateChatPhoto):
            nc.post(name: .chatPhoto, object: updateChatPhoto)
        case .updateChatAccentColor(let updateChatAccentColor):
            nc.post(name: .chatAccentColor, object: updateChatAccentColor)
        case .updateChatBackgroundCustomEmoji(let updateChatBackgroundCustomEmoji):
            nc.post(name: .chatBackgroundCustomEmoji, object: updateChatBackgroundCustomEmoji)
        case .updateChatPermissions(let updateChatPermissions):
            nc.post(name: .chatPermissions, object: updateChatPermissions)
        case .updateChatLastMessage(let updateChatLastMessage):
            nc.post(name: .chatLastMessage, object: updateChatLastMessage)
        case .updateChatPosition(let updateChatPosition):
            nc.post(name: .chatPosition, object: updateChatPosition)
        case .updateChatReadInbox(let updateChatReadInbox):
            Task.main { nc.post(name: .chatReadInbox, object: updateChatReadInbox) }
        case .updateChatReadOutbox(let updateChatReadOutbox):
            nc.post(name: .chatReadOutbox, object: updateChatReadOutbox)
        case .updateChatActionBar(let updateChatActionBar):
            nc.post(name: .chatActionBar, object: updateChatActionBar)
        case .updateChatAvailableReactions(let updateChatAvailableReactions):
            nc.post(name: .chatAvailableReactions, object: updateChatAvailableReactions)
        case .updateChatDraftMessage(let updateChatDraftMessage):
            nc.post(name: .chatDraftMessage, object: updateChatDraftMessage)
        case .updateChatMessageSender(let updateChatMessageSender):
            nc.post(name: .chatMessageSender, object: updateChatMessageSender)
        case .updateChatMessageAutoDeleteTime(let updateChatMessageAutoDeleteTime):
            nc.post(name: .chatMessageAutoDeleteTime, object: updateChatMessageAutoDeleteTime)
        case .updateChatNotificationSettings(let updateChatNotificationSettings):
            nc.post(name: .chatNotificationSettings, object: updateChatNotificationSettings)
        case .updateChatPendingJoinRequests(let updateChatPendingJoinRequests):
            nc.post(name: .chatPendingJoinRequests, object: updateChatPendingJoinRequests)
        case .updateChatReplyMarkup(let updateChatReplyMarkup):
            nc.post(name: .chatReplyMarkup, object: updateChatReplyMarkup)
        case .updateChatBackground(let updateChatBackground):
            nc.post(name: .chatBackground, object: updateChatBackground)
        case .updateChatTheme(let updateChatTheme):
            nc.post(name: .chatTheme, object: updateChatTheme)
        case .updateChatUnreadMentionCount(let updateChatUnreadMentionCount):
            nc.post(name: .chatUnreadMentionCount, object: updateChatUnreadMentionCount)
        case .updateChatUnreadReactionCount(let updateChatUnreadReactionCount):
            nc.post(name: .chatUnreadReactionCount, object: updateChatUnreadReactionCount)
        case .updateChatVideoChat(let updateChatVideoChat):
            nc.post(name: .chatVideoChat, object: updateChatVideoChat)
        case .updateChatDefaultDisableNotification(let updateChatDefaultDisableNotification):
            nc.post(name: .chatDefaultDisableNotification, object: updateChatDefaultDisableNotification)
        case .updateChatHasProtectedContent(let updateChatHasProtectedContent):
            nc.post(name: .chatHasProtectedContent, object: updateChatHasProtectedContent)
        case .updateChatIsTranslatable(let updateChatIsTranslatable):
            nc.post(name: .chatIsTranslatable, object: updateChatIsTranslatable)
        case .updateChatIsMarkedAsUnread(let updateChatIsMarkedAsUnread):
            nc.post(name: .chatIsMarkedAsUnread, object: updateChatIsMarkedAsUnread)
        case .updateChatViewAsTopics(let updateChatViewAsTopics):
            nc.post(name: .chatViewAsTopics, object: updateChatViewAsTopics)
        case .updateChatBlockList(let updateChatBlockList):
            nc.post(name: .chatBlockList, object: updateChatBlockList)
        case .updateChatHasScheduledMessages(let updateChatHasScheduledMessages):
            nc.post(name: .chatHasScheduledMessages, object: updateChatHasScheduledMessages)
        case .updateChatFolders(let updateChatFolders):
            nc.post(name: .chatFolders, object: updateChatFolders)
        case .updateChatOnlineMemberCount(let updateChatOnlineMemberCount):
            nc.post(name: .chatOnlineMemberCount, object: updateChatOnlineMemberCount)
        case .updateForumTopicInfo(let updateForumTopicInfo):
            nc.post(name: .forumTopicInfo, object: updateForumTopicInfo)
        case .updateScopeNotificationSettings(let updateScopeNotificationSettings):
            nc.post(name: .scopeNotificationSettings, object: updateScopeNotificationSettings)
        case .updateNotification(let updateNotification):
            nc.post(name: .notification, object: updateNotification)
        case .updateNotificationGroup(let updateNotificationGroup):
            nc.post(name: .notificationGroup, object: updateNotificationGroup)
        case .updateActiveNotifications(let updateActiveNotifications):
            nc.post(name: .activeNotifications, object: updateActiveNotifications)
        case .updateHavePendingNotifications(let updateHavePendingNotifications):
            nc.post(name: .havePendingNotifications, object: updateHavePendingNotifications)
        case .updateDeleteMessages(let updateDeleteMessages):
            nc.post(name: .deleteMessages, object: updateDeleteMessages)
        case .updateChatAction(let updateChatAction):
            nc.post(name: .chatAction, object: updateChatAction)
        case .updateUserStatus(let updateUserStatus):
            nc.post(name: .userStatus, object: updateUserStatus)
        case .updateUser(let updateUser):
            nc.post(name: .user, object: updateUser)
        case .updateBasicGroup(let updateBasicGroup):
            nc.post(name: .basicGroup, object: updateBasicGroup)
        case .updateSupergroup(let updateSupergroup):
            nc.post(name: .supergroup, object: updateSupergroup)
        case .updateSecretChat(let updateSecretChat):
            nc.post(name: .secretChat, object: updateSecretChat)
        case .updateUserFullInfo(let updateUserFullInfo):
            nc.post(name: .userFullInfo, object: updateUserFullInfo)
        case .updateBasicGroupFullInfo(let updateBasicGroupFullInfo):
            nc.post(name: .basicGroupFullInfo, object: updateBasicGroupFullInfo)
        case .updateSupergroupFullInfo(let updateSupergroupFullInfo):
            nc.post(name: .supergroupFullInfo, object: updateSupergroupFullInfo)
        case .updateServiceNotification(let updateServiceNotification):
            nc.post(name: .serviceNotification, object: updateServiceNotification)
        case .updateFile(let updateFile):
            Task.main { nc.post(name: .file, object: updateFile) }
        case .updateFileGenerationStart(let updateFileGenerationStart):
            nc.post(name: .fileGenerationStart, object: updateFileGenerationStart)
        case .updateFileGenerationStop(let updateFileGenerationStop):
            nc.post(name: .fileGenerationStop, object: updateFileGenerationStop)
        case .updateFileDownloads(let updateFileDownloads):
            nc.post(name: .fileDownloads, object: updateFileDownloads)
        case .updateFileAddedToDownloads(let updateFileAddedToDownloads):
            nc.post(name: .fileAddedToDownloads, object: updateFileAddedToDownloads)
        case .updateFileDownload(let updateFileDownload):
            nc.post(name: .fileDownload, object: updateFileDownload)
        case .updateFileRemovedFromDownloads(let updateFileRemovedFromDownloads):
            nc.post(name: .fileRemovedFromDownloads, object: updateFileRemovedFromDownloads)
        case .updateCall(let updateCall):
            nc.post(name: .call, object: updateCall)
        case .updateGroupCall(let updateGroupCall):
            nc.post(name: .groupCall, object: updateGroupCall)
        case .updateGroupCallParticipant(let updateGroupCallParticipant):
            nc.post(name: .groupCallParticipant, object: updateGroupCallParticipant)
        case .updateNewCallSignalingData(let updateNewCallSignalingData):
            nc.post(name: .newCallSignalingData, object: updateNewCallSignalingData)
        case .updateUserPrivacySettingRules(let updateUserPrivacySettingRules):
            nc.post(name: .userPrivacySettingRules, object: updateUserPrivacySettingRules)
        case .updateUnreadMessageCount(let updateUnreadMessageCount):
            nc.post(name: .unreadMessageCount, object: updateUnreadMessageCount)
        case .updateUnreadChatCount(let updateUnreadChatCount):
            nc.post(name: .unreadChatCount, object: updateUnreadChatCount)
        case .updateStory(let updateStory):
            nc.post(name: .story, object: updateStory)
        case .updateStoryDeleted(let updateStoryDeleted):
            nc.post(name: .storyDeleted, object: updateStoryDeleted)
        case .updateStorySendSucceeded(let updateStorySendSucceeded):
            nc.post(name: .storySendSucceeded, object: updateStorySendSucceeded)
        case .updateStorySendFailed(let updateStorySendFailed):
            nc.post(name: .storySendFailed, object: updateStorySendFailed)
        case .updateChatActiveStories(let updateChatActiveStories):
            nc.post(name: .chatActiveStories, object: updateChatActiveStories)
        case .updateStoryListChatCount(let updateStoryListChatCount):
            nc.post(name: .storyListChatCount, object: updateStoryListChatCount)
        case .updateStoryStealthMode(let updateStoryStealthMode):
            nc.post(name: .storyStealthMode, object: updateStoryStealthMode)
        case .updateOption(let updateOption):
            nc.post(name: .option, object: updateOption)
        case .updateStickerSet(let updateStickerSet):
            nc.post(name: .stickerSet, object: updateStickerSet)
        case .updateInstalledStickerSets(let updateInstalledStickerSets):
            nc.post(name: .installedStickerSets, object: updateInstalledStickerSets)
        case .updateTrendingStickerSets(let updateTrendingStickerSets):
            nc.post(name: .trendingStickerSets, object: updateTrendingStickerSets)
        case .updateRecentStickers(let updateRecentStickers):
            nc.post(name: .recentStickers, object: updateRecentStickers)
        case .updateFavoriteStickers(let updateFavoriteStickers):
            nc.post(name: .favoriteStickers, object: updateFavoriteStickers)
        case .updateSavedAnimations(let updateSavedAnimations):
            nc.post(name: .savedAnimations, object: updateSavedAnimations)
        case .updateSavedNotificationSounds(let updateSavedNotificationSounds):
            nc.post(name: .savedNotificationSounds, object: updateSavedNotificationSounds)
        case .updateSelectedBackground(let updateSelectedBackground):
            nc.post(name: .selectedBackground, object: updateSelectedBackground)
        case .updateChatThemes(let updateChatThemes):
            nc.post(name: .chatThemes, object: updateChatThemes)
        case .updateAccentColors(let updateAccentColors):
            nc.post(name: .accentColors, object: updateAccentColors)
        case .updateProfileAccentColors(let updateProfileAccentColors):
            nc.post(name: .profileAccentColors, object: updateProfileAccentColors)
        case .updateLanguagePackStrings(let updateLanguagePackStrings):
            nc.post(name: .languagePackStrings, object: updateLanguagePackStrings)
        case .updateConnectionState(let updateConnectionState):
            nc.post(name: .connectionState, object: updateConnectionState)
        case .updateTermsOfService(let updateTermsOfService):
            nc.post(name: .termsOfService, object: updateTermsOfService)
        case .updateUsersNearby(let updateUsersNearby):
            nc.post(name: .usersNearby, object: updateUsersNearby)
        case .updateUnconfirmedSession(let updateUnconfirmedSession):
            nc.post(name: .unconfirmedSession, object: updateUnconfirmedSession)
        case .updateAttachmentMenuBots(let updateAttachmentMenuBots):
            nc.post(name: .attachmentMenuBots, object: updateAttachmentMenuBots)
        case .updateWebAppMessageSent(let updateWebAppMessageSent):
            nc.post(name: .webAppMessageSent, object: updateWebAppMessageSent)
        case .updateActiveEmojiReactions(let updateActiveEmojiReactions):
            nc.post(name: .activeEmojiReactions, object: updateActiveEmojiReactions)
        case .updateDefaultReactionType(let updateDefaultReactionType):
            nc.post(name: .defaultReactionType, object: updateDefaultReactionType)
        case .updateSpeechRecognitionTrial(let updateSpeechRecognitionTrial):
            nc.post(name: .speechRecognitionTrial, object: updateSpeechRecognitionTrial)
        case .updateDiceEmojis(let updateDiceEmojis):
            nc.post(name: .diceEmojis, object: updateDiceEmojis)
        case .updateAnimatedEmojiMessageClicked(let updateAnimatedEmojiMessageClicked):
            nc.post(name: .animatedEmojiMessageClicked, object: updateAnimatedEmojiMessageClicked)
        case .updateAnimationSearchParameters(let updateAnimationSearchParameters):
            nc.post(name: .animationSearchParameters, object: updateAnimationSearchParameters)
        case .updateSuggestedActions(let updateSuggestedActions):
            nc.post(name: .suggestedActions, object: updateSuggestedActions)
        case .updateAddChatMembersPrivacyForbidden(let updateAddChatMembersPrivacyForbidden):
            nc.post(name: .addChatMembersPrivacyForbidden, object: updateAddChatMembersPrivacyForbidden)
        case .updateAutosaveSettings(let updateAutosaveSettings):
            nc.post(name: .autosaveSettings, object: updateAutosaveSettings)
        case .updateNewInlineQuery(let updateNewInlineQuery):
            nc.post(name: .newInlineQuery, object: updateNewInlineQuery)
        case .updateNewChosenInlineResult(let updateNewChosenInlineResult):
            nc.post(name: .newChosenInlineResult, object: updateNewChosenInlineResult)
        case .updateNewCallbackQuery(let updateNewCallbackQuery):
            nc.post(name: .newCallbackQuery, object: updateNewCallbackQuery)
        case .updateNewInlineCallbackQuery(let updateNewInlineCallbackQuery):
            nc.post(name: .newInlineCallbackQuery, object: updateNewInlineCallbackQuery)
        case .updateNewShippingQuery(let updateNewShippingQuery):
            nc.post(name: .newShippingQuery, object: updateNewShippingQuery)
        case .updateNewPreCheckoutQuery(let updateNewPreCheckoutQuery):
            nc.post(name: .newPreCheckoutQuery, object: updateNewPreCheckoutQuery)
        case .updateNewCustomEvent(let updateNewCustomEvent):
            nc.post(name: .newCustomEvent, object: updateNewCustomEvent)
        case .updateNewCustomQuery(let updateNewCustomQuery):
            nc.post(name: .newCustomQuery, object: updateNewCustomQuery)
        case .updatePoll(let updatePoll):
            nc.post(name: .poll, object: updatePoll)
        case .updatePollAnswer(let updatePollAnswer):
            nc.post(name: .pollAnswer, object: updatePollAnswer)
        case .updateChatMember(let updateChatMember):
            nc.post(name: .chatMember, object: updateChatMember)
        case .updateNewChatJoinRequest(let updateNewChatJoinRequest):
            nc.post(name: .newChatJoinRequest, object: updateNewChatJoinRequest)
        case .updateChatBoost(let updateChatBoost):
            nc.post(name: .chatBoost, object: updateChatBoost)
    }
}

private func updateAuthorizationState(_ authorizationState: AuthorizationState) {
    switch authorizationState {
        case .authorizationStateWaitTdlibParameters:
            nc.post(name: .waitTdlibParameters)
        case .authorizationStateWaitPhoneNumber:
            Task.main { nc.post(name: .waitPhoneNumber) }
        case .authorizationStateWaitEmailAddress(let authorizationStateWaitEmailAddress):
            nc.post(name: .waitEmailAddress, object: authorizationStateWaitEmailAddress)
        case .authorizationStateWaitEmailCode(let authorizationStateWaitEmailCode):
            nc.post(name: .waitEmailCode, object: authorizationStateWaitEmailCode)
        case .authorizationStateWaitCode(let authorizationStateWaitCode):
            Task.main { nc.post(name: .waitCode, object: authorizationStateWaitCode) }
        case .authorizationStateWaitOtherDeviceConfirmation(let authorizationStateWaitOtherDeviceConfirmation):
            nc.post(name: .waitOtherDeviceConfirmation, object: authorizationStateWaitOtherDeviceConfirmation)
        case .authorizationStateWaitRegistration(let authorizationStateWaitRegistration):
            nc.post(name: .waitRegistration, object: authorizationStateWaitRegistration)
        case .authorizationStateWaitPassword(let authorizationStateWaitPassword):
            Task.main { nc.post(name: .waitPassword, object: authorizationStateWaitPassword) }
        case .authorizationStateReady:
            Task.main { nc.post(name: .ready) }
        case .authorizationStateLoggingOut:
            Task.main { nc.post(name: .loggingOut) }
        case .authorizationStateClosing:
            Task.main { nc.post(name: .closing) }
        case .authorizationStateClosed:
            Task.main { nc.post(name: .closed) }
    }
}

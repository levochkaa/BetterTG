file_path = "BetterTG/Extensions/Td+Generated.swift"

core = """// Td+Generated.swift

// This file is generated from td.py
// Any modifications will be overwritten

import SwiftUI
@preconcurrency import TDLibKit

// swiftlint:disable line_length

"""

update_func = """// swiftlint:disable:next function_body_length
func update(_ update: Update) {
    switch update {
        case .updateAuthorizationState(let updateAuthorizationState):
            UpdateAuthorizationState(updateAuthorizationState.authorizationState)
"""

def main(update: str):
    (notifications, notification_names, update_cases) = ([], [], [])
    for line in update.split("\n"):
        if "case " in line and "(" in line and "(let" not in line:
            after_case = line.split("case ")[1]
            name_split = after_case.split("(")
            name = name_split[0]
            type = name_split[1].split(")")[0]
            notifications.append(
                f"    static var {name}: TdNotification<{
                    type}> {{ .init(.{name}) }}\n"
            )
            notification_names.append(
                f"    static let {name} = Self(\"{name}\")\n")
            if name == "updateAuthorizationState":
                continue
            update_cases.append(
                (
                    f"        case .{name}(let {name}):\n",
                    f"            nc.post(name: .{name}, object: {name})\n"
                )
            )

    file = open(file_path, "w")

    file.write(core)

    for line in update_func:
        file.write(line)
    for update_case in update_cases:
        file.write(update_case[0])
        file.write(update_case[1])
    file.write("    }\n")
    file.write("}\n\n")

    file.write("extension TdNotification {\n")
    for notification in notifications:
        file.write(notification)
    file.write("}\n\n")

    file.write("extension Foundation.Notification.Name {\n")
    for notification_name in notification_names:
        file.write(notification_name)
    file.write("}\n\n")

    file.write("// swiftlint:enable line_length\n\n")
    file.write("// swiftlint:disable:this file_length\n")

    file.close()

# probably, fetching from currently used tdlib is better, but this solution is faster to implement
update = """
public indirect enum Update: Codable, Equatable, Hashable {

    /// The user authorization state has changed
    case updateAuthorizationState(UpdateAuthorizationState)

    /// A new message was received; can also be an outgoing message
    case updateNewMessage(UpdateNewMessage)

    /// A request to send a message has reached the Telegram server. This doesn't mean that the message will be sent successfully. This update is sent only if the option "use_quick_ack" is set to true. This update may be sent multiple times for the same message
    case updateMessageSendAcknowledged(UpdateMessageSendAcknowledged)

    /// A message has been successfully sent
    case updateMessageSendSucceeded(UpdateMessageSendSucceeded)

    /// A message failed to send. Be aware that some messages being sent can be irrecoverably deleted, in which case updateDeleteMessages will be received instead of this update
    case updateMessageSendFailed(UpdateMessageSendFailed)

    /// The message content has changed
    case updateMessageContent(UpdateMessageContent)

    /// A message was edited. Changes in the message content will come in a separate updateMessageContent
    case updateMessageEdited(UpdateMessageEdited)

    /// The message pinned state was changed
    case updateMessageIsPinned(UpdateMessageIsPinned)

    /// The information about interactions with a message has changed
    case updateMessageInteractionInfo(UpdateMessageInteractionInfo)

    /// The message content was opened. Updates voice note messages to "listened", video note messages to "viewed" and starts the self-destruct timer
    case updateMessageContentOpened(UpdateMessageContentOpened)

    /// A message with an unread mention was read
    case updateMessageMentionRead(UpdateMessageMentionRead)

    /// The list of unread reactions added to a message was changed
    case updateMessageUnreadReactions(UpdateMessageUnreadReactions)

    /// A fact-check added to a message was changed
    case updateMessageFactCheck(UpdateMessageFactCheck)

    /// A message with a live location was viewed. When the update is received, the application is expected to update the live location
    case updateMessageLiveLocationViewed(UpdateMessageLiveLocationViewed)

    /// An automatically scheduled message with video has been successfully sent after conversion
    case updateVideoPublished(UpdateVideoPublished)

    /// A new chat has been loaded/created. This update is guaranteed to come before the chat identifier is returned to the application. The chat field changes will be reported through separate updates
    case updateNewChat(UpdateNewChat)

    /// The title of a chat was changed
    case updateChatTitle(UpdateChatTitle)

    /// A chat photo was changed
    case updateChatPhoto(UpdateChatPhoto)

    /// Chat accent colors have changed
    case updateChatAccentColors(UpdateChatAccentColors)

    /// Chat permissions were changed
    case updateChatPermissions(UpdateChatPermissions)

    /// The last message of a chat was changed
    case updateChatLastMessage(UpdateChatLastMessage)

    /// The position of a chat in a chat list has changed. An updateChatLastMessage or updateChatDraftMessage update might be sent instead of the update
    case updateChatPosition(UpdateChatPosition)

    /// A chat was added to a chat list
    case updateChatAddedToList(UpdateChatAddedToList)

    /// A chat was removed from a chat list
    case updateChatRemovedFromList(UpdateChatRemovedFromList)

    /// Incoming messages were read or the number of unread messages has been changed
    case updateChatReadInbox(UpdateChatReadInbox)

    /// Outgoing messages were read
    case updateChatReadOutbox(UpdateChatReadOutbox)

    /// The chat action bar was changed
    case updateChatActionBar(UpdateChatActionBar)

    /// The bar for managing business bot was changed in a chat
    case updateChatBusinessBotManageBar(UpdateChatBusinessBotManageBar)

    /// The chat available reactions were changed
    case updateChatAvailableReactions(UpdateChatAvailableReactions)

    /// A chat draft has changed. Be aware that the update may come in the currently opened chat but with old content of the draft. If the user has changed the content of the draft, this update mustn't be applied
    case updateChatDraftMessage(UpdateChatDraftMessage)

    /// Chat emoji status has changed
    case updateChatEmojiStatus(UpdateChatEmojiStatus)

    /// The message sender that is selected to send messages in a chat has changed
    case updateChatMessageSender(UpdateChatMessageSender)

    /// The message auto-delete or self-destruct timer setting for a chat was changed
    case updateChatMessageAutoDeleteTime(UpdateChatMessageAutoDeleteTime)

    /// Notification settings for a chat were changed
    case updateChatNotificationSettings(UpdateChatNotificationSettings)

    /// The chat pending join requests were changed
    case updateChatPendingJoinRequests(UpdateChatPendingJoinRequests)

    /// The default chat reply markup was changed. Can occur because new messages with reply markup were received or because an old reply markup was hidden by the user
    case updateChatReplyMarkup(UpdateChatReplyMarkup)

    /// The chat background was changed
    case updateChatBackground(UpdateChatBackground)

    /// The chat theme was changed
    case updateChatTheme(UpdateChatTheme)

    /// The chat unread_mention_count has changed
    case updateChatUnreadMentionCount(UpdateChatUnreadMentionCount)

    /// The chat unread_reaction_count has changed
    case updateChatUnreadReactionCount(UpdateChatUnreadReactionCount)

    /// A chat video chat state has changed
    case updateChatVideoChat(UpdateChatVideoChat)

    /// The value of the default disable_notification parameter, used when a message is sent to the chat, was changed
    case updateChatDefaultDisableNotification(UpdateChatDefaultDisableNotification)

    /// A chat content was allowed or restricted for saving
    case updateChatHasProtectedContent(UpdateChatHasProtectedContent)

    /// Translation of chat messages was enabled or disabled
    case updateChatIsTranslatable(UpdateChatIsTranslatable)

    /// A chat was marked as unread or was read
    case updateChatIsMarkedAsUnread(UpdateChatIsMarkedAsUnread)

    /// A chat default appearance has changed
    case updateChatViewAsTopics(UpdateChatViewAsTopics)

    /// A chat was blocked or unblocked
    case updateChatBlockList(UpdateChatBlockList)

    /// A chat's has_scheduled_messages field has changed
    case updateChatHasScheduledMessages(UpdateChatHasScheduledMessages)

    /// The list of chat folders or a chat folder has changed
    case updateChatFolders(UpdateChatFolders)

    /// The number of online group members has changed. This update with non-zero number of online group members is sent only for currently opened chats. There is no guarantee that it is sent just after the number of online users has changed
    case updateChatOnlineMemberCount(UpdateChatOnlineMemberCount)

    /// Basic information about a Saved Messages topic has changed. This update is guaranteed to come before the topic identifier is returned to the application
    case updateSavedMessagesTopic(UpdateSavedMessagesTopic)

    /// Number of Saved Messages topics has changed
    case updateSavedMessagesTopicCount(UpdateSavedMessagesTopicCount)

    /// Basic information about a quick reply shortcut has changed. This update is guaranteed to come before the quick shortcut name is returned to the application
    case updateQuickReplyShortcut(UpdateQuickReplyShortcut)

    /// A quick reply shortcut and all its messages were deleted
    case updateQuickReplyShortcutDeleted(UpdateQuickReplyShortcutDeleted)

    /// The list of quick reply shortcuts has changed
    case updateQuickReplyShortcuts(UpdateQuickReplyShortcuts)

    /// The list of quick reply shortcut messages has changed
    case updateQuickReplyShortcutMessages(UpdateQuickReplyShortcutMessages)

    /// Basic information about a topic in a forum chat was changed
    case updateForumTopicInfo(UpdateForumTopicInfo)

    /// Notification settings for some type of chats were updated
    case updateScopeNotificationSettings(UpdateScopeNotificationSettings)

    /// Notification settings for reactions were updated
    case updateReactionNotificationSettings(UpdateReactionNotificationSettings)

    /// A notification was changed
    case updateNotification(UpdateNotification)

    /// A list of active notifications in a notification group has changed
    case updateNotificationGroup(UpdateNotificationGroup)

    /// Contains active notifications that were shown on previous application launches. This update is sent only if the message database is used. In that case it comes once before any updateNotification and updateNotificationGroup update
    case updateActiveNotifications(UpdateActiveNotifications)

    /// Describes whether there are some pending notification updates. Can be used to prevent application from killing, while there are some pending notifications
    case updateHavePendingNotifications(UpdateHavePendingNotifications)

    /// Some messages were deleted
    case updateDeleteMessages(UpdateDeleteMessages)

    /// A message sender activity in the chat has changed
    case updateChatAction(UpdateChatAction)

    /// The user went online or offline
    case updateUserStatus(UpdateUserStatus)

    /// Some data of a user has changed. This update is guaranteed to come before the user identifier is returned to the application
    case updateUser(UpdateUser)

    /// Some data of a basic group has changed. This update is guaranteed to come before the basic group identifier is returned to the application
    case updateBasicGroup(UpdateBasicGroup)

    /// Some data of a supergroup or a channel has changed. This update is guaranteed to come before the supergroup identifier is returned to the application
    case updateSupergroup(UpdateSupergroup)

    /// Some data of a secret chat has changed. This update is guaranteed to come before the secret chat identifier is returned to the application
    case updateSecretChat(UpdateSecretChat)

    /// Some data in userFullInfo has been changed
    case updateUserFullInfo(UpdateUserFullInfo)

    /// Some data in basicGroupFullInfo has been changed
    case updateBasicGroupFullInfo(UpdateBasicGroupFullInfo)

    /// Some data in supergroupFullInfo has been changed
    case updateSupergroupFullInfo(UpdateSupergroupFullInfo)

    /// A service notification from the server was received. Upon receiving this the application must show a popup with the content of the notification
    case updateServiceNotification(UpdateServiceNotification)

    /// Information about a file was updated
    case updateFile(UpdateFile)

    /// The file generation process needs to be started by the application. Use setFileGenerationProgress and finishFileGeneration to generate the file
    case updateFileGenerationStart(UpdateFileGenerationStart)

    /// File generation is no longer needed
    case updateFileGenerationStop(UpdateFileGenerationStop)

    /// The state of the file download list has changed
    case updateFileDownloads(UpdateFileDownloads)

    /// A file was added to the file download list. This update is sent only after file download list is loaded for the first time
    case updateFileAddedToDownloads(UpdateFileAddedToDownloads)

    /// A file download was changed. This update is sent only after file download list is loaded for the first time
    case updateFileDownload(UpdateFileDownload)

    /// A file was removed from the file download list. This update is sent only after file download list is loaded for the first time
    case updateFileRemovedFromDownloads(UpdateFileRemovedFromDownloads)

    /// A request can't be completed unless application verification is performed; for official mobile applications only. The method setApplicationVerificationToken must be called once the verification is completed or failed
    case updateApplicationVerificationRequired(UpdateApplicationVerificationRequired)

    /// New call was created or information about a call was updated
    case updateCall(UpdateCall)

    /// Information about a group call was updated
    case updateGroupCall(UpdateGroupCall)

    /// Information about a group call participant was changed. The updates are sent only after the group call is received through getGroupCall and only if the call is joined or being joined
    case updateGroupCallParticipant(UpdateGroupCallParticipant)

    /// New call signaling data arrived
    case updateNewCallSignalingData(UpdateNewCallSignalingData)

    /// Some privacy setting rules have been changed
    case updateUserPrivacySettingRules(UpdateUserPrivacySettingRules)

    /// Number of unread messages in a chat list has changed. This update is sent only if the message database is used
    case updateUnreadMessageCount(UpdateUnreadMessageCount)

    /// Number of unread chats, i.e. with unread messages or marked as unread, has changed. This update is sent only if the message database is used
    case updateUnreadChatCount(UpdateUnreadChatCount)

    /// A story was changed
    case updateStory(UpdateStory)

    /// A story became inaccessible
    case updateStoryDeleted(UpdateStoryDeleted)

    /// A story has been successfully sent
    case updateStorySendSucceeded(UpdateStorySendSucceeded)

    /// A story failed to send. If the story sending is canceled, then updateStoryDeleted will be received instead of this update
    case updateStorySendFailed(UpdateStorySendFailed)

    /// The list of active stories posted by a specific chat has changed
    case updateChatActiveStories(UpdateChatActiveStories)

    /// Number of chats in a story list has changed
    case updateStoryListChatCount(UpdateStoryListChatCount)

    /// Story stealth mode settings have changed
    case updateStoryStealthMode(UpdateStoryStealthMode)

    /// An option changed its value
    case updateOption(UpdateOption)

    /// A sticker set has changed
    case updateStickerSet(UpdateStickerSet)

    /// The list of installed sticker sets was updated
    case updateInstalledStickerSets(UpdateInstalledStickerSets)

    /// The list of trending sticker sets was updated or some of them were viewed
    case updateTrendingStickerSets(UpdateTrendingStickerSets)

    /// The list of recently used stickers was updated
    case updateRecentStickers(UpdateRecentStickers)

    /// The list of favorite stickers was updated
    case updateFavoriteStickers(UpdateFavoriteStickers)

    /// The list of saved animations was updated
    case updateSavedAnimations(UpdateSavedAnimations)

    /// The list of saved notification sounds was updated. This update may not be sent until information about a notification sound was requested for the first time
    case updateSavedNotificationSounds(UpdateSavedNotificationSounds)

    /// The default background has changed
    case updateDefaultBackground(UpdateDefaultBackground)

    /// The list of available chat themes has changed
    case updateChatThemes(UpdateChatThemes)

    /// The list of supported accent colors has changed
    case updateAccentColors(UpdateAccentColors)

    /// The list of supported accent colors for user profiles has changed
    case updateProfileAccentColors(UpdateProfileAccentColors)

    /// Some language pack strings have been updated
    case updateLanguagePackStrings(UpdateLanguagePackStrings)

    /// The connection state has changed. This update must be used only to show a human-readable description of the connection state
    case updateConnectionState(UpdateConnectionState)

    /// New terms of service must be accepted by the user. If the terms of service are declined, then the deleteAccount method must be called with the reason "Decline ToS update"
    case updateTermsOfService(UpdateTermsOfService)

    /// The first unconfirmed session has changed
    case updateUnconfirmedSession(UpdateUnconfirmedSession)

    /// The list of bots added to attachment or side menu has changed
    case updateAttachmentMenuBots(UpdateAttachmentMenuBots)

    /// A message was sent by an opened Web App, so the Web App needs to be closed
    case updateWebAppMessageSent(UpdateWebAppMessageSent)

    /// The list of active emoji reactions has changed
    case updateActiveEmojiReactions(UpdateActiveEmojiReactions)

    /// The list of available message effects has changed
    case updateAvailableMessageEffects(UpdateAvailableMessageEffects)

    /// The type of default reaction has changed
    case updateDefaultReactionType(UpdateDefaultReactionType)

    /// Tags used in Saved Messages or a Saved Messages topic have changed
    case updateSavedMessagesTags(UpdateSavedMessagesTags)

    /// The list of messages with active live location that need to be updated by the application has changed. The list is persistent across application restarts only if the message database is used
    case updateActiveLiveLocationMessages(UpdateActiveLiveLocationMessages)

    /// The number of Telegram Stars owned by the current user has changed
    case updateOwnedStarCount(UpdateOwnedStarCount)

    /// The revenue earned from sponsored messages in a chat has changed. If chat revenue screen is opened, then getChatRevenueTransactions may be called to fetch new transactions
    case updateChatRevenueAmount(UpdateChatRevenueAmount)

    /// The Telegram Star revenue earned by a bot or a chat has changed. If Telegram Star transaction screen of the chat is opened, then getStarTransactions may be called to fetch new transactions
    case updateStarRevenueStatus(UpdateStarRevenueStatus)

    /// The parameters of speech recognition without Telegram Premium subscription has changed
    case updateSpeechRecognitionTrial(UpdateSpeechRecognitionTrial)

    /// The list of supported dice emojis has changed
    case updateDiceEmojis(UpdateDiceEmojis)

    /// Some animated emoji message was clicked and a big animated sticker must be played if the message is visible on the screen. chatActionWatchingAnimations with the text of the message needs to be sent if the sticker is played
    case updateAnimatedEmojiMessageClicked(UpdateAnimatedEmojiMessageClicked)

    /// The parameters of animation search through getOption("animation_search_bot_username") bot has changed
    case updateAnimationSearchParameters(UpdateAnimationSearchParameters)

    /// The list of suggested to the user actions has changed
    case updateSuggestedActions(UpdateSuggestedActions)

    /// Download or upload file speed for the user was limited, but it can be restored by subscription to Telegram Premium. The notification can be postponed until a being downloaded or uploaded file is visible to the user. Use getOption("premium_download_speedup") or getOption("premium_upload_speedup") to get expected speedup after subscription to Telegram Premium
    case updateSpeedLimitNotification(UpdateSpeedLimitNotification)

    /// The list of contacts that had birthdays recently or will have birthday soon has changed
    case updateContactCloseBirthdays(UpdateContactCloseBirthdays)

    /// Autosave settings for some type of chats were updated
    case updateAutosaveSettings(UpdateAutosaveSettings)

    /// A business connection has changed; for bots only
    case updateBusinessConnection(UpdateBusinessConnection)

    /// A new message was added to a business account; for bots only
    case updateNewBusinessMessage(UpdateNewBusinessMessage)

    /// A message in a business account was edited; for bots only
    case updateBusinessMessageEdited(UpdateBusinessMessageEdited)

    /// Messages in a business account were deleted; for bots only
    case updateBusinessMessagesDeleted(UpdateBusinessMessagesDeleted)

    /// A new incoming inline query; for bots only
    case updateNewInlineQuery(UpdateNewInlineQuery)

    /// The user has chosen a result of an inline query; for bots only
    case updateNewChosenInlineResult(UpdateNewChosenInlineResult)

    /// A new incoming callback query; for bots only
    case updateNewCallbackQuery(UpdateNewCallbackQuery)

    /// A new incoming callback query from a message sent via a bot; for bots only
    case updateNewInlineCallbackQuery(UpdateNewInlineCallbackQuery)

    /// A new incoming callback query from a business message; for bots only
    case updateNewBusinessCallbackQuery(UpdateNewBusinessCallbackQuery)

    /// A new incoming shipping query; for bots only. Only for invoices with flexible price
    case updateNewShippingQuery(UpdateNewShippingQuery)

    /// A new incoming pre-checkout query; for bots only. Contains full information about a checkout
    case updateNewPreCheckoutQuery(UpdateNewPreCheckoutQuery)

    /// A new incoming event; for bots only
    case updateNewCustomEvent(UpdateNewCustomEvent)

    /// A new incoming query; for bots only
    case updateNewCustomQuery(UpdateNewCustomQuery)

    /// A poll was updated; for bots only
    case updatePoll(UpdatePoll)

    /// A user changed the answer to a poll; for bots only
    case updatePollAnswer(UpdatePollAnswer)

    /// User rights changed in a chat; for bots only
    case updateChatMember(UpdateChatMember)

    /// A user sent a join request to a chat; for bots only
    case updateNewChatJoinRequest(UpdateNewChatJoinRequest)

    /// A chat boost has changed; for bots only
    case updateChatBoost(UpdateChatBoost)

    /// User changed its reactions on a message with public reactions; for bots only
    case updateMessageReaction(UpdateMessageReaction)

    /// Reactions added to a message with anonymous reactions have changed; for bots only
    case updateMessageReactions(UpdateMessageReactions)

    /// Paid media were purchased by a user; for bots only
    case updatePaidMediaPurchased(UpdatePaidMediaPurchased)


    private enum Kind: String, Codable {
        case updateAuthorizationState
        case updateNewMessage
        case updateMessageSendAcknowledged
        case updateMessageSendSucceeded
        case updateMessageSendFailed
        case updateMessageContent
        case updateMessageEdited
        case updateMessageIsPinned
        case updateMessageInteractionInfo
        case updateMessageContentOpened
        case updateMessageMentionRead
        case updateMessageUnreadReactions
        case updateMessageFactCheck
        case updateMessageLiveLocationViewed
        case updateVideoPublished
        case updateNewChat
        case updateChatTitle
        case updateChatPhoto
        case updateChatAccentColors
        case updateChatPermissions
        case updateChatLastMessage
        case updateChatPosition
        case updateChatAddedToList
        case updateChatRemovedFromList
        case updateChatReadInbox
        case updateChatReadOutbox
        case updateChatActionBar
        case updateChatBusinessBotManageBar
        case updateChatAvailableReactions
        case updateChatDraftMessage
        case updateChatEmojiStatus
        case updateChatMessageSender
        case updateChatMessageAutoDeleteTime
        case updateChatNotificationSettings
        case updateChatPendingJoinRequests
        case updateChatReplyMarkup
        case updateChatBackground
        case updateChatTheme
        case updateChatUnreadMentionCount
        case updateChatUnreadReactionCount
        case updateChatVideoChat
        case updateChatDefaultDisableNotification
        case updateChatHasProtectedContent
        case updateChatIsTranslatable
        case updateChatIsMarkedAsUnread
        case updateChatViewAsTopics
        case updateChatBlockList
        case updateChatHasScheduledMessages
        case updateChatFolders
        case updateChatOnlineMemberCount
        case updateSavedMessagesTopic
        case updateSavedMessagesTopicCount
        case updateQuickReplyShortcut
        case updateQuickReplyShortcutDeleted
        case updateQuickReplyShortcuts
        case updateQuickReplyShortcutMessages
        case updateForumTopicInfo
        case updateScopeNotificationSettings
        case updateReactionNotificationSettings
        case updateNotification
        case updateNotificationGroup
        case updateActiveNotifications
        case updateHavePendingNotifications
        case updateDeleteMessages
        case updateChatAction
        case updateUserStatus
        case updateUser
        case updateBasicGroup
        case updateSupergroup
        case updateSecretChat
        case updateUserFullInfo
        case updateBasicGroupFullInfo
        case updateSupergroupFullInfo
        case updateServiceNotification
        case updateFile
        case updateFileGenerationStart
        case updateFileGenerationStop
        case updateFileDownloads
        case updateFileAddedToDownloads
        case updateFileDownload
        case updateFileRemovedFromDownloads
        case updateApplicationVerificationRequired
        case updateCall
        case updateGroupCall
        case updateGroupCallParticipant
        case updateNewCallSignalingData
        case updateUserPrivacySettingRules
        case updateUnreadMessageCount
        case updateUnreadChatCount
        case updateStory
        case updateStoryDeleted
        case updateStorySendSucceeded
        case updateStorySendFailed
        case updateChatActiveStories
        case updateStoryListChatCount
        case updateStoryStealthMode
        case updateOption
        case updateStickerSet
        case updateInstalledStickerSets
        case updateTrendingStickerSets
        case updateRecentStickers
        case updateFavoriteStickers
        case updateSavedAnimations
        case updateSavedNotificationSounds
        case updateDefaultBackground
        case updateChatThemes
        case updateAccentColors
        case updateProfileAccentColors
        case updateLanguagePackStrings
        case updateConnectionState
        case updateTermsOfService
        case updateUnconfirmedSession
        case updateAttachmentMenuBots
        case updateWebAppMessageSent
        case updateActiveEmojiReactions
        case updateAvailableMessageEffects
        case updateDefaultReactionType
        case updateSavedMessagesTags
        case updateActiveLiveLocationMessages
        case updateOwnedStarCount
        case updateChatRevenueAmount
        case updateStarRevenueStatus
        case updateSpeechRecognitionTrial
        case updateDiceEmojis
        case updateAnimatedEmojiMessageClicked
        case updateAnimationSearchParameters
        case updateSuggestedActions
        case updateSpeedLimitNotification
        case updateContactCloseBirthdays
        case updateAutosaveSettings
        case updateBusinessConnection
        case updateNewBusinessMessage
        case updateBusinessMessageEdited
        case updateBusinessMessagesDeleted
        case updateNewInlineQuery
        case updateNewChosenInlineResult
        case updateNewCallbackQuery
        case updateNewInlineCallbackQuery
        case updateNewBusinessCallbackQuery
        case updateNewShippingQuery
        case updateNewPreCheckoutQuery
        case updateNewCustomEvent
        case updateNewCustomQuery
        case updatePoll
        case updatePollAnswer
        case updateChatMember
        case updateNewChatJoinRequest
        case updateChatBoost
        case updateMessageReaction
        case updateMessageReactions
        case updatePaidMediaPurchased
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DtoCodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)
        switch type {
        case .updateAuthorizationState:
            let value = try UpdateAuthorizationState(from: decoder)
            self = .updateAuthorizationState(value)
        case .updateNewMessage:
            let value = try UpdateNewMessage(from: decoder)
            self = .updateNewMessage(value)
        case .updateMessageSendAcknowledged:
            let value = try UpdateMessageSendAcknowledged(from: decoder)
            self = .updateMessageSendAcknowledged(value)
        case .updateMessageSendSucceeded:
            let value = try UpdateMessageSendSucceeded(from: decoder)
            self = .updateMessageSendSucceeded(value)
        case .updateMessageSendFailed:
            let value = try UpdateMessageSendFailed(from: decoder)
            self = .updateMessageSendFailed(value)
        case .updateMessageContent:
            let value = try UpdateMessageContent(from: decoder)
            self = .updateMessageContent(value)
        case .updateMessageEdited:
            let value = try UpdateMessageEdited(from: decoder)
            self = .updateMessageEdited(value)
        case .updateMessageIsPinned:
            let value = try UpdateMessageIsPinned(from: decoder)
            self = .updateMessageIsPinned(value)
        case .updateMessageInteractionInfo:
            let value = try UpdateMessageInteractionInfo(from: decoder)
            self = .updateMessageInteractionInfo(value)
        case .updateMessageContentOpened:
            let value = try UpdateMessageContentOpened(from: decoder)
            self = .updateMessageContentOpened(value)
        case .updateMessageMentionRead:
            let value = try UpdateMessageMentionRead(from: decoder)
            self = .updateMessageMentionRead(value)
        case .updateMessageUnreadReactions:
            let value = try UpdateMessageUnreadReactions(from: decoder)
            self = .updateMessageUnreadReactions(value)
        case .updateMessageFactCheck:
            let value = try UpdateMessageFactCheck(from: decoder)
            self = .updateMessageFactCheck(value)
        case .updateMessageLiveLocationViewed:
            let value = try UpdateMessageLiveLocationViewed(from: decoder)
            self = .updateMessageLiveLocationViewed(value)
        case .updateVideoPublished:
            let value = try UpdateVideoPublished(from: decoder)
            self = .updateVideoPublished(value)
        case .updateNewChat:
            let value = try UpdateNewChat(from: decoder)
            self = .updateNewChat(value)
        case .updateChatTitle:
            let value = try UpdateChatTitle(from: decoder)
            self = .updateChatTitle(value)
        case .updateChatPhoto:
            let value = try UpdateChatPhoto(from: decoder)
            self = .updateChatPhoto(value)
        case .updateChatAccentColors:
            let value = try UpdateChatAccentColors(from: decoder)
            self = .updateChatAccentColors(value)
        case .updateChatPermissions:
            let value = try UpdateChatPermissions(from: decoder)
            self = .updateChatPermissions(value)
        case .updateChatLastMessage:
            let value = try UpdateChatLastMessage(from: decoder)
            self = .updateChatLastMessage(value)
        case .updateChatPosition:
            let value = try UpdateChatPosition(from: decoder)
            self = .updateChatPosition(value)
        case .updateChatAddedToList:
            let value = try UpdateChatAddedToList(from: decoder)
            self = .updateChatAddedToList(value)
        case .updateChatRemovedFromList:
            let value = try UpdateChatRemovedFromList(from: decoder)
            self = .updateChatRemovedFromList(value)
        case .updateChatReadInbox:
            let value = try UpdateChatReadInbox(from: decoder)
            self = .updateChatReadInbox(value)
        case .updateChatReadOutbox:
            let value = try UpdateChatReadOutbox(from: decoder)
            self = .updateChatReadOutbox(value)
        case .updateChatActionBar:
            let value = try UpdateChatActionBar(from: decoder)
            self = .updateChatActionBar(value)
        case .updateChatBusinessBotManageBar:
            let value = try UpdateChatBusinessBotManageBar(from: decoder)
            self = .updateChatBusinessBotManageBar(value)
        case .updateChatAvailableReactions:
            let value = try UpdateChatAvailableReactions(from: decoder)
            self = .updateChatAvailableReactions(value)
        case .updateChatDraftMessage:
            let value = try UpdateChatDraftMessage(from: decoder)
            self = .updateChatDraftMessage(value)
        case .updateChatEmojiStatus:
            let value = try UpdateChatEmojiStatus(from: decoder)
            self = .updateChatEmojiStatus(value)
        case .updateChatMessageSender:
            let value = try UpdateChatMessageSender(from: decoder)
            self = .updateChatMessageSender(value)
        case .updateChatMessageAutoDeleteTime:
            let value = try UpdateChatMessageAutoDeleteTime(from: decoder)
            self = .updateChatMessageAutoDeleteTime(value)
        case .updateChatNotificationSettings:
            let value = try UpdateChatNotificationSettings(from: decoder)
            self = .updateChatNotificationSettings(value)
        case .updateChatPendingJoinRequests:
            let value = try UpdateChatPendingJoinRequests(from: decoder)
            self = .updateChatPendingJoinRequests(value)
        case .updateChatReplyMarkup:
            let value = try UpdateChatReplyMarkup(from: decoder)
            self = .updateChatReplyMarkup(value)
        case .updateChatBackground:
            let value = try UpdateChatBackground(from: decoder)
            self = .updateChatBackground(value)
        case .updateChatTheme:
            let value = try UpdateChatTheme(from: decoder)
            self = .updateChatTheme(value)
        case .updateChatUnreadMentionCount:
            let value = try UpdateChatUnreadMentionCount(from: decoder)
            self = .updateChatUnreadMentionCount(value)
        case .updateChatUnreadReactionCount:
            let value = try UpdateChatUnreadReactionCount(from: decoder)
            self = .updateChatUnreadReactionCount(value)
        case .updateChatVideoChat:
            let value = try UpdateChatVideoChat(from: decoder)
            self = .updateChatVideoChat(value)
        case .updateChatDefaultDisableNotification:
            let value = try UpdateChatDefaultDisableNotification(from: decoder)
            self = .updateChatDefaultDisableNotification(value)
        case .updateChatHasProtectedContent:
            let value = try UpdateChatHasProtectedContent(from: decoder)
            self = .updateChatHasProtectedContent(value)
        case .updateChatIsTranslatable:
            let value = try UpdateChatIsTranslatable(from: decoder)
            self = .updateChatIsTranslatable(value)
        case .updateChatIsMarkedAsUnread:
            let value = try UpdateChatIsMarkedAsUnread(from: decoder)
            self = .updateChatIsMarkedAsUnread(value)
        case .updateChatViewAsTopics:
            let value = try UpdateChatViewAsTopics(from: decoder)
            self = .updateChatViewAsTopics(value)
        case .updateChatBlockList:
            let value = try UpdateChatBlockList(from: decoder)
            self = .updateChatBlockList(value)
        case .updateChatHasScheduledMessages:
            let value = try UpdateChatHasScheduledMessages(from: decoder)
            self = .updateChatHasScheduledMessages(value)
        case .updateChatFolders:
            let value = try UpdateChatFolders(from: decoder)
            self = .updateChatFolders(value)
        case .updateChatOnlineMemberCount:
            let value = try UpdateChatOnlineMemberCount(from: decoder)
            self = .updateChatOnlineMemberCount(value)
        case .updateSavedMessagesTopic:
            let value = try UpdateSavedMessagesTopic(from: decoder)
            self = .updateSavedMessagesTopic(value)
        case .updateSavedMessagesTopicCount:
            let value = try UpdateSavedMessagesTopicCount(from: decoder)
            self = .updateSavedMessagesTopicCount(value)
        case .updateQuickReplyShortcut:
            let value = try UpdateQuickReplyShortcut(from: decoder)
            self = .updateQuickReplyShortcut(value)
        case .updateQuickReplyShortcutDeleted:
            let value = try UpdateQuickReplyShortcutDeleted(from: decoder)
            self = .updateQuickReplyShortcutDeleted(value)
        case .updateQuickReplyShortcuts:
            let value = try UpdateQuickReplyShortcuts(from: decoder)
            self = .updateQuickReplyShortcuts(value)
        case .updateQuickReplyShortcutMessages:
            let value = try UpdateQuickReplyShortcutMessages(from: decoder)
            self = .updateQuickReplyShortcutMessages(value)
        case .updateForumTopicInfo:
            let value = try UpdateForumTopicInfo(from: decoder)
            self = .updateForumTopicInfo(value)
        case .updateScopeNotificationSettings:
            let value = try UpdateScopeNotificationSettings(from: decoder)
            self = .updateScopeNotificationSettings(value)
        case .updateReactionNotificationSettings:
            let value = try UpdateReactionNotificationSettings(from: decoder)
            self = .updateReactionNotificationSettings(value)
        case .updateNotification:
            let value = try UpdateNotification(from: decoder)
            self = .updateNotification(value)
        case .updateNotificationGroup:
            let value = try UpdateNotificationGroup(from: decoder)
            self = .updateNotificationGroup(value)
        case .updateActiveNotifications:
            let value = try UpdateActiveNotifications(from: decoder)
            self = .updateActiveNotifications(value)
        case .updateHavePendingNotifications:
            let value = try UpdateHavePendingNotifications(from: decoder)
            self = .updateHavePendingNotifications(value)
        case .updateDeleteMessages:
            let value = try UpdateDeleteMessages(from: decoder)
            self = .updateDeleteMessages(value)
        case .updateChatAction:
            let value = try UpdateChatAction(from: decoder)
            self = .updateChatAction(value)
        case .updateUserStatus:
            let value = try UpdateUserStatus(from: decoder)
            self = .updateUserStatus(value)
        case .updateUser:
            let value = try UpdateUser(from: decoder)
            self = .updateUser(value)
        case .updateBasicGroup:
            let value = try UpdateBasicGroup(from: decoder)
            self = .updateBasicGroup(value)
        case .updateSupergroup:
            let value = try UpdateSupergroup(from: decoder)
            self = .updateSupergroup(value)
        case .updateSecretChat:
            let value = try UpdateSecretChat(from: decoder)
            self = .updateSecretChat(value)
        case .updateUserFullInfo:
            let value = try UpdateUserFullInfo(from: decoder)
            self = .updateUserFullInfo(value)
        case .updateBasicGroupFullInfo:
            let value = try UpdateBasicGroupFullInfo(from: decoder)
            self = .updateBasicGroupFullInfo(value)
        case .updateSupergroupFullInfo:
            let value = try UpdateSupergroupFullInfo(from: decoder)
            self = .updateSupergroupFullInfo(value)
        case .updateServiceNotification:
            let value = try UpdateServiceNotification(from: decoder)
            self = .updateServiceNotification(value)
        case .updateFile:
            let value = try UpdateFile(from: decoder)
            self = .updateFile(value)
        case .updateFileGenerationStart:
            let value = try UpdateFileGenerationStart(from: decoder)
            self = .updateFileGenerationStart(value)
        case .updateFileGenerationStop:
            let value = try UpdateFileGenerationStop(from: decoder)
            self = .updateFileGenerationStop(value)
        case .updateFileDownloads:
            let value = try UpdateFileDownloads(from: decoder)
            self = .updateFileDownloads(value)
        case .updateFileAddedToDownloads:
            let value = try UpdateFileAddedToDownloads(from: decoder)
            self = .updateFileAddedToDownloads(value)
        case .updateFileDownload:
            let value = try UpdateFileDownload(from: decoder)
            self = .updateFileDownload(value)
        case .updateFileRemovedFromDownloads:
            let value = try UpdateFileRemovedFromDownloads(from: decoder)
            self = .updateFileRemovedFromDownloads(value)
        case .updateApplicationVerificationRequired:
            let value = try UpdateApplicationVerificationRequired(from: decoder)
            self = .updateApplicationVerificationRequired(value)
        case .updateCall:
            let value = try UpdateCall(from: decoder)
            self = .updateCall(value)
        case .updateGroupCall:
            let value = try UpdateGroupCall(from: decoder)
            self = .updateGroupCall(value)
        case .updateGroupCallParticipant:
            let value = try UpdateGroupCallParticipant(from: decoder)
            self = .updateGroupCallParticipant(value)
        case .updateNewCallSignalingData:
            let value = try UpdateNewCallSignalingData(from: decoder)
            self = .updateNewCallSignalingData(value)
        case .updateUserPrivacySettingRules:
            let value = try UpdateUserPrivacySettingRules(from: decoder)
            self = .updateUserPrivacySettingRules(value)
        case .updateUnreadMessageCount:
            let value = try UpdateUnreadMessageCount(from: decoder)
            self = .updateUnreadMessageCount(value)
        case .updateUnreadChatCount:
            let value = try UpdateUnreadChatCount(from: decoder)
            self = .updateUnreadChatCount(value)
        case .updateStory:
            let value = try UpdateStory(from: decoder)
            self = .updateStory(value)
        case .updateStoryDeleted:
            let value = try UpdateStoryDeleted(from: decoder)
            self = .updateStoryDeleted(value)
        case .updateStorySendSucceeded:
            let value = try UpdateStorySendSucceeded(from: decoder)
            self = .updateStorySendSucceeded(value)
        case .updateStorySendFailed:
            let value = try UpdateStorySendFailed(from: decoder)
            self = .updateStorySendFailed(value)
        case .updateChatActiveStories:
            let value = try UpdateChatActiveStories(from: decoder)
            self = .updateChatActiveStories(value)
        case .updateStoryListChatCount:
            let value = try UpdateStoryListChatCount(from: decoder)
            self = .updateStoryListChatCount(value)
        case .updateStoryStealthMode:
            let value = try UpdateStoryStealthMode(from: decoder)
            self = .updateStoryStealthMode(value)
        case .updateOption:
            let value = try UpdateOption(from: decoder)
            self = .updateOption(value)
        case .updateStickerSet:
            let value = try UpdateStickerSet(from: decoder)
            self = .updateStickerSet(value)
        case .updateInstalledStickerSets:
            let value = try UpdateInstalledStickerSets(from: decoder)
            self = .updateInstalledStickerSets(value)
        case .updateTrendingStickerSets:
            let value = try UpdateTrendingStickerSets(from: decoder)
            self = .updateTrendingStickerSets(value)
        case .updateRecentStickers:
            let value = try UpdateRecentStickers(from: decoder)
            self = .updateRecentStickers(value)
        case .updateFavoriteStickers:
            let value = try UpdateFavoriteStickers(from: decoder)
            self = .updateFavoriteStickers(value)
        case .updateSavedAnimations:
            let value = try UpdateSavedAnimations(from: decoder)
            self = .updateSavedAnimations(value)
        case .updateSavedNotificationSounds:
            let value = try UpdateSavedNotificationSounds(from: decoder)
            self = .updateSavedNotificationSounds(value)
        case .updateDefaultBackground:
            let value = try UpdateDefaultBackground(from: decoder)
            self = .updateDefaultBackground(value)
        case .updateChatThemes:
            let value = try UpdateChatThemes(from: decoder)
            self = .updateChatThemes(value)
        case .updateAccentColors:
            let value = try UpdateAccentColors(from: decoder)
            self = .updateAccentColors(value)
        case .updateProfileAccentColors:
            let value = try UpdateProfileAccentColors(from: decoder)
            self = .updateProfileAccentColors(value)
        case .updateLanguagePackStrings:
            let value = try UpdateLanguagePackStrings(from: decoder)
            self = .updateLanguagePackStrings(value)
        case .updateConnectionState:
            let value = try UpdateConnectionState(from: decoder)
            self = .updateConnectionState(value)
        case .updateTermsOfService:
            let value = try UpdateTermsOfService(from: decoder)
            self = .updateTermsOfService(value)
        case .updateUnconfirmedSession:
            let value = try UpdateUnconfirmedSession(from: decoder)
            self = .updateUnconfirmedSession(value)
        case .updateAttachmentMenuBots:
            let value = try UpdateAttachmentMenuBots(from: decoder)
            self = .updateAttachmentMenuBots(value)
        case .updateWebAppMessageSent:
            let value = try UpdateWebAppMessageSent(from: decoder)
            self = .updateWebAppMessageSent(value)
        case .updateActiveEmojiReactions:
            let value = try UpdateActiveEmojiReactions(from: decoder)
            self = .updateActiveEmojiReactions(value)
        case .updateAvailableMessageEffects:
            let value = try UpdateAvailableMessageEffects(from: decoder)
            self = .updateAvailableMessageEffects(value)
        case .updateDefaultReactionType:
            let value = try UpdateDefaultReactionType(from: decoder)
            self = .updateDefaultReactionType(value)
        case .updateSavedMessagesTags:
            let value = try UpdateSavedMessagesTags(from: decoder)
            self = .updateSavedMessagesTags(value)
        case .updateActiveLiveLocationMessages:
            let value = try UpdateActiveLiveLocationMessages(from: decoder)
            self = .updateActiveLiveLocationMessages(value)
        case .updateOwnedStarCount:
            let value = try UpdateOwnedStarCount(from: decoder)
            self = .updateOwnedStarCount(value)
        case .updateChatRevenueAmount:
            let value = try UpdateChatRevenueAmount(from: decoder)
            self = .updateChatRevenueAmount(value)
        case .updateStarRevenueStatus:
            let value = try UpdateStarRevenueStatus(from: decoder)
            self = .updateStarRevenueStatus(value)
        case .updateSpeechRecognitionTrial:
            let value = try UpdateSpeechRecognitionTrial(from: decoder)
            self = .updateSpeechRecognitionTrial(value)
        case .updateDiceEmojis:
            let value = try UpdateDiceEmojis(from: decoder)
            self = .updateDiceEmojis(value)
        case .updateAnimatedEmojiMessageClicked:
            let value = try UpdateAnimatedEmojiMessageClicked(from: decoder)
            self = .updateAnimatedEmojiMessageClicked(value)
        case .updateAnimationSearchParameters:
            let value = try UpdateAnimationSearchParameters(from: decoder)
            self = .updateAnimationSearchParameters(value)
        case .updateSuggestedActions:
            let value = try UpdateSuggestedActions(from: decoder)
            self = .updateSuggestedActions(value)
        case .updateSpeedLimitNotification:
            let value = try UpdateSpeedLimitNotification(from: decoder)
            self = .updateSpeedLimitNotification(value)
        case .updateContactCloseBirthdays:
            let value = try UpdateContactCloseBirthdays(from: decoder)
            self = .updateContactCloseBirthdays(value)
        case .updateAutosaveSettings:
            let value = try UpdateAutosaveSettings(from: decoder)
            self = .updateAutosaveSettings(value)
        case .updateBusinessConnection:
            let value = try UpdateBusinessConnection(from: decoder)
            self = .updateBusinessConnection(value)
        case .updateNewBusinessMessage:
            let value = try UpdateNewBusinessMessage(from: decoder)
            self = .updateNewBusinessMessage(value)
        case .updateBusinessMessageEdited:
            let value = try UpdateBusinessMessageEdited(from: decoder)
            self = .updateBusinessMessageEdited(value)
        case .updateBusinessMessagesDeleted:
            let value = try UpdateBusinessMessagesDeleted(from: decoder)
            self = .updateBusinessMessagesDeleted(value)
        case .updateNewInlineQuery:
            let value = try UpdateNewInlineQuery(from: decoder)
            self = .updateNewInlineQuery(value)
        case .updateNewChosenInlineResult:
            let value = try UpdateNewChosenInlineResult(from: decoder)
            self = .updateNewChosenInlineResult(value)
        case .updateNewCallbackQuery:
            let value = try UpdateNewCallbackQuery(from: decoder)
            self = .updateNewCallbackQuery(value)
        case .updateNewInlineCallbackQuery:
            let value = try UpdateNewInlineCallbackQuery(from: decoder)
            self = .updateNewInlineCallbackQuery(value)
        case .updateNewBusinessCallbackQuery:
            let value = try UpdateNewBusinessCallbackQuery(from: decoder)
            self = .updateNewBusinessCallbackQuery(value)
        case .updateNewShippingQuery:
            let value = try UpdateNewShippingQuery(from: decoder)
            self = .updateNewShippingQuery(value)
        case .updateNewPreCheckoutQuery:
            let value = try UpdateNewPreCheckoutQuery(from: decoder)
            self = .updateNewPreCheckoutQuery(value)
        case .updateNewCustomEvent:
            let value = try UpdateNewCustomEvent(from: decoder)
            self = .updateNewCustomEvent(value)
        case .updateNewCustomQuery:
            let value = try UpdateNewCustomQuery(from: decoder)
            self = .updateNewCustomQuery(value)
        case .updatePoll:
            let value = try UpdatePoll(from: decoder)
            self = .updatePoll(value)
        case .updatePollAnswer:
            let value = try UpdatePollAnswer(from: decoder)
            self = .updatePollAnswer(value)
        case .updateChatMember:
            let value = try UpdateChatMember(from: decoder)
            self = .updateChatMember(value)
        case .updateNewChatJoinRequest:
            let value = try UpdateNewChatJoinRequest(from: decoder)
            self = .updateNewChatJoinRequest(value)
        case .updateChatBoost:
            let value = try UpdateChatBoost(from: decoder)
            self = .updateChatBoost(value)
        case .updateMessageReaction:
            let value = try UpdateMessageReaction(from: decoder)
            self = .updateMessageReaction(value)
        case .updateMessageReactions:
            let value = try UpdateMessageReactions(from: decoder)
            self = .updateMessageReactions(value)
        case .updatePaidMediaPurchased:
            let value = try UpdatePaidMediaPurchased(from: decoder)
            self = .updatePaidMediaPurchased(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DtoCodingKeys.self)
        switch self {
        case .updateAuthorizationState(let value):
            try container.encode(Kind.updateAuthorizationState, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewMessage(let value):
            try container.encode(Kind.updateNewMessage, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageSendAcknowledged(let value):
            try container.encode(Kind.updateMessageSendAcknowledged, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageSendSucceeded(let value):
            try container.encode(Kind.updateMessageSendSucceeded, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageSendFailed(let value):
            try container.encode(Kind.updateMessageSendFailed, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageContent(let value):
            try container.encode(Kind.updateMessageContent, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageEdited(let value):
            try container.encode(Kind.updateMessageEdited, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageIsPinned(let value):
            try container.encode(Kind.updateMessageIsPinned, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageInteractionInfo(let value):
            try container.encode(Kind.updateMessageInteractionInfo, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageContentOpened(let value):
            try container.encode(Kind.updateMessageContentOpened, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageMentionRead(let value):
            try container.encode(Kind.updateMessageMentionRead, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageUnreadReactions(let value):
            try container.encode(Kind.updateMessageUnreadReactions, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageFactCheck(let value):
            try container.encode(Kind.updateMessageFactCheck, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageLiveLocationViewed(let value):
            try container.encode(Kind.updateMessageLiveLocationViewed, forKey: .type)
            try value.encode(to: encoder)
        case .updateVideoPublished(let value):
            try container.encode(Kind.updateVideoPublished, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewChat(let value):
            try container.encode(Kind.updateNewChat, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatTitle(let value):
            try container.encode(Kind.updateChatTitle, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatPhoto(let value):
            try container.encode(Kind.updateChatPhoto, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatAccentColors(let value):
            try container.encode(Kind.updateChatAccentColors, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatPermissions(let value):
            try container.encode(Kind.updateChatPermissions, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatLastMessage(let value):
            try container.encode(Kind.updateChatLastMessage, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatPosition(let value):
            try container.encode(Kind.updateChatPosition, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatAddedToList(let value):
            try container.encode(Kind.updateChatAddedToList, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatRemovedFromList(let value):
            try container.encode(Kind.updateChatRemovedFromList, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatReadInbox(let value):
            try container.encode(Kind.updateChatReadInbox, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatReadOutbox(let value):
            try container.encode(Kind.updateChatReadOutbox, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatActionBar(let value):
            try container.encode(Kind.updateChatActionBar, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatBusinessBotManageBar(let value):
            try container.encode(Kind.updateChatBusinessBotManageBar, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatAvailableReactions(let value):
            try container.encode(Kind.updateChatAvailableReactions, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatDraftMessage(let value):
            try container.encode(Kind.updateChatDraftMessage, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatEmojiStatus(let value):
            try container.encode(Kind.updateChatEmojiStatus, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatMessageSender(let value):
            try container.encode(Kind.updateChatMessageSender, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatMessageAutoDeleteTime(let value):
            try container.encode(Kind.updateChatMessageAutoDeleteTime, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatNotificationSettings(let value):
            try container.encode(Kind.updateChatNotificationSettings, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatPendingJoinRequests(let value):
            try container.encode(Kind.updateChatPendingJoinRequests, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatReplyMarkup(let value):
            try container.encode(Kind.updateChatReplyMarkup, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatBackground(let value):
            try container.encode(Kind.updateChatBackground, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatTheme(let value):
            try container.encode(Kind.updateChatTheme, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatUnreadMentionCount(let value):
            try container.encode(Kind.updateChatUnreadMentionCount, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatUnreadReactionCount(let value):
            try container.encode(Kind.updateChatUnreadReactionCount, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatVideoChat(let value):
            try container.encode(Kind.updateChatVideoChat, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatDefaultDisableNotification(let value):
            try container.encode(Kind.updateChatDefaultDisableNotification, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatHasProtectedContent(let value):
            try container.encode(Kind.updateChatHasProtectedContent, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatIsTranslatable(let value):
            try container.encode(Kind.updateChatIsTranslatable, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatIsMarkedAsUnread(let value):
            try container.encode(Kind.updateChatIsMarkedAsUnread, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatViewAsTopics(let value):
            try container.encode(Kind.updateChatViewAsTopics, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatBlockList(let value):
            try container.encode(Kind.updateChatBlockList, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatHasScheduledMessages(let value):
            try container.encode(Kind.updateChatHasScheduledMessages, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatFolders(let value):
            try container.encode(Kind.updateChatFolders, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatOnlineMemberCount(let value):
            try container.encode(Kind.updateChatOnlineMemberCount, forKey: .type)
            try value.encode(to: encoder)
        case .updateSavedMessagesTopic(let value):
            try container.encode(Kind.updateSavedMessagesTopic, forKey: .type)
            try value.encode(to: encoder)
        case .updateSavedMessagesTopicCount(let value):
            try container.encode(Kind.updateSavedMessagesTopicCount, forKey: .type)
            try value.encode(to: encoder)
        case .updateQuickReplyShortcut(let value):
            try container.encode(Kind.updateQuickReplyShortcut, forKey: .type)
            try value.encode(to: encoder)
        case .updateQuickReplyShortcutDeleted(let value):
            try container.encode(Kind.updateQuickReplyShortcutDeleted, forKey: .type)
            try value.encode(to: encoder)
        case .updateQuickReplyShortcuts(let value):
            try container.encode(Kind.updateQuickReplyShortcuts, forKey: .type)
            try value.encode(to: encoder)
        case .updateQuickReplyShortcutMessages(let value):
            try container.encode(Kind.updateQuickReplyShortcutMessages, forKey: .type)
            try value.encode(to: encoder)
        case .updateForumTopicInfo(let value):
            try container.encode(Kind.updateForumTopicInfo, forKey: .type)
            try value.encode(to: encoder)
        case .updateScopeNotificationSettings(let value):
            try container.encode(Kind.updateScopeNotificationSettings, forKey: .type)
            try value.encode(to: encoder)
        case .updateReactionNotificationSettings(let value):
            try container.encode(Kind.updateReactionNotificationSettings, forKey: .type)
            try value.encode(to: encoder)
        case .updateNotification(let value):
            try container.encode(Kind.updateNotification, forKey: .type)
            try value.encode(to: encoder)
        case .updateNotificationGroup(let value):
            try container.encode(Kind.updateNotificationGroup, forKey: .type)
            try value.encode(to: encoder)
        case .updateActiveNotifications(let value):
            try container.encode(Kind.updateActiveNotifications, forKey: .type)
            try value.encode(to: encoder)
        case .updateHavePendingNotifications(let value):
            try container.encode(Kind.updateHavePendingNotifications, forKey: .type)
            try value.encode(to: encoder)
        case .updateDeleteMessages(let value):
            try container.encode(Kind.updateDeleteMessages, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatAction(let value):
            try container.encode(Kind.updateChatAction, forKey: .type)
            try value.encode(to: encoder)
        case .updateUserStatus(let value):
            try container.encode(Kind.updateUserStatus, forKey: .type)
            try value.encode(to: encoder)
        case .updateUser(let value):
            try container.encode(Kind.updateUser, forKey: .type)
            try value.encode(to: encoder)
        case .updateBasicGroup(let value):
            try container.encode(Kind.updateBasicGroup, forKey: .type)
            try value.encode(to: encoder)
        case .updateSupergroup(let value):
            try container.encode(Kind.updateSupergroup, forKey: .type)
            try value.encode(to: encoder)
        case .updateSecretChat(let value):
            try container.encode(Kind.updateSecretChat, forKey: .type)
            try value.encode(to: encoder)
        case .updateUserFullInfo(let value):
            try container.encode(Kind.updateUserFullInfo, forKey: .type)
            try value.encode(to: encoder)
        case .updateBasicGroupFullInfo(let value):
            try container.encode(Kind.updateBasicGroupFullInfo, forKey: .type)
            try value.encode(to: encoder)
        case .updateSupergroupFullInfo(let value):
            try container.encode(Kind.updateSupergroupFullInfo, forKey: .type)
            try value.encode(to: encoder)
        case .updateServiceNotification(let value):
            try container.encode(Kind.updateServiceNotification, forKey: .type)
            try value.encode(to: encoder)
        case .updateFile(let value):
            try container.encode(Kind.updateFile, forKey: .type)
            try value.encode(to: encoder)
        case .updateFileGenerationStart(let value):
            try container.encode(Kind.updateFileGenerationStart, forKey: .type)
            try value.encode(to: encoder)
        case .updateFileGenerationStop(let value):
            try container.encode(Kind.updateFileGenerationStop, forKey: .type)
            try value.encode(to: encoder)
        case .updateFileDownloads(let value):
            try container.encode(Kind.updateFileDownloads, forKey: .type)
            try value.encode(to: encoder)
        case .updateFileAddedToDownloads(let value):
            try container.encode(Kind.updateFileAddedToDownloads, forKey: .type)
            try value.encode(to: encoder)
        case .updateFileDownload(let value):
            try container.encode(Kind.updateFileDownload, forKey: .type)
            try value.encode(to: encoder)
        case .updateFileRemovedFromDownloads(let value):
            try container.encode(Kind.updateFileRemovedFromDownloads, forKey: .type)
            try value.encode(to: encoder)
        case .updateApplicationVerificationRequired(let value):
            try container.encode(Kind.updateApplicationVerificationRequired, forKey: .type)
            try value.encode(to: encoder)
        case .updateCall(let value):
            try container.encode(Kind.updateCall, forKey: .type)
            try value.encode(to: encoder)
        case .updateGroupCall(let value):
            try container.encode(Kind.updateGroupCall, forKey: .type)
            try value.encode(to: encoder)
        case .updateGroupCallParticipant(let value):
            try container.encode(Kind.updateGroupCallParticipant, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewCallSignalingData(let value):
            try container.encode(Kind.updateNewCallSignalingData, forKey: .type)
            try value.encode(to: encoder)
        case .updateUserPrivacySettingRules(let value):
            try container.encode(Kind.updateUserPrivacySettingRules, forKey: .type)
            try value.encode(to: encoder)
        case .updateUnreadMessageCount(let value):
            try container.encode(Kind.updateUnreadMessageCount, forKey: .type)
            try value.encode(to: encoder)
        case .updateUnreadChatCount(let value):
            try container.encode(Kind.updateUnreadChatCount, forKey: .type)
            try value.encode(to: encoder)
        case .updateStory(let value):
            try container.encode(Kind.updateStory, forKey: .type)
            try value.encode(to: encoder)
        case .updateStoryDeleted(let value):
            try container.encode(Kind.updateStoryDeleted, forKey: .type)
            try value.encode(to: encoder)
        case .updateStorySendSucceeded(let value):
            try container.encode(Kind.updateStorySendSucceeded, forKey: .type)
            try value.encode(to: encoder)
        case .updateStorySendFailed(let value):
            try container.encode(Kind.updateStorySendFailed, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatActiveStories(let value):
            try container.encode(Kind.updateChatActiveStories, forKey: .type)
            try value.encode(to: encoder)
        case .updateStoryListChatCount(let value):
            try container.encode(Kind.updateStoryListChatCount, forKey: .type)
            try value.encode(to: encoder)
        case .updateStoryStealthMode(let value):
            try container.encode(Kind.updateStoryStealthMode, forKey: .type)
            try value.encode(to: encoder)
        case .updateOption(let value):
            try container.encode(Kind.updateOption, forKey: .type)
            try value.encode(to: encoder)
        case .updateStickerSet(let value):
            try container.encode(Kind.updateStickerSet, forKey: .type)
            try value.encode(to: encoder)
        case .updateInstalledStickerSets(let value):
            try container.encode(Kind.updateInstalledStickerSets, forKey: .type)
            try value.encode(to: encoder)
        case .updateTrendingStickerSets(let value):
            try container.encode(Kind.updateTrendingStickerSets, forKey: .type)
            try value.encode(to: encoder)
        case .updateRecentStickers(let value):
            try container.encode(Kind.updateRecentStickers, forKey: .type)
            try value.encode(to: encoder)
        case .updateFavoriteStickers(let value):
            try container.encode(Kind.updateFavoriteStickers, forKey: .type)
            try value.encode(to: encoder)
        case .updateSavedAnimations(let value):
            try container.encode(Kind.updateSavedAnimations, forKey: .type)
            try value.encode(to: encoder)
        case .updateSavedNotificationSounds(let value):
            try container.encode(Kind.updateSavedNotificationSounds, forKey: .type)
            try value.encode(to: encoder)
        case .updateDefaultBackground(let value):
            try container.encode(Kind.updateDefaultBackground, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatThemes(let value):
            try container.encode(Kind.updateChatThemes, forKey: .type)
            try value.encode(to: encoder)
        case .updateAccentColors(let value):
            try container.encode(Kind.updateAccentColors, forKey: .type)
            try value.encode(to: encoder)
        case .updateProfileAccentColors(let value):
            try container.encode(Kind.updateProfileAccentColors, forKey: .type)
            try value.encode(to: encoder)
        case .updateLanguagePackStrings(let value):
            try container.encode(Kind.updateLanguagePackStrings, forKey: .type)
            try value.encode(to: encoder)
        case .updateConnectionState(let value):
            try container.encode(Kind.updateConnectionState, forKey: .type)
            try value.encode(to: encoder)
        case .updateTermsOfService(let value):
            try container.encode(Kind.updateTermsOfService, forKey: .type)
            try value.encode(to: encoder)
        case .updateUnconfirmedSession(let value):
            try container.encode(Kind.updateUnconfirmedSession, forKey: .type)
            try value.encode(to: encoder)
        case .updateAttachmentMenuBots(let value):
            try container.encode(Kind.updateAttachmentMenuBots, forKey: .type)
            try value.encode(to: encoder)
        case .updateWebAppMessageSent(let value):
            try container.encode(Kind.updateWebAppMessageSent, forKey: .type)
            try value.encode(to: encoder)
        case .updateActiveEmojiReactions(let value):
            try container.encode(Kind.updateActiveEmojiReactions, forKey: .type)
            try value.encode(to: encoder)
        case .updateAvailableMessageEffects(let value):
            try container.encode(Kind.updateAvailableMessageEffects, forKey: .type)
            try value.encode(to: encoder)
        case .updateDefaultReactionType(let value):
            try container.encode(Kind.updateDefaultReactionType, forKey: .type)
            try value.encode(to: encoder)
        case .updateSavedMessagesTags(let value):
            try container.encode(Kind.updateSavedMessagesTags, forKey: .type)
            try value.encode(to: encoder)
        case .updateActiveLiveLocationMessages(let value):
            try container.encode(Kind.updateActiveLiveLocationMessages, forKey: .type)
            try value.encode(to: encoder)
        case .updateOwnedStarCount(let value):
            try container.encode(Kind.updateOwnedStarCount, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatRevenueAmount(let value):
            try container.encode(Kind.updateChatRevenueAmount, forKey: .type)
            try value.encode(to: encoder)
        case .updateStarRevenueStatus(let value):
            try container.encode(Kind.updateStarRevenueStatus, forKey: .type)
            try value.encode(to: encoder)
        case .updateSpeechRecognitionTrial(let value):
            try container.encode(Kind.updateSpeechRecognitionTrial, forKey: .type)
            try value.encode(to: encoder)
        case .updateDiceEmojis(let value):
            try container.encode(Kind.updateDiceEmojis, forKey: .type)
            try value.encode(to: encoder)
        case .updateAnimatedEmojiMessageClicked(let value):
            try container.encode(Kind.updateAnimatedEmojiMessageClicked, forKey: .type)
            try value.encode(to: encoder)
        case .updateAnimationSearchParameters(let value):
            try container.encode(Kind.updateAnimationSearchParameters, forKey: .type)
            try value.encode(to: encoder)
        case .updateSuggestedActions(let value):
            try container.encode(Kind.updateSuggestedActions, forKey: .type)
            try value.encode(to: encoder)
        case .updateSpeedLimitNotification(let value):
            try container.encode(Kind.updateSpeedLimitNotification, forKey: .type)
            try value.encode(to: encoder)
        case .updateContactCloseBirthdays(let value):
            try container.encode(Kind.updateContactCloseBirthdays, forKey: .type)
            try value.encode(to: encoder)
        case .updateAutosaveSettings(let value):
            try container.encode(Kind.updateAutosaveSettings, forKey: .type)
            try value.encode(to: encoder)
        case .updateBusinessConnection(let value):
            try container.encode(Kind.updateBusinessConnection, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewBusinessMessage(let value):
            try container.encode(Kind.updateNewBusinessMessage, forKey: .type)
            try value.encode(to: encoder)
        case .updateBusinessMessageEdited(let value):
            try container.encode(Kind.updateBusinessMessageEdited, forKey: .type)
            try value.encode(to: encoder)
        case .updateBusinessMessagesDeleted(let value):
            try container.encode(Kind.updateBusinessMessagesDeleted, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewInlineQuery(let value):
            try container.encode(Kind.updateNewInlineQuery, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewChosenInlineResult(let value):
            try container.encode(Kind.updateNewChosenInlineResult, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewCallbackQuery(let value):
            try container.encode(Kind.updateNewCallbackQuery, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewInlineCallbackQuery(let value):
            try container.encode(Kind.updateNewInlineCallbackQuery, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewBusinessCallbackQuery(let value):
            try container.encode(Kind.updateNewBusinessCallbackQuery, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewShippingQuery(let value):
            try container.encode(Kind.updateNewShippingQuery, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewPreCheckoutQuery(let value):
            try container.encode(Kind.updateNewPreCheckoutQuery, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewCustomEvent(let value):
            try container.encode(Kind.updateNewCustomEvent, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewCustomQuery(let value):
            try container.encode(Kind.updateNewCustomQuery, forKey: .type)
            try value.encode(to: encoder)
        case .updatePoll(let value):
            try container.encode(Kind.updatePoll, forKey: .type)
            try value.encode(to: encoder)
        case .updatePollAnswer(let value):
            try container.encode(Kind.updatePollAnswer, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatMember(let value):
            try container.encode(Kind.updateChatMember, forKey: .type)
            try value.encode(to: encoder)
        case .updateNewChatJoinRequest(let value):
            try container.encode(Kind.updateNewChatJoinRequest, forKey: .type)
            try value.encode(to: encoder)
        case .updateChatBoost(let value):
            try container.encode(Kind.updateChatBoost, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageReaction(let value):
            try container.encode(Kind.updateMessageReaction, forKey: .type)
            try value.encode(to: encoder)
        case .updateMessageReactions(let value):
            try container.encode(Kind.updateMessageReactions, forKey: .type)
            try value.encode(to: encoder)
        case .updatePaidMediaPurchased(let value):
            try container.encode(Kind.updatePaidMediaPurchased, forKey: .type)
            try value.encode(to: encoder)
        }
    }
}
"""

if __name__ == "__main__":
    main(update)

// TDClient+Generated.swift

import Foundation
import TDLibKit

extension TDClient {
    func addChatToList(chatId: Int64, chatList: TDNativeChatList) async throws -> TDNativeOk {
        try await send(TDNativeRequests.addChatToList(chatId: chatId, chatList: chatList))
    }

    func addChecklistTasks(
        chatId: Int64,
        messageId: Int64,
        tasks: [TDNativeInputChecklistTask],
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.addChecklistTasks(chatId: chatId, messageId: messageId, tasks: tasks))
    }

    func addContact(
        contact: TDNativeImportedContact,
        sharePhoneNumber: Bool,
        userId: Int64,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.addContact(
            userId: userId,
            contact: contact,
            sharePhoneNumber: sharePhoneNumber,
        ))
    }

    func addMessageReaction(
        chatId: Int64,
        isBig: Bool,
        messageId: Int64,
        reactionType: TDNativeReactionType,
        updateRecentReactions: Bool,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.addMessageReaction(
            chatId: chatId,
            messageId: messageId,
            reactionType: reactionType,
            isBig: isBig,
            updateRecentReactions: updateRecentReactions,
        ))
    }

    func canSendMessageToUser(onlyLocal: Bool, userId: Int64) async throws -> TDNativeCanSendMessageToUserResult {
        try await send(TDNativeRequests.canSendMessageToUser(userId: userId, onlyLocal: onlyLocal))
    }

    func canSendMessageToUser(userId: Int64, onlyLocal: Bool) async throws -> TDNativeCanSendMessageToUserResult {
        try await send(TDNativeRequests.canSendMessageToUser(userId: userId, onlyLocal: onlyLocal))
    }

    func canTransferOwnership() async throws -> TDNativeCanTransferOwnershipResult {
        try await send(TDNativeRequests.canTransferOwnership())
    }

    func cancelDownloadFile(fileId: Int, onlyIfPending: Bool) async throws -> TDNativeOk {
        try await send(TDNativeRequests.cancelDownloadFile(fileId: fileId, onlyIfPending: onlyIfPending))
    }

    func checkAuthenticationCode(code: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.checkAuthenticationCode(code: code))
    }

    func checkAuthenticationEmailCode(code: TDNativeEmailAddressAuthentication) async throws -> TDNativeOk {
        try await send(TDNativeRequests.checkAuthenticationEmailCode(code: code))
    }

    func checkAuthenticationPassword(password: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.checkAuthenticationPassword(password: password))
    }

    func checkAuthenticationPasswordRecoveryCode(recoveryCode: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.checkAuthenticationPasswordRecoveryCode(recoveryCode: recoveryCode))
    }

    func closeChat(chatId: Int64) async throws -> TDNativeOk {
        try await send(TDNativeRequests.closeChat(chatId: chatId))
    }

    func closeStory(storyId: Int, storyPosterChatId: Int64) async throws -> TDNativeOk {
        try await send(TDNativeRequests.closeStory(storyPosterChatId: storyPosterChatId, storyId: storyId))
    }

    func createBasicGroupChat(basicGroupId: Int64, force: Bool) async throws -> TDNativeChat {
        try await send(TDNativeRequests.createBasicGroupChat(basicGroupId: basicGroupId, force: force))
    }

    func createChatFolder(folder: TDNativeChatFolder) async throws -> TDNativeChatFolderInfo {
        try await send(TDNativeRequests.createChatFolder(folder: folder))
    }

    func createPrivateChat(force: Bool, userId: Int64) async throws -> TDNativeChat {
        try await send(TDNativeRequests.createPrivateChat(userId: userId, force: force))
    }

    func createSupergroupChat(force: Bool, supergroupId: Int64) async throws -> TDNativeChat {
        try await send(TDNativeRequests.createSupergroupChat(supergroupId: supergroupId, force: force))
    }

    func deleteChatFolder(chatFolderId: Int, leaveChatIds: [Int64]) async throws -> TDNativeOk {
        try await send(TDNativeRequests.deleteChatFolder(chatFolderId: chatFolderId, leaveChatIds: leaveChatIds))
    }

    func deleteChatHistory(chatId: Int64, removeFromChatList: Bool, revoke: Bool) async throws -> TDNativeOk {
        try await send(TDNativeRequests.deleteChatHistory(
            chatId: chatId,
            removeFromChatList: removeFromChatList,
            revoke: revoke,
        ))
    }

    func deleteChatReplyMarkup(chatId: Int64, messageId: Int64) async throws -> TDNativeOk {
        try await send(TDNativeRequests.deleteChatReplyMarkup(chatId: chatId, messageId: messageId))
    }

    func deleteMessages(chatId: Int64, messageIds: [Int64], revoke: Bool) async throws -> TDNativeOk {
        try await send(TDNativeRequests.deleteMessages(chatId: chatId, messageIds: messageIds, revoke: revoke))
    }

    func destroy() async throws -> TDNativeOk {
        try await send(TDNativeRequests.destroy())
    }

    func downloadFile(
        fileId: Int,
        limit: Int64,
        offset: Int64,
        priority: Int,
        synchronous: Bool,
    ) async throws -> TDNativeFile {
        try await send(TDNativeRequests.downloadFile(
            fileId: fileId,
            priority: priority,
            offset: offset,
            limit: limit,
            synchronous: synchronous,
        ))
    }

    func downloadFile(
        fileId: Int,
        priority: Int,
        offset: Int64,
        limit: Int64,
        synchronous: Bool,
    ) async throws -> TDNativeFile {
        try await send(TDNativeRequests.downloadFile(
            fileId: fileId,
            priority: priority,
            offset: offset,
            limit: limit,
            synchronous: synchronous,
        ))
    }

    func editChatFolder(chatFolderId: Int, folder: TDNativeChatFolder) async throws -> TDNativeChatFolderInfo {
        try await send(TDNativeRequests.editChatFolder(chatFolderId: chatFolderId, folder: folder))
    }

    func editMessageCaption(
        caption: TDNativeFormattedText?,
        chatId: Int64,
        messageId: Int64,
        replyMarkup: TDNativeReplyMarkup?,
        showCaptionAboveMedia: Bool,
    ) async throws -> TDNativeMessage {
        try await send(TDNativeRequests.editMessageCaption(
            chatId: chatId,
            messageId: messageId,
            replyMarkup: replyMarkup,
            caption: caption,
            showCaptionAboveMedia: showCaptionAboveMedia,
        ))
    }

    func editMessageLiveLocation(
        chatId: Int64,
        messageId: Int64,
        replyMarkup: TDNativeReplyMarkup?,
        location: TDNativeLiveLocation?,
    ) async throws -> TDNativeMessage {
        try await send(TDNativeRequests.editMessageLiveLocation(
            chatId: chatId,
            messageId: messageId,
            replyMarkup: replyMarkup,
            location: location,
        ))
    }

    func editMessageText(
        chatId: Int64,
        inputMessageContent: TDNativeInputMessageContent,
        messageId: Int64,
        replyMarkup: TDNativeReplyMarkup?,
    ) async throws -> TDNativeMessage {
        try await send(TDNativeRequests.editMessageText(
            chatId: chatId,
            messageId: messageId,
            replyMarkup: replyMarkup,
            inputMessageContent: inputMessageContent,
        ))
    }

    func finishFileGeneration(generationId: Int64, error: TDNativeError?) async throws -> TDNativeOk {
        try await send(TDNativeRequests.finishFileGeneration(generationId: generationId, error: error))
    }

    func forwardMessages(
        chatId: Int64,
        fromChatId: Int64,
        messageIds: [Int64],
        options: TDNativeMessageSendOptions?,
        removeCaption: Bool,
        sendCopy: Bool,
        topicId: TDNativeMessageTopic?,
    ) async throws -> TDNativeMessages {
        try await send(TDNativeRequests.forwardMessages(
            chatId: chatId,
            topicId: topicId,
            fromChatId: fromChatId,
            messageIds: messageIds,
            options: options,
            sendCopy: sendCopy,
            removeCaption: removeCaption,
        ))
    }

    func getAutoDownloadSettingsPresets() async throws -> TDNativeAutoDownloadSettingsPresets {
        try await send(TDNativeRequests.getAutoDownloadSettingsPresets())
    }

    func getBasicGroup(basicGroupId: Int64) async throws -> TDNativeBasicGroup {
        try await send(TDNativeRequests.getBasicGroup(basicGroupId: basicGroupId))
    }

    func getBasicGroupFullInfo(basicGroupId: Int64) async throws -> TDNativeBasicGroupFullInfo {
        try await send(TDNativeRequests.getBasicGroupFullInfo(basicGroupId: basicGroupId))
    }

    func getCallbackQueryAnswer(
        chatId: Int64,
        messageId: Int64,
        payload: TDNativeCallbackQueryPayload,
    ) async throws -> TDNativeCallbackQueryAnswer {
        try await send(TDNativeRequests.getCallbackQueryAnswer(chatId: chatId, messageId: messageId, payload: payload))
    }

    func getChat(chatId: Int64) async throws -> TDNativeChat {
        try await send(TDNativeRequests.getChat(chatId: chatId))
    }

    func getChatActiveStories(chatId: Int64) async throws -> TDNativeChatActiveStories {
        try await send(TDNativeRequests.getChatActiveStories(chatId: chatId))
    }

    func getChatAdministrators(chatId: Int64) async throws -> TDNativeChatAdministrators {
        try await send(TDNativeRequests.getChatAdministrators(chatId: chatId))
    }

    func getChatFolder(chatFolderId: Int) async throws -> TDNativeChatFolder {
        try await send(TDNativeRequests.getChatFolder(chatFolderId: chatFolderId))
    }

    func getChatFolderChatCount(folder: TDNativeChatFolder) async throws -> TDNativeCount {
        try await send(TDNativeRequests.getChatFolderChatCount(folder: folder))
    }

    func getChatHistory(
        chatId: Int64,
        fromMessageId: Int64,
        limit: Int,
        offset: Int,
        onlyLocal: Bool,
    ) async throws -> TDNativeMessages {
        try await send(TDNativeRequests.getChatHistory(
            chatId: chatId,
            fromMessageId: fromMessageId,
            offset: offset,
            limit: limit,
            onlyLocal: onlyLocal,
        ))
    }

    func getChatHistory(
        chatId: Int64,
        fromMessageId: Int64,
        offset: Int,
        limit: Int,
        onlyLocal: Bool,
    ) async throws -> TDNativeMessages {
        try await send(TDNativeRequests.getChatHistory(
            chatId: chatId,
            fromMessageId: fromMessageId,
            offset: offset,
            limit: limit,
            onlyLocal: onlyLocal,
        ))
    }

    func getChatMember(chatId: Int64, memberId: TDNativeMessageSender) async throws -> TDNativeChatMember {
        try await send(TDNativeRequests.getChatMember(chatId: chatId, memberId: memberId))
    }

    func getChatMessageCount(
        chatId: Int64,
        filter: TDNativeSearchMessagesFilter,
        returnLocal: Bool,
        topicId: TDNativeMessageTopic?,
    ) async throws -> TDNativeCount {
        try await send(TDNativeRequests.getChatMessageCount(
            chatId: chatId,
            topicId: topicId,
            filter: filter,
            returnLocal: returnLocal,
        ))
    }

    func getChatMessageCount(
        chatId: Int64,
        topicId: TDNativeMessageTopic?,
        filter: TDNativeSearchMessagesFilter,
        returnLocal: Bool,
    ) async throws -> TDNativeCount {
        try await send(TDNativeRequests.getChatMessageCount(
            chatId: chatId,
            topicId: topicId,
            filter: filter,
            returnLocal: returnLocal,
        ))
    }

    func getChatMessagePosition(
        chatId: Int64,
        filter: TDNativeSearchMessagesFilter,
        messageId: Int64,
        topicId: TDNativeMessageTopic?,
    ) async throws -> TDNativeCount {
        try await send(TDNativeRequests.getChatMessagePosition(
            chatId: chatId,
            topicId: topicId,
            filter: filter,
            messageId: messageId,
        ))
    }

    func getChatPinnedMessage(chatId: Int64) async throws -> TDNativeMessage {
        try await send(TDNativeRequests.getChatPinnedMessage(chatId: chatId))
    }

    func getChatSparseMessagePositions(
        chatId: Int64,
        filter: TDNativeSearchMessagesFilter,
        fromMessageId: Int64,
        limit: Int,
        savedMessagesTopicId: Int64,
    ) async throws -> TDNativeMessagePositions {
        try await send(TDNativeRequests.getChatSparseMessagePositions(
            chatId: chatId,
            filter: filter,
            fromMessageId: fromMessageId,
            limit: limit,
            savedMessagesTopicId: savedMessagesTopicId,
        ))
    }

    func getChats(chatList: TDNativeChatList?, limit: Int) async throws -> TDNativeChats {
        try await send(TDNativeRequests.getChats(chatList: chatList, limit: limit))
    }

    func getCountries() async throws -> TDNativeCountries {
        try await send(TDNativeRequests.getCountries())
    }

    func getCountryCode() async throws -> TDNativeText {
        try await send(TDNativeRequests.getCountryCode())
    }

    func getCustomEmojiStickers(customEmojiIds: [Int64]) async throws -> TDNativeStickers {
        try await send(TDNativeRequests.getCustomEmojiStickers(customEmojiIds: customEmojiIds))
    }

    func getDirectMessagesChatTopicHistory(
        chatId: Int64,
        fromMessageId: Int64,
        limit: Int,
        offset: Int,
        topicId: Int64,
    ) async throws -> TDNativeMessages {
        try await send(TDNativeRequests.getDirectMessagesChatTopicHistory(
            chatId: chatId,
            topicId: topicId,
            fromMessageId: fromMessageId,
            offset: offset,
            limit: limit,
        ))
    }

    func getFile(fileId: Int) async throws -> TDNativeFile {
        try await send(TDNativeRequests.getFile(fileId: fileId))
    }

    func getFileDownloadedPrefixSize(fileId: Int, offset: Int64) async throws -> TDNativeFileDownloadedPrefixSize {
        try await send(TDNativeRequests.getFileDownloadedPrefixSize(fileId: fileId, offset: offset))
    }

    func getForumTopic(chatId: Int64, forumTopicId: Int) async throws -> TDNativeForumTopic {
        try await send(TDNativeRequests.getForumTopic(chatId: chatId, forumTopicId: forumTopicId))
    }

    func getForumTopicHistory(
        chatId: Int64,
        forumTopicId: Int,
        fromMessageId: Int64,
        limit: Int,
        offset: Int,
    ) async throws -> TDNativeMessages {
        try await send(TDNativeRequests.getForumTopicHistory(
            chatId: chatId,
            forumTopicId: forumTopicId,
            fromMessageId: fromMessageId,
            offset: offset,
            limit: limit,
        ))
    }

    func getForumTopics(
        chatId: Int64,
        limit: Int,
        offsetDate: Int,
        offsetForumTopicId: Int,
        offsetMessageId: Int64,
        query: String,
    ) async throws -> TDNativeForumTopics {
        try await send(TDNativeRequests.getForumTopics(
            chatId: chatId,
            query: query,
            offsetDate: offsetDate,
            offsetMessageId: offsetMessageId,
            offsetForumTopicId: offsetForumTopicId,
            limit: limit,
        ))
    }

    func getGroupsInCommon(userId: Int64, offsetChatId: Int64, limit: Int) async throws -> TDNativeChats {
        try await send(TDNativeRequests.getGroupsInCommon(userId: userId, offsetChatId: offsetChatId, limit: limit))
    }

    func getInternalLink(type: TDNativeInternalLinkType, isHttp: Bool) async throws -> TDNativeHttpUrl {
        try await send(TDNativeRequests.getInternalLink(type: type, isHttp: isHttp))
    }

    func getLanguagePackInfo(languagePackId: String) async throws -> TDNativeLanguagePackInfo {
        try await send(TDNativeRequests.getLanguagePackInfo(languagePackId: languagePackId))
    }

    func getLanguagePackStrings(keys: [String], languagePackId: String) async throws -> TDNativeLanguagePackStrings {
        try await send(TDNativeRequests.getLanguagePackStrings(languagePackId: languagePackId, keys: keys))
    }

    func getLocalizationTargetInfo(onlyLocal: Bool) async throws -> TDNativeLocalizationTargetInfo {
        try await send(TDNativeRequests.getLocalizationTargetInfo(onlyLocal: onlyLocal))
    }

    func getLoginUrl(
        chatId: Int64,
        messageId: Int64,
        buttonId: Int64,
        allowWriteAccess: Bool,
    ) async throws -> TDNativeHttpUrl {
        try await send(TDNativeRequests.getLoginUrl(
            chatId: chatId,
            messageId: messageId,
            buttonId: buttonId,
            allowWriteAccess: allowWriteAccess,
        ))
    }

    func getLoginUrlInfo(chatId: Int64, messageId: Int64, buttonId: Int64) async throws -> TDNativeLoginUrlInfo {
        try await send(TDNativeRequests.getLoginUrlInfo(chatId: chatId, messageId: messageId, buttonId: buttonId))
    }

    func getMe() async throws -> TDNativeUser {
        try await send(TDNativeRequests.getMe())
    }

    func getMessage(chatId: Int64, messageId: Int64) async throws -> TDNativeMessage {
        try await send(TDNativeRequests.getMessage(chatId: chatId, messageId: messageId))
    }

    func getMessageAvailableReactions(
        chatId: Int64,
        messageId: Int64,
        rowSize: Int,
    ) async throws -> TDNativeAvailableReactions {
        try await send(TDNativeRequests.getMessageAvailableReactions(
            chatId: chatId,
            messageId: messageId,
            rowSize: rowSize,
        ))
    }

    func getMessageLocally(chatId: Int64, messageId: Int64) async throws -> TDNativeMessage {
        try await send(TDNativeRequests.getMessageLocally(chatId: chatId, messageId: messageId))
    }

    func getMessageProperties(chatId: Int64, messageId: Int64) async throws -> TDNativeMessageProperties {
        try await send(TDNativeRequests.getMessageProperties(chatId: chatId, messageId: messageId))
    }

    func getMessageThread(chatId: Int64, messageId: Int64) async throws -> TDNativeMessageThreadInfo {
        try await send(TDNativeRequests.getMessageThread(chatId: chatId, messageId: messageId))
    }

    func getMessageThreadHistory(
        chatId: Int64,
        fromMessageId: Int64,
        limit: Int,
        messageId: Int64,
        offset: Int,
    ) async throws -> TDNativeMessages {
        try await send(TDNativeRequests.getMessageThreadHistory(
            chatId: chatId,
            messageId: messageId,
            fromMessageId: fromMessageId,
            offset: offset,
            limit: limit,
        ))
    }

    func getMessages(chatId: Int64, messageIds: [Int64]) async throws -> TDNativeMessages {
        try await send(TDNativeRequests.getMessages(chatId: chatId, messageIds: messageIds))
    }

    func getOption(name: String) async throws -> TDNativeOptionValue {
        try await send(TDNativeRequests.getOption(name: name))
    }

    func getPollVoters(
        chatId: Int64,
        limit: Int,
        messageId: Int64,
        offset: Int,
        optionId: Int,
    ) async throws -> TDNativePollVoters {
        try await send(TDNativeRequests.getPollVoters(
            chatId: chatId,
            messageId: messageId,
            optionId: optionId,
            offset: offset,
            limit: limit,
        ))
    }

    func getRepliedMessage(chatId: Int64, messageId: Int64) async throws -> TDNativeMessage {
        try await send(TDNativeRequests.getRepliedMessage(chatId: chatId, messageId: messageId))
    }

    func getSavedAnimations() async throws -> TDNativeAnimations {
        try await send(TDNativeRequests.getSavedAnimations())
    }

    func getSavedMessagesTopicHistory(
        fromMessageId: Int64,
        limit: Int,
        offset: Int,
        savedMessagesTopicId: Int64,
    ) async throws -> TDNativeMessages {
        try await send(TDNativeRequests.getSavedMessagesTopicHistory(
            savedMessagesTopicId: savedMessagesTopicId,
            fromMessageId: fromMessageId,
            offset: offset,
            limit: limit,
        ))
    }

    func getScopeNotificationSettings(scope: TDNativeNotificationSettingsScope) async throws
    -> TDNativeScopeNotificationSettings {
        try await send(TDNativeRequests.getScopeNotificationSettings(scope: scope))
    }

    func getStickers(
        chatId: Int64,
        limit: Int,
        query: String,
        stickerType: TDNativeStickerType,
    ) async throws -> TDNativeStickers {
        try await send(TDNativeRequests.getStickers(
            stickerType: stickerType,
            query: query,
            limit: limit,
            chatId: chatId,
        ))
    }

    func getStory(onlyLocal: Bool, storyId: Int, storyPosterChatId: Int64) async throws -> TDNativeStory {
        try await send(TDNativeRequests.getStory(
            storyPosterChatId: storyPosterChatId,
            storyId: storyId,
            onlyLocal: onlyLocal,
        ))
    }

    func getSupergroup(supergroupId: Int64) async throws -> TDNativeSupergroup {
        try await send(TDNativeRequests.getSupergroup(supergroupId: supergroupId))
    }

    func getSupergroupFullInfo(supergroupId: Int64) async throws -> TDNativeSupergroupFullInfo {
        try await send(TDNativeRequests.getSupergroupFullInfo(supergroupId: supergroupId))
    }

    func getSupergroupMembers(
        filter: TDNativeSupergroupMembersFilter?,
        limit: Int,
        offset: Int,
        supergroupId: Int64,
    ) async throws -> TDNativeChatMembers {
        try await send(TDNativeRequests.getSupergroupMembers(
            supergroupId: supergroupId,
            filter: filter,
            offset: offset,
            limit: limit,
        ))
    }

    func getUser(userId: Int64) async throws -> TDNativeUser {
        try await send(TDNativeRequests.getUser(userId: userId))
    }

    func getUserFullInfo(userId: Int64) async throws -> TDNativeUserFullInfo {
        try await send(TDNativeRequests.getUserFullInfo(userId: userId))
    }

    func getUserProfilePhotos(limit: Int, offset: Int, userId: Int64) async throws -> TDNativeChatPhotos {
        try await send(TDNativeRequests.getUserProfilePhotos(userId: userId, offset: offset, limit: limit))
    }

    func logOut() async throws -> TDNativeOk {
        try await send(TDNativeRequests.logOut())
    }

    func markChecklistTasksAsDone(
        chatId: Int64,
        markedAsDoneTaskIds: [Int],
        markedAsNotDoneTaskIds: [Int],
        messageId: Int64,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.markChecklistTasksAsDone(
            chatId: chatId,
            messageId: messageId,
            markedAsDoneTaskIds: markedAsDoneTaskIds,
            markedAsNotDoneTaskIds: markedAsNotDoneTaskIds,
        ))
    }

    func openChat(chatId: Int64) async throws -> TDNativeOk {
        try await send(TDNativeRequests.openChat(chatId: chatId))
    }

    func openMessageContent(chatId: Int64, messageId: Int64) async throws -> TDNativeOk {
        try await send(TDNativeRequests.openMessageContent(chatId: chatId, messageId: messageId))
    }

    func openStory(storyId: Int, storyPosterChatId: Int64) async throws -> TDNativeOk {
        try await send(TDNativeRequests.openStory(storyPosterChatId: storyPosterChatId, storyId: storyId))
    }

    func pinChatMessage(
        chatId: Int64,
        disableNotification: Bool,
        messageId: Int64,
        onlyForSelf: Bool,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.pinChatMessage(
            chatId: chatId,
            messageId: messageId,
            disableNotification: disableNotification,
            onlyForSelf: onlyForSelf,
        ))
    }

    func processPushNotification(payload: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.processPushNotification(payload: payload))
    }

    func readAllChatReactions(chatId: Int64) async throws -> TDNativeOk {
        try await send(TDNativeRequests.readAllChatReactions(chatId: chatId))
    }

    func readAllForumTopicReactions(chatId: Int64, forumTopicId: Int) async throws -> TDNativeOk {
        try await send(TDNativeRequests.readAllForumTopicReactions(chatId: chatId, forumTopicId: forumTopicId))
    }

    func readChatList(chatList: TDNativeChatList) async throws -> TDNativeOk {
        try await send(TDNativeRequests.readChatList(chatList: chatList))
    }

    func recoverAuthenticationPassword(
        recoveryCode: String,
        newPassword: String,
        newHint: String,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.recoverAuthenticationPassword(
            recoveryCode: recoveryCode,
            newPassword: newPassword,
            newHint: newHint,
        ))
    }

    func registerDevice(
        deviceToken: TDNativeDeviceToken,
        otherUserIds: [Int64],
    ) async throws -> TDNativePushReceiverId {
        try await send(TDNativeRequests.registerDevice(deviceToken: deviceToken, otherUserIds: otherUserIds))
    }

    func registerUser(firstName: String, lastName: String, disableNotification: Bool) async throws -> TDNativeOk {
        try await send(TDNativeRequests.registerUser(
            firstName: firstName,
            lastName: lastName,
            disableNotification: disableNotification,
        ))
    }

    func removeMessageReaction(
        chatId: Int64,
        messageId: Int64,
        reactionType: TDNativeReactionType,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.removeMessageReaction(
            chatId: chatId,
            messageId: messageId,
            reactionType: reactionType,
        ))
    }

    func reorderChatFolders(chatFolderIds: [Int], mainChatListPosition: Int) async throws -> TDNativeOk {
        try await send(TDNativeRequests.reorderChatFolders(
            chatFolderIds: chatFolderIds,
            mainChatListPosition: mainChatListPosition,
        ))
    }

    func requestAuthenticationPasswordRecovery() async throws -> TDNativeOk {
        try await send(TDNativeRequests.requestAuthenticationPasswordRecovery())
    }

    func requestQrCodeAuthentication(otherUserIds: [Int64]) async throws -> TDNativeOk {
        try await send(TDNativeRequests.requestQrCodeAuthentication(otherUserIds: otherUserIds))
    }

    func resendAuthenticationCode(reason: TDNativeResendCodeReason?) async throws -> TDNativeOk {
        try await send(TDNativeRequests.resendAuthenticationCode(reason: reason))
    }

    func resendMessages(
        chatId: Int64,
        messageIds: [Int64],
        paidMessageStarCount: Int64,
        quote: TDNativeInputTextQuote?,
    ) async throws -> TDNativeMessages {
        try await send(TDNativeRequests.resendMessages(
            chatId: chatId,
            messageIds: messageIds,
            quote: quote,
            paidMessageStarCount: paidMessageStarCount,
        ))
    }

    func resetAuthenticationEmailAddress() async throws -> TDNativeOk {
        try await send(TDNativeRequests.resetAuthenticationEmailAddress())
    }

    func searchChatMessages(
        chatId: Int64,
        filter: TDNativeSearchMessagesFilter?,
        fromMessageId: Int64,
        limit: Int,
        offset: Int,
        query: String,
        senderId: TDNativeMessageSender?,
        topicId: TDNativeMessageTopic?,
    ) async throws -> TDNativeFoundChatMessages {
        try await send(TDNativeRequests.searchChatMessages(
            chatId: chatId,
            topicId: topicId,
            query: query,
            senderId: senderId,
            fromMessageId: fromMessageId,
            offset: offset,
            limit: limit,
            filter: filter,
        ))
    }

    func searchChatRecentLocationMessages(chatId: Int64, limit: Int) async throws -> TDNativeMessages {
        try await send(TDNativeRequests.searchChatRecentLocationMessages(chatId: chatId, limit: limit))
    }

    func searchChats(
        limit: Int,
        query: String,
        typeFilter: TDNativeSearchChatTypeFilter?,
    ) async throws -> TDNativeChats {
        try await send(TDNativeRequests.searchChats(query: query, typeFilter: typeFilter, limit: limit))
    }

    func searchChatsOnServer(
        limit: Int,
        query: String,
        typeFilter: TDNativeSearchChatTypeFilter?,
    ) async throws -> TDNativeChats {
        try await send(TDNativeRequests.searchChatsOnServer(query: query, typeFilter: typeFilter, limit: limit))
    }

    func searchContacts(query: String, limit: Int) async throws -> TDNativeUsers {
        try await send(TDNativeRequests.searchContacts(query: query, limit: limit))
    }

    func searchMessages(
        chatList: TDNativeChatList?,
        query: String,
        offset: String,
        limit: Int,
        filter: TDNativeSearchMessagesFilter?,
        chatTypeFilter: TDNativeSearchMessagesChatTypeFilter?,
        minDate: Int,
        maxDate: Int,
    ) async throws -> TDNativeFoundMessages {
        try await send(TDNativeRequests.searchMessages(
            chatList: chatList,
            query: query,
            offset: offset,
            limit: limit,
            filter: filter,
            chatTypeFilter: chatTypeFilter,
            minDate: minDate,
            maxDate: maxDate,
        ))
    }

    func searchPublicChats(query: String, typeFilter: TDNativeSearchChatTypeFilter?) async throws -> TDNativeChats {
        try await send(TDNativeRequests.searchPublicChats(query: query, typeFilter: typeFilter))
    }

    func sendChatAction(
        action: TDNativeChatAction?,
        businessConnectionId: String,
        chatId: Int64,
        topicId: TDNativeMessageTopic?,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.sendChatAction(
            chatId: chatId,
            topicId: topicId,
            businessConnectionId: businessConnectionId,
            action: action,
        ))
    }

    func sendMessage(
        chatId: Int64,
        inputMessageContent: TDNativeInputMessageContent,
        options: TDNativeMessageSendOptions?,
        replyMarkup: TDNativeReplyMarkup?,
        replyTo: TDNativeInputMessageReplyTo?,
        topicId: TDNativeMessageTopic?,
    ) async throws -> TDNativeMessage {
        try await send(TDNativeRequests.sendMessage(
            chatId: chatId,
            topicId: topicId,
            replyTo: replyTo,
            options: options,
            replyMarkup: replyMarkup,
            inputMessageContent: inputMessageContent,
        ))
    }

    func sendMessageAlbum(
        chatId: Int64,
        inputMessageContents: [TDNativeInputMessageContent],
        options: TDNativeMessageSendOptions?,
        replyTo: TDNativeInputMessageReplyTo?,
        topicId: TDNativeMessageTopic?,
    ) async throws -> TDNativeMessages {
        try await send(TDNativeRequests.sendMessageAlbum(
            chatId: chatId,
            topicId: topicId,
            replyTo: replyTo,
            options: options,
            inputMessageContents: inputMessageContents,
        ))
    }

    func setAuthenticationEmailAddress(emailAddress: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setAuthenticationEmailAddress(emailAddress: emailAddress))
    }

    func setAuthenticationPhoneNumber(
        phoneNumber: String,
        settings: TDNativePhoneNumberAuthenticationSettings?,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setAuthenticationPhoneNumber(phoneNumber: phoneNumber, settings: settings))
    }

    func setBio(bio: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setBio(bio: bio))
    }

    func setChatDescription(chatId: Int64, description: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setChatDescription(chatId: chatId, description: description))
    }

    func setChatDraftMessage(
        chatId: Int64,
        draftMessage: TDNativeDraftMessage?,
        topicId: TDNativeMessageTopic?,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setChatDraftMessage(
            chatId: chatId,
            topicId: topicId,
            draftMessage: draftMessage,
        ))
    }

    func setChatMemberTag(chatId: Int64, tag: String, userId: Int64) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setChatMemberTag(chatId: chatId, userId: userId, tag: tag))
    }

    func setChatNotificationSettings(
        chatId: Int64,
        notificationSettings: TDNativeChatNotificationSettings,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setChatNotificationSettings(
            chatId: chatId,
            notificationSettings: notificationSettings,
        ))
    }

    func setChatTitle(chatId: Int64, title: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setChatTitle(chatId: chatId, title: title))
    }

    func setName(firstName: String, lastName: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setName(firstName: firstName, lastName: lastName))
    }

    func setOption(name: String, value: TDNativeOptionValue?) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setOption(name: name, value: value))
    }

    func setPollAnswer(chatId: Int64, messageId: Int64, optionIds: [Int]) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setPollAnswer(chatId: chatId, messageId: messageId, optionIds: optionIds))
    }

    func setTdlibParameters(
        useTestDc: Bool,
        databaseDirectory: String,
        filesDirectory: String,
        databaseEncryptionKey: Data,
        useFileDatabase: Bool,
        useChatInfoDatabase: Bool,
        useMessageDatabase: Bool,
        useSecretChats: Bool,
        apiId: Int,
        apiHash: String,
        systemLanguageCode: String,
        deviceModel: String,
        systemVersion: String,
        applicationVersion: String,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setTdlibParameters(
            useTestDc: useTestDc,
            databaseDirectory: databaseDirectory,
            filesDirectory: filesDirectory,
            databaseEncryptionKey: databaseEncryptionKey,
            useFileDatabase: useFileDatabase,
            useChatInfoDatabase: useChatInfoDatabase,
            useMessageDatabase: useMessageDatabase,
            useSecretChats: useSecretChats,
            apiId: apiId,
            apiHash: apiHash,
            systemLanguageCode: systemLanguageCode,
            deviceModel: deviceModel,
            systemVersion: systemVersion,
            applicationVersion: applicationVersion,
        ))
    }

    func stopPoll(chatId: Int64, messageId: Int64, replyMarkup: TDNativeReplyMarkup?) async throws -> TDNativeOk {
        try await send(TDNativeRequests.stopPoll(chatId: chatId, messageId: messageId, replyMarkup: replyMarkup))
    }

    func synchronizeLanguagePack(languagePackId: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.synchronizeLanguagePack(languagePackId: languagePackId))
    }

    func toggleChatIsMarkedAsUnread(chatId: Int64, isMarkedAsUnread: Bool) async throws -> TDNativeOk {
        try await send(TDNativeRequests.toggleChatIsMarkedAsUnread(chatId: chatId, isMarkedAsUnread: isMarkedAsUnread))
    }

    func toggleChatIsPinned(chatId: Int64, chatList: TDNativeChatList, isPinned: Bool) async throws -> TDNativeOk {
        try await send(TDNativeRequests.toggleChatIsPinned(chatList: chatList, chatId: chatId, isPinned: isPinned))
    }

    func unpinChatMessage(chatId: Int64, messageId: Int64) async throws -> TDNativeOk {
        try await send(TDNativeRequests.unpinChatMessage(chatId: chatId, messageId: messageId))
    }

    func viewMessages(
        chatId: Int64,
        forceRead: Bool,
        messageIds: [Int64],
        source: TDNativeMessageSource?,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.viewMessages(
            chatId: chatId,
            messageIds: messageIds,
            source: source,
            forceRead: forceRead,
        ))
    }
}

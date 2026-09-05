// TDClient+Generated.swift

import Foundation
import TDLibKit

extension TDClient {
    func addChatToList(chatId: Int64, chatList: TDNativeChatList) async throws -> TDNativeOk {
        try await send(TDNativeRequests.addChatToList(chatId: chatId, chatList: chatList))
    }

    func canSendMessageToUser(userId: Int64, onlyLocal: Bool) async throws -> TDNativeCanSendMessageToUserResult {
        try await send(TDNativeRequests.canSendMessageToUser(userId: userId, onlyLocal: onlyLocal))
    }

    func cancelDownloadFile(fileId: Int, onlyIfPending: Bool) async throws -> TDNativeOk {
        try await send(TDNativeRequests.cancelDownloadFile(fileId: fileId, onlyIfPending: onlyIfPending))
    }

    func checkAuthenticationCode(code: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.checkAuthenticationCode(code: code))
    }

    func checkAuthenticationPassword(password: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.checkAuthenticationPassword(password: password))
    }

    func closeChat(chatId: Int64) async throws -> TDNativeOk {
        try await send(TDNativeRequests.closeChat(chatId: chatId))
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

    func getAuthorizationState() async throws -> TDNativeAuthorizationState {
        try await send(TDNativeRequests.getAuthorizationState())
    }

    func getBasicGroup(basicGroupId: Int64) async throws -> TDNativeBasicGroup {
        try await send(TDNativeRequests.getBasicGroup(basicGroupId: basicGroupId))
    }

    func getBasicGroupFullInfo(basicGroupId: Int64) async throws -> TDNativeBasicGroupFullInfo {
        try await send(TDNativeRequests.getBasicGroupFullInfo(basicGroupId: basicGroupId))
    }

    func getChat(chatId: Int64) async throws -> TDNativeChat {
        try await send(TDNativeRequests.getChat(chatId: chatId))
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

    func getFile(fileId: Int) async throws -> TDNativeFile {
        try await send(TDNativeRequests.getFile(fileId: fileId))
    }

    func getFileDownloadedPrefixSize(fileId: Int, offset: Int64) async throws -> TDNativeFileDownloadedPrefixSize {
        try await send(TDNativeRequests.getFileDownloadedPrefixSize(fileId: fileId, offset: offset))
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

    func getMe() async throws -> TDNativeUser {
        try await send(TDNativeRequests.getMe())
    }

    func getMessage(chatId: Int64, messageId: Int64) async throws -> TDNativeMessage {
        try await send(TDNativeRequests.getMessage(chatId: chatId, messageId: messageId))
    }

    func getMessageProperties(chatId: Int64, messageId: Int64) async throws -> TDNativeMessageProperties {
        try await send(TDNativeRequests.getMessageProperties(chatId: chatId, messageId: messageId))
    }

    func getScopeNotificationSettings(scope: TDNativeNotificationSettingsScope) async throws
    -> TDNativeScopeNotificationSettings {
        try await send(TDNativeRequests.getScopeNotificationSettings(scope: scope))
    }

    func getSupergroup(supergroupId: Int64) async throws -> TDNativeSupergroup {
        try await send(TDNativeRequests.getSupergroup(supergroupId: supergroupId))
    }

    func getSupergroupFullInfo(supergroupId: Int64) async throws -> TDNativeSupergroupFullInfo {
        try await send(TDNativeRequests.getSupergroupFullInfo(supergroupId: supergroupId))
    }

    func getUser(userId: Int64) async throws -> TDNativeUser {
        try await send(TDNativeRequests.getUser(userId: userId))
    }

    func logOut() async throws -> TDNativeOk {
        try await send(TDNativeRequests.logOut())
    }

    func openChat(chatId: Int64) async throws -> TDNativeOk {
        try await send(TDNativeRequests.openChat(chatId: chatId))
    }

    func openMessageContent(chatId: Int64, messageId: Int64) async throws -> TDNativeOk {
        try await send(TDNativeRequests.openMessageContent(chatId: chatId, messageId: messageId))
    }

    func processPushNotification(payload: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.processPushNotification(payload: payload))
    }

    func readChatList(chatList: TDNativeChatList) async throws -> TDNativeOk {
        try await send(TDNativeRequests.readChatList(chatList: chatList))
    }

    func registerDevice(
        deviceToken: TDNativeDeviceToken,
        otherUserIds: [Int64],
    ) async throws -> TDNativePushReceiverId {
        try await send(TDNativeRequests.registerDevice(deviceToken: deviceToken, otherUserIds: otherUserIds))
    }

    func reorderChatFolders(chatFolderIds: [Int], mainChatListPosition: Int) async throws -> TDNativeOk {
        try await send(TDNativeRequests.reorderChatFolders(
            chatFolderIds: chatFolderIds,
            mainChatListPosition: mainChatListPosition,
        ))
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

    func setAuthenticationPhoneNumber(
        phoneNumber: String,
        settings: TDNativePhoneNumberAuthenticationSettings?,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setAuthenticationPhoneNumber(phoneNumber: phoneNumber, settings: settings))
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

    func setChatNotificationSettings(
        chatId: Int64,
        notificationSettings: TDNativeChatNotificationSettings,
    ) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setChatNotificationSettings(
            chatId: chatId,
            notificationSettings: notificationSettings,
        ))
    }

    func setOption(name: String, value: TDNativeOptionValue?) async throws -> TDNativeOk {
        try await send(TDNativeRequests.setOption(name: name, value: value))
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

    func synchronizeLanguagePack(languagePackId: String) async throws -> TDNativeOk {
        try await send(TDNativeRequests.synchronizeLanguagePack(languagePackId: languagePackId))
    }

    func toggleChatIsMarkedAsUnread(chatId: Int64, isMarkedAsUnread: Bool) async throws -> TDNativeOk {
        try await send(TDNativeRequests.toggleChatIsMarkedAsUnread(chatId: chatId, isMarkedAsUnread: isMarkedAsUnread))
    }

    func toggleChatIsPinned(chatId: Int64, chatList: TDNativeChatList, isPinned: Bool) async throws -> TDNativeOk {
        try await send(TDNativeRequests.toggleChatIsPinned(chatList: chatList, chatId: chatId, isPinned: isPinned))
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

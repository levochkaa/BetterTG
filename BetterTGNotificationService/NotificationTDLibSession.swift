// NotificationTDLibSession.swift

import Foundation
import os.log
import TDLibKitDynamic

final class NotificationTDLibSession: @unchecked Sendable {
    // MARK: Private

    private struct MediaCandidate {
        let file: File
        let placeholder: Data?
        let kind: String
    }

    private let account: TelegramAccount
    private let payload: String
    private let metadata: RelayNotificationMetadata
    private let target: RichNotificationTarget?
    private let allowsQuickReply: Bool
    private let logger: os.Logger
    private let manager = TDLibClientManager()
    private let stateLock = NSLock()
    private var client: TDLibClient?
    private var resolutionContinuation: CheckedContinuation<ResolvedTelegramNotification?, Never>?
    private var configured = false
    private var processingStarted = false
    private var finished = false

    init(
        account: TelegramAccount,
        payload: String,
        metadata: RelayNotificationMetadata,
        allowsQuickReply: Bool,
        logger: os.Logger,
    ) {
        self.account = account
        self.payload = payload
        self.metadata = metadata
        self.target = RichNotificationTarget(
            accountID: metadata.accountID, peer: metadata.peer, serverMessageID: metadata.serverMessageID,
        )
        self.allowsQuickReply = allowsQuickReply
        self.logger = logger
    }

    // MARK: Internal

    func resolve() async -> ResolvedTelegramNotification? {
        guard let target, target.matches(accountUserID: account.userID) else { return nil }
        let result = await withCheckedContinuation { continuation in
            stateLock.lock()
            resolutionContinuation = continuation
            stateLock.unlock()

            client = manager.createClient { [weak self] data, client in
                self?.handle(data: data, client: client)
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 14) { [weak self] in
                self?.finish(nil, reason: "timeout")
            }
        }
        await close()
        return result
    }

    private func handle(data: Data, client: TDLibClient) {
        guard let update = try? client.decoder.decode(Update.self, from: data) else { return }
        switch update {
        case .updateAuthorizationState(let value):
            handle(authorizationState: value.authorizationState, client: client)
        case .updateNotificationGroup(let value):
            guard let target,
                  let notification = target.notification(in: value.addedNotifications, groupChatID: value.chatId)
            else { return }
            Task { [weak self] in
                guard let self,
                      let chat = try? await client.getChat(chatId: value.chatId),
                      target.matches(chat: chat, requestedChatID: value.chatId)
                else { return }
                let resolved = await resolve(notification: notification, chat: chat, target: target, client: client)
                finish(resolved, reason: resolved == nil ? "unresolved" : "notification")
            }
        default:
            break
        }
    }

    private func handle(authorizationState: AuthorizationState, client: TDLibClient) {
        switch authorizationState {
        case .authorizationStateWaitTdlibParameters:
            stateLock.lock()
            let shouldConfigure = !configured
            configured = true
            stateLock.unlock()
            guard shouldConfigure else { return }
            Task { [weak self] in
                await self?.configure(client: client)
            }
        case .authorizationStateReady:
            stateLock.lock()
            let shouldProcess = !processingStarted
            processingStarted = true
            stateLock.unlock()
            guard shouldProcess else { return }
            Task { [weak self] in
                await self?.process(client: client)
            }
        case .authorizationStateClosed,
             .authorizationStateClosing,
             .authorizationStateLoggingOut,
             .authorizationStateWaitCode,
             .authorizationStateWaitPassword,
             .authorizationStateWaitPhoneNumber:
            finish(nil, reason: "authorization")
        default:
            break
        }
    }

    private func configure(client: TDLibClient) async {
        do {
            let directory = try TelegramAccountRegistry().databaseDirectory(for: account.id)
            try await client.setTdlibParameters(
                apiHash: Secret.apiHash,
                apiId: Secret.apiId,
                applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    ?? "1",
                databaseDirectory: directory.path,
                databaseEncryptionKey: Data(),
                deviceModel: "BetterTG Notification Service",
                filesDirectory: directory.path,
                systemLanguageCode: Locale.current.identifier,
                systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                useChatInfoDatabase: true,
                useFileDatabase: true,
                useMessageDatabase: true,
                useSecretChats: true,
                useTestDc: false,
            )
        } catch {
            logger.error("rich_notification.tdlib_config_failed")
            finish(nil, reason: "configuration")
        }
    }

    private func process(client: TDLibClient) async {
        do {
            _ = try await client.setOption(
                name: "notification_group_count_max",
                value: .optionValueInteger(.init(value: 20)),
            )
            _ = try await client.setOption(
                name: "notification_group_size_max",
                value: .optionValueInteger(.init(value: 10)),
            )
            _ = try await client.processPushNotification(payload: payload)
            logger.log("rich_notification.tdlib_processed")
        } catch {
            logger.log("rich_notification.tdlib_processing_waiting_for_updates")
        }
    }

    private func resolve(
        notification: TDLibKitDynamic.Notification,
        chat: Chat,
        target: RichNotificationTarget,
        client: TDLibClient,
    ) async -> ResolvedTelegramNotification? {
        guard target.matches(notification: notification, groupChatID: chat.id),
              target.matches(chat: chat, requestedChatID: chat.id) else { return nil }
        let chatID = chat.id
        var senderID: MessageSender
        var senderName: String
        var media: MediaCandidate?
        var body: String?
        var expectsMedia = false

        switch notification.type {
        case .notificationTypeNewPushMessage(let value):
            senderID = value.senderId
            senderName = value.senderName
            media = mediaCandidate(for: value.content)
            body = notificationBody(for: value.content)
            expectsMedia = isMediaContent(value.content)
            if media == nil,
               let message = await fetchMessage(
                   chatID: chatID,
                   target: target,
                   client: client,
               )
            {
                senderID = message.senderId
                senderName = await displayName(for: message.senderId, client: client)
                    ?? senderName
                media = mediaCandidate(for: message.content)
                body = notificationBody(for: message.content) ?? body
                expectsMedia = isMediaContent(message.content)
            }
        case .notificationTypeNewMessage(let value):
            senderID = value.message.senderId
            senderName = await displayName(for: value.message.senderId, client: client)
                ?? metadata.senderName
                ?? "Telegram"
            media = mediaCandidate(for: value.message.content)
            body = notificationBody(for: value.message.content)
            expectsMedia = isMediaContent(value.message.content)
        default:
            return nil
        }

        logger.log(
            "rich_notification.media_resolved available=\(media != nil, privacy: .public) expected=\(expectsMedia, privacy: .public)",
        )
        RichNotificationDiagnostics.record(
            "media_resolved",
            fields: ["available": String(media != nil), "expected": String(expectsMedia)],
        )

        let resolvedSenderID = senderID
        let resolvedMediaCandidate = media
        let conversation = chat
        async let senderAvatar = avatarData(for: resolvedSenderID, client: client)
        async let conversationAvatar = imageData(
            file: conversation.photo?.small,
            placeholder: conversation.photo?.minithumbnail?.data,
            client: client,
        )
        async let mediaData = imageData(
            file: resolvedMediaCandidate?.file,
            placeholder: resolvedMediaCandidate?.placeholder,
            client: client,
        )

        let resolvedSenderAvatar = await senderAvatar
            ?? RichNotificationCache.avatarData(for: metadata.sender, accountID: metadata.accountID)
        let resolvedConversationAvatar = await conversationAvatar
            ?? RichNotificationCache.avatarData(for: metadata.peer, accountID: metadata.accountID)
        let resolvedMedia = await mediaData
        if expectsMedia {
            logger.log(
                "rich_notification.media_downloaded success=\(resolvedMedia != nil, privacy: .public) kind=\(resolvedMediaCandidate?.kind ?? "none", privacy: .public)",
            )
            RichNotificationDiagnostics.record(
                "media_downloaded",
                fields: [
                    "kind": resolvedMediaCandidate?.kind ?? "none",
                    "success": String(resolvedMedia != nil),
                ],
            )
        }
        let canQuickReply =
            if allowsQuickReply {
                await QuickReplyNotification.canSendText(to: conversation, using: client)
            } else {
                false
            }
        guard !Task.isCancelled,
              RichNotificationCache.matchesAccount(metadata.accountID, boundUserID: account.userID) else { return nil }
        if let resolvedMedia, let message = metadata.messageReference {
            RichNotificationCache.cacheMedia(resolvedMedia, for: message, accountID: metadata.accountID)
        }
        if let resolvedSenderAvatar {
            RichNotificationCache.cacheAvatar(resolvedSenderAvatar, for: metadata.sender, accountID: metadata.accountID)
        }
        if let resolvedConversationAvatar {
            RichNotificationCache.cacheAvatar(
                resolvedConversationAvatar,
                for: metadata.peer,
                accountID: metadata.accountID,
            )
        }

        return ResolvedTelegramNotification(
            senderName: senderName.isEmpty ? (metadata.senderName ?? "Telegram") : senderName,
            conversationTitle: conversation.title,
            senderAvatarData: resolvedSenderAvatar,
            conversationAvatarData: resolvedConversationAvatar,
            mediaData: resolvedMedia,
            body: body,
            canQuickReply: canQuickReply,
        )
    }

    private func fetchMessage(
        chatID: Int64,
        target: RichNotificationTarget,
        client: TDLibClient,
    ) async -> Message? {
        let messageIDs = [target.messageID]

        for messageID in messageIDs {
            if let message = try? await client.getMessage(chatId: chatID, messageId: messageID),
               target.matches(message: message, chatID: chatID)
            {
                logger.log("rich_notification.message_fetched source=get_message")
                RichNotificationDiagnostics.record("message_fetched", fields: ["source": "get_message"])
                return message
            }
            if let history = try? await client.getChatHistory(
                chatId: chatID,
                fromMessageId: messageID,
                limit: 3,
                offset: -1,
                onlyLocal: false,
            ), let message = history.messages?.first(where: { target.matches(message: $0, chatID: chatID) }) {
                logger.log("rich_notification.message_fetched source=chat_history")
                RichNotificationDiagnostics.record("message_fetched", fields: ["source": "chat_history"])
                return message
            }
        }

        for _ in 0..<3 {
            if let history = try? await client.getChatHistory(
                chatId: chatID,
                fromMessageId: 0,
                limit: 10,
                offset: 0,
                onlyLocal: false,
            ), let messages = history.messages {
                if let message = messages.first(where: { target.matches(message: $0, chatID: chatID) }) {
                    logger.log("rich_notification.message_fetched source=latest_history")
                    RichNotificationDiagnostics.record("message_fetched", fields: ["source": "latest_history"])
                    return message
                }
            }
            for messageID in messageIDs {
                if let message = try? await client.getMessage(chatId: chatID, messageId: messageID),
                   target.matches(message: message, chatID: chatID)
                {
                    logger.log("rich_notification.message_fetched source=get_message_after_history")
                    RichNotificationDiagnostics.record(
                        "message_fetched",
                        fields: ["source": "get_message_after_history"],
                    )
                    return message
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        logger.log("rich_notification.message_fetched source=network success=false")
        RichNotificationDiagnostics.record(
            "message_fetched",
            fields: ["source": "network", "success": "false"],
        )
        return nil
    }

    private func avatarData(for sender: MessageSender, client: TDLibClient) async -> Data? {
        switch sender {
        case .messageSenderUser(let value):
            guard let user = try? await client.getUser(userId: value.userId) else { return nil }
            return await imageData(
                file: user.profilePhoto?.small,
                placeholder: user.profilePhoto?.minithumbnail?.data,
                client: client,
            )
        case .messageSenderChat(let value):
            guard let chat = try? await client.getChat(chatId: value.chatId) else { return nil }
            return await imageData(
                file: chat.photo?.small,
                placeholder: chat.photo?.minithumbnail?.data,
                client: client,
            )
        }
    }

    private func displayName(for sender: MessageSender, client: TDLibClient) async -> String? {
        switch sender {
        case .messageSenderUser(let value):
            guard let user = try? await client.getUser(userId: value.userId) else { return nil }
            let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            return name.isEmpty ? nil : name
        case .messageSenderChat(let value):
            return try? await client.getChat(chatId: value.chatId).title
        }
    }

    private func imageData(file: File?, placeholder: Data?, client: TDLibClient) async -> Data? {
        if let file {
            let resolved = await (try? client.downloadFile(
                fileId: file.id,
                limit: 0,
                offset: 0,
                priority: 32,
                synchronous: true,
            )) ?? file
            if resolved.local.isDownloadingCompleted,
               let data = try? Data(contentsOf: URL(fileURLWithPath: resolved.local.path)),
               RichNotificationCache.normalizedJPEG(data, maximumPixelSize: 1280) != nil
            {
                return data
            }
        }
        return placeholder
    }

    private func mediaCandidate(for content: PushMessageContent) -> MediaCandidate? {
        switch content {
        case .pushMessageContentPhoto(let value):
            guard !value.isSecret else { return nil }
            return value.photo.flatMap { photoCandidate($0, kind: "photo") }
        case .pushMessageContentVideo(let value):
            guard !value.isSecret else { return nil }
            return value.video.flatMap {
                thumbnailCandidate($0.thumbnail, placeholder: $0.minithumbnail?.data, kind: "video")
            }
        case .pushMessageContentAnimation(let value):
            return value.animation.flatMap {
                thumbnailCandidate($0.thumbnail, placeholder: $0.minithumbnail?.data, kind: "animation")
            }
        case .pushMessageContentDocument(let value):
            return value.document.flatMap {
                thumbnailCandidate($0.thumbnail, placeholder: $0.minithumbnail?.data, kind: "document")
            }
        case .pushMessageContentSticker(let value):
            return value.sticker.flatMap {
                thumbnailCandidate($0.thumbnail, placeholder: nil, kind: "sticker")
            }
        case .pushMessageContentVideoNote(let value):
            return value.videoNote.flatMap {
                thumbnailCandidate($0.thumbnail, placeholder: $0.minithumbnail?.data, kind: "video_note")
            }
        default:
            return nil
        }
    }

    private func mediaCandidate(for content: MessageContent) -> MediaCandidate? {
        switch content {
        case .messagePhoto(let value):
            guard !value.isSecret, !value.hasSpoiler else { return nil }
            return photoCandidate(value.photo, kind: "photo")
        case .messageVideo(let value):
            guard !value.isSecret, !value.hasSpoiler else { return nil }
            return thumbnailCandidate(
                value.video.thumbnail,
                placeholder: value.video.minithumbnail?.data,
                kind: "video",
            )
        case .messageAnimation(let value):
            guard !value.isSecret, !value.hasSpoiler else { return nil }
            return thumbnailCandidate(
                value.animation.thumbnail,
                placeholder: value.animation.minithumbnail?.data,
                kind: "animation",
            )
        case .messageDocument(let value):
            return thumbnailCandidate(
                value.document.thumbnail,
                placeholder: value.document.minithumbnail?.data,
                kind: "document",
            )
        case .messageSticker(let value):
            return thumbnailCandidate(value.sticker.thumbnail, placeholder: nil, kind: "sticker")
        case .messageVideoNote(let value):
            guard !value.isSecret else { return nil }
            return thumbnailCandidate(
                value.videoNote.thumbnail,
                placeholder: value.videoNote.minithumbnail?.data,
                kind: "video_note",
            )
        default:
            return nil
        }
    }

    private func photoCandidate(_ photo: Photo, kind: String) -> MediaCandidate? {
        guard let size = photo.sizes.min(by: { lhs, rhs in
            abs(max(lhs.width, lhs.height) - 1280) < abs(max(rhs.width, rhs.height) - 1280)
        }) else { return nil }
        return MediaCandidate(file: size.photo, placeholder: photo.minithumbnail?.data, kind: kind)
    }

    private func thumbnailCandidate(
        _ thumbnail: Thumbnail?,
        placeholder: Data?,
        kind: String,
    ) -> MediaCandidate? {
        guard let thumbnail else { return nil }
        return MediaCandidate(file: thumbnail.file, placeholder: placeholder, kind: kind)
    }

    private func isMediaContent(_ content: PushMessageContent) -> Bool {
        switch content {
        case .pushMessageContentAnimation,
             .pushMessageContentDocument,
             .pushMessageContentPhoto,
             .pushMessageContentSticker,
             .pushMessageContentVideo,
             .pushMessageContentVideoNote:
            true
        default:
            false
        }
    }

    private func isMediaContent(_ content: MessageContent) -> Bool {
        switch content {
        case .messageAnimation,
             .messageDocument,
             .messagePhoto,
             .messageSticker,
             .messageVideo,
             .messageVideoNote:
            true
        default:
            false
        }
    }

    private func notificationBody(for content: PushMessageContent) -> String? {
        switch content {
        case .pushMessageContentPhoto(let value):
            captionedMediaBody(icon: "🖼", caption: value.caption, fallback: "Photo")
        case .pushMessageContentVideo(let value):
            captionedMediaBody(icon: "📹", caption: value.caption, fallback: "Video")
        case .pushMessageContentAnimation(let value):
            captionedMediaBody(icon: "🎬", caption: value.caption, fallback: "GIF")
        case .pushMessageContentDocument:
            "📎 File"
        case .pushMessageContentSticker(let value):
            value.emoji.isEmpty ? "Sticker" : "\(value.emoji) Sticker"
        case .pushMessageContentVideoNote:
            "Video message"
        default:
            nil
        }
    }

    private func notificationBody(for content: MessageContent) -> String? {
        switch content {
        case .messagePhoto(let value):
            captionedMediaBody(icon: "🖼", caption: value.caption.text, fallback: "Photo")
        case .messageVideo(let value):
            captionedMediaBody(icon: "📹", caption: value.caption.text, fallback: "Video")
        case .messageAnimation(let value):
            captionedMediaBody(icon: "🎬", caption: value.caption.text, fallback: "GIF")
        case .messageDocument(let value):
            captionedMediaBody(
                icon: "📎",
                caption: value.caption.text,
                fallback: value.document.fileName.isEmpty ? "File" : value.document.fileName,
            )
        case .messageSticker(let value):
            value.sticker.emoji.isEmpty ? "Sticker" : "\(value.sticker.emoji) Sticker"
        case .messageVideoNote:
            "Video message"
        default:
            nil
        }
    }

    private func captionedMediaBody(icon: String, caption: String, fallback: String) -> String {
        "\(icon) \(caption.isEmpty ? fallback : caption)"
    }

    private func finish(_ result: ResolvedTelegramNotification?, reason: String) {
        stateLock.lock()
        guard !finished else {
            stateLock.unlock()
            return
        }
        finished = true
        let continuation = resolutionContinuation
        resolutionContinuation = nil
        stateLock.unlock()
        logger.log("rich_notification.tdlib_finished reason=\(reason, privacy: .public)")
        RichNotificationDiagnostics.record("tdlib_finished", fields: ["reason": reason])
        continuation?.resume(returning: result)
    }

    private func close() async {
        let manager = manager
        await Task.detached(priority: .utility) {
            manager.closeClients()
        }.value
    }
}

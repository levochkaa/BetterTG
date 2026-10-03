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

    private typealias Lifetime = RichNotificationSessionLifetime<ResolvedTelegramNotification>

    private let account: TelegramAccount
    private let payload: String
    private let metadata: RelayNotificationMetadata
    private let target: RichNotificationTarget?
    private let allowsQuickReply: Bool
    private let logger: os.Logger
    private let manager = TDLibClientManager()
    private let lifetime = Lifetime()
    private var previewObservation = RichNotificationPreviewPolicy.Observation()

    private var deniedResult: ResolvedTelegramNotification {
        ResolvedTelegramNotification(
            senderName: metadata.senderName?.isEmpty == false ? metadata.senderName! : "Telegram",
            conversationTitle: metadata.conversationTitle,
            senderAvatarData: nil,
            conversationAvatarData: nil,
            preview: .denied,
            body: nil,
            canQuickReply: allowsQuickReply && metadata.isQuickReplyCandidate,
        )
    }

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
        guard let target, target.expectedChatID != nil,
              target.matches(accountUserID: account.userID) else { return nil }
        return await withTaskCancellationHandler {
            let result = await withCheckedContinuation { continuation in
                guard lifetime.begin({ continuation.resume(returning: $0) }) else { return }
                guard lifetime.createClient({
                    manager.createClient { [weak self] data, client in
                        self?.handle(data: data, client: client)
                    }
                    .id
                }) else { return }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 14) { [weak self] in
                    self?.finish(nil, reason: "timeout")
                }
            }
            await close()
            return result
        } onCancel: {
            self.finish(nil, reason: "cancelled")
        }
    }

    private func handle(data: Data, client: TDLibClient) {
        guard lifetime.isCurrent(clientID: client.id),
              let update = try? client.decoder.decode(Update.self, from: data) else { return }
        if let target, lifetime.finish(deniedResult, clientID: client.id, when: {
            previewObservation.revokes(update, target: target)
        }) {
            logger.log("rich_notification.tdlib_finished reason=preview_revoked")
            return
        }
        switch update {
        case .updateAuthorizationState(let value):
            handle(authorizationState: value.authorizationState, client: client)
        case .updateNotificationGroup(let value):
            guard let target,
                  let notification = target.notification(in: value.addedNotifications, groupChatID: value.chatId)
            else { return }
            start(.resolve, client: client) { [self] ticket in
                guard isCurrent(ticket) else { return }
                guard let chat = try? await client.getChat(chatId: value.chatId), isCurrent(ticket),
                      target.matches(chat: chat, requestedChatID: value.chatId)
                else {
                    finish(nil, reason: "chat", ticket: ticket)
                    return
                }
                let resolved = await resolve(
                    notification: notification, chat: chat, target: target, client: client, ticket: ticket,
                )
                guard isCurrent(ticket) else { return }
                finish(resolved, reason: resolved == nil ? "unresolved" : "notification", ticket: ticket)
            }
        default:
            break
        }
    }

    private func handle(authorizationState: AuthorizationState, client: TDLibClient) {
        switch authorizationState {
        case .authorizationStateWaitTdlibParameters:
            start(.configure, client: client) { [self] ticket in
                await configure(client: client, ticket: ticket)
            }
        case .authorizationStateReady:
            start(.process, client: client) { [self] ticket in
                await process(client: client, ticket: ticket)
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

    private func start(
        _ role: Lifetime.Role, client: TDLibClient, operation: @escaping (Lifetime.Ticket) async -> Void,
    ) {
        guard let ticket = lifetime.reserve(role, clientID: client.id) else { return }
        let lifetime = lifetime
        let task = Task {
            guard !Task.isCancelled, lifetime.isCurrent(ticket) else { return }
            await operation(ticket)
            lifetime.complete(ticket)
        }
        lifetime.install(task, for: ticket)
    }

    private func isCurrent(_ ticket: Lifetime.Ticket) -> Bool {
        !Task.isCancelled && lifetime.isCurrent(ticket)
    }

    private func configure(client: TDLibClient, ticket: Lifetime.Ticket) async {
        guard isCurrent(ticket) else { return }
        do {
            let directory = try TelegramAccountRegistry().databaseDirectory(for: account.id)
            guard isCurrent(ticket) else { return }
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
            guard isCurrent(ticket) else { return }
            logger.error("rich_notification.tdlib_config_failed")
            finish(nil, reason: "configuration", ticket: ticket)
        }
    }

    private func process(client: TDLibClient, ticket: Lifetime.Ticket) async {
        guard isCurrent(ticket) else { return }
        do {
            _ = try await client.setOption(
                name: "notification_group_count_max",
                value: .optionValueInteger(.init(value: 20)),
            )
            guard isCurrent(ticket) else { return }
            _ = try await client.setOption(
                name: "notification_group_size_max",
                value: .optionValueInteger(.init(value: 10)),
            )
            guard isCurrent(ticket) else { return }
            _ = try await client.processPushNotification(payload: payload)
            guard isCurrent(ticket) else { return }
            logger.log("rich_notification.tdlib_processed")
        } catch {
            guard isCurrent(ticket) else { return }
            logger.log("rich_notification.tdlib_processing_waiting_for_updates")
        }
    }

    private func resolve(
        notification: TDLibKitDynamic.Notification,
        chat: Chat,
        target: RichNotificationTarget,
        client: TDLibClient,
        ticket: Lifetime.Ticket,
    ) async -> ResolvedTelegramNotification? {
        guard isCurrent(ticket), target.matches(notification: notification, groupChatID: chat.id),
              target.matches(chat: chat, requestedChatID: chat.id) else { return nil }
        let chatID = chat.id
        var senderID: MessageSender
        var senderName: String
        var media: MediaCandidate?
        var body: String?

        let selection = await RichNotificationPreviewPolicy.select(
            notification: notification, target: target, chatID: chatID,
            isCurrent: { self.isCurrent(ticket) },
            fetch: { await self.fetchMessage(chatID: chatID, target: target, client: client, ticket: ticket) },
        )
        guard isCurrent(ticket) else { return nil }
        if case .denied = selection {
            finish(deniedResult, reason: "concealed_message", ticket: ticket)
            return nil
        }

        switch notification.type {
        case .notificationTypeNewPushMessage(let value):
            senderID = value.senderId
            senderName = value.senderName
        case .notificationTypeNewMessage(let value):
            senderID = value.message.senderId
            senderName = metadata.senderName ?? "Telegram"
        default:
            return nil
        }

        if case .message(let message) = selection {
            senderID = message.senderId
            media = mediaCandidate(for: message.content)
            body = notificationBody(for: message.content)
        }
        if case .notificationTypeNewMessage = notification.type {
            senderName = await displayName(for: senderID, client: client, ticket: ticket) ?? senderName
        } else if case .message = selection {
            senderName = await displayName(for: senderID, client: client, ticket: ticket) ?? senderName
        }
        let expectsMedia: Bool =
            switch selection {
            case .message: true
            case .unresolved: metadata.expectsMedia
            case .denied, .nonMedia: false
            }
        guard isCurrent(ticket) else { return nil }
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
        async let senderAvatar = avatarData(for: resolvedSenderID, client: client, ticket: ticket)
        async let conversationAvatar = imageData(
            file: conversation.photo?.small,
            placeholder: conversation.photo?.minithumbnail?.data,
            client: client,
            ticket: ticket,
        )
        async let mediaData = imageData(
            file: resolvedMediaCandidate?.file,
            placeholder: resolvedMediaCandidate?.placeholder,
            client: client,
            ticket: ticket,
        )

        let senderAvatarData = await senderAvatar
        guard isCurrent(ticket) else { return nil }
        let resolvedSenderAvatar = senderAvatarData
            ?? RichNotificationCache.avatarData(for: metadata.sender, accountID: metadata.accountID)
        let conversationAvatarData = await conversationAvatar
        guard isCurrent(ticket) else { return nil }
        let resolvedConversationAvatar = conversationAvatarData
            ?? RichNotificationCache.avatarData(for: metadata.peer, accountID: metadata.accountID)
        let resolvedMedia = await mediaData
        guard isCurrent(ticket) else { return nil }
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
        guard isCurrent(ticket),
              RichNotificationCache.matchesAccount(metadata.accountID, boundUserID: account.userID) else { return nil }
        guard lifetime.publish(ticket, {
            if let resolvedSenderAvatar {
                RichNotificationCache.cacheAvatar(
                    resolvedSenderAvatar,
                    for: metadata.sender,
                    accountID: metadata.accountID,
                )
            }
            if let resolvedConversationAvatar {
                RichNotificationCache.cacheAvatar(
                    resolvedConversationAvatar, for: metadata.peer, accountID: metadata.accountID,
                )
            }
        }) else { return nil }

        return ResolvedTelegramNotification(
            senderName: senderName.isEmpty ? (metadata.senderName ?? "Telegram") : senderName,
            conversationTitle: conversation.title,
            senderAvatarData: resolvedSenderAvatar,
            conversationAvatarData: resolvedConversationAvatar,
            preview: selection.preview(data: resolvedMedia),
            body: selection.preview(data: nil).bodyOverride(body),
            canQuickReply: canQuickReply,
        )
    }

    private func fetchMessage(
        chatID: Int64,
        target: RichNotificationTarget,
        client: TDLibClient,
        ticket: Lifetime.Ticket,
    ) async -> Message? {
        guard isCurrent(ticket) else { return nil }
        let messageIDs = [target.messageID]

        for messageID in messageIDs {
            if let message = try? await client.getMessage(chatId: chatID, messageId: messageID),
               isCurrent(ticket),
               target.matches(message: message, chatID: chatID)
            {
                logger.log("rich_notification.message_fetched source=get_message")
                RichNotificationDiagnostics.record("message_fetched", fields: ["source": "get_message"])
                return message
            }
            guard isCurrent(ticket) else { return nil }
            if let history = try? await client.getChatHistory(
                chatId: chatID,
                fromMessageId: messageID,
                limit: 3,
                offset: -1,
                onlyLocal: false,
            ), isCurrent(ticket),
            let message = history.messages?.first(where: { target.matches(message: $0, chatID: chatID) }) {
                logger.log("rich_notification.message_fetched source=chat_history")
                RichNotificationDiagnostics.record("message_fetched", fields: ["source": "chat_history"])
                return message
            }
        }

        for _ in 0..<3 {
            guard isCurrent(ticket) else { return nil }
            if let history = try? await client.getChatHistory(
                chatId: chatID,
                fromMessageId: 0,
                limit: 10,
                offset: 0,
                onlyLocal: false,
            ), isCurrent(ticket), let messages = history.messages {
                if let message = messages.first(where: { target.matches(message: $0, chatID: chatID) }) {
                    logger.log("rich_notification.message_fetched source=latest_history")
                    RichNotificationDiagnostics.record("message_fetched", fields: ["source": "latest_history"])
                    return message
                }
            }
            for messageID in messageIDs {
                guard isCurrent(ticket) else { return nil }
                if let message = try? await client.getMessage(chatId: chatID, messageId: messageID),
                   isCurrent(ticket),
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
            guard isCurrent(ticket) else { return nil }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard isCurrent(ticket) else { return nil }
        logger.log("rich_notification.message_fetched source=network success=false")
        RichNotificationDiagnostics.record(
            "message_fetched",
            fields: ["source": "network", "success": "false"],
        )
        return nil
    }

    private func avatarData(for sender: MessageSender, client: TDLibClient, ticket: Lifetime.Ticket) async -> Data? {
        guard isCurrent(ticket) else { return nil }
        switch sender {
        case .messageSenderUser(let value):
            guard let user = try? await client.getUser(userId: value.userId), isCurrent(ticket) else { return nil }
            return await imageData(
                file: user.profilePhoto?.small,
                placeholder: user.profilePhoto?.minithumbnail?.data,
                client: client,
                ticket: ticket,
            )
        case .messageSenderChat(let value):
            guard let chat = try? await client.getChat(chatId: value.chatId), isCurrent(ticket) else { return nil }
            return await imageData(
                file: chat.photo?.small,
                placeholder: chat.photo?.minithumbnail?.data,
                client: client,
                ticket: ticket,
            )
        }
    }

    private func displayName(for sender: MessageSender, client: TDLibClient, ticket: Lifetime.Ticket) async -> String? {
        guard isCurrent(ticket) else { return nil }
        switch sender {
        case .messageSenderUser(let value):
            guard let user = try? await client.getUser(userId: value.userId), isCurrent(ticket) else { return nil }
            let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            return name.isEmpty ? nil : name
        case .messageSenderChat(let value):
            let chat = try? await client.getChat(chatId: value.chatId)
            return isCurrent(ticket) ? chat?.title : nil
        }
    }

    private func imageData(
        file: File?,
        placeholder: Data?,
        client: TDLibClient,
        ticket: Lifetime.Ticket,
    ) async -> Data? {
        guard isCurrent(ticket) else { return nil }
        if let file {
            let resolved = await (try? client.downloadFile(
                fileId: file.id,
                limit: 0,
                offset: 0,
                priority: 32,
                synchronous: true,
            )) ?? file
            guard isCurrent(ticket) else { return nil }
            if resolved.local.isDownloadingCompleted,
               let data = try? Data(contentsOf: URL(fileURLWithPath: resolved.local.path)),
               RichNotificationCache.normalizedJPEG(data, maximumPixelSize: 1280) != nil
            {
                return data
            }
        }
        return placeholder
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

    private func notificationBody(for content: MessageContent) -> String? {
        switch content {
        case .messagePhoto(let value):
            RichNotificationPreviewPolicy.captionedBody(icon: "🖼", caption: value.caption, fallback: "Photo")
        case .messageVideo(let value):
            RichNotificationPreviewPolicy.captionedBody(icon: "📹", caption: value.caption, fallback: "Video")
        case .messageAnimation(let value):
            RichNotificationPreviewPolicy.captionedBody(icon: "🎬", caption: value.caption, fallback: "GIF")
        case .messageDocument(let value):
            RichNotificationPreviewPolicy.captionedBody(
                icon: "📎",
                caption: value.caption,
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

    private func finish(_ result: ResolvedTelegramNotification?, reason: String, ticket: Lifetime.Ticket? = nil) {
        guard lifetime.finish(result, ticket: ticket) else { return }
        logger.log("rich_notification.tdlib_finished reason=\(reason, privacy: .public)")
        RichNotificationDiagnostics.record("tdlib_finished", fields: ["reason": reason])
    }

    private func close() async {
        guard lifetime.claimClose() else { return }
        let manager = manager
        // Pinned TDLibKit async RPCs do not observe Task cancellation. Close
        // without joining those tasks, and retain the process lock until closed.
        await Task.detached(priority: .utility) {
            manager.closeClients()
        }.value
    }
}

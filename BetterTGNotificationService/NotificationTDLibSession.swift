// NotificationTDLibSession.swift

import Foundation
import os.log
import TDLibKitDynamic

final class NotificationTDLibSession: @unchecked Sendable {
    // MARK: Private

    private struct MediaCandidate {
        let file: File
        let placeholder: Data?
    }

    private let account: TelegramAccount
    private let payload: String
    private let metadata: RelayNotificationMetadata
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
        self.allowsQuickReply = allowsQuickReply
        self.logger = logger
    }

    // MARK: Internal

    func resolve() async -> ResolvedTelegramNotification? {
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
            guard let notification = value.addedNotifications.last(where: matchesExpectedMessage)
                ?? value.addedNotifications.last
            else { return }
            Task { [weak self] in
                guard let self else { return }
                let resolved = await resolve(notification: notification, chatID: value.chatId, client: client)
                finish(resolved, reason: resolved == nil ? "unresolved" : "notification")
            }
        default:
            break
        }
    }

    private func matchesExpectedMessage(_ notification: TDLibKitDynamic.Notification) -> Bool {
        guard let serverMessageID = metadata.serverMessageID else { return true }
        switch notification.type {
        case .notificationTypeNewPushMessage(let value):
            return value.messageId >> 20 == serverMessageID
        case .notificationTypeNewMessage(let value):
            return value.message.id >> 20 == serverMessageID
        default:
            return false
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
        chatID: Int64,
        client: TDLibClient,
    ) async -> ResolvedTelegramNotification? {
        let senderID: MessageSender
        let senderName: String
        let media: MediaCandidate?

        switch notification.type {
        case .notificationTypeNewPushMessage(let value):
            senderID = value.senderId
            senderName = value.senderName
            media = mediaCandidate(for: value.content)
        case .notificationTypeNewMessage(let value):
            senderID = value.message.senderId
            senderName = await displayName(for: value.message.senderId, client: client)
                ?? metadata.senderName
                ?? "Telegram"
            media = mediaCandidate(for: value.message.content)
        default:
            return nil
        }

        let conversation = try? await client.getChat(chatId: chatID)
        async let senderAvatar = avatarData(for: senderID, client: client)
        async let conversationAvatar = imageData(
            file: conversation?.photo?.small,
            placeholder: conversation?.photo?.minithumbnail?.data,
            client: client,
        )
        async let mediaData = imageData(file: media?.file, placeholder: media?.placeholder, client: client)

        let resolvedSenderAvatar = await senderAvatar
            ?? RichNotificationCache.avatarData(for: metadata.sender)
        let resolvedConversationAvatar = await conversationAvatar
            ?? RichNotificationCache.avatarData(for: metadata.peer)
        let resolvedMedia = await mediaData
        let canQuickReply =
            if allowsQuickReply, let conversation {
                await QuickReplyNotification.canSendText(to: conversation, using: client)
            } else {
                false
            }
        if let resolvedMedia, let message = metadata.messageReference {
            RichNotificationCache.cacheMedia(resolvedMedia, for: message)
        }
        if let resolvedSenderAvatar {
            RichNotificationCache.cacheAvatar(resolvedSenderAvatar, for: metadata.sender)
        }
        if let resolvedConversationAvatar {
            RichNotificationCache.cacheAvatar(resolvedConversationAvatar, for: metadata.peer)
        }

        return ResolvedTelegramNotification(
            senderName: senderName.isEmpty ? (metadata.senderName ?? "Telegram") : senderName,
            conversationTitle: conversation?.title ?? metadata.conversationTitle,
            senderAvatarData: resolvedSenderAvatar,
            conversationAvatarData: resolvedConversationAvatar,
            mediaData: resolvedMedia,
            canQuickReply: canQuickReply,
        )
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
            value.photo.flatMap(photoCandidate)
        case .pushMessageContentVideo(let value):
            value.video.flatMap { thumbnailCandidate($0.thumbnail, placeholder: $0.minithumbnail?.data) }
        case .pushMessageContentAnimation(let value):
            value.animation.flatMap { thumbnailCandidate($0.thumbnail, placeholder: $0.minithumbnail?.data) }
        case .pushMessageContentDocument(let value):
            value.document.flatMap { thumbnailCandidate($0.thumbnail, placeholder: $0.minithumbnail?.data) }
        case .pushMessageContentSticker(let value):
            value.sticker.flatMap { thumbnailCandidate($0.thumbnail, placeholder: nil) }
        case .pushMessageContentVideoNote(let value):
            value.videoNote.flatMap { thumbnailCandidate($0.thumbnail, placeholder: $0.minithumbnail?.data) }
        default:
            nil
        }
    }

    private func mediaCandidate(for content: MessageContent) -> MediaCandidate? {
        switch content {
        case .messagePhoto(let value):
            photoCandidate(value.photo)
        case .messageVideo(let value):
            thumbnailCandidate(value.video.thumbnail, placeholder: value.video.minithumbnail?.data)
        case .messageAnimation(let value):
            thumbnailCandidate(value.animation.thumbnail, placeholder: value.animation.minithumbnail?.data)
        case .messageDocument(let value):
            thumbnailCandidate(value.document.thumbnail, placeholder: value.document.minithumbnail?.data)
        case .messageSticker(let value):
            thumbnailCandidate(value.sticker.thumbnail, placeholder: nil)
        case .messageVideoNote(let value):
            thumbnailCandidate(value.videoNote.thumbnail, placeholder: value.videoNote.minithumbnail?.data)
        default:
            nil
        }
    }

    private func photoCandidate(_ photo: Photo) -> MediaCandidate? {
        guard let size = photo.sizes.min(by: { lhs, rhs in
            abs(max(lhs.width, lhs.height) - 1280) < abs(max(rhs.width, rhs.height) - 1280)
        }) else { return nil }
        return MediaCandidate(file: size.photo, placeholder: photo.minithumbnail?.data)
    }

    private func thumbnailCandidate(_ thumbnail: Thumbnail?, placeholder: Data?) -> MediaCandidate? {
        guard let thumbnail else { return nil }
        return MediaCandidate(file: thumbnail.file, placeholder: placeholder)
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
        continuation?.resume(returning: result)
    }

    private func close() async {
        let manager = manager
        await Task.detached(priority: .utility) {
            manager.closeClients()
        }.value
    }
}

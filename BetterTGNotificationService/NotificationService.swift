// NotificationService.swift

import os.log
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    // MARK: Private

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.levochkaaa.BetterTG.NotificationService",
        category: "NotificationService",
    )
    private let completionLock = NSLock()
    private var processingTask: Task<Void, Never>?
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestContent: UNNotificationContent?

    // MARK: Internal

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void,
    ) {
        completionLock.lock()
        self.contentHandler = contentHandler
        bestContent = request.content
        completionLock.unlock()

        guard let metadata = RelayNotificationMetadata(userInfo: request.content.userInfo) else {
            finish(with: request.content)
            return
        }
        logger.log("rich_notification.received event=\(metadata.event ?? "unknown", privacy: .public)")
        RichNotificationDiagnostics.record("received", fields: ["event": metadata.event ?? "unknown"])

        processingTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let fallback = RichNotificationContentBuilder.fallback(
                metadata: metadata,
                canQuickReply: canQuickReplyUsingMetadata(metadata),
            )
            var resolved = fallback

            do {
                guard !Task.isCancelled else { return }
                logger.log("rich_notification.tdlib_lock_wait_started")
                RichNotificationDiagnostics.record("tdlib_lock_wait_started")
                if let processLock = try TDLibProcessLock.acquire(waitingUpTo: 6) {
                    defer { processLock.unlock() }
                    guard !Task.isCancelled else { return }
                    logger.log("rich_notification.tdlib_lock_acquired")
                    RichNotificationDiagnostics.record("tdlib_lock_acquired")
                    if let token = metadata.notificationPayloadToken,
                       let state = try TelegramAccountRegistry().loadExisting(),
                       let account = state.accounts.first(where: {
                           RichNotificationCache.matchesAccount(metadata.accountID, boundUserID: $0.userID)
                       })
                    {
                        let payload = try await NotificationPayloadClient().fetch(token: token)
                        guard !Task.isCancelled else { return }
                        logger.log("rich_notification.payload_fetched")
                        RichNotificationDiagnostics.record("payload_fetched")
                        if let tdlibResolved = await NotificationTDLibSession(
                            account: account,
                            payload: payload,
                            metadata: metadata,
                            allowsQuickReply: account.id == state.activeAccountID,
                            logger: logger,
                        ).resolve() {
                            resolved = tdlibResolved
                            logger.log("rich_notification.resolved source=tdlib")
                        } else {
                            logger.log("rich_notification.resolved source=cache_after_tdlib")
                        }
                    } else {
                        logger.log("rich_notification.resolved source=cache_missing_session")
                    }
                } else {
                    logger.log("rich_notification.tdlib_lock_timed_out")
                    RichNotificationDiagnostics.record("tdlib_lock_timed_out")
                    resolved = await waitForCachedMedia(
                        metadata: metadata,
                        fallback: fallback,
                        timeout: 4,
                    )
                    logger.log("rich_notification.resolved source=cache_after_lock_timeout")
                    RichNotificationDiagnostics.record("resolved", fields: ["source": "cache_after_lock_timeout"])
                }
            } catch {
                logger
                    .error(
                        "rich_notification.resolved source=cache error=\(error.localizedDescription, privacy: .public)",
                    )
                RichNotificationDiagnostics.record("resolved_error")
            }

            guard !Task.isCancelled else { return }
            let content = RichNotificationContentBuilder.content(
                from: request.content,
                metadata: metadata,
                resolved: resolved,
            )
            logger.log(
                "rich_notification.attachment_added success=\(!content.attachments.isEmpty, privacy: .public)",
            )
            RichNotificationDiagnostics.record(
                "attachment_added",
                fields: ["success": String(!content.attachments.isEmpty)],
            )
            finish(with: content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        logger.error("rich_notification.expired")
        RichNotificationDiagnostics.record("expired")
        processingTask?.cancel()
        finish(with: nil)
    }

    private func canQuickReplyUsingMetadata(_ metadata: RelayNotificationMetadata) -> Bool {
        guard metadata.isQuickReplyCandidate,
              let state = try? TelegramAccountRegistry().loadExisting(),
              let activeAccount = state.accounts.first(where: { $0.id == state.activeAccountID }),
              RichNotificationCache.matchesAccount(metadata.accountID, boundUserID: activeAccount.userID)
        else { return false }
        return true
    }

    private func waitForCachedMedia(
        metadata: RelayNotificationMetadata,
        fallback: ResolvedTelegramNotification,
        timeout: TimeInterval,
    ) async -> ResolvedTelegramNotification {
        guard metadata.expectsMedia, let reference = metadata.messageReference else { return fallback }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let url = RichNotificationCache.mediaURL(for: reference, accountID: metadata.accountID),
               let data = try? Data(contentsOf: url)
            {
                logger.log("rich_notification.media_resolved source=shared_cache")
                RichNotificationDiagnostics.record("media_resolved", fields: ["source": "shared_cache"])
                return ResolvedTelegramNotification(
                    senderName: fallback.senderName,
                    conversationTitle: fallback.conversationTitle,
                    senderAvatarData: fallback.senderAvatarData,
                    conversationAvatarData: fallback.conversationAvatarData,
                    mediaData: data,
                    body: fallback.body,
                    canQuickReply: fallback.canQuickReply,
                )
            }
            try? await Task.sleep(for: .milliseconds(100))
        } while !Task.isCancelled && Date() < deadline
        logger.log("rich_notification.media_resolved source=shared_cache success=false")
        RichNotificationDiagnostics.record(
            "media_resolved",
            fields: ["source": "shared_cache", "success": "false"],
        )
        return fallback
    }

    private func finish(with content: UNNotificationContent?) {
        completionLock.lock()
        guard let handler = contentHandler else {
            completionLock.unlock()
            return
        }
        contentHandler = nil
        let finalContent = content ?? bestContent
        bestContent = finalContent
        completionLock.unlock()

        if let finalContent {
            handler(finalContent)
        }
    }
}

// NotificationService.swift

import os.log
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private typealias Requests = RichNotificationRequestCoordinator<UNNotificationContent>

    // MARK: Private

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.levochkaaa.BetterTG.NotificationService",
        category: "NotificationService",
    )
    private let requests = Requests()

    // MARK: Internal

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void,
    ) {
        let ticket = requests.begin(original: request.content, handler: contentHandler)
        guard requests.isCurrent(ticket) else { return }

        guard let metadata = RelayNotificationMetadata(userInfo: request.content.userInfo) else {
            requests.finish(ticket) { request.content }
            return
        }
        logger.log("rich_notification.received event=\(metadata.event ?? "unknown", privacy: .public)")
        RichNotificationDiagnostics.record("received", fields: ["event": metadata.event ?? "unknown"])

        let processingTask = Task { [weak self] in
            guard let self, isCurrent(ticket) else { return }
            let fallback = RichNotificationContentBuilder.fallback(
                metadata: metadata,
                canQuickReply: canQuickReplyUsingMetadata(metadata),
            )
            var resolved = fallback
            var pushText: TelegramPushText?

            do {
                guard isCurrent(ticket) else { return }
                logger.log("rich_notification.tdlib_lock_wait_started")
                RichNotificationDiagnostics.record("tdlib_lock_wait_started")
                if let processLock = try TDLibProcessLock.acquire(waitingUpTo: 6) {
                    defer { processLock.unlock() }
                    guard isCurrent(ticket) else { return }
                    logger.log("rich_notification.tdlib_lock_acquired")
                    RichNotificationDiagnostics.record("tdlib_lock_acquired")
                    if let token = metadata.notificationPayloadToken,
                       let state = try TelegramAccountRegistry().loadExisting(),
                       let account = state.accounts.first(where: {
                           RichNotificationCache.matchesAccount(metadata.accountID, boundUserID: $0.userID)
                       })
                    {
                        let payload = try await NotificationPayloadClient().fetch(token: token)
                        guard isCurrent(ticket) else { return }
                        pushText = TelegramPushText(payload: payload, strings: .load())
                        logger.log("rich_notification.payload_fetched")
                        RichNotificationDiagnostics.record("payload_fetched")
                        if let tdlibResolved = await NotificationTDLibSession(
                            account: account,
                            payload: payload,
                            metadata: metadata,
                            allowsQuickReply: account.id == state.activeAccountID,
                            logger: logger,
                        ).resolve() {
                            guard isCurrent(ticket) else { return }
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
                    // Raw JPEGs have no concealment/revision evidence. Leave
                    // media unresolved until the verified v2 cache is available.
                    logger.log("rich_notification.resolved source=metadata_after_lock_timeout")
                    RichNotificationDiagnostics.record("resolved", fields: ["source": "metadata_after_lock_timeout"])
                }
            } catch {
                logger
                    .error(
                        "rich_notification.resolved source=cache error=\(error.localizedDescription, privacy: .public)",
                    )
                RichNotificationDiagnostics.record("resolved_error")
            }

            guard isCurrent(ticket) else { return }
            requests.finish(ticket) {
                let content = RichNotificationContentBuilder.content(
                    from: request.content,
                    metadata: metadata,
                    resolved: resolved,
                    pushText: pushText,
                )
                self.logger.log(
                    "rich_notification.attachment_added success=\(!content.attachments.isEmpty, privacy: .public)",
                )
                RichNotificationDiagnostics.record(
                    "attachment_added",
                    fields: ["success": String(!content.attachments.isEmpty)],
                )
                return content
            }
        }
        requests.install(processingTask, for: ticket)
    }

    override func serviceExtensionTimeWillExpire() {
        logger.error("rich_notification.expired")
        RichNotificationDiagnostics.record("expired")
        requests.expire()
    }

    private func isCurrent(_ ticket: Requests.Ticket) -> Bool {
        !Task.isCancelled && requests.isCurrent(ticket)
    }

    private func canQuickReplyUsingMetadata(_ metadata: RelayNotificationMetadata) -> Bool {
        guard metadata.isQuickReplyCandidate,
              let state = try? TelegramAccountRegistry().loadExisting(),
              let activeAccount = state.accounts.first(where: { $0.id == state.activeAccountID }),
              RichNotificationCache.matchesAccount(metadata.accountID, boundUserID: activeAccount.userID)
        else { return false }
        return true
    }
}

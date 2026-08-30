// NotificationService.swift

import os.log
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
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

        processingTask = Task { [weak self] in
            guard let self else { return }
            let fallback = RichNotificationContentBuilder.fallback(metadata: metadata)
            var resolved = fallback

            do {
                if let processLock = try TDLibProcessLock.acquire(wait: false) {
                    defer { processLock.unlock() }
                    if let token = metadata.notificationPayloadToken,
                       let state = try TelegramAccountRegistry().loadExisting(),
                       let account = state.accounts.first(where: { $0.userID == metadata.accountID })
                       ?? state.accounts.first(where: { $0.id == state.activeAccountID })
                    {
                        let payload = try await NotificationPayloadClient().fetch(token: token)
                        if let tdlibResolved = await NotificationTDLibSession(
                            account: account,
                            payload: payload,
                            metadata: metadata,
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
                    logger.log("rich_notification.resolved source=cache_main_app_active")
                }
            } catch {
                logger
                    .error(
                        "rich_notification.resolved source=cache error=\(error.localizedDescription, privacy: .public)",
                    )
            }

            let content = RichNotificationContentBuilder.content(
                from: request.content,
                metadata: metadata,
                resolved: resolved,
            )
            finish(with: content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        logger.error("rich_notification.expired")
        processingTask?.cancel()
        finish(with: nil)
    }

    // MARK: Private

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.levochkaaa.BetterTG.NotificationService",
        category: "NotificationService",
    )
    private let completionLock = NSLock()
    private var processingTask: Task<Void, Never>?
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestContent: UNNotificationContent?

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

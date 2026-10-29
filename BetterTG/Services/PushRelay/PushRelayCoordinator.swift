// PushRelayCoordinator.swift

import Combine
import Foundation
import TDLibKit
import UIKit
import UserNotifications

@MainActor final class PushRelayCoordinator: NSObject, UNUserNotificationCenterDelegate {
    // MARK: Internal

    static let shared = PushRelayCoordinator()

    // MARK: Private

    private let configuration: PushRelayConfiguration?
    private let stateStore = PushRelayStateStore()
    private let api: PushRelayAPIClient?
    private let appAttest: AppAttestClient?
    private var apnsToken: String?
    private var telegramReady = false
    private var authorizationEpoch = 0
    private var registeredAuthorizationEpoch: Int?
    private var started = false
    private var synchronizationTask: Task<Void, Never>?
    private var synchronizationRetryTask: Task<Void, Never>?
    private var registrationRefreshTask: Task<Void, Never>?
    private var revocationRetryTask: Task<Void, Never>?
    private var synchronizationRequested = false
    /// A tapped notification waiting for its account's client to be ready.
    private var routeOpening: AnyCancellable?
    private var lastOpenedRoute: PushNotificationRoute?
    private var handledQuickReplyRequestIdentifiers = Set<String>()
    private var cancellables = Set<AnyCancellable>()

    /// Whether the build has a relay, so Settings can offer to turn it off.
    var isAvailable: Bool { configuration != nil }

    var isEnabled: Bool { PushRelaySettings.isEnabled }

    override private init() {
        self.configuration = .current
        if let configuration {
            let api = PushRelayAPIClient(baseURL: configuration.baseURL)
            self.api = api
            self.appAttest = AppAttestClient(stateStore: stateStore)
        } else {
            self.api = nil
            self.appAttest = nil
        }
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        configureNotificationCategories(center: center)

        nc.publisher(&cancellables, for: .appLanguageChanged) { [weak self] _ in
            self?.configureNotificationCategories(center: .current())
        }

        nc
            .publisher(for: .authorizationStateReady)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if !telegramReady {
                    authorizationEpoch &+= 1
                }
                telegramReady = true
                log("Push relay TDLib authorization is ready")
                scheduleSynchronization()
            }
            .store(in: &cancellables)

        nc
            .publisher(for: .activeTelegramAccountChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                telegramReady = false
                registeredAuthorizationEpoch = nil
                registrationRefreshTask?.cancel()
                synchronizationRetryTask?.cancel()
                synchronizationRetryTask = nil
            }
            .store(in: &cancellables)

        nc
            .publisher(for: .authorizationStateLoggingOut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                telegramReady = false
                registeredAuthorizationEpoch = nil
                registrationRefreshTask?.cancel()
            }
            .store(in: &cancellables)

        guard configuration != nil else {
            log("Push relay disabled: BetterTGRelayBaseURL is not configured")
            return
        }

        if let configuration {
            PushRelaySharedConfiguration.store(baseURL: configuration.baseURL)
        }

        log("Push relay enabled: \(configuration?.baseURL.absoluteString ?? "unknown URL")")

        if !PushRelaySettings.isEnabled {
            // Finishes a deletion that failed before.
            scheduleSynchronization()
        }

        Task {
            await retryPendingRevocation()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                let settings = await center.notificationSettings()
                log(
                    "Notification authorization completed: granted=\(granted), status=\(settings.authorizationStatus.rawValue)",
                )
            } catch {
                log("Notification authorization failed: \(error.localizedDescription)")
            }
            log("Requesting APNs device token")
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// The synchronization registers with the relay or deletes the device's data from it, so a switch waits for a
    /// registration still running.
    func setEnabled(_ enabled: Bool) {
        guard PushRelaySettings.isEnabled != enabled else { return }
        PushRelaySettings.isEnabled = enabled
        log("Push relay \(enabled ? "enabled" : "disabled") in Settings")
        registrationRefreshTask?.cancel()
        registrationRefreshTask = nil
        registeredAuthorizationEpoch = nil
        scheduleSynchronization()
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        apnsToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        log(
            "APNs device token received: bytes=\(deviceToken.count), environment=\(RelayAPNsEnvironment.current.rawValue)",
        )
        scheduleSynchronization()
    }

    func didFailToRegisterForRemoteNotifications(_ error: any Swift.Error) {
        log("APNs registration failed: \(error.localizedDescription)")
    }

    func handleNotificationResponse(userInfo: [AnyHashable: Any]) {
        guard let route = PushNotificationRoute(userInfo: userInfo) else { return }
        log("Push notification response received: event=\(route.event ?? "unknown")")
        openWhenReady(route)
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) async {
        if response.actionIdentifier == QuickReplyNotification.actionIdentifier {
            guard let response = response as? UNTextInputNotificationResponse,
                  !response.userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let route = PushNotificationRoute(
                      userInfo: response.notification.request.content.userInfo,
                  )
            else { return }
            if handledQuickReplyRequestIdentifiers.count >= 128 {
                handledQuickReplyRequestIdentifiers.removeAll(keepingCapacity: true)
            }
            guard handledQuickReplyRequestIdentifiers.insert(
                response.notification.request.identifier,
            )
            .inserted else { return }
            await sendQuickReply(response.userText, route: route)
        } else {
            handleNotificationResponse(userInfo: response.notification.request.content.userInfo)
        }
    }

    func handleBackgroundNotification(userInfo: [AnyHashable: Any]) async -> Bool {
        guard let stateRoute = PushNotificationRoute(userInfo: userInfo) else {
            log("Background push received without a recognized route")
            return false
        }
        log("Background push received: event=\(stateRoute.event ?? "unknown")")
        guard ["MESSAGE_DELETED", "READ_HISTORY", "READ_REACTION"].contains(stateRoute.event) else {
            return false
        }

        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let identifiers = delivered.compactMap { notification -> String? in
            guard let messageRoute = PushNotificationRoute(
                userInfo: notification.request.content.userInfo,
            ),
                  stateRoute.refersToSameConversation(as: messageRoute),
                  let messageID = messageRoute.serverMessageID
            else { return nil }

            switch stateRoute.event {
            case "READ_HISTORY":
                guard let maxID = stateRoute.maxID, messageID <= maxID else { return nil }
            case "MESSAGE_DELETED",
                 "READ_REACTION":
                guard stateRoute.deletedMessageIDs.contains(messageID) else { return nil }
            default:
                return nil
            }
            return notification.request.identifier
        }
        guard !identifiers.isEmpty else { return false }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        return true
    }

    func prepareForLogout(using client: TDLibClient) async {
        log("Push relay logout cleanup started")
        telegramReady = false
        registeredAuthorizationEpoch = nil
        registrationRefreshTask?.cancel()
        synchronizationRetryTask?.cancel()
        synchronizationRetryTask = nil

        guard let api else {
            return
        }
        do {
            var state = try await stateStore.load()
            guard let installation = state.installation,
                  let subscription = state.subscription
            else {
                try await clearSubscriptionState()
                log("Push relay logout cleanup completed without an active subscription")
                return
            }

            state.pendingSubscriptionRevocation = true
            try await stateStore.save(state)
            do {
                try await deregisterFromTDLib(subscription, using: client)
            } catch {
                log("TDLib Web Push logout deregistration failed: \(error.localizedDescription)")
            }
            try await deleteTelegramSubscriptionIfPresent(
                api: api,
                subscription: subscription,
                installation: installation,
            )
            try await clearSubscriptionState()
            log("Push relay logout cleanup completed")
        } catch {
            log("Push relay logout cleanup failed: \(error.localizedDescription)")
            scheduleRevocationRetry()
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (Int) -> Void,
    ) {
        let route = PushNotificationRoute(userInfo: notification.request.content.userInfo)
        if let route {
            log("Foreground push received: event=\(route.event ?? "unknown")")
        } else {
            log("Foreground push received without a recognized route")
        }
        // The relay sends a silent message without a sound.
        let isSilent = notification.request.content.sound == nil
        Task { @MainActor in
            let options = InAppNotificationPresentation.options(for: route, isSilent: isSilent)
            completionHandler(Int(options.rawValue))
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
    ) async {
        await handleNotificationResponse(response)
    }

    private func configureNotificationCategories(center: UNUserNotificationCenter) {
        let replyAction = UNTextInputNotificationAction(
            identifier: QuickReplyNotification.actionIdentifier,
            title: L10n.telegram("Conversation.ContextMenuReply"),
            options: [],
            textInputButtonTitle: L10n.telegram("Conversation.ContextMenuReply"),
            textInputPlaceholder: L10n.telegram("Conversation.InputTextPlaceholder"),
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: QuickReplyNotification.messageCategoryIdentifier,
                actions: [],
                intentIdentifiers: [],
            ),
            UNNotificationCategory(
                identifier: QuickReplyNotification.categoryIdentifier,
                actions: [replyAction],
                intentIdentifiers: [],
            ),
        ])
    }

    private func scheduleSynchronization() {
        synchronizationRequested = true
        guard synchronizationTask == nil else { return }
        synchronizationTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                synchronizationRequested = false
                do {
                    try await synchronizeWithRecovery()
                    synchronizationRetryTask?.cancel()
                    synchronizationRetryTask = nil
                } catch {
                    log("Push relay synchronization failed: \(error.localizedDescription)")
                    scheduleSynchronizationRetry()
                }
            } while synchronizationRequested
            synchronizationTask = nil
        }
    }

    private func synchronizeWithRecovery() async throws {
        do {
            try await synchronize()
        } catch let error as RelayAPIError where error.statusCode == 401 {
            try await stateStore.update {
                $0.installation = nil
                $0.subscription = nil
                $0.apnsToken = nil
                $0.lastTDLibRegistrationAt = nil
                $0.registeredTelegramUserId = nil
                $0.pushReceiverId = nil
                $0.pendingSubscriptionRevocation = false
            }
            registeredAuthorizationEpoch = nil
            try await synchronize()
        }
    }

    private func synchronize() async throws {
        if !PushRelaySettings.isEnabled {
            guard let api else { return }
            try await deleteRelayData(api: api)
            return
        }
        guard telegramReady else {
            log("Push relay synchronization waiting for TDLib authorization")
            return
        }
        guard let apnsToken else {
            log("Push relay synchronization waiting for APNs device token")
            return
        }
        guard let api, let appAttest else {
            log("Push relay synchronization skipped: relay is not configured")
            return
        }

        var state = try await stateStore.load()
        log(
            "Push relay synchronization started: installation=\(state.installation != nil), subscription=\(state.subscription != nil)",
        )
        if state.pendingSubscriptionRevocation,
           state.installation != nil,
           state.subscription != nil
        {
            try await revokePendingSubscription(api: api)
            state = try await stateStore.load()
        }

        if state.installation == nil {
            log("Creating push relay installation")
            if state.installationIdempotencyKey == nil {
                state.installationIdempotencyKey = UUID().uuidString.lowercased()
                try await stateStore.save(state)
            }
            guard let idempotencyKey = state.installationIdempotencyKey else { return }
            let signedRequest = try await appAttest.signedInstallationRequest(
                api: api,
                apnsToken: apnsToken,
            )
            let credentials: RelayInstallationCredentials
            do {
                credentials = try await api.createInstallation(
                    signedRequest: signedRequest,
                    idempotencyKey: idempotencyKey,
                )
            } catch let error as RelayAPIError where error.statusCode == 401 {
                try await appAttest.resetKey()
                let retry = try await appAttest.signedInstallationRequest(
                    api: api,
                    apnsToken: apnsToken,
                )
                credentials = try await api.createInstallation(
                    signedRequest: retry,
                    idempotencyKey: idempotencyKey,
                )
            }
            state = try await stateStore.load()
            state.installation = credentials
            state.apnsToken = apnsToken
            state.installationIdempotencyKey = nil
            try await stateStore.save(state)
            log("Push relay installation created")
        }

        guard let installation = state.installation else { return }
        if state.apnsToken != apnsToken {
            log("Updating push relay APNs device token")
            try await api.updateAPNsToken(
                installation: installation,
                request: RelayUpdateAPNsTokenRequest(
                    apnsToken: apnsToken,
                    apnsEnvironment: .current,
                    appVersion: Utils.applicationVersion,
                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                ),
            )
            state.apnsToken = apnsToken
            try await stateStore.save(state)
            log("Push relay APNs device token updated")
        }

        if state.subscription == nil {
            log("Creating Telegram Web Push subscription")
            state.subscription = try await api.createTelegramSubscription(installation: installation)
            try await stateStore.save(state)
            log("Telegram Web Push subscription created")
        }

        guard telegramReady else {
            log("Push relay synchronization stopped because TDLib authorization changed")
            return
        }
        guard let subscription = state.subscription else { return }
        let currentUser = try await td.getMe()
        let authorizationChanged = registeredAuthorizationEpoch != authorizationEpoch
        let registrationExpired = state.lastTDLibRegistrationAt.map {
            Date().timeIntervalSince($0) >= 24 * 60 * 60
        } ?? true
        let userChanged = state.registeredTelegramUserId != currentUser.id
        guard authorizationChanged || registrationExpired || userChanged else {
            let age = Date().timeIntervalSince(state.lastTDLibRegistrationAt ?? .distantPast)
            log("TDLib Web Push registration is current")
            scheduleRegistrationRefresh(after: max(60, 24 * 60 * 60 - age))
            return
        }

        let reason =
            if authorizationChanged {
                "authorization-ready"
            } else if userChanged {
                "telegram-user-changed"
            } else {
                "registration-expired"
            }
        log("Refreshing TDLib Web Push registration: reason=\(reason)")
        try await deregisterFromTDLib(subscription)
        log("Registering Telegram Web Push endpoint with TDLib")
        let receiver = try await td.registerDevice(
            deviceToken: .deviceTokenWebPush(
                DeviceTokenWebPush(
                    authBase64url: subscription.authBase64url,
                    endpoint: subscription.endpoint,
                    p256dhBase64url: subscription.p256dhBase64url,
                ),
            ),
            otherUserIds: [],
        )
        state.lastTDLibRegistrationAt = Date()
        state.registeredTelegramUserId = currentUser.id
        state.pushReceiverId = receiver.id
        try await stateStore.save(state)
        registeredAuthorizationEpoch = authorizationEpoch
        log("TDLib Web Push endpoint registered: receiverId=\(receiver.id)")
        scheduleRegistrationRefresh(after: 24 * 60 * 60)
    }

    private func deregisterFromTDLib(
        _ subscription: RelayTelegramSubscription,
        using client: TDLibClient? = nil,
    ) async throws {
        let receiver = try await (client ?? td).registerDevice(
            deviceToken: .deviceTokenWebPush(
                DeviceTokenWebPush(
                    authBase64url: subscription.authBase64url,
                    endpoint: "",
                    p256dhBase64url: subscription.p256dhBase64url,
                ),
            ),
            otherUserIds: [],
        )
        log("TDLib Web Push endpoint deregistered: receiverId=\(receiver.id)")
    }

    /// Telegram (AppDelegate.openChatWhenReady) switches to the notification's account and opens the chat once that
    /// account's client is ready; a later tap replaces a route still waiting. The switch waits for a ready client as
    /// well, so it never runs while the notification service owns TDLib (L-8).
    private func openWhenReady(_ route: PushNotificationRoute) {
        let targetAccountID = route.accountID.flatMap { userID in
            TDLib.shared.accounts.first { $0.userID == userID }?.id
        }
        var switchedAccount = false
        routeOpening = TDLib.shared
            .readyClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                guard let self, let source, source == TDLib.shared.activeUpdateSource,
                      source.accountID == TDLib.shared.activeAccountID else { return }
                guard let targetAccountID, source.accountID != targetAccountID else {
                    routeOpening = nil
                    open(route: route)
                    return
                }
                // Another account became ready after the switch: the user chose it, and the route is dropped.
                guard !switchedAccount else {
                    routeOpening = nil
                    return
                }
                switchedAccount = true
                log("Push route switches to its account")
                do {
                    try TDLib.shared.switchToAccount(targetAccountID)
                } catch {
                    routeOpening = nil
                    log("Unable to switch to the push route's account: \(error.localizedDescription)")
                }
            }
    }

    private func scheduleSynchronizationRetry() {
        guard synchronizationRetryTask == nil else { return }
        synchronizationRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled else { return }
            synchronizationRetryTask = nil
            scheduleSynchronization()
        }
    }

    private func scheduleRegistrationRefresh(after interval: TimeInterval) {
        registrationRefreshTask?.cancel()
        registrationRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard let self, !Task.isCancelled else { return }
            registrationRefreshTask = nil
            scheduleSynchronization()
        }
    }

    private func scheduleRevocationRetry() {
        guard revocationRetryTask == nil else { return }
        revocationRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled else { return }
            revocationRetryTask = nil
            await retryPendingRevocation()
        }
    }

    private func retryPendingRevocation() async {
        guard let api else { return }
        do {
            try await revokePendingSubscription(api: api)
        } catch {
            log("Push relay revocation retry failed: \(error.localizedDescription)")
            scheduleRevocationRetry()
        }
    }

    private func revokePendingSubscription(api: PushRelayAPIClient) async throws {
        let state = try await stateStore.load()
        guard state.pendingSubscriptionRevocation,
              let installation = state.installation,
              let subscription = state.subscription
        else {
            if state.pendingSubscriptionRevocation {
                try await clearSubscriptionState()
            }
            return
        }
        try await deleteTelegramSubscriptionIfPresent(
            api: api,
            subscription: subscription,
            installation: installation,
        )
        try await clearSubscriptionState()
    }

    private func deleteTelegramSubscriptionIfPresent(
        api: PushRelayAPIClient,
        subscription: RelayTelegramSubscription,
        installation: RelayInstallationCredentials,
    ) async throws {
        do {
            try await api.deleteTelegramSubscription(subscription, installation: installation)
        } catch let error as RelayAPIError where error.statusCode == 404 {
            log("Telegram Web Push subscription was already revoked")
        }
    }

    /// Settings turned the relay off: Telegram stops sending to the endpoint, and the relay deletes the installation
    /// with its subscription and App Attest key. Without a ready TDLib client, Telegram drops the endpoint once the
    /// relay rejects it. A failure retries with the synchronization, also after a relaunch.
    private func deleteRelayData(api: PushRelayAPIClient) async throws {
        let state = try await stateStore.load()
        guard state.installation != nil || state.subscription != nil || state.appAttestKeyId != nil else { return }
        log("Deleting push relay data")
        if let subscription = state.subscription, telegramReady {
            do {
                try await deregisterFromTDLib(subscription)
            } catch {
                log("TDLib Web Push deregistration failed: \(error.localizedDescription)")
            }
        }
        if let installation = state.installation {
            do {
                try await api.deleteInstallation(installation)
            } catch let error as RelayAPIError where [401, 404].contains(error.statusCode) {
                log("Push relay installation was already deleted")
            }
        }
        try await stateStore.save(PushRelayPersistentState())
        registeredAuthorizationEpoch = nil
        log("Push relay data deleted")
    }

    private func clearSubscriptionState() async throws {
        try await stateStore.update {
            $0.subscription = nil
            $0.pendingSubscriptionRevocation = false
            $0.lastTDLibRegistrationAt = nil
            $0.registeredTelegramUserId = nil
            $0.pushReceiverId = nil
        }
    }

    private func sendQuickReply(_ text: String, route: PushNotificationRoute) async {
        guard await waitForTelegramAuthorization() else {
            log("Unable to send quick reply: TDLib authorization timed out")
            return
        }

        do {
            let client = TDLib.shared.activeClient
            let accountID = TDLib.shared.activeAccountID
            let currentUser = try await client.getMe()
            guard TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            guard let routeAccountID = route.accountID,
                  routeAccountID == currentUser.id
            else {
                log("Unable to send quick reply: notification account couldn't be verified")
                return
            }

            let chat = try await chat(for: route, using: client)
            guard TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            var destinationTopic: MessageTopic?
            var verifiedReplyMessageID: Int64?
            if case .chatTypeSupergroup(let supergroupChat) = chat.type {
                let supergroup: Supergroup
                do {
                    supergroup = try await client.getSupergroup(
                        supergroupId: supergroupChat.supergroupId,
                    )
                } catch {
                    log("Unable to send quick reply: supergroup couldn't be checked")
                    return
                }
                guard TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else { return }
                if supergroup.isForum {
                    guard let notificationMessageID = route.tdlibMessageID,
                          let targetMessage = try? await client.getMessage(
                              chatId: chat.id,
                              messageId: notificationMessageID,
                          ),
                          targetMessage.chatId == chat.id,
                          case .messageTopicForum(let forumTopic) = targetMessage.topicId,
                          let topic = try? await client.getForumTopic(
                              chatId: chat.id,
                              forumTopicId: forumTopic.forumTopicId,
                          )
                    else {
                        log("Unable to send quick reply: forum topic couldn't be verified")
                        return
                    }
                    guard TDLib.shared.activeAccountID == accountID,
                          TDLib.shared.activeClient.id == client.id
                    else { return }
                    let canManageTopics: Bool =
                        switch supergroup.status {
                        case .chatMemberStatusCreator:
                            true
                        case .chatMemberStatusAdministrator(let administrator):
                            administrator.rights.canManageTopics
                        default:
                            false
                        }
                    let restricted = topic.info.isClosed || topic.info.isHidden
                    guard !restricted || topic.info.isOutgoing || canManageTopics else {
                        log("Unable to send quick reply: forum topic is closed")
                        return
                    }
                    destinationTopic = targetMessage.topicId
                    verifiedReplyMessageID = targetMessage.id
                }
            } else if chat.viewAsTopics {
                log("Unable to send quick reply: topic destination couldn't be verified")
                return
            }
            guard await QuickReplyNotification.canSendText(to: chat, using: client),
                  TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else {
                log("Unable to send quick reply: sending messages is no longer allowed")
                return
            }

            let replyTo = (verifiedReplyMessageID ?? route.tdlibTopMessageID).map {
                InputMessageReplyTo.inputMessageReplyToMessage(
                    InputMessageReplyToMessage(
                        checklistTaskId: 0,
                        messageId: $0,
                        pollOptionId: "",
                        quote: nil,
                    ),
                )
            }
            let sentMessage = try await client.sendMessage(
                chatId: chat.id,
                inputMessageContent: .inputMessageText(
                    InputMessageText(
                        clearDraft: false,
                        linkPreviewOptions: nil,
                        text: FormattedText(entities: [], text: text),
                    ),
                ),
                options: nil,
                replyMarkup: nil,
                replyTo: replyTo,
                topicId: destinationTopic,
            )
            guard sentMessage.chatId == chat.id,
                  sentMessage.topicId == destinationTopic
            else {
                log("Unable to send quick reply: Telegram returned a different topic")
                return
            }
            guard TDLib.shared.activeAccountID == accountID,
                  TDLib.shared.activeClient.id == client.id
            else { return }
            if let messageID = route.tdlibMessageID {
                // A forum reply reads only its topic; reading the whole forum would mark other topics' older
                // unread messages as read.
                let isForumTopic =
                    if case .messageTopicForum = destinationTopic {
                        true
                    } else {
                        false
                    }
                _ = try? await client.viewMessages(
                    chatId: chat.id,
                    forceRead: true,
                    messageIds: [messageID],
                    source: isForumTopic ? .messageSourceForumTopicHistory : nil,
                )
            }
            log("Quick reply sent")
        } catch {
            log("Unable to send quick reply: \(error.localizedDescription)")
        }
    }

    private func waitForTelegramAuthorization() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(15))
        while !telegramReady, clock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }
        return telegramReady
    }

    private func chat(for route: PushNotificationRoute, using client: TDLibClient) async throws -> Chat {
        switch route.peerType {
        case .privateChat:
            try await client.createPrivateChat(force: false, userId: route.peerID)
        case .basicGroup:
            try await client.createBasicGroupChat(basicGroupId: route.peerID, force: false)
        case .supergroup:
            try await client.createSupergroupChat(force: false, supergroupId: route.peerID)
        }
    }

    private func open(route: PushNotificationRoute) {
        guard lastOpenedRoute != route else { return }
        lastOpenedRoute = route
        let client = TDLib.shared.activeClient
        let accountID = TDLib.shared.activeAccountID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard self?.lastOpenedRoute == route else { return }
            self?.lastOpenedRoute = nil
        }
        Task {
            do {
                guard TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else { return }
                let currentUser = try await client.getMe()
                guard TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id,
                      route.accountID == nil || route.accountID == currentUser.id else { return }
                let chat = try await chat(for: route, using: client)
                guard TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id,
                      let customChat = await RootVM.shared.getCustomChatForNavigation(
                          from: chat.id,
                          client: client,
                      ),
                      TDLib.shared.activeAccountID == accountID,
                      TDLib.shared.activeClient.id == client.id
                else { return }
                NavigationStorage.shared.push(
                    .customChat(
                        customChat,
                        location: ChatLocation(
                            accountID: accountID,
                            chatID: chat.id,
                            clientID: client.id,
                            topic: nil,
                        ),
                        targetMessageID: route.tdlibMessageID,
                    ),
                )
            } catch {
                log("Unable to open push route: \(error.localizedDescription)")
            }
        }
    }
}

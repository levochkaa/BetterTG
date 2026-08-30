// PushRelayCoordinator.swift

import Combine
import Foundation
import TDLibKit
import UIKit
import UserNotifications

@MainActor final class PushRelayCoordinator: NSObject, UNUserNotificationCenterDelegate {
    // MARK: Lifecycle

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

    // MARK: Internal

    static let shared = PushRelayCoordinator()

    func start() {
        guard !started else { return }
        started = true

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: "TELEGRAM_MESSAGE",
                actions: [],
                intentIdentifiers: [],
            ),
        ])

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
                openPendingRouteIfPossible()
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
                Task { await self.prepareForLogout() }
            }
            .store(in: &cancellables)

        guard configuration != nil else {
            log("Push relay disabled: BetterTGRelayBaseURL is not configured")
            return
        }

        log("Push relay enabled: \(configuration?.baseURL.absoluteString ?? "unknown URL")")

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
        if !telegramReady {
            pendingRoute = route
            return
        }
        open(route: route)
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
                let messageId = messageRoute.serverMessageId
            else { return nil }

            switch stateRoute.event {
            case "READ_HISTORY":
                guard let maxId = stateRoute.maxId, messageId <= maxId else { return nil }
            case "MESSAGE_DELETED", "READ_REACTION":
                guard stateRoute.deletedMessageIds.contains(messageId) else { return nil }
            default:
                return nil
            }
            return notification.request.identifier
        }
        guard !identifiers.isEmpty else { return false }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        return true
    }

    func prepareForLogout() async {
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
                try await deregisterFromTDLib(subscription)
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
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        if let route = PushNotificationRoute(userInfo: notification.request.content.userInfo) {
            log("Foreground push received: event=\(route.event ?? "unknown")")
        } else {
            log("Foreground push received without a recognized route")
        }
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
    ) async {
        await handleNotificationResponse(userInfo: response.notification.request.content.userInfo)
    }

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
    private var pendingRoute: PushNotificationRoute?
    private var lastOpenedRoute: PushNotificationRoute?
    private var cancellables = Set<AnyCancellable>()

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
        state.pushReceiverId = receiver.id.rawValue
        try await stateStore.save(state)
        registeredAuthorizationEpoch = authorizationEpoch
        log("TDLib Web Push endpoint registered: receiverId=\(receiver.id.rawValue)")
        scheduleRegistrationRefresh(after: 24 * 60 * 60)
    }

    private func deregisterFromTDLib(_ subscription: RelayTelegramSubscription) async throws {
        let receiver = try await td.registerDevice(
            deviceToken: .deviceTokenWebPush(
                DeviceTokenWebPush(
                    authBase64url: subscription.authBase64url,
                    endpoint: "",
                    p256dhBase64url: subscription.p256dhBase64url,
                ),
            ),
            otherUserIds: [],
        )
        log("TDLib Web Push endpoint deregistered: receiverId=\(receiver.id.rawValue)")
    }

    private func openPendingRouteIfPossible() {
        guard let pendingRoute else { return }
        self.pendingRoute = nil
        open(route: pendingRoute)
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

    private func clearSubscriptionState() async throws {
        try await stateStore.update {
            $0.subscription = nil
            $0.pendingSubscriptionRevocation = false
            $0.lastTDLibRegistrationAt = nil
            $0.registeredTelegramUserId = nil
            $0.pushReceiverId = nil
        }
    }

    private func open(route: PushNotificationRoute) {
        guard lastOpenedRoute != route else { return }
        lastOpenedRoute = route
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard self?.lastOpenedRoute == route else { return }
            self?.lastOpenedRoute = nil
        }
        Task {
            do {
                let currentUser = try await td.getMe()
                guard route.accountId == nil || route.accountId == currentUser.id else { return }
                let chat: Chat =
                    switch route.peerType {
                    case .privateChat:
                        try await td.createPrivateChat(force: false, userId: route.peerId)
                    case .basicGroup:
                        try await td.createBasicGroupChat(basicGroupId: route.peerId, force: false)
                    case .supergroup:
                        try await td.createSupergroupChat(force: false, supergroupId: route.peerId)
                    }
                let position = chat.positions.first ?? ChatPosition(
                    isPinned: false,
                    list: .chatListMain,
                    order: 0,
                    source: nil,
                )
                guard let customChat = await RootVM.shared.getCustomChat(from: chat, position: position) else {
                    return
                }
                NavigationStorage.shared.push(
                    .customChat(customChat, targetMessageID: route.tdlibMessageId),
                )
            } catch {
                log("Unable to open push route: \(error.localizedDescription)")
            }
        }
    }
}

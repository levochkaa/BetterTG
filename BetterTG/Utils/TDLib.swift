// TDLib.swift

import Combine
@preconcurrency import TDLibKitDynamic
import UIKit

var td: TDLibClient { TDLib.shared.activeClient }

// MARK: - TelegramAccountError

enum TelegramAccountError: LocalizedError {
    case unavailable
    case persistenceFailed

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The selected account is no longer available."
        case .persistenceFailed:
            "BetterTG couldn't save the account list."
        }
    }
}

// MARK: - TDLib

final class TDLib: @unchecked Sendable {
    // MARK: Private

    private struct ClientSnapshot {
        let client: TDLibClient
        let accountID: UUID
    }

    // MARK: Internal

    static let shared = TDLib()

    private(set) var accounts = [TelegramAccount]()
    private(set) var activeAccountID: UUID?
    private(set) var isActiveAccountReady = false

    private let manager = TDLibClientManager()
    private let registry = TelegramAccountRegistry()
    private var processLock: TDLibProcessLock?
    private var ownershipReleaseTask: Task<Void, Never>?
    private var ownershipResumeTask: Task<Void, Never>?
    private var ownershipBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    private var ownershipBackgroundTaskEndTask: Task<Void, Never>?
    private var lifecycleSuspended = false
    private var wantsForegroundOwnership = true
    private let clientLock = NSLock()
    private var storedActiveClient: TDLibClient?
    private var started = false
    private var configuredClientIDs = Set<Int32>()
    private var retiringClientIDs = Set<Int32>()
    private var recoveringClientIDs = Set<Int32>()
    private var cancellables = Set<AnyCancellable>()

    var activeAccount: TelegramAccount? {
        accounts.first(where: { $0.id == activeAccountID })
    }

    var sortedAccounts: [TelegramAccount] {
        accounts.sorted(by: { $0.lastActiveAt > $1.lastActiveAt })
    }

    var activeClient: TDLibClient {
        clientLock.lock()
        defer { clientLock.unlock() }
        guard let storedActiveClient else {
            preconditionFailure("TDLib was accessed before account bootstrap completed")
        }
        return storedActiveClient
    }

    private init() {}

    func startTdLibUpdateHandler() {
        guard !started else { return }

        do {
            processLock = try TDLibProcessLock.acquire(wait: true)
            guard processLock != nil else { throw TelegramAccountError.unavailable }
            started = true
            let state = try registry.loadOrCreate()
            accounts = state.accounts
            activeAccountID = state.activeAccountID
            guard let account = activeAccount else { throw TelegramAccountError.unavailable }
            activate(account: account, notify: false)
        } catch {
            log("TDLib account bootstrap failed: \(error.localizedDescription)")
        }

        nc.publisher(&cancellables, for: UIApplication.willTerminateNotification) { [weak self] _ in
            guard let self else { return }
            manager.closeClients()
            processLock?.unlock()
            processLock = nil
        }
    }

    @MainActor func releaseForNotificationService() {
        wantsForegroundOwnership = false
        guard started, !lifecycleSuspended else { return }
        lifecycleSuspended = true
        log("TDLib ownership handoff started")

        beginOwnershipBackgroundTask()
        let manager = manager
        ownershipReleaseTask = Task { @MainActor [weak self] in
            await Task.detached(priority: .userInitiated) {
                manager.closeClients()
            }.value
            guard let self else { return }
            processLock?.unlock()
            processLock = nil
            log("TDLib ownership released for notification service")
        }
    }

    @MainActor func resumeAfterNotificationService() {
        wantsForegroundOwnership = true
        guard started, lifecycleSuspended, ownershipResumeTask == nil else { return }
        let releaseTask = ownershipReleaseTask
        ownershipResumeTask = Task { @MainActor [weak self] in
            await releaseTask?.value
            guard let self else { return }
            ownershipReleaseTask = nil

            do {
                let lock = try await Task.detached(priority: .userInitiated) {
                    try TDLibProcessLock.acquire(wait: true)
                }.value
                guard wantsForegroundOwnership else {
                    lock?.unlock()
                    ownershipResumeTask = nil
                    return
                }
                guard let lock, let account = activeAccount else {
                    throw TelegramAccountError.unavailable
                }
                processLock = lock
                lifecycleSuspended = false
                activate(account: account, notify: false)
                log("TDLib ownership restored to main application")
            } catch {
                log("TDLib ownership restore failed: \(error.localizedDescription)")
            }
            ownershipResumeTask = nil
        }
    }

    @MainActor func addAccount() throws {
        let now = Date()
        let account = TelegramAccount(
            id: UUID(),
            displayName: nil,
            phoneNumber: nil,
            userID: nil,
            createdAt: now,
            lastActiveAt: now,
        )
        _ = try registry.databaseDirectory(for: account.id)

        var updatedAccounts = accounts
        updatedAccounts.append(account)
        try persist(accounts: updatedAccounts, activeAccountID: account.id)

        let previous = activeClientSnapshot()
        accounts = updatedAccounts
        activeAccountID = account.id
        activate(account: account, notify: true)
        retire(previous, accountID: previous?.accountID, endingSession: false, removeDirectory: false)
    }

    @MainActor func switchToAccount(_ accountID: UUID) throws {
        guard accountID != activeAccountID else { return }
        guard var account = accounts.first(where: { $0.id == accountID }) else {
            throw TelegramAccountError.unavailable
        }

        let previous = activeClientSnapshot()
        let discardedAccountID = !isActiveAccountReady && activeAccount?.userID == nil ? activeAccountID : nil
        var updatedAccounts = accounts.filter { $0.id != discardedAccountID }
        guard let index = updatedAccounts.firstIndex(where: { $0.id == accountID }) else {
            throw TelegramAccountError.unavailable
        }
        account.lastActiveAt = Date()
        updatedAccounts[index] = account
        try persist(accounts: updatedAccounts, activeAccountID: accountID)

        accounts = updatedAccounts
        activeAccountID = accountID
        activate(account: account, notify: true)
        retire(
            previous,
            accountID: previous?.accountID,
            endingSession: false,
            removeDirectory: discardedAccountID != nil,
        )
    }

    @MainActor func logOutActiveAccount() throws {
        guard let removedAccount = activeAccount else { throw TelegramAccountError.unavailable }
        let previous = activeClientSnapshot()
        let survivors = accounts.filter { $0.id != removedAccount.id }
        var updatedAccounts = survivors
        let replacement: TelegramAccount

        if var existing = survivors.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }).first {
            existing.lastActiveAt = Date()
            replacement = existing
            if let index = updatedAccounts.firstIndex(where: { $0.id == existing.id }) {
                updatedAccounts[index] = existing
            }
        } else {
            let now = Date()
            replacement = TelegramAccount(
                id: UUID(),
                displayName: nil,
                phoneNumber: nil,
                userID: nil,
                createdAt: now,
                lastActiveAt: now,
            )
            _ = try registry.databaseDirectory(for: replacement.id)
            updatedAccounts.append(replacement)
        }

        try persist(accounts: updatedAccounts, activeAccountID: replacement.id)
        accounts = updatedAccounts
        activeAccountID = replacement.id
        activate(account: replacement, notify: true)
        retire(previous, accountID: removedAccount.id, endingSession: true, removeDirectory: true)
    }

    func UpdateAuthorizationState(_ authorizationState: AuthorizationState) {
        log("TDLib authorization state received: \(authorizationState.diagnosticName)")
        switch authorizationState {
        case .authorizationStateWaitTdlibParameters:
            nc.post(name: .authorizationStateWaitTdlibParameters)
        case .authorizationStateWaitPhoneNumber:
            isActiveAccountReady = false
            nc.post(name: .authorizationStateWaitPhoneNumber)
        case .authorizationStateWaitEmailAddress(let value):
            isActiveAccountReady = false
            nc.post(name: .authorizationStateWaitEmailAddress, object: value)
        case .authorizationStateWaitEmailCode(let value):
            isActiveAccountReady = false
            nc.post(name: .authorizationStateWaitEmailCode, object: value)
        case .authorizationStateWaitCode(let value):
            isActiveAccountReady = false
            nc.post(name: .authorizationStateWaitCode, object: value)
        case .authorizationStateWaitOtherDeviceConfirmation(let value):
            isActiveAccountReady = false
            nc.post(name: .authorizationStateWaitOtherDeviceConfirmation, object: value)
        case .authorizationStateWaitRegistration(let value):
            isActiveAccountReady = false
            nc.post(name: .authorizationStateWaitRegistration, object: value)
        case .authorizationStateWaitPassword(let value):
            isActiveAccountReady = false
            nc.post(name: .authorizationStateWaitPassword, object: value)
        case .authorizationStateReady:
            isActiveAccountReady = true
            nc.post(name: .authorizationStateReady)
        case .authorizationStateLoggingOut:
            isActiveAccountReady = false
            nc.post(name: .authorizationStateLoggingOut)
        case .authorizationStateClosing:
            isActiveAccountReady = false
            nc.post(name: .authorizationStateClosing)
        case .authorizationStateClosed:
            isActiveAccountReady = false
            nc.post(name: .authorizationStateClosed)
        case .authorizationStateWaitPremiumPurchase(let value):
            isActiveAccountReady = false
            nc.post(name: .authorizationStateWaitPremiumPurchase, object: value)
        }
    }

    private func activeClientSnapshot() -> ClientSnapshot? {
        clientLock.lock()
        defer { clientLock.unlock() }
        guard let client = storedActiveClient, let activeAccountID else { return nil }
        return ClientSnapshot(client: client, accountID: activeAccountID)
    }

    private func setActiveClient(_ client: TDLibClient) {
        clientLock.lock()
        storedActiveClient = client
        clientLock.unlock()
    }

    private func activate(account: TelegramAccount, notify: Bool) {
        isActiveAccountReady = false
        let accountID = account.id
        let client = manager.createClient { [weak self] data, callbackClient in
            do {
                let decoded = try callbackClient.decoder.decode(Update.self, from: data)
                DispatchQueue.main.async {
                    self?.handle(decoded, from: callbackClient, accountID: accountID)
                }
            } catch {
                log("Error TdLibUpdateHandler: \(error)")
            }
        }
        setActiveClient(client)
        try? client.setLogStream(logStream: .logStreamEmpty) { _ in }

        if notify {
            nc.post(name: .activeTelegramAccountChanged, object: account.id)
            nc.post(name: .telegramAccountsChanged)
        }
    }

    @MainActor private func handle(_ incomingUpdate: Update, from client: TDLibClient, accountID: UUID) {
        if case .updateAuthorizationState(let updateAuthorizationState) = incomingUpdate {
            let state = updateAuthorizationState.authorizationState
            if case .authorizationStateWaitTdlibParameters = state {
                configureIfNeeded(client: client, accountID: accountID)
            }
            if case .authorizationStateClosed = state {
                configuredClientIDs.remove(client.id)
                retiringClientIDs.remove(client.id)
            }

            guard isActive(client: client, accountID: accountID) else { return }
            if lifecycleSuspended {
                switch state {
                case .authorizationStateClosed, .authorizationStateClosing:
                    return
                default:
                    break
                }
            }
            update(incomingUpdate)

            switch state {
            case .authorizationStateReady:
                fetchAccountMetadata(client: client, accountID: accountID)
            case .authorizationStateLoggingOut:
                recoverUnexpectedLogout(client: client, accountID: accountID)
            case .authorizationStateClosed:
                recoverUnexpectedClose(accountID: accountID, clientID: client.id)
            default:
                break
            }
            return
        }

        guard isActive(client: client, accountID: accountID) else { return }
        update(incomingUpdate)
    }

    private func isActive(client: TDLibClient, accountID: UUID) -> Bool {
        activeAccountID == accountID && activeClientSnapshot()?.client == client
    }

    private func configureIfNeeded(client: TDLibClient, accountID: UUID) {
        guard configuredClientIDs.insert(client.id).inserted else { return }
        log("TDLib requested client parameters for account \(accountID.uuidString)")
        Task {
            do {
                let directory = try registry.databaseDirectory(for: accountID)
                try await client.setTdlibParameters(
                    apiHash: Secret.apiHash,
                    apiId: Secret.apiId,
                    applicationVersion: Utils.applicationVersion,
                    databaseDirectory: directory.path,
                    databaseEncryptionKey: Data(),
                    deviceModel: Utils.modelName,
                    filesDirectory: directory.path,
                    systemLanguageCode: "en-US",
                    systemVersion: UIDevice.current.systemVersion,
                    useChatInfoDatabase: true,
                    useFileDatabase: true,
                    useMessageDatabase: true,
                    useSecretChats: true,
                    useTestDc: false,
                )
                let state = try await client.getAuthorizationState()
                DispatchQueue.main.async { [weak self] in
                    guard let self, isActive(client: client, accountID: accountID) else { return }
                    if case .authorizationStateWaitTdlibParameters = state {
                        return
                    }
                    UpdateAuthorizationState(state)
                }
            } catch {
                configuredClientIDs.remove(client.id)
                log("TDLib client parameter configuration failed: \(error.localizedDescription)")
            }
        }
    }

    private func fetchAccountMetadata(client: TDLibClient, accountID: UUID) {
        Task {
            do {
                let me = try await client.getMe()
                DispatchQueue.main.async { [weak self] in
                    self?.storeAccountMetadata(me, accountID: accountID)
                }
            } catch {
                log("TDLib getMe failed: \(error.localizedDescription)")
            }
        }
    }

    private func storeAccountMetadata(_ user: User, accountID: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let fullName = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        accounts[index].displayName = fullName.isEmpty ? nil : fullName
        accounts[index].phoneNumber = user.phoneNumber.isEmpty ? nil : user.phoneNumber
        accounts[index].userID = user.id
        do {
            try persist(accounts: accounts, activeAccountID: activeAccountID ?? accountID)
            nc.post(name: .telegramAccountsChanged)
        } catch {
            log("Unable to persist Telegram account metadata: \(error.localizedDescription)")
        }
    }

    private func persist(accounts: [TelegramAccount], activeAccountID: UUID) throws {
        do {
            try registry.save(
                TelegramAccountRegistryState(version: 1, activeAccountID: activeAccountID, accounts: accounts),
            )
        } catch {
            log("Unable to persist Telegram accounts: \(error.localizedDescription)")
            throw TelegramAccountError.persistenceFailed
        }
    }

    @MainActor private func recoverUnexpectedLogout(client: TDLibClient, accountID: UUID) {
        guard !retiringClientIDs.contains(client.id), activeAccountID == accountID else { return }
        do {
            try removeActiveAccountAfterExternalLogout(client: client, accountID: accountID)
        } catch {
            log("Unable to recover externally logged out account: \(error.localizedDescription)")
        }
    }

    @MainActor private func removeActiveAccountAfterExternalLogout(client: TDLibClient, accountID: UUID) throws {
        let survivors = accounts.filter { $0.id != accountID }
        var updatedAccounts = survivors
        let replacement: TelegramAccount
        if var existing = survivors.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }).first {
            existing.lastActiveAt = Date()
            replacement = existing
            if let index = updatedAccounts.firstIndex(where: { $0.id == existing.id }) {
                updatedAccounts[index] = existing
            }
        } else {
            let now = Date()
            replacement = TelegramAccount(
                id: UUID(),
                displayName: nil,
                phoneNumber: nil,
                userID: nil,
                createdAt: now,
                lastActiveAt: now,
            )
            _ = try registry.databaseDirectory(for: replacement.id)
            updatedAccounts.append(replacement)
        }
        try persist(accounts: updatedAccounts, activeAccountID: replacement.id)
        accounts = updatedAccounts
        activeAccountID = replacement.id
        activate(account: replacement, notify: true)
        retire(
            ClientSnapshot(client: client, accountID: accountID),
            accountID: accountID,
            endingSession: true,
            removeDirectory: true,
            logoutAlreadyStarted: true,
        )
    }

    @MainActor private func recoverUnexpectedClose(accountID: UUID, clientID: Int32) {
        guard !lifecycleSuspended,
              activeAccountID == accountID,
              !recoveringClientIDs.contains(clientID),
              let account = activeAccount
        else {
            return
        }
        recoveringClientIDs.insert(clientID)
        activate(account: account, notify: true)
        recoveringClientIDs.remove(clientID)
    }

    @MainActor private func retire(
        _ snapshot: ClientSnapshot?,
        accountID: UUID?,
        endingSession: Bool,
        removeDirectory: Bool,
        logoutAlreadyStarted: Bool = false,
    ) {
        guard let snapshot, snapshot.accountID == accountID else { return }
        retiringClientIDs.insert(snapshot.client.id)
        let client = snapshot.client
        let id = snapshot.accountID

        Task { @MainActor [weak self] in
            guard let self else { return }
            var closed = false
            if endingSession {
                Task { await PushRelayCoordinator.shared.prepareForLogout(using: client) }
                if !logoutAlreadyStarted {
                    Task {
                        do {
                            _ = try await client.logOut()
                        } catch {
                            log("TDLib logout request failed: \(error.localizedDescription)")
                        }
                    }
                }
                closed = await waitUntilClosed(client, timeout: 15)
                if !closed {
                    log("TDLib logout stuck for 15s; destroying local account data")
                    Task {
                        do {
                            _ = try await client.destroy()
                        } catch {
                            log("TDLib destroy request failed: \(error.localizedDescription)")
                        }
                    }
                    closed = await waitUntilClosed(client, timeout: 5)
                }
            } else {
                Task {
                    do {
                        _ = try await client.close()
                    } catch {
                        log("TDLib close request failed: \(error.localizedDescription)")
                    }
                }
                closed = await waitUntilClosed(client, timeout: 5)
            }

            retiringClientIDs.remove(client.id)
            if removeDirectory, closed {
                registry.removeDatabaseDirectory(for: id)
            } else if removeDirectory {
                log("TDLib account directory kept because client \(client.id) did not close")
            }
        }
    }

    private func waitUntilClosed(_ client: TDLibClient, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while manager.clients[client.id] != nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return manager.clients[client.id] == nil
    }

    @MainActor private func beginOwnershipBackgroundTask() {
        if ownershipBackgroundTaskIdentifier == .invalid {
            ownershipBackgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(
                withName: "Release TDLib and retain background process",
            ) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    log("TDLib background retention expired before 30 seconds")
                    self.endOwnershipBackgroundTask()
                }
            }
        }

        guard ownershipBackgroundTaskIdentifier != .invalid else {
            log("TDLib background retention was not granted")
            return
        }

        ownershipBackgroundTaskEndTask?.cancel()
        ownershipBackgroundTaskEndTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            log("TDLib background retention completed after 30 seconds")
            endOwnershipBackgroundTask()
        }
    }

    @MainActor private func endOwnershipBackgroundTask() {
        ownershipBackgroundTaskEndTask?.cancel()
        ownershipBackgroundTaskEndTask = nil
        guard ownershipBackgroundTaskIdentifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(ownershipBackgroundTaskIdentifier)
        ownershipBackgroundTaskIdentifier = .invalid
    }
}

private extension AuthorizationState {
    var diagnosticName: String {
        switch self {
        case .authorizationStateWaitTdlibParameters:
            "waitTdlibParameters"
        case .authorizationStateWaitPhoneNumber:
            "waitPhoneNumber"
        case .authorizationStateWaitEmailAddress:
            "waitEmailAddress"
        case .authorizationStateWaitEmailCode:
            "waitEmailCode"
        case .authorizationStateWaitCode:
            "waitCode"
        case .authorizationStateWaitOtherDeviceConfirmation:
            "waitOtherDeviceConfirmation"
        case .authorizationStateWaitRegistration:
            "waitRegistration"
        case .authorizationStateWaitPassword:
            "waitPassword"
        case .authorizationStateReady:
            "ready"
        case .authorizationStateLoggingOut:
            "loggingOut"
        case .authorizationStateClosing:
            "closing"
        case .authorizationStateClosed:
            "closed"
        case .authorizationStateWaitPremiumPurchase:
            "waitPremiumPurchase"
        }
    }
}

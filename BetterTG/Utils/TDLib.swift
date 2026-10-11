// TDLib.swift

import Combine
@preconcurrency import TDLibKit
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
            L10n.betterTG("Accounts.Unavailable")
        case .persistenceFailed:
            L10n.betterTG("Accounts.PersistenceFailed")
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

    private var manager = TDLibClientManager()
    private let registry = TelegramAccountRegistry()
    private var processLock: TDLibProcessLock?
    private var ownershipReleaseTask: Task<Void, Never>?
    private var ownershipResumeTask: Task<Void, Never>?
    private var ownershipBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    private var ownershipBackgroundTaskEndTask: Task<Void, Never>?
    private var lifecycleSuspended = false
    private var wantsForegroundOwnership = true
    private let clientLock = NSLock()
    private var storedActiveClient: ClientSnapshot?
    private var activationGeneration: UUID?
    private var started = false
    private var configuredClientIDs = Set<Int32>()
    private var retiringClientIDs = Set<Int32>()
    private var recoveringClientIDs = Set<Int32>()
    private var cancellables = Set<AnyCancellable>()
    private var mediaUpdates = TDLibMediaUpdateStreams(source: nil)
    private let activeClientChangesSubject = PassthroughSubject<TdUpdateSource, Never>()
    private let clientReadiness = TDLibClientReadiness()
    private let authorizationState = TDLibAuthorizationState()
    private var activeVODRanges: TDLibVODRangeCoordinator?

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
        return storedActiveClient.client
    }

    var deleteMessageUpdates: AnyPublisher<UpdateDeleteMessages, Never> {
        mediaUpdates.deleteMessageUpdates
    }

    var activeClientChanges: AnyPublisher<TdUpdateSource, Never> {
        activeClientChangesSubject.eraseToAnyPublisher()
    }

    var readyClientChanges: AnyPublisher<TdUpdateSource?, Never> {
        clientReadiness.publisher
    }

    var activeUpdateSource: TdUpdateSource? {
        activeClientSnapshot().map { TdUpdateSource(accountID: $0.accountID, clientID: $0.client.id) }
    }

    var authorizationUpdates: AnyPublisher<TDLibAuthorizationState.Snapshot?, Never> { authorizationState.publisher }

    @MainActor var activeAuthorizationSource: TdUpdateSource? {
        guard let source = authorizationState.current?.source,
              authorizationClient(for: source) != nil else { return nil }
        return source
    }

    var vodRanges: TDLibVODRangeCoordinator {
        guard let activeVODRanges else {
            preconditionFailure("TDLib VOD ranges were accessed before account bootstrap completed")
        }
        return activeVODRanges
    }

    private init() {}

    @MainActor func authorizationClient(for source: TdUpdateSource) -> TDLibClient? {
        guard !lifecycleSuspended, authorizationState.current?.source == source,
              let snapshot = activeClientSnapshot(), snapshot.accountID == source.accountID,
              snapshot.client.id == source.clientID else { return nil }
        return snapshot.client
    }

    func startTdLibUpdateHandler() {
        guard !started else { return }

        do {
            processLock = try TDLibProcessLock.acquire(wait: true)
            guard processLock != nil else { throw TelegramAccountError.unavailable }
            started = true
            let state = try registry.loadOrCreate()
            accounts = state.accounts
            activeAccountID = state.activeAccountID
            ChatDraftLegacyMigrationPolicy.captureIfNeeded(accountIDs: accounts.map(\.id))
            guard let account = activeAccount else { throw TelegramAccountError.unavailable }
            activate(account: account, notify: false)
        } catch {
            log("TDLib account bootstrap failed: \(error.localizedDescription)")
        }

        nc.publisher(&cancellables, for: UIApplication.willTerminateNotification) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.manager.closeClients()
                self.processLock?.unlock()
                self.processLock = nil
            }
        }
    }

    @MainActor func releaseForNotificationService() {
        wantsForegroundOwnership = false
        guard started, !lifecycleSuspended else { return }
        lifecycleSuspended = true
        authorizationState.invalidate()
        if let source = activeUpdateSource { clientReadiness.update(ready: false, source: source) }
        log("TDLib ownership handoff started")

        beginOwnershipBackgroundTask()
        let manager = manager
        ownershipReleaseTask = Task { @MainActor [weak self] in
            await manager.closeClients()
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
                manager = TDLibClientManager()
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

    private func publishAuthorizationState(_ authorizationState: AuthorizationState, source: TdUpdateSource) {
        log("TDLib authorization state received: \(authorizationState.diagnosticName)")
        isActiveAccountReady = authorizationState == .authorizationStateReady
        self.authorizationState.update(authorizationState, source: source)
        switch authorizationState {
        case .authorizationStateWaitTdlibParameters:
            nc.post(name: .authorizationStateWaitTdlibParameters)
        case .authorizationStateWaitPhoneNumber:
            nc.post(name: .authorizationStateWaitPhoneNumber)
        case .authorizationStateWaitEmailAddress(let value):
            nc.post(name: .authorizationStateWaitEmailAddress, object: value)
        case .authorizationStateWaitEmailCode(let value):
            nc.post(name: .authorizationStateWaitEmailCode, object: value)
        case .authorizationStateWaitCode(let value):
            nc.post(name: .authorizationStateWaitCode, object: value)
        case .authorizationStateWaitOtherDeviceConfirmation(let value):
            nc.post(name: .authorizationStateWaitOtherDeviceConfirmation, object: value)
        case .authorizationStateWaitRegistration(let value):
            nc.post(name: .authorizationStateWaitRegistration, object: value)
        case .authorizationStateWaitPassword(let value):
            nc.post(name: .authorizationStateWaitPassword, object: value)
        case .authorizationStateReady:
            nc.post(name: .authorizationStateReady)
        case .authorizationStateLoggingOut:
            nc.post(name: .authorizationStateLoggingOut)
        case .authorizationStateClosing:
            nc.post(name: .authorizationStateClosing)
        case .authorizationStateClosed:
            nc.post(name: .authorizationStateClosed)
        case .authorizationStateWaitPremiumPurchase(let value):
            nc.post(name: .authorizationStateWaitPremiumPurchase, object: value)
        }
    }

    private func activeClientSnapshot() -> ClientSnapshot? {
        clientLock.lock()
        defer { clientLock.unlock() }
        return storedActiveClient
    }

    private func setActiveClient(_ client: TDLibClient, accountID: UUID) {
        clientLock.lock()
        storedActiveClient = ClientSnapshot(client: client, accountID: accountID)
        clientLock.unlock()
    }

    private func activate(account: TelegramAccount, notify: Bool) {
        isActiveAccountReady = false
        let accountID = account.id
        let manager = manager
        let generation = UUID()
        activationGeneration = generation
        // TDLibKit 2 creates clients asynchronously. Until the new client exists, the previous
        // account/client pair stays published as one snapshot so no source mixes two epochs.
        Task { @MainActor [weak self] in
            let client: TDLibClient
            do {
                client = try await manager.createClient()
            } catch {
                log("TDLib client activation failed: \(error.localizedDescription)")
                return
            }
            guard let self, activationGeneration == generation, self.manager === manager,
                  activeAccountID == accountID
            else {
                try? await client.close()
                return
            }
            let source = TdUpdateSource(accountID: accountID, clientID: client.id)
            setActiveClient(client, accountID: accountID)
            authorizationState.activate(source)
            clientReadiness.activate(source)
            let mediaUpdates = TDLibMediaUpdateStreams(source: source)
            self.mediaUpdates = mediaUpdates
            activeVODRanges = TDLibVODRangeCoordinator(
                accountID: accountID.uuidString,
                client: .live(client),
                updates: mediaUpdates.fileUpdates,
            )
            activeClientChangesSubject.send(source)

            if notify {
                nc.post(name: .activeTelegramAccountChanged, object: account.id)
                nc.post(name: .telegramAccountsChanged)
            }

            for await incomingUpdate in client.updates {
                handle(incomingUpdate, from: client, accountID: accountID)
            }
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
            TelegramChatListStore.shared.consume(incomingUpdate, accountID: accountID, clientID: client.id)
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
        TelegramChatListStore.shared.consume(incomingUpdate, accountID: accountID, clientID: client.id)
        publishMediaUpdate(incomingUpdate)
        update(incomingUpdate)
    }

    private func publishMediaUpdate(_ update: Update) {
        switch update {
        case .updateFile(let fileUpdate):
            fileUpdates.send(fileUpdate)
        case .updateDeleteMessages(let deleteUpdate):
            deleteMessageUpdatesSubject.send(deleteUpdate)
        default:
            break
        }
    }

    private func isActive(client: TDLibClient, accountID: UUID) -> Bool {
        guard activeAccountID == accountID, let snapshot = activeClientSnapshot() else { return false }
        return snapshot.accountID == accountID && snapshot.client.id == client.id
    }

    private func configureIfNeeded(client: TDLibClient, accountID: UUID) {
        guard configuredClientIDs.insert(client.id).inserted else { return }
        log("TDLib requested client parameters for account \(accountID.uuidString)")
        Task { [self] in
            do {
                let directory = try registry.databaseDirectory(for: accountID)
                // TDLib defers pre-authentication setOption responses until it receives these parameters.
                _ = try await client.setTdlibParameters(
                    useTestDc: false,
                    databaseDirectory: directory.path,
                    filesDirectory: directory.path,
                    databaseEncryptionKey: Data(),
                    useFileDatabase: true,
                    useChatInfoDatabase: true,
                    useMessageDatabase: true,
                    useSecretChats: true,
                    apiId: Secret.apiId,
                    apiHash: Secret.apiHash,
                    systemLanguageCode: Locale.preferredLanguages.first ?? "en-US",
                    deviceModel: Utils.modelName,
                    systemVersion: UIDevice.current.systemVersion,
                    applicationVersion: Utils.applicationVersion,
                )
                try await AppLocalization.shared.configureTDLibClient(client, databaseDirectory: directory)
                AppLocalization.shared.clientDidConfigure(client)
            } catch {
                configuredClientIDs.remove(client.id)
                log("TDLib client parameter configuration failed: \(error.localizedDescription)")
            }
        }
    }

    private func fetchAccountMetadata(client: TDLibClient, accountID: UUID) {
        Task { [self] in
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
        while await !(manager.isClientClosed(client.id)), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await manager.isClientClosed(client.id)
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

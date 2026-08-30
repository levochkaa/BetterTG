// TelegramAccount.swift

import Foundation

// MARK: - TelegramAccount

struct TelegramAccount: Codable, Equatable, Identifiable {
    let id: UUID
    var displayName: String?
    var phoneNumber: String?
    var userID: Int64?
    var createdAt: Date
    var lastActiveAt: Date

    var title: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        if let phoneNumber, !phoneNumber.isEmpty {
            return "+\(phoneNumber)"
        }
        return "New Account"
    }
}

// MARK: - TelegramAccountRegistryState

struct TelegramAccountRegistryState: Codable, Equatable {
    var version: Int
    var activeAccountID: UUID
    var accounts: [TelegramAccount]
}

// MARK: - TelegramAccountRegistry

struct TelegramAccountRegistry {
    // MARK: Private

    private let fileManager: FileManager

    private var baseDirectory: URL {
        (BetterTGAppGroup.containerURL(fileManager: fileManager)
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("tdlib", isDirectory: true)
    }

    private var previousApplicationSupportDirectory: URL {
        fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tdlib", isDirectory: true)
    }

    private var registryURL: URL {
        baseDirectory.appendingPathComponent("accounts.json")
    }

    private var legacyDatabaseDirectory: URL {
        fileManager
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("td", isDirectory: true)
    }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: Internal

    func loadOrCreate() throws -> TelegramAccountRegistryState {
        try migrateApplicationSupportDirectoryIfNeeded()
        if fileManager.fileExists(atPath: registryURL.path) {
            let data = try Data(contentsOf: registryURL)
            guard var state = try? JSONDecoder().decode(TelegramAccountRegistryState.self, from: data) else {
                return try makeInitialState()
            }
            guard !state.accounts.isEmpty else { return try makeInitialState() }
            if !state.accounts.contains(where: { $0.id == state.activeAccountID }) {
                state.activeAccountID = state.accounts[0].id
                try save(state)
            }
            return state
        }
        return try makeInitialState()
    }

    func loadExisting() throws -> TelegramAccountRegistryState? {
        guard fileManager.fileExists(atPath: registryURL.path) else { return nil }
        let data = try Data(contentsOf: registryURL)
        let state = try JSONDecoder().decode(TelegramAccountRegistryState.self, from: data)
        return state.accounts.isEmpty ? nil : state
    }

    func save(_ state: TelegramAccountRegistryState) throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: registryURL, options: .atomic)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: registryURL.path,
        )
    }

    func databaseDirectory(for accountID: UUID) throws -> URL {
        let directory = baseDirectory.appendingPathComponent(accountID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func removeDatabaseDirectory(for accountID: UUID) {
        try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(accountID.uuidString, isDirectory: true))
    }

    private func migrateApplicationSupportDirectoryIfNeeded() throws {
        let source = previousApplicationSupportDirectory
        guard source.standardizedFileURL != baseDirectory.standardizedFileURL,
              fileManager.fileExists(atPath: source.appendingPathComponent("accounts.json").path),
              !fileManager.fileExists(atPath: registryURL.path)
        else { return }

        try fileManager.createDirectory(
            at: baseDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        if fileManager.fileExists(atPath: baseDirectory.path) {
            let contents = try fileManager.contentsOfDirectory(atPath: baseDirectory.path)
            guard contents.isEmpty else { return }
            try fileManager.removeItem(at: baseDirectory)
        }
        try fileManager.moveItem(at: source, to: baseDirectory)
    }

    private func makeInitialState() throws -> TelegramAccountRegistryState {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: legacyDatabaseDirectory.path) {
            let account = makeAccount()
            let destination = baseDirectory.appendingPathComponent(account.id.uuidString, isDirectory: true)
            try fileManager.moveItem(at: legacyDatabaseDirectory, to: destination)
            let state = TelegramAccountRegistryState(version: 1, activeAccountID: account.id, accounts: [account])
            do {
                try save(state)
            } catch {
                try? fileManager.moveItem(at: destination, to: legacyDatabaseDirectory)
                throw error
            }
            return state
        }

        let recoveredAccounts = try fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles],
        )
        .compactMap { url -> TelegramAccount? in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
            guard values?.isDirectory == true, let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            let createdAt = values?.creationDate ?? Date()
            return TelegramAccount(
                id: id,
                displayName: nil,
                phoneNumber: nil,
                userID: nil,
                createdAt: createdAt,
                lastActiveAt: createdAt,
            )
        }

        if let recovered = recoveredAccounts.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }).first {
            let state = TelegramAccountRegistryState(
                version: 1,
                activeAccountID: recovered.id,
                accounts: recoveredAccounts,
            )
            try save(state)
            return state
        }

        let account = makeAccount()
        let destination = baseDirectory.appendingPathComponent(account.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let state = TelegramAccountRegistryState(version: 1, activeAccountID: account.id, accounts: [account])
        try save(state)
        return state
    }

    private func makeAccount() -> TelegramAccount {
        let now = Date()
        return TelegramAccount(
            id: UUID(),
            displayName: nil,
            phoneNumber: nil,
            userID: nil,
            createdAt: now,
            lastActiveAt: now,
        )
    }
}

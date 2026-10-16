// WebAppStorage.swift

import Foundation
import Security

// MARK: - WebAppDeviceStorage

/// Telegram's bot storage (TelegramBotStorageState, `setBotStorageValue`) behind DeviceStorage: string values per
/// account and bot, kept on this device, at most 5 MB of values together.
enum WebAppDeviceStorage {
    enum Failure: Error {
        case quotaExceeded
        case unknown
    }

    private static let maxSize = 5 * 1024 * 1024

    static func value(accountID: UUID, botUserID: Int64, key: String) -> String? {
        load(accountID: accountID, botUserID: botUserID)[key]
    }

    /// A nil value removes the key.
    static func setValue(_ value: String?, accountID: UUID, botUserID: Int64, key: String) throws(Failure) {
        var data = load(accountID: accountID, botUserID: botUserID)
        data[key] = value
        try save(data, accountID: accountID, botUserID: botUserID)
    }

    static func clear(accountID: UUID, botUserID: Int64) throws(Failure) {
        try save([:], accountID: accountID, botUserID: botUserID)
    }

    private static func url(accountID: UUID, botUserID: Int64) -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("WebAppDeviceStorage", isDirectory: true)
            .appendingPathComponent(accountID.uuidString, isDirectory: true)
            .appendingPathComponent("\(botUserID).json")
    }

    private static func load(accountID: UUID, botUserID: Int64) -> [String: String] {
        guard let url = url(accountID: accountID, botUserID: botUserID), let data = try? Data(contentsOf: url) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func save(_ values: [String: String], accountID: UUID, botUserID: Int64) throws(Failure) {
        guard values.values.reduce(0, { $0 + $1.utf8.count }) <= maxSize else { throw .quotaExceeded }
        guard let url = url(accountID: accountID, botUserID: botUserID) else { throw .unknown }
        do {
            if values.isEmpty {
                try? FileManager.default.removeItem(at: url)
                return
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try JSONEncoder().encode(values).write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            throw .unknown
        }
    }
}

// MARK: - WebAppSecureStorage

/// Telegram's WebAppSecureStorage behind SecureStorage: up to 10 keys per account and bot in the Keychain, readable
/// only on this device while it has a passcode. Each account stores under its own random identifier, so keys left by
/// an account that is no longer signed in can be restored into another one.
enum WebAppSecureStorage {
    enum Failure: Error {
        case quotaExceeded
        case canRestore
        case storageNotEmpty
        case unknown
    }

    /// A key another account stored, which this one may import.
    struct ExistingKey: Equatable {
        let uuid: String
        let accountName: String
        let timestamp: Int32
    }

    private struct StorageValue: Codable {
        let timestamp: Int32
        let accountName: String
        let value: String
    }

    private static let maxKeyCount = 10
    private static let service = "TMASecureStorage"

    /// `secureBotStorageUuid`: one random identifier per account, made on first use.
    static func uuid(accountID: UUID) -> String {
        let defaultsKey = uuidDefaultsKey(accountID: accountID)
        if let existing = UserDefaults.standard.string(forKey: defaultsKey) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: defaultsKey)
        return created
    }

    static func setValue(
        _ value: String?,
        accountID: UUID,
        accountName: String,
        botUserID: Int64,
        key: String,
    ) throws(Failure) {
        let uuid = uuid(accountID: accountID)
        var query = makeQuery(uuid: uuid, botUserID: botUserID, key: key)
        guard let value else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw .unknown }
            return
        }
        let storageValue = StorageValue(
            timestamp: Int32(Date().timeIntervalSince1970),
            accountName: accountName,
            value: value,
        )
        guard let data = try? JSONEncoder().encode(storageValue) else { throw .unknown }
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        switch SecItemCopyMatching(query as CFDictionary, nil) {
        case errSecSuccess:
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard status == errSecSuccess else { throw .unknown }
        case errSecItemNotFound:
            guard countKeys(uuid: uuid, botUserID: botUserID) < maxKeyCount else { throw .quotaExceeded }
            query[kSecValueData as String] = data
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw .unknown }
        default:
            throw .unknown
        }
    }

    /// Throws `canRestore` when this account has no such key but an account that is gone stored one.
    static func value(accountID: UUID, activeAccountIDs: [UUID], botUserID: Int64, key: String) throws(Failure)
        -> String?
    {
        var query = makeQuery(uuid: uuid(accountID: accountID), botUserID: botUserID, key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let storageValue = try? JSONDecoder().decode(StorageValue.self, from: data)
        {
            return storageValue.value
        }
        guard status == errSecItemNotFound else { throw .unknown }
        if !restorableKeys(activeAccountIDs: activeAccountIDs, botUserID: botUserID, key: key).isEmpty {
            throw .canRestore
        }
        return nil
    }

    /// `checkRestoreAvailability`: only an empty storage may import another account's keys.
    static func restorableKeys(
        accountID: UUID,
        activeAccountIDs: [UUID],
        botUserID: Int64,
        key: String,
    ) throws(Failure) -> [ExistingKey] {
        guard countKeys(uuid: uuid(accountID: accountID), botUserID: botUserID) == 0 else {
            throw .storageNotEmpty
        }
        return restorableKeys(activeAccountIDs: activeAccountIDs, botUserID: botUserID, key: key)
    }

    /// `transferAllValues`: copies every key the other identifier stored for the bot, then removes them there.
    static func transferAllValues(fromUUID: String, accountID: UUID, botUserID: Int64) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return }
        let fromPrefix = keyPrefix(uuid: fromUUID, botUserID: botUserID)
        let toPrefix = keyPrefix(uuid: uuid(accountID: accountID), botUserID: botUserID)
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(fromPrefix),
                  let data = item[kSecValueData as String] as? Data else { continue }
            let newItem: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: toPrefix + account.dropFirst(fromPrefix.count),
                kSecAttrService as String: service,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            ]
            SecItemAdd(newItem as CFDictionary, nil)
        }
        clear(uuid: fromUUID, botUserID: botUserID)
    }

    static func clear(accountID: UUID, botUserID: Int64) {
        clear(uuid: uuid(accountID: accountID), botUserID: botUserID)
    }

    private static func uuidDefaultsKey(accountID: UUID) -> String {
        "WebAppSecureStorageUUID.\(accountID.uuidString)"
    }

    private static func keyPrefix(uuid: String, botUserID: Int64) -> String {
        "WebBot\(UInt64(bitPattern: botUserID))U\(uuid)Key_"
    }

    private static func makeQuery(uuid: String, botUserID: Int64, key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyPrefix(uuid: uuid, botUserID: botUserID) + key,
            kSecAttrService as String: service,
        ]
    }

    private static func accounts() -> [[String: Any]] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items
    }

    private static func countKeys(uuid: String, botUserID: Int64) -> Int {
        let prefix = keyPrefix(uuid: uuid, botUserID: botUserID)
        return accounts().count { ($0[kSecAttrAccount as String] as? String)?.hasPrefix(prefix) == true }
    }

    private static func clear(uuid: String, botUserID: Int64) {
        let prefix = keyPrefix(uuid: uuid, botUserID: botUserID)
        for item in accounts() {
            guard let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(prefix) else { continue }
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
                kSecAttrService as String: service,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    /// `findRestorableKeys`: `key` as other identifiers stored it for the bot, minus the signed in accounts'.
    private static func restorableKeys(activeAccountIDs: [UUID], botUserID: Int64, key: String) -> [ExistingKey] {
        let activeUUIDs = Set(activeAccountIDs.compactMap {
            UserDefaults.standard.string(forKey: uuidDefaultsKey(accountID: $0))
        })
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        let botPrefix = "WebBot\(UInt64(bitPattern: botUserID))U"
        let keySuffix = "Key_\(key)"
        return items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(botPrefix),
                  account.hasSuffix(keySuffix),
                  let data = item[kSecValueData as String] as? Data,
                  let value = try? JSONDecoder().decode(StorageValue.self, from: data)
            else { return nil }
            let uuid = String(account.dropFirst(botPrefix.count).dropLast(keySuffix.count))
            guard !activeUUIDs.contains(uuid) else { return nil }
            return ExistingKey(uuid: uuid, accountName: value.accountName, timestamp: value.timestamp)
        }
    }
}

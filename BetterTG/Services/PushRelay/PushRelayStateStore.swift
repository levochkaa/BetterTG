// PushRelayStateStore.swift

import Foundation
import Security

// MARK: - PushRelayStateStore

actor PushRelayStateStore {
    // MARK: Internal

    func load() throws -> PushRelayPersistentState {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query(returningData: true) as CFDictionary, &result)
        if status == errSecItemNotFound {
            return PushRelayPersistentState()
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return try JSONDecoder().decode(PushRelayPersistentState.self, from: data)
    }

    func save(_ state: PushRelayPersistentState) throws {
        let data = try JSONEncoder().encode(state)
        let updateStatus = SecItemUpdate(
            query(returningData: false) as CFDictionary,
            [kSecValueData: data] as CFDictionary,
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else { throw KeychainError(status: updateStatus) }

        var item = query(returningData: false)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    @discardableResult
    func update(_ changes: (inout PushRelayPersistentState) throws -> Void) throws -> PushRelayPersistentState {
        var state = try load()
        try changes(&state)
        try save(state)
        return state
    }

    // MARK: Private

    private func query(returningData: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.levochkaaa.BetterTG.push-relay",
            kSecAttrAccount as String: "state",
            kSecUseDataProtectionKeychain as String: true,
        ]
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }
}

// MARK: - KeychainError

private struct KeychainError: Error {
    let status: OSStatus
}

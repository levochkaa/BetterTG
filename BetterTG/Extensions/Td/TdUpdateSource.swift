// TdUpdateSource.swift

import Foundation

// MARK: - TdUpdateSource

/// Origin captured at TDLib's accepted-update boundary, never at subscriber delivery.
struct TdUpdateSource: Equatable {
    fileprivate static let userInfoKey = "BetterTG.TdUpdateSource"

    let accountID: UUID
    let clientID: Int32

    func matches(_ location: ChatLocation) -> Bool {
        accountID == location.accountID && clientID == location.clientID
    }
}

// MARK: - TdScopedUpdate

struct TdScopedUpdate<Value> {
    let source: TdUpdateSource
    let value: Value

    init?(notification: Notification) {
        guard let source = notification.userInfo?[TdUpdateSource.userInfoKey] as? TdUpdateSource,
              let value = notification.object as? Value
        else { return nil }
        self.source = source
        self.value = value
    }
}

extension NotificationCenter {
    /// Keep the legacy name/object contract and publish only once. Scoped subscribers
    /// reject a missing source instead of assigning an event to the active account.
    func postTdUpdate(name: Notification.Name, object: Any, source: TdUpdateSource?) {
        post(
            name: name,
            object: object,
            userInfo: source.map { [TdUpdateSource.userInfoKey: $0] },
        )
    }
}

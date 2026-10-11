// ChatListActionAuthority.swift

import TDLibKit
import UIKit

// MARK: - ChatListActionAuthority

/// A folder or chat ID is meaningful only in the client that supplied it.
@MainActor final class ChatListActionAuthority {
    private static var currentSource: TdUpdateSource? {
        TDLib.shared.activeAccountID.map {
            TdUpdateSource(accountID: $0, clientID: TDLib.shared.activeClient.id)
        }
    }

    let client: TDLibClient

    let source: TdUpdateSource?

    var isCurrent: Bool {
        source != nil && source == Self.currentSource
    }

    init() {
        let client = TDLib.shared.activeClient
        self.client = client
        self.source = TDLib.shared.activeAccountID.map { TdUpdateSource(accountID: $0, clientID: client.id) }
    }

    func scope(owner: UIViewController) -> ChatListActionScope {
        ChatListActionScope(
            source: source,
            currentSource: { Self.currentSource },
            ownerIsAttached: { [weak owner] in owner?.chatListActionOwnerIsAttached == true },
        )
    }
}

// MARK: - ChatListActionScope

/// The same gate wraps production reads, writes and their asynchronous completion.
@MainActor struct ChatListActionScope {
    let source: TdUpdateSource?
    let currentSource: () -> TdUpdateSource?
    let ownerIsAttached: () -> Bool

    var isCurrent: Bool {
        !Task.isCancelled && source != nil && source == currentSource() && ownerIsAttached()
    }

    func check() throws {
        guard isCurrent else { throw CancellationError() }
    }

    func perform<Value>(_ request: @MainActor () async throws -> Value) async throws -> Value {
        try check()
        do {
            let value = try await request()
            try check()
            return value
        } catch {
            try check()
            throw error
        }
    }

    /// Preserve per-chat failure handling, but stop the whole operation when its
    /// originating account, client or controller is no longer current.
    func updateEach<Value>(
        ids: [Int64],
        read: @MainActor (Int64) async throws -> Value,
        write: @MainActor (Int64, Value) async throws -> Void,
    ) async throws {
        var firstError: (any Swift.Error)?
        for id in ids {
            do {
                let value = try await perform { try await read(id) }
                try await perform { try await write(id, value) }
            } catch {
                try check()
                firstError = firstError ?? error
            }
        }
        try check()
        if let firstError { throw firstError }
    }
}

extension UIViewController {
    var chatListActionOwnerIsAttached: Bool {
        var node: UIViewController = self
        var window: UIWindow?
        var visited = Set<ObjectIdentifier>()
        while visited.insert(ObjectIdentifier(node)).inserted {
            guard !node.isBeingDismissed, !node.isMovingFromParent else { return false }
            if let nodeWindow = node.viewIfLoaded?.window {
                guard window == nil || window === nodeWindow else { return false }
                window = nodeWindow
            }
            if let parent = node.parent {
                guard parent.children.contains(where: { $0 === node }) else { return false }
                if let navigation = parent as? UINavigationController {
                    guard navigation.viewControllers.contains(where: { $0 === node }) else { return false }
                }
                // A covered stack entry still owns callbacks, but its navigation
                // controller must itself belong to the live root/presentation tree.
                node = parent
            } else if let presenter = node.presentingViewController {
                guard presenter.presentedViewController === node else { return false }
                node = presenter
            } else {
                // UIKit can keep popped/dismissed pixels attached during teardown.
                // A window alone never grants a detached controller authority.
                return window?.rootViewController === node
            }
        }
        return false
    }
}

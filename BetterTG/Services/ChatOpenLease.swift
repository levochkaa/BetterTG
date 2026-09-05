// ChatOpenLease.swift

import Foundation
import TDLibKit

// MARK: - ChatOpenLeaseKey

struct ChatOpenLeaseKey: Hashable {
    let accountID: UUID?
    let chatID: Int64
    let clientID: Int32
}

// MARK: - ChatOpenLease

final class ChatOpenLease {
    private let lock = NSLock()
    private let releaseAction: @Sendable () -> Void
    private var active = true

    init(key: ChatOpenLeaseKey, coordinator: ChatOpenLeaseCoordinator) {
        self.releaseAction = {
            Task { @MainActor [weak coordinator] in
                coordinator?.release(key: key)
            }
        }
    }

    func invalidate() {
        lock.lock()
        let shouldRelease = active
        active = false
        lock.unlock()
        guard shouldRelease else { return }
        releaseAction()
    }
}

// MARK: - ChatOpenLeaseCoordinator

@MainActor final class ChatOpenLeaseCoordinator {
    private struct Entry {
        let client: TDLibClient
        var leaseCount: Int
    }

    static let shared = ChatOpenLeaseCoordinator()

    private var entries = [ChatOpenLeaseKey: Entry]()
    private var transitions = [ChatOpenLeaseKey: (id: UUID, task: Task<Void, Never>)]()

    private init() {}

    func acquire(location: ChatLocation, client: TDLibClient) -> ChatOpenLease {
        let key = ChatOpenLeaseKey(
            accountID: location.accountID,
            chatID: location.chatID,
            clientID: location.clientID,
        )
        if var entry = entries[key] {
            entry.leaseCount += 1
            entries[key] = entry
        } else {
            entries[key] = Entry(client: client, leaseCount: 1)
            enqueueTransition(key: key) {
                _ = try? await client.openChat(chatId: key.chatID)
            }
        }
        return ChatOpenLease(key: key, coordinator: self)
    }

    func release(key: ChatOpenLeaseKey) {
        guard var entry = entries[key] else { return }
        entry.leaseCount -= 1
        if entry.leaseCount > 0 {
            entries[key] = entry
        } else {
            entries[key] = nil
            let client = entry.client
            enqueueTransition(key: key) {
                _ = try? await client.closeChat(chatId: key.chatID)
            }
        }
    }

    private func enqueueTransition(key: ChatOpenLeaseKey, operation: @escaping @MainActor () async -> Void) {
        let previous = transitions[key]?.task
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await operation()
            if self?.transitions[key]?.id == id {
                self?.transitions[key] = nil
            }
        }
        transitions[key] = (id, task)
    }
}

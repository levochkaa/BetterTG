// ChatDraftKey.swift

import Foundation
import TDLibKitDynamic

// MARK: - ChatDraftKey

/// Stable on-disk identity for composer-owned media. TDLib client identifiers are
/// intentionally excluded because they change after process/account restoration.
struct ChatDraftKey: Codable, Hashable {
    let accountID: UUID?
    let chatID: Int64
    let topic: MessageTopic?

    init(
        accountID: UUID?,
        chatID: Int64,
        topic: MessageTopic?,
    ) {
        self.accountID = accountID
        self.chatID = chatID
        self.topic = topic
    }

    init(location: ChatLocation) {
        self.init(
            accountID: location.accountID,
            chatID: location.chatID,
            topic: location.topic,
        )
    }

    static func legacy(chatID: Int64) -> ChatDraftKey {
        ChatDraftKey(accountID: nil, chatID: chatID, topic: nil)
    }

    func matches(message: Message) -> Bool {
        message.chatId == chatID && message.topicId == topic
    }

    func matches(accountID: UUID?, chatID: Int64) -> Bool {
        self.accountID == accountID && self.chatID == chatID
    }
}

// MARK: - ChatDraftScoped

protocol ChatDraftScoped {
    var chatID: Int64 { get }
    var destination: ChatDraftKey? { get set }
}

extension ChatDraftScoped {
    var resolvedDestination: ChatDraftKey {
        destination ?? .legacy(chatID: chatID)
    }

    func belongs(
        to destination: ChatDraftKey,
        allowingLegacy: Bool = false,
    ) -> Bool {
        if let storedDestination = self.destination {
            return storedDestination == destination
        }
        return destination.topic == nil
            && destination.chatID == chatID
            && (destination.accountID == nil || allowingLegacy)
    }

    func belongsToAccount(_ accountID: UUID?, chatID: Int64) -> Bool {
        if let destination {
            return destination.matches(accountID: accountID, chatID: chatID)
        }
        return accountID == nil && self.chatID == chatID
    }
}

extension ChatLocation {
    var draftKey: ChatDraftKey {
        ChatDraftKey(location: self)
    }
}

// MARK: - ChatDraftLegacyMigrationPolicy

enum ChatDraftLegacyMigrationPolicy {
    private struct Snapshot: Codable {
        let accountIDs: [UUID]
        let version: Int
    }

    private static let lock = NSLock()

    private static var snapshotURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatDraftLegacyMigration", isDirectory: true)
            .appendingPathComponent("accounts-v1.json")
    }

    static func captureIfNeeded(accountIDs: [UUID]) {
        lock.lock()
        defer { lock.unlock() }
        let url = snapshotURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let snapshot = Snapshot(
            accountIDs: accountIDs.sorted { $0.uuidString < $1.uuidString },
            version: 1,
        )
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch {
            log("Chat draft legacy migration snapshot couldn't be saved: \(error)")
        }
    }

    static func canBindLegacyDrafts(to destination: ChatDraftKey) -> Bool {
        guard destination.topic == nil, let accountID = destination.accountID else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == 1
        else { return false }
        return snapshot.accountIDs == [accountID]
    }
}

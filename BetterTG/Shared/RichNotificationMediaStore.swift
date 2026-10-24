// RichNotificationMediaStore.swift

import CryptoKit
import Darwin
import Foundation
import TDLibKit

/// Synchronous utility-queue API; never call on main or under a session lock.
/// Final publication alone may use request ownership -> account flock, never the
/// reverse. Its effect only builds the attachment/body; no main/request/session
/// callbacks, store reentry, await, or donation under flock. Entered consumption
/// can delay expiry/revocation; there is no hard deadline guarantee.
/// The stable flock serializes revision checks, replacement and eviction across
/// processes. An invalidation ACK means a successful write, not power-loss fsync.
final class RichNotificationMediaStore {
    struct Key: Codable, Equatable, Hashable {
        let accountID: Int64
        let chatID: Int64
        let messageID: Int64

        fileprivate var valid: Bool {
            Self(accountID: accountID, chatID: chatID, messageID: messageID) != nil
        }

        init?(accountID: Int64, chatID: Int64, messageID: Int64) {
            guard accountID > 0, chatID != 0, messageID > 0,
                  messageID & ((1 << 20) - 1) == 0,
                  messageID >> 20 <= Int64(Int32.max) else { return nil }
            self.accountID = accountID
            self.chatID = chatID
            self.messageID = messageID
        }
    }

    struct Token: Equatable {
        let key: Key
        let revision: UUID
    }

    struct Evidence: Codable, Equatable {
        static let policyVersion = 1

        let policy: Int
        let peer: RichNotificationPeerReference
        let chatID: Int64
        let messageID: Int64
        let kind: RichNotificationMediaCandidate.Kind
        let resourceFingerprint: String

        /// `chat` must be the exact cloud Chat resolved by the captured client.
        /// Numeric raw-chat mapping alone cannot certify that it isn't secret.
        init?(key: Key, message: Message, chat: Chat, candidate: RichNotificationMediaCandidate, producerID: UUID) {
            let peer: RichNotificationPeerReference
            switch chat.type {
            case .chatTypePrivate(let value): peer = .init(kind: .privateChat, id: value.userId)
            case .chatTypeBasicGroup(let value): peer = .init(kind: .basicGroup, id: value.basicGroupId)
            case .chatTypeSupergroup(let value): peer = .init(kind: .supergroup, id: value.supergroupId)
            case .chatTypeSecret: return nil
            }
            guard key.valid, chat.id == key.chatID, message.chatId == key.chatID, message.id == key.messageID,
                  let target = RichNotificationTarget(
                      accountID: key.accountID,
                      peer: peer,
                      serverMessageID: key.messageID >> 20,
                  ),
                  target.expectedChatID == key.chatID, target.matches(chat: chat, requestedChatID: key.chatID),
                  RichNotificationMediaCandidate(message: message) == candidate else { return nil }
            self.policy = Self.policyVersion
            self.peer = peer
            self.chatID = key.chatID
            self.messageID = key.messageID
            self.kind = candidate.kind
            self.resourceFingerprint = candidate.file.remote.uniqueId.isEmpty
                ? "local:\(producerID.uuidString):\(candidate.file.id)"
                : "remote:\(candidate.file.remote.uniqueId)"
            guard resourceFingerprint.utf8.count <= 1024 else { return nil }
        }

        fileprivate func matches(_ key: Key) -> Bool {
            key.valid && policy == Self.policyVersion && chatID == key.chatID && messageID == key.messageID
                && !resourceFingerprint.isEmpty && resourceFingerprint.utf8.count <= 1024
                && RichNotificationTarget(accountID: key.accountID, peer: peer, serverMessageID: key.messageID >> 20)?
                .expectedChatID == key.chatID
        }
    }

    struct Receipt: Equatable {
        let key: Key
        let revision: UUID
        let evidence: Evidence
        let digest: String
    }

    private enum Status: String, Codable { case pending, valid, invalidated }
    private struct Record: Codable {
        let schema: Int
        let key: Key
        let revision: UUID
        let status: Status
        let evidence: Evidence?
        let jpeg: Data?
        let digest: String?
        let rank: Int?
    }

    static let maximumRecords = 128
    static let maximumInputBytes = 16 * 1024 * 1024
    static let maximumJPEGBytes = 4 * 1024 * 1024
    static let maximumRecordBytes = 5 * 1024 * 1024

    private let containerURL: () -> URL?

    init(containerURL: @escaping () -> URL? = { BetterTGAppGroup.containerURL() }) {
        self.containerURL = containerURL
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func prepare(_ key: Key) -> Token? {
        guard key.valid else { return nil }
        let token = Token(key: key, revision: UUID())
        return locked(key.accountID) { directory in
            try write(Record(
                schema: 2,
                key: key,
                revision: token.revision,
                status: .pending,
                evidence: nil,
                jpeg: nil,
                digest: nil,
                rank: nil,
            ), in: directory)
            return token
        }
    }

    @discardableResult func invalidate(_ key: Key) -> Bool {
        guard key.valid else { return false }
        return locked(key.accountID) { directory in
            try write(Record(
                schema: 2,
                key: key,
                revision: UUID(),
                status: .invalidated,
                evidence: nil,
                jpeg: nil,
                digest: nil,
                rank: nil,
            ), in: directory)
            return true
        } ?? false
    }

    /// Overflow barrier: only this account's owned v2 records are removed.
    /// Partial I/O failure returns no ACK. The stable lock and legacy data stay.
    @discardableResult func invalidateAccount(_ accountID: Int64) -> Bool {
        locked(accountID) { directory in
            let urls = try recordURLs(in: directory, accountID: accountID)
            guard urls.count <= Self.maximumRecords else { return false }
            var success = true
            for url in urls {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    success = false
                }
            }
            return try success && recordURLs(in: directory, accountID: accountID).isEmpty
        } ?? false
    }

    /// Normalize before flock. Failed writes never advance rank. Only the exact
    /// existing prepared revision can commit; absence/eviction is not an upsert.
    @discardableResult func commit(_ token: Token, evidence: Evidence, data: Data, rank: Int) -> Bool {
        guard token.key.valid, evidence.matches(token.key), (0...1).contains(rank),
              !data.isEmpty, data.count <= Self.maximumInputBytes,
              let jpeg = RichNotificationCache.normalizedJPEG(data, maximumPixelSize: 1280),
              jpeg.count <= Self.maximumJPEGBytes else { return false }
        let digest = Self.digest(jpeg)
        return locked(token.key.accountID) { directory in
            guard let existing = try readRecord(token.key, in: directory), existing.revision == token.revision,
                  existing.status == .pending || existing.status == .valid else { return false }
            if existing.status == .valid {
                guard existing.evidence == evidence, let oldRank = existing.rank else { return false }
                if oldRank >= rank { return oldRank == rank && existing.digest == digest }
            }
            try write(Record(
                schema: 2,
                key: token.key,
                revision: token.revision,
                status: .valid,
                evidence: evidence,
                jpeg: jpeg,
                digest: digest,
                rank: rank,
            ), in: directory)
            return true
        } ?? false
    }

    func read(_ key: Key) -> Receipt? {
        guard key.valid else { return nil }
        return locked(key.accountID) { directory -> Receipt? in
            guard let record = try readRecord(key, in: directory), record.status == .valid,
                  let evidence = record.evidence, let digest = record.digest else { return nil }
            return Receipt(key: key, revision: record.revision, evidence: evidence, digest: digest)
        } ?? nil
    }

    /// Revalidates even receipts read before invalidation ACK. The synchronous
    /// effect runs under flock: no await, dispatch-to-main, or store reentry.
    /// It may finish before a competing invalidation can ACK, never after ACK.
    func withCurrent<T>(_ receipt: Receipt, effect: (Data) -> T) -> T? {
        guard receipt.key.valid else { return nil }
        return locked(receipt.key.accountID) { directory -> T? in
            guard let record = try readRecord(receipt.key, in: directory), record.status == .valid,
                  record.revision == receipt.revision, record.evidence == receipt.evidence,
                  record.digest == receipt.digest, let jpeg = record.jpeg else { return nil }
            return effect(jpeg)
        } ?? nil
    }

    private func locked<T>(_ accountID: Int64, _ operation: (URL) throws -> T) -> T? {
        guard accountID > 0, let root = containerURL() else { return nil }
        do {
            let account = root.appendingPathComponent("RichNotifications/accounts/\(accountID)", isDirectory: true)
            try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
            let descriptor = open(
                account.appendingPathComponent("media-v2.lock").path,
                O_CREAT | O_RDWR,
                S_IRUSR | S_IWUSR,
            )
            guard descriptor >= 0 else { return nil }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX) == 0 else { return nil }
            defer { flock(descriptor, LOCK_UN) }
            let directory = account.appendingPathComponent("media-v2", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try operation(directory)
        } catch {
            return nil
        }
    }

    private func write(_ record: Record, in directory: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(record)
        guard data.count <= Self.maximumRecordBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        let destination = url(record.key, in: directory)
        let existing = try recordURLs(in: directory, accountID: record.key.accountID)
        if !existing.contains(destination), existing.count >= Self.maximumRecords {
            let oldest = existing.sorted {
                let lhs = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let rhs = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if lhs == rhs { return $0.lastPathComponent < $1.lastPathComponent }
                return (lhs ?? .distantPast) < (rhs ?? .distantPast)
            }
            for evicted in oldest.prefix(existing.count - Self.maximumRecords + 1) {
                try FileManager.default.removeItem(at: evicted)
            }
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func readRecord(_ key: Key, in directory: URL) throws -> Record? {
        let file = try FileHandle(forReadingFrom: url(key, in: directory))
        defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size > 0, size <= Self.maximumRecordBytes else { return nil }
        try file.seek(toOffset: 0)
        guard let data = try file.read(upToCount: Self.maximumRecordBytes + 1), data.count == size,
              data.count <= Self.maximumRecordBytes,
              let record = try? PropertyListDecoder().decode(Record.self, from: data),
              record.schema == 2, record.key == key else { return nil }
        switch record.status {
        case .invalidated,
             .pending:
            guard record.evidence == nil, record.jpeg == nil, record.digest == nil,
                  record.rank == nil else { return nil }
        case .valid:
            guard let evidence = record.evidence, evidence.matches(key), let jpeg = record.jpeg,
                  !jpeg.isEmpty, jpeg.count <= Self.maximumJPEGBytes,
                  let rank = record.rank, (0...1).contains(rank), record.digest == Self.digest(jpeg) else { return nil }
        }
        return record
    }

    private func recordURLs(in directory: URL, accountID: Int64) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey],
            )
            .filter { url in
                guard url.pathExtension == "record" else { return false }
                let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_")
                guard parts.count == 2, Int64(parts[0]).flatMap({ chat in
                    Int64(parts[1]).flatMap { Key(accountID: accountID, chatID: chat, messageID: $0) }
                }) != nil else { return false }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw CocoaError(.fileReadUnsupportedScheme)
                }
                return true
            }
    }

    private func url(_ key: Key, in directory: URL) -> URL {
        directory.appendingPathComponent("\(key.chatID)_\(key.messageID).record")
    }
}

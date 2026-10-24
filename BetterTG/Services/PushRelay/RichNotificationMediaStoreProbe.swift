// RichNotificationMediaStoreProbe.swift

#if DEBUG
    import Foundation
    import TDLibKit
    import UIKit

    enum RichNotificationMediaStoreProbe {
        private typealias Store = RichNotificationMediaStore
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        private final class ReceiptBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value: Bool?

            func set(_ value: Bool) { lock.lock()
            self.value = value
            lock.unlock()
            }

            func get() -> Bool? { lock.lock()
            defer { lock.unlock() }
            return value
            }
        }

        @MainActor static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-notification-media-store") else { return }
            let message = RichNotificationMediaPrewarmerProbe.message(
                RichNotificationMediaPrewarmerProbe.content(.photo), chatID: -7,
            )
            let chat = ProbeFixtures.chat(
                .init(isPinned: false, list: .chatListMain, order: 1, source: nil),
                id: -7,
            )
.chat
            let hidden = RichNotificationMediaPrewarmerProbe.message(
                RichNotificationMediaPrewarmerProbe.content(.photo, spoiler: true), chatID: -7,
            )
            Task {
                let report = await Task.detached(priority: .utility) {
                    do {
                        try verify(message: message, chat: chat, hidden: hidden)
                        return "PASS: real v2 store/two instances/isolated JPEG IO on utility; exact full evidence/cloud identity; "
                            + "atomic pending/valid/invalidated, increasing rank, CAS missing/revoked/evicted refused; "
                            + "bounded records/input/envelope, schema/key/policy/digest corruption rejected; "
                            + "receipt revalidated under flock, held consume precedes competing revocation ACK; "
                            + "account clear invalidates token/receipt, failed IO has no ACK, legacy/avatar untouched; "
                            + "app/NSE integration/cross-process delivery/power-loss durability=unverified; RPC/donations=0"
                    } catch {
                        return "FAIL: \(error)"
                    }
                }.value
                log(report)
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(report.utf8).write(
                        to: documents.appendingPathComponent("notification-media-store-probe.txt"), options: .atomic,
                    )
                }
            }
        }

        private static func verify(message: Message, chat: Chat, hidden: Message) throws {
            try require(!Thread.isMainThread, "store fixture is running on main")
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent(
                "notification-media-store-\(UUID())",
                isDirectory: true,
            )
            defer { try? fm.removeItem(at: root) }
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let first = Store(containerURL: { root })
            let second = Store(containerURL: { root })
            let key = Store.Key(accountID: 101, chatID: -7, messageID: message.id)!
            let other = Store.Key(accountID: 202, chatID: -7, messageID: message.id)!
            let candidate = RichNotificationMediaCandidate(message: message)!
            let producer = UUID()
            guard let evidence = Store.Evidence(
                key: key,
                message: message,
                chat: chat,
                candidate: candidate,
                producerID: producer,
            ),
                  let otherEvidence = Store.Evidence(
                      key: other,
                      message: message,
                      chat: chat,
                      candidate: candidate,
                      producerID: producer,
                  )
            else { throw Failure(description: "eligible cloud evidence absent") }
            try require(
                RichNotificationMediaCandidate(message: hidden) == nil
                        && Store.Evidence(
                            key: key,
                            message: hidden,
                            chat: chat,
                            candidate: candidate,
                            producerID: producer,
                        ) == nil,
                "spoiler message certified by candidate reuse",
            )
            let wrongKey = Store.Key(accountID: 101, chatID: 7, messageID: message.id)!
            try require(
                Store
                    .Evidence(
                        key: wrongKey,
                        message: message,
                        chat: chat,
                        candidate: candidate,
                        producerID: producer,
                    ) ==
                    nil,
                "numeric key certified wrong cloud chat",
            )
            try verifySecretChat(key: key, message: message, chat: chat, candidate: candidate, producer: producer)
            for invalid in [
                Store.Key(accountID: 0, chatID: -7, messageID: message.id),
                Store.Key(accountID: 101, chatID: 0, messageID: message.id),
                Store.Key(accountID: 101, chatID: -7, messageID: 0),
                Store.Key(accountID: 101, chatID: -7, messageID: message.id + 1),
                Store.Key(accountID: 101, chatID: -7, messageID: (Int64(Int32.max) + 1) << 20),
            ] {
                try require(invalid == nil, "invalid raw identity accepted")
            }
            let red = image(.red)
            let blue = image(.blue)
            let expectedRed = RichNotificationCache.normalizedJPEG(red, maximumPixelSize: 1280)!
            let expectedBlue = RichNotificationCache.normalizedJPEG(blue, maximumPixelSize: 1280)!
            try require(expectedRed != expectedBlue, "JPEG colors not armed")

            let legacy = root.appendingPathComponent("RichNotifications/accounts/101/media/legacy.jpg")
            let avatar = root.appendingPathComponent("RichNotifications/accounts/101/avatars/legacy.jpg")
            for url in [legacy, avatar] {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try red.write(to: url)
            }
            try require(first.read(key) == nil, "v2 read used legacy bytes")
            guard let token = first.prepare(key) else { throw Failure(description: "prepare failed") }
            try require(second.read(key) == nil, "pending record exposed bytes")
            try require(second.commit(token, evidence: evidence, data: red, rank: 0), "placeholder commit failed")
            guard let low = first.read(key) else { throw Failure(description: "placeholder receipt absent") }
            try require(second.withCurrent(low) { $0 == expectedRed } == true, "placeholder bytes differ")
            try require(first.commit(token, evidence: evidence, data: blue, rank: 1), "full upgrade failed")
            guard let receipt = second.read(key) else { throw Failure(description: "full receipt absent") }
            try require(
                first.withCurrent(receipt) { $0 == expectedBlue } == true
                        && first.withCurrent(low) { _ in true } == nil,
                "full bytes changed or old digest receipt remained current",
            )
            try require(
                !second.commit(token, evidence: evidence, data: red, rank: 0)
                        && !second.commit(token, evidence: evidence, data: red, rank: 1)
                        && second.commit(token, evidence: evidence, data: blue, rank: 1),
                "rank/digest monotonicity failed",
            )
            try require(
                !first.commit(token, evidence: otherEvidence, data: Data(), rank: 1)
                        && !first.commit(token, evidence: evidence, data: red, rank: 2)
                        && !first.commit(
                            token,
                            evidence: evidence,
                            data: Data(repeating: 0, count: Store.maximumInputBytes + 1),
                            rank: 1,
                        ),
                "invalid input/rank accepted",
            )
            guard let otherToken = second.prepare(other)
                else { throw Failure(description: "second account prepare failed") }
            try require(
                second.commit(otherToken, evidence: otherEvidence, data: red, rank: 1),
                "second account commit failed",
            )
            guard let otherReceipt = second.read(other)
                else { throw Failure(description: "second account receipt absent") }
            try require(first.withCurrent(otherReceipt) { $0 == expectedRed } == true, "account bytes crossed")

            try verifyCorruption(root: root, key: key, receipt: receipt, store: first)
            try require(
                first.invalidate(key) && second.read(key) == nil
                        && second.withCurrent(receipt) { _ in true } == nil
                        && !second.commit(token, evidence: evidence, data: red, rank: 1),
                "revoked lease resurrected",
            )
            let absent = Store.Key(accountID: 101, chatID: -7, messageID: 999 << 20)!
            try require(first.invalidate(absent) && second.read(absent) == nil, "absent-job revoke failed")
            guard let refreshed = first.prepare(key) else { throw Failure(description: "reprepare failed") }
            try require(
                second.commit(refreshed, evidence: evidence, data: red, rank: 1)
                        && !second.commit(token, evidence: evidence, data: blue, rank: 1),
                "old token replaced fresh revision",
            )
            try verifyConsumption(root: root, key: key, evidence: evidence, bytes: blue)
            guard let evicted = first.prepare(key) else { throw Failure(description: "eviction token absent") }
            try fm.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1)],
                ofItemAtPath: record(root, key: key).path,
            )
            for id in 1000..<1128 {
                let added = Store.Key(accountID: 101, chatID: -7, messageID: Int64(id) << 20)!
                try require(first.prepare(added) != nil, "bounded prepare failed")
            }
            let files = try fm.contentsOfDirectory(at: directory(root, account: 101), includingPropertiesForKeys: nil)
            try require(
                files.count(where: { $0.pathExtension == "record" }) == Store.maximumRecords
                        && !second.commit(evicted, evidence: evidence, data: blue, rank: 1),
                "evicted lease recreated record",
            )
            guard let clearing = first.prepare(key) else { throw Failure(description: "clear token absent") }
            try require(first.commit(clearing, evidence: evidence, data: red, rank: 1), "clear candidate absent")
            guard let clearingReceipt = first.read(key) else { throw Failure(description: "clear receipt absent") }
            let lockURL = directory(root, account: 101)
.deletingLastPathComponent()
                .appendingPathComponent("media-v2.lock")
            let inode = try fm.attributesOfItem(atPath: lockURL.path)[.systemFileNumber] as? NSNumber
            try require(
                first.invalidateAccount(101) && first.invalidateAccount(101)
                        && second.withCurrent(clearingReceipt) { _ in true } == nil
                        && !second.commit(clearing, evidence: evidence, data: blue, rank: 1),
                "account clear left live lease",
            )
            try require(
                (fm.attributesOfItem(atPath: lockURL.path)[.systemFileNumber] as? NSNumber) == inode,
                "stable lock inode replaced",
            )
            try require(
                second.withCurrent(otherReceipt) { $0 == expectedRed } == true
                        && Data(contentsOf: legacy) == red && Data(contentsOf: avatar) == red,
                "clear touched another account/legacy/avatar",
            )
            try verifyFailures(root: root, key: key, store: first)
        }

        private static func verifySecretChat(
            key: Store.Key,
            message: Message,
            chat: Chat,
            candidate: RichNotificationMediaCandidate,
            producer: UUID,
        ) throws {
            let secret = replacingType(of: chat, with: .chatTypeSecret(ChatTypeSecret(secretChatId: 1, userId: 7)))
            try require(
                Store
                    .Evidence(key: key, message: message, chat: secret, candidate: candidate, producerID: producer) ==
                    nil,
                "secret Chat admitted by matching numeric key",
            )
        }

        /// Native TDLibKit 2 views are immutable and not Codable; copy every field except the type.
        private static func replacingType(of chat: Chat, with type: ChatType) -> Chat {
            Chat(
                id: chat.id,
                type: type,
                title: chat.title,
                photo: chat.photo,
                accentColorId: chat.accentColorId,
                backgroundCustomEmojiId: chat.backgroundCustomEmojiId,
                upgradedGiftColors: chat.upgradedGiftColors,
                profileAccentColorId: chat.profileAccentColorId,
                profileBackgroundCustomEmojiId: chat.profileBackgroundCustomEmojiId,
                permissions: chat.permissions,
                lastMessage: chat.lastMessage,
                positions: chat.positions,
                chatLists: chat.chatLists,
                messageSenderId: chat.messageSenderId,
                blockList: chat.blockList,
                hasProtectedContent: chat.hasProtectedContent,
                isTranslatable: chat.isTranslatable,
                isMarkedAsUnread: chat.isMarkedAsUnread,
                viewAsTopics: chat.viewAsTopics,
                hasScheduledMessages: chat.hasScheduledMessages,
                hasWelcomeMessages: chat.hasWelcomeMessages,
                canBeDeletedOnlyForSelf: chat.canBeDeletedOnlyForSelf,
                canBeDeletedForAllUsers: chat.canBeDeletedForAllUsers,
                canBeReported: chat.canBeReported,
                defaultDisableNotification: chat.defaultDisableNotification,
                unreadCount: chat.unreadCount,
                lastReadInboxMessageId: chat.lastReadInboxMessageId,
                lastReadOutboxMessageId: chat.lastReadOutboxMessageId,
                unreadMentionCount: chat.unreadMentionCount,
                unreadReactionCount: chat.unreadReactionCount,
                unreadPollVoteCount: chat.unreadPollVoteCount,
                notificationSettings: chat.notificationSettings,
                availableReactions: chat.availableReactions,
                messageAutoDeleteTime: chat.messageAutoDeleteTime,
                emojiStatus: chat.emojiStatus,
                background: chat.background,
                theme: chat.theme,
                actionBar: chat.actionBar,
                businessBotManageBar: chat.businessBotManageBar,
                videoChat: chat.videoChat,
                pendingJoinRequests: chat.pendingJoinRequests,
                replyMarkupMessageId: chat.replyMarkupMessageId,
                draftMessage: chat.draftMessage,
                clientData: chat.clientData,
            )
        }

        private static func verifyCorruption(root: URL, key: Store.Key, receipt: Store.Receipt, store: Store) throws {
            let url = record(root, key: key)
            let original = try Data(contentsOf: url)
            defer { try? original.write(to: url, options: .atomic) }
            let plist = try PropertyListSerialization.propertyList(
                from: original,
                // C++ interop imports these options without the Objective-C default argument.
                options: PropertyListSerialization.ReadOptions(),
                format: nil,
            ) as! [String: Any]
            for field in ["schema", "digest", "key", "evidence"] {
                var altered = plist
                switch field {
                case "schema": altered[field] = 99
                case "digest": altered[field] = "wrong"
                case "key":
                    var value = altered[field] as! [String: Any]
                    value["accountID"] = 202
                    altered[field] = value
                default:
                    var value = altered[field] as! [String: Any]
                    value["policy"] = 99
                    altered[field] = value
                }
                try PropertyListSerialization.data(fromPropertyList: altered, format: .binary, options: 0).write(
                    to: url,
                    options: .atomic,
                )
                try require(
                    store.read(key) == nil && store.withCurrent(receipt) { _ in true } == nil,
                    "corrupt \(field) admitted",
                )
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(Store.maximumRecordBytes + 1))
            try handle.close()
            try require(store.read(key) == nil, "oversized envelope admitted")
            try Data([0, 1]).write(to: url, options: .atomic)
            try require(store.read(key) == nil, "malformed envelope admitted")
        }

        private static func verifyConsumption(root: URL, key: Store.Key, evidence: Store.Evidence, bytes: Data) throws {
            let store = Store(containerURL: { root })
            guard let token = store.prepare(key), store.commit(token, evidence: evidence, data: bytes, rank: 1),
                  let receipt = store.read(key) else { throw Failure(description: "consume fixture not armed") }
            let entered = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let consumeDone = DispatchSemaphore(value: 0)
            let revokeEntered = DispatchSemaphore(value: 0)
            let revokeDone = DispatchSemaphore(value: 0)
            let consumed = ReceiptBox()
            let revoked = ReceiptBox()
            defer { release.signal() }
            DispatchQueue.global(qos: .utility).async {
                let local = Store(containerURL: { root })
                let result = local.withCurrent(receipt) { data in
                    entered.signal()
                    guard release.wait(timeout: .now() + 5) == .success else { return false }
                    return data == RichNotificationCache.normalizedJPEG(bytes, maximumPixelSize: 1280)
                }
                consumed.set(result == true)
                consumeDone.signal()
            }
            try require(entered.wait(timeout: .now() + 5) == .success, "consume lock not entered")
            DispatchQueue.global(qos: .utility).async {
                revokeEntered.signal()
                revoked.set(Store(containerURL: { root }).invalidate(key))
                revokeDone.signal()
            }
            try require(
                revokeEntered.wait(timeout: .now() + 5) == .success && revoked.get() == nil,
                "revocation acknowledged inside held consume",
            )
            release.signal()
            try require(
                consumeDone.wait(timeout: .now() + 5) == .success
                        && revokeDone.wait(timeout: .now() + 5) == .success
                        && consumed.get() == true && revoked.get() == true,
                "held consume/revoke did not finish",
            )
            try require(store.withCurrent(receipt) { _ in true } == nil, "pre-ACK receipt consumed after ACK")
        }

        private static func verifyFailures(root: URL, key: Store.Key, store: Store) throws {
            var lookups = 0
            let invalid = Store(containerURL: { lookups += 1
            return root
            })
            try require(!invalid.invalidateAccount(0) && lookups == 0, "invalid account touched storage")
            let unavailable = Store(containerURL: { nil })
            try require(
                unavailable.prepare(key) == nil && !unavailable.invalidate(key)
                        && !unavailable.invalidateAccount(key.accountID),
                "unavailable root acknowledged",
            )
            let fileRoot = root.appendingPathComponent("not-a-directory")
            try Data([1]).write(to: fileRoot)
            let blocked = Store(containerURL: { fileRoot })
            try require(
                blocked.prepare(key) == nil && !blocked.invalidate(key)
                        && !blocked.invalidateAccount(key.accountID),
                "failed write acknowledged",
            )
            let obstructed = record(root, key: key)
            try FileManager.default.createDirectory(at: obstructed, withIntermediateDirectories: true)
            let marker = obstructed.appendingPathComponent("untouched")
            try Data([4]).write(to: marker)
            try require(
                !store.invalidate(key) && !store.invalidateAccount(key.accountID)
                        && Data(contentsOf: marker) == Data([4]),
                "directory obstruction acknowledged or recursively removed",
            )
            try FileManager.default.removeItem(at: obstructed)
            try require(store.invalidate(key), "failed write became permanently deduped")
        }

        private static func directory(_ root: URL, account: Int64) -> URL {
            root.appendingPathComponent("RichNotifications/accounts/\(account)/media-v2", isDirectory: true)
        }

        private static func record(_ root: URL, key: Store.Key) -> URL {
            directory(root, account: key.accountID).appendingPathComponent("\(key.chatID)_\(key.messageID).record")
        }

        private static func image(_ color: UIColor) -> Data {
            UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
        }

        private static func require(_ condition: Bool, _ detail: String) throws {
            if !condition { throw Failure(description: detail) }
        }
    }
#endif

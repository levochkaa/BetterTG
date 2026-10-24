// RichNotificationCacheProbe.swift

#if DEBUG
    import Combine
    import UIKit

    @MainActor enum RichNotificationCacheProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-notification-cache-scope") else { return }
            Task {
                let result: String
                do {
                    try verifyCache()
                    try await verifySourceAdmission()
                    result = "PASS: real JPEG/cache IO in isolated temporary root; colliding peer/message IDs isolated; "
                        + "nil/invalid scope performs no container lookup; legacy files untouched/unread; "
                        + "exact nonnil account matching; queued scoped publisher and delayed source/client admission=true; "
                        + "file-ID generations isolated; actual coordinator TDLib/NSE delivery/main-thread relief=unverified; RPC/account-stores=0"
                } catch {
                    result = "FAIL: \(error)"
                }
                log(result)
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("notification-cache-scope-probe.txt"), options: .atomic,
                    )
                }
            }
        }

        private static func verifyCache() throws {
            let manager = FileManager.default
            let root = manager.temporaryDirectory.appendingPathComponent(
                "notification-cache-scope-\(UUID())",
                isDirectory: true,
            )
            defer { try? manager.removeItem(at: root) }
            var containerLookups = 0
            let container = { containerLookups += 1
            return Optional(root)
            }
            let peer = RichNotificationPeerReference(kind: .privateChat, id: 77)
            let message = RichNotificationMessageReference(peer: peer, serverMessageID: 88)
            let red = image(.red)
            let blue = image(.blue)
            for account: Int64? in [nil, 0, -1] {
                RichNotificationCache.cacheAvatar(red, for: peer, accountID: account, containerURL: container)
                RichNotificationCache.cacheMedia(red, for: message, accountID: account, containerURL: container)
                try require(
                    RichNotificationCache.avatarData(for: peer, accountID: account, containerURL: container) == nil
                        && RichNotificationCache
                            .mediaURL(for: message, accountID: account, containerURL: container) == nil,
                    "invalid scope exposed cache data",
                )
            }
            try require(
                containerLookups == 0 && !manager.fileExists(atPath: root.path),
                "invalid scope touched storage",
            )
            try require(
                !RichNotificationCache.matchesAccount(nil, boundUserID: nil)
                    && !RichNotificationCache.matchesAccount(0, boundUserID: 0)
                    && !RichNotificationCache.matchesAccount(101, boundUserID: 202)
                    && RichNotificationCache.matchesAccount(101, boundUserID: 101),
                "missing or mismatched account selected a session",
            )

            let legacy = root.appendingPathComponent("RichNotifications", isDirectory: true)
            let legacyAvatars = legacy.appendingPathComponent("avatars", isDirectory: true)
            let legacyMedia = legacy.appendingPathComponent("media", isDirectory: true)
            try manager.createDirectory(at: legacyAvatars, withIntermediateDirectories: true)
            try manager.createDirectory(at: legacyMedia, withIntermediateDirectories: true)
            let oldAvatar = legacyAvatars.appendingPathComponent("\(peer.cacheKey).jpg")
            let oldMedia = legacyMedia.appendingPathComponent("\(message.cacheKey).jpg")
            try red.write(to: oldAvatar)
            try red.write(to: oldMedia)
            // Enough old entries to detect accidental legacy-directory trimming.
            for index in 0..<129 {
                try red.write(to: legacyMedia.appendingPathComponent("legacy-\(index).jpg"))
            }
            let legacyNames = try manager.contentsOfDirectory(atPath: legacyMedia.path).sorted()
            for account: Int64 in [101, 202] {
                try require(
                    RichNotificationCache.avatarData(for: peer, accountID: account, containerURL: container) == nil
                        && RichNotificationCache
                            .mediaURL(for: message, accountID: account, containerURL: container) == nil,
                    "account namespace fell back to unscoped legacy entry",
                )
            }
            RichNotificationCache.cacheAvatar(red, for: peer, accountID: 101, containerURL: container)
            RichNotificationCache.cacheAvatar(blue, for: peer, accountID: 202, containerURL: container)
            RichNotificationCache.cacheMedia(red, for: message, accountID: 101, containerURL: container)
            RichNotificationCache.cacheMedia(blue, for: message, accountID: 202, containerURL: container)
            guard let avatarA = RichNotificationCache.avatarData(for: peer, accountID: 101, containerURL: container),
                  let avatarB = RichNotificationCache.avatarData(for: peer, accountID: 202, containerURL: container),
                  let mediaA = RichNotificationCache.mediaURL(for: message, accountID: 101, containerURL: container),
                  let mediaB = RichNotificationCache.mediaURL(for: message, accountID: 202, containerURL: container)
            else { throw Failure(description: "valid scoped cache did not round trip") }
            let mediaDataA = try Data(contentsOf: mediaA)
            let mediaDataB = try Data(contentsOf: mediaB)
            try require(
                avatarA != avatarB && avatarA == RichNotificationCache.normalizedJPEG(red, maximumPixelSize: 256)
                    && avatarB == RichNotificationCache.normalizedJPEG(blue, maximumPixelSize: 256)
                    && mediaA != mediaB && mediaDataA != mediaDataB
                    && mediaDataA == RichNotificationCache.normalizedJPEG(red, maximumPixelSize: 1280)
                    && mediaDataB == RichNotificationCache.normalizedJPEG(blue, maximumPixelSize: 1280),
                "colliding peer/message payloads crossed account namespaces",
            )
            let remainingAvatar = try Data(contentsOf: oldAvatar)
            let remainingMedia = try Data(contentsOf: oldMedia)
            let remainingNames = try manager.contentsOfDirectory(atPath: legacyMedia.path).sorted()
            try require(
                remainingAvatar == red && remainingMedia == red && remainingNames == legacyNames
                    && peer.cacheKey == "private-77" && message.cacheKey == "private-77-88",
                "logical identity or legacy files changed",
            )
            try require(
                RichNotificationCache.avatarData(for: peer, accountID: 101, containerURL: { nil }) == nil,
                "unavailable app-group storage used a fallback",
            )
        }

        private static func verifySourceAdmission() async throws {
            let sourceA = TdUpdateSource(accountID: UUID(), clientID: 11)
            let sourceB = TdUpdateSource(accountID: UUID(), clientID: 22)
            let replacement = TdUpdateSource(accountID: sourceB.accountID, clientID: 23)
            let accountA = account(sourceA.accountID, userID: 101)
            let accountB = account(sourceB.accountID, userID: 202)
            let scopeA = RichNotificationCacheSource(updateSource: sourceA, userID: 101)
            let scopeB = RichNotificationCacheSource(updateSource: sourceB, userID: 202)
            let scopeReplacement = RichNotificationCacheSource(updateSource: replacement, userID: 202)
            var currentSource = sourceA
            var currentAccount = accountA
            let center = NotificationCenter()
            let notification = TdNotification<Int>(.init("notification-cache-source-\(UUID())"))
            var cancellables = Set<AnyCancellable>()
            var admitted = [Int]()
            center.scopedPublisher(&cancellables, for: notification) { update in
                guard let userID = currentAccount.userID else { return }
                let captured = RichNotificationCacheSource(updateSource: update.source, userID: userID)
                if captured
                    .isCurrent(source: currentSource, account: currentAccount, clientID: currentSource.clientID)
                {
                    admitted.append(update.value)
                }
            }
            center.postTdUpdate(name: notification.name, object: 1, source: sourceA)
            currentSource = sourceB
            currentAccount = accountB
            center.postTdUpdate(name: notification.name, object: 2, source: sourceB)
            center.postTdUpdate(name: notification.name, object: 3, source: nil)
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            try require(admitted == [2], "queued old or unscoped publication acquired the active source")
            try require(
                scopeB.isCurrent(source: currentSource, account: currentAccount, clientID: currentSource.clientID),
                "current captured context was not admitted",
            )
            // The real coordinator invokes this same predicate after each await.
            // This fixture changes generation across an await, without a TDLib RPC.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { currentSource = replacement
                continuation.resume()
                }
            }
            try require(
                !scopeB.isCurrent(source: currentSource, account: currentAccount, clientID: currentSource.clientID)
                    && !scopeA.isCurrent(
                        source: currentSource,
                        account: currentAccount,
                        clientID: currentSource.clientID,
                    )
                    && !scopeReplacement.isCurrent(source: currentSource, account: currentAccount, clientID: nil)
                    && !scopeReplacement.isCurrent(source: currentSource, account: currentAccount, clientID: 22)
                    && !scopeReplacement.isCurrent(
                        source: currentSource,
                        account: account(sourceB.accountID, userID: nil),
                        clientID: 23,
                    )
                    && !scopeReplacement.isCurrent(
                        source: currentSource,
                        account: account(sourceB.accountID, userID: 303),
                        clientID: 23,
                    )
                    && scopeReplacement.isCurrent(source: currentSource, account: currentAccount, clientID: 23),
                "old await result, missing identity, or unavailable client acquired current cache authority",
            )
            let peerA = RichNotificationPeerReference(kind: .privateChat, id: 77)
            let peerB = RichNotificationPeerReference(kind: .basicGroup, id: 77)
            var references = RichNotificationAvatarReferences()
            references.bind(scopeA)
            _ = references.replace(peerA, fileIDs: [9], source: scopeA)
            try require(references.references(for: 9, source: scopeA) == [peerA], "initial avatar reference missing")
            references.bind(scopeB)
            _ = references.replace(peerA, fileIDs: [9], source: scopeA)
            try require(references.references(for: 9, source: scopeB) == nil, "old account file ID survived reset")
            _ = references.replace(peerB, fileIDs: [9], source: scopeB)
            try require(references.references(for: 9, source: scopeB) == [peerB], "current colliding file ID rejected")
            references.bind(scopeReplacement)
            try require(
                references.references(for: 9, source: scopeB) == nil
                    && references.references(for: 9, source: scopeReplacement) == nil,
                "same-account replacement reused the old client file map",
            )
        }

        private static func image(_ color: UIColor) -> Data {
            UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
        }

        private static func account(_ id: UUID, userID: Int64?) -> TelegramAccount {
            .init(
                id: id,
                displayName: nil,
                phoneNumber: nil,
                userID: userID,
                createdAt: .distantPast,
                lastActiveAt: .distantPast,
            )
        }

        private static func require(_ condition: Bool, _ detail: String) throws {
            if !condition { throw Failure(description: detail) }
        }
    }
#endif

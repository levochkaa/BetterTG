// RootScopeSettingsLoadingProbe.swift

#if DEBUG
    import Foundation
    import TDLibKit

    @MainActor enum RootScopeSettingsLoadingProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }
        @MainActor private final class Fixture {
            let loader = RootScopeSettingsLoading()
            let authority = RootListAuthority()
            var source = TdUpdateSource(accountID: UUID(), clientID: 1)
            var values = [NotificationSettingsScope: ScopeNotificationSettings]()
            var fetches = [NotificationSettingsScope]()
            var publications = [NotificationSettingsScope]()
            var pending = [Int: CheckedContinuation<ScopeNotificationSettings, Swift.Error>]()
            var tasks = [Task<Void, Never>]()

            func start() throws -> Task<Void, Never> {
                guard let ticket = authority.capture(ownerAccountID: source.accountID, activeSource: source)
                else { throw Failure(description: "fixture could not capture authority") }
                let reads = loader.reserveReads()
                let loader = loader
                let task = Task { [weak self] in
                    await loader.load(
                        reads,
                        accepts: { [weak self] in
                            guard let self else { return false }
                            return authority.accepts(
                                ticket, ownerAccountID: source.accountID, activeSource: source,
                            )
                        },
                        fetch: { [weak self] scope in
                            guard let self else { throw Failure(description: "fixture released") }
                            fetches.append(scope)
                            let id = fetches.count
                            return try await withCheckedThrowingContinuation { self.pending[id] = $0 }
                        },
                        publish: { [weak self] scope, settings in
                            self?.values[scope] = settings
                            self?.publications.append(scope)
                        },
                    )
                }
                tasks.append(task)
                return task
            }

            func update(_ scope: NotificationSettingsScope, muteFor: Int, source: TdUpdateSource? = nil) {
                guard authority.accepts(
                    source ?? self.source, ownerAccountID: self.source.accountID, activeSource: self.source,
                ) else { return }
                loader.invalidate(scope: scope)
                values[scope] = settings(muteFor)
                publications.append(scope)
            }

            func complete(_ id: Int, muteFor: Int?) throws {
                guard let continuation = pending.removeValue(forKey: id)
                else { throw Failure(description: "missing suspended read \(id)") }
                if let muteFor {
                    continuation.resume(returning: settings(muteFor))
                } else {
                    continuation.resume(throwing: Failure(description: "fixture read failure"))
                }
            }

            func finish() {
                for task in tasks {
                    task.cancel()
                }
                loader.invalidate()
                let suspended = pending.values
                pending.removeAll()
                for continuation in suspended {
                    continuation.resume(throwing: CancellationError())
                }
            }
        }

        private static let privateScope = NotificationSettingsScope.notificationSettingsScopePrivateChats
        private static let groupScope = NotificationSettingsScope.notificationSettingsScopeGroupChats
        private static let channelScope = NotificationSettingsScope.notificationSettingsScopeChannelChats

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-root-scope-settings") else { return }
            Task {
                let result: String
                do {
                    try await verifyUpdates()
                    try await verifyOverlappingLoads()
                    try await verifyAuthorityAndCancellation()
                    result = "Root scope settings probe passed: actual-helper/suspended-reads=true; "
                        + "per-scope-immediate-publish/update-before-dispatch/in-flight-update=true; "
                        + "overlapping-loads/late-success/late-failure/new-load-after-update=true; "
                        + "account/client/epoch/cancellation=fenced; failure-preserves-values=true; "
                        + "RootVM/TDLib-RPC/visible-mute-badges=source-reviewed-only; server-calls=0"
                } catch {
                    result = "Root scope settings probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("root-scope-settings-probe.txt"), options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ value: Bool, _ message: String) throws {
            if !value { throw Failure(description: message) }
        }

        private static func until(_ condition: () -> Bool, _ message: String) async throws {
            for _ in 0..<1000 {
                if condition() { return }
                await Task.yield()
            }
            throw Failure(description: message)
        }

        private static func verifyUpdates() async throws {
            let f = Fixture()
            defer { f.finish() }
            let first = try f.start()
            try await until({ f.fetches.count == 1 }, "private read did not start")
            try f.complete(1, muteFor: 1)
            try await until({ f.fetches.count == 2 }, "group read did not start")
            try require(f.values[privateScope]?.muteFor == 1, "private value waited for final batch")
            f.update(privateScope, muteFor: 9)
            f.update(groupScope, muteFor: 8)
            try f.complete(2, muteFor: 2)
            try await until({ f.fetches.count == 3 }, "channel read did not start")
            try f.complete(3, muteFor: 3)
            await first.value
            try require(
                f.values[privateScope]?.muteFor == 9 && f.values[groupScope]?.muteFor == 8
                    && f.values[channelScope]?.muteFor == 3,
                "batch or in-flight response overwrote accepted update",
            )

            let second = try f.start()
            f.update(privateScope, muteFor: 19)
            try await until({ f.fetches.count == 4 }, "remaining scope did not start")
            try require(f.fetches[3] == groupScope, "revoked before-dispatch private read was sent")
            try f.complete(4, muteFor: nil)
            try await until({ f.fetches.count == 5 }, "channel after failure did not start")
            try f.complete(5, muteFor: 13)
            await second.value
            try require(
                f.values[privateScope]?.muteFor == 19 && f.values[groupScope]?.muteFor == 8
                    && f.values[channelScope]?.muteFor == 13,
                "failure lost prior value or revoked unrelated scope",
            )

            // An update before a genuine later load must not block that load.
            let third = try f.start()
            try await until({ f.fetches.count == 6 }, "later private read was blocked")
            try f.complete(6, muteFor: 29)
            try await until({ f.fetches.count == 7 }, "later group read missing")
            try f.complete(7, muteFor: 28)
            try await until({ f.fetches.count == 8 }, "later channel read missing")
            try f.complete(8, muteFor: nil)
            await third.value
            try require(
                f.values[privateScope]?.muteFor == 29 && f.values[groupScope]?.muteFor == 28
                    && f.values[channelScope]?.muteFor == 13,
                "later load or failed scope value incorrect",
            )
        }

        private static func verifyOverlappingLoads() async throws {
            let f = Fixture()
            defer { f.finish() }
            let skipped = try f.start()
            let first = try f.start()
            try await until({ f.fetches.count == 1 }, "latest reserved batch did not start")
            await skipped.value
            let second = try f.start()
            try await until({ f.fetches.count == 2 }, "overlapping private read did not start")
            try f.complete(1, muteFor: nil)
            await first.value
            try require(f.fetches.count == 2 && f.values.isEmpty, "old failure started or published stale scopes")
            try f.complete(2, muteFor: 20)
            try await until({ f.fetches.count == 3 }, "late failure released newer read")
            let third = try f.start()
            try await until({ f.fetches.count == 4 }, "third private read did not start")
            try f.complete(3, muteFor: 21)
            await second.value
            try require(f.values[groupScope] == nil, "superseded success published")
            try f.complete(4, muteFor: 30)
            try await until({ f.fetches.count == 5 }, "third group read missing")
            try f.complete(5, muteFor: 31)
            try await until({ f.fetches.count == 6 }, "third channel read missing")
            try f.complete(6, muteFor: 32)
            await third.value
            try require(
                f.values[privateScope]?.muteFor == 30 && f.values[groupScope]?.muteFor == 31
                    && f.values[channelScope]?.muteFor == 32 && f.publications.count == 4,
                "latest read ownership or publication count incorrect",
            )
        }

        private static func verifyAuthorityAndCancellation() async throws {
            let f = Fixture()
            defer { f.finish() }
            let oldSource = f.source
            let old = try f.start()
            try await until({ f.fetches.count == 1 }, "old account read missing")
            f.source = TdUpdateSource(accountID: UUID(), clientID: oldSource.clientID)
            f.authority.invalidate()
            f.loader.invalidate()
            f.values = [:]
            f.update(privateScope, muteFor: 999, source: oldSource)
            let current = try f.start()
            try await until({ f.fetches.count == 2 }, "current account read missing")
            try f.complete(1, muteFor: 99)
            await old.value
            try require(f.values.isEmpty, "old account update/read crossed numeric client collision")
            try f.complete(2, muteFor: 40)
            try await until({ f.fetches.count == 3 }, "current group read missing")
            try f.complete(3, muteFor: 41)
            try await until({ f.fetches.count == 4 }, "current channel read missing")
            try f.complete(4, muteFor: 42)
            await current.value

            let epoch = try f.start()
            try await until({ f.fetches.count == 5 }, "epoch read missing")
            f.authority.invalidate()
            try f.complete(5, muteFor: 500)
            await epoch.value
            try require(
                f.fetches.count == 5 && f.values[privateScope]?.muteFor == 40,
                "old same-source epoch published",
            )

            let client = try f.start()
            try await until({ f.fetches.count == 6 }, "old client read missing")
            f.source = TdUpdateSource(accountID: f.source.accountID, clientID: 2)
            try f.complete(6, muteFor: 600)
            await client.value
            try require(f.fetches.count == 6 && f.values[privateScope]?.muteFor == 40, "old client published")

            let canceled = try f.start()
            try await until({ f.fetches.count == 7 }, "canceled read missing")
            canceled.cancel()
            try f.complete(7, muteFor: 700)
            await canceled.value
            try require(
                f.fetches.count == 7 && f.values[privateScope]?.muteFor == 40 && f.publications.count == 3,
                "canceled response published or dispatched another scope",
            )
        }

        private static func settings(_ muteFor: Int) -> ScopeNotificationSettings {
            ScopeNotificationSettings(
                disableMentionNotifications: false, disablePinnedMessageNotifications: false,
                muteFor: muteFor, muteStories: false, showPreview: true, showStoryPoster: true,
                soundId: 0, storySoundId: 0, useDefaultMuteStories: true,
            )
        }
    }
#endif

// ChatListActionAuthorityProbe.swift

#if DEBUG
    import Foundation

    @MainActor enum ChatListActionAuthorityProbe {
        private struct Failure: Swift.Error, CustomStringConvertible {
            let description: String
        }

        private final class Gate {
            private var entered = false
            private var continuation: CheckedContinuation<Void, Never>?
            private var observer: CheckedContinuation<Void, Never>?

            func wait() async {
                entered = true
                observer?.resume()
                observer = nil
                await withCheckedContinuation { continuation = $0 }
            }

            func waitUntilEntered() async {
                guard !entered else { return }
                await withCheckedContinuation { observer = $0 }
            }

            func open() {
                continuation?.resume()
                continuation = nil
            }
        }

        private enum Invalidation: CaseIterable {
            case otherAccount
            case replacedClient
            case dismissedOwner
            case cancelledTask
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-list-action-authority") else { return }
            Task {
                let result: String
                do {
                    try await verify()
                    result = "List action authority probe passed: production-bulk-helper=true; "
                        + "A-to-B-colliding-ID-writes=0; same-account-new-client-writes=0; "
                        + "dismissed-owner-writes=0; cancelled-writes=0; unscoped-writes=0; "
                        + "late-success/error-UI=0; completion-delivery-fenced; current-errors-preserved; "
                        + "current-bulk-writes=2; server-writes=0; UIKit-attachment-runtime=unverified"
                } catch {
                    result = "List action authority probe failed: \(error)"
                }
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("list-action-authority-probe.txt"), options: .atomic,
                    )
                }
                log(result)
            }
        }

        private static func require(_ value: Bool, _ message: String) throws {
            guard value else { throw Failure(description: message) }
        }

        private static func verify() async throws {
            let sourceA = TdUpdateSource(accountID: UUID(), clientID: 401)
            // Matching client/chat numbers must not hide a different account.
            let sourceB = TdUpdateSource(accountID: UUID(), clientID: sourceA.clientID)
            let replacedA = TdUpdateSource(accountID: sourceA.accountID, clientID: 402)

            for invalidation in Invalidation.allCases {
                for readThrows in [false, true] {
                    var current = sourceA
                    var attached = true
                    let scope = ChatListActionScope(
                        source: sourceA, currentSource: { current }, ownerIsAttached: { attached },
                    )
                    let gate = Gate()
                    var reads = 0
                    var writes = 0
                    var UICompletions = 0
                    let task = Task {
                        do {
                            try await scope.updateEach(
                                ids: [17, 18],
                                read: { id in
                                    reads += 1
                                    await gate.wait()
                                    if readThrows { throw Failure(description: "read error") }
                                    return (sourceA, id)
                                },
                                write: { id, value in
                                    try require(value.0 == sourceA && value.1 == id, "lost read identity")
                                    writes += 1
                                },
                            )
                            if scope.isCurrent { UICompletions += 1 }
                            return false
                        } catch is CancellationError {
                            if scope.isCurrent { UICompletions += 1 }
                            return true
                        } catch {
                            return false
                        }
                    }
                    await gate.waitUntilEntered()
                    switch invalidation {
                    case .otherAccount: current = sourceB
                    case .replacedClient: current = replacedA
                    case .dismissedOwner: attached = false
                    case .cancelledTask: task.cancel()
                    }
                    gate.open()
                    let cancelled = await task.value
                    try require(
                        cancelled && reads == 1 && writes == 0 && UICompletions == 0,
                        "stale read continued: \(invalidation), error=\(readThrows)",
                    )
                }
            }

            // An already submitted write cannot be undone. It must neither start
            // another write nor deliver a stale success/error to its old editor.
            for writeThrows in [false, true] {
                var current = sourceA
                let scope = ChatListActionScope(
                    source: sourceA, currentSource: { current }, ownerIsAttached: { true },
                )
                let gate = Gate()
                var writes = 0
                var UICompletions = 0
                let task = Task {
                    do {
                        try await scope.updateEach(
                            ids: [17, 18], read: { $0 },
                            write: { _, _ in
                                writes += 1
                                await gate.wait()
                                if writeThrows { throw Failure(description: "write error") }
                            },
                        )
                        if scope.isCurrent { UICompletions += 1 }
                        return false
                    } catch is CancellationError {
                        if scope.isCurrent { UICompletions += 1 }
                        return true
                    } catch {
                        return false
                    }
                }
                await gate.waitUntilEntered()
                current = replacedA
                gate.open()
                let cancelled = await task.value
                try require(cancelled && writes == 1 && UICompletions == 0, "stale write completion")
            }

            var current = sourceA
            let scope = ChatListActionScope(
                source: sourceA, currentSource: { current }, ownerIsAttached: { true },
            )
            var writtenIDs = [Int64]()
            try await scope.updateEach(ids: [17, 18], read: { $0 }) { id, value in
                try require(id == value, "current bulk payload changed")
                writtenIDs.append(id)
            }
            try require(writtenIDs == [17, 18], "current bulk writes missing")

            writtenIDs.removeAll()
            var reportedError: String?
            do {
                try await scope.updateEach(ids: [17, 18, 19], read: { id in
                    if id == 17 { throw Failure(description: "first read error") }
                    return id
                }) { id, _ in
                    writtenIDs.append(id)
                    if id == 18 { throw Failure(description: "later write error") }
                }
            } catch let error as Failure {
                reportedError = error.description
            }
            try require(
                writtenIDs == [18, 19] && reportedError == "first read error",
                "per-chat error continuation changed",
            )

            // The caller must recheck after receiving perform's return value.
            _ = try await scope.perform { 17 }
            current = sourceB
            try require(!scope.isCurrent, "caller delivery fence missing")
            var lateCalls = 0
            do {
                _ = try await scope.perform { lateCalls += 1 }
                throw Failure(description: "stale preflight accepted")
            } catch is CancellationError {}
            let unscoped = ChatListActionScope(
                source: nil, currentSource: { nil }, ownerIsAttached: { true },
            )
            do {
                _ = try await unscoped.perform { lateCalls += 1 }
                throw Failure(description: "missing account accepted")
            } catch is CancellationError {}
            try require(lateCalls == 0, "stale/unscoped request executed")
        }
    }
#endif

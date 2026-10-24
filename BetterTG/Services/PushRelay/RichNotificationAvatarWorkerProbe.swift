// RichNotificationAvatarWorkerProbe.swift

#if DEBUG
    import UIKit

    @MainActor enum RichNotificationAvatarWorkerProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }

        /// Blocks only the fixture's utility worker, after encoding and before
        /// its real prewrite check. Main awaits an exact arrival receipt.
        /// Mutable fields are lock-protected; waiting/signaling uses a semaphore.
        private final class Gate: @unchecked Sendable {
            private let lock = NSLock()
            private let release = DispatchSemaphore(value: 0)
            private var entered = false
            private var observer: CheckedContinuation<Bool, Never>?
            private var expired = false

            var timedOut: Bool { lock.lock()
            defer { lock.unlock() }
            return expired
            }

            func arrive() {
                lock.lock()
                guard !entered else { lock.unlock()
                return
                }
                entered = true
                let observer = observer
                self.observer = nil
                lock.unlock()
                observer?.resume(returning: true)
                if release.wait(timeout: .now() + 5) == .timedOut {
                    lock.lock()
                    expired = true
                    lock.unlock()
                }
            }

            func wait() async -> Bool {
                await withCheckedContinuation { continuation in
                    lock.lock()
                    if entered { lock.unlock()
                    continuation.resume(returning: true)
                    return
                    }
                    observer = continuation
                    lock.unlock()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { [self] in
                        lock.lock()
                        let observer = observer
                        self.observer = nil
                        lock.unlock()
                        observer?.resume(returning: false)
                    }
                }
            }

            func open() { release.signal() }
        }

        @MainActor private final class Cleanup {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "notification-avatar-worker-\(UUID())",
                isDirectory: true,
            )
            var workers = [RichNotificationAvatarWorker]()
            var gates = [Gate]()

            func finish() async {
                workers.forEach { $0.bind(nil) }
                gates.forEach { $0.open() }
                for worker in workers {
                    await worker.probeFlush()
                }
                try? FileManager.default.removeItem(at: root)
            }
        }

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-notification-avatar-worker") else { return }
            Task {
                let result: String
                do {
                    try await verify()
                    result = "PASS: real isolated avatar worker IO; one active drain; bounded/coalesced pending and success receipts; "
                        + "held prewrite source/photo revocation; same-photo quality monotonic; failed write retry; "
                        + "decode/path/write utility-only; current-peer registration count uncapped; "
                        + "actual coordinator/profile/NSE strict handoff/media pipeline=unverified; RPC/account-stores=0"
                } catch {
                    result = "FAIL: \(error)"
                }
                log(result)
                if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: documents.appendingPathComponent("notification-avatar-worker-probe.txt"),
                        options: .atomic,
                    )
                }
            }
        }

        private static func verify() async throws {
            let cleanup = Cleanup()
            do {
                try await exercise(cleanup)
            } catch {
                await cleanup.finish()
            throw error
            }
            await cleanup.finish()
        }

        private static func exercise(_ cleanup: Cleanup) async throws {
            let root = cleanup.root
            let red = image(.red)
            let blue = image(.blue)
            let source = RichNotificationCacheSource(updateSource: .init(accountID: UUID(), clientID: 11), userID: 101)
            let peer = RichNotificationPeerReference(kind: .privateChat, id: 77)
            let gate = Gate()
            cleanup.gates.append(gate)
            let worker = RichNotificationAvatarWorker(pendingLimit: 3, successLimit: 2, containerURL: {
                Thread.isMainThread ? nil : root
            })
            cleanup.workers.append(worker)
            worker.probeBeforeCommit = { gate.arrive() }
            worker.bind(source)
            let revision = RichNotificationAvatarRevision()
            worker.offer(.init(peer: peer, source: source, revision: revision, rank: 0, input: .data(red)))
            try await require(gate.wait(), "utility job never reached encoded prewrite gate")
            for _ in 0..<100 {
                worker.offer(.init(peer: peer, source: source, revision: revision, rank: 2, input: .data(blue)))
            }
            worker.offer(.init(peer: peer, source: source, revision: revision, rank: 0, input: .data(red)))
            try require(
                worker.probeState.pending == 1 && worker.probeState.starts == 1,
                "same-peer burst was not coalesced behind one active job",
            )
            gate.open()
            await worker.probeFlush()
            try require(
                !gate.timedOut && worker.probeState.starts == 2 && worker.probeState.writes == 2
                && worker.probeState.offMain && !worker.probeState.draining,
                "coalesced drain receipts or thread ownership failed",
            )
            try require(
                RichNotificationCache.avatarData(for: peer, accountID: 101, containerURL: { root })
                == RichNotificationCache.normalizedJPEG(blue, maximumPixelSize: 256),
                "latest full avatar did not win",
            )
            let written = worker.probeState.writes
            worker.offer(.init(peer: peer, source: source, revision: revision, rank: 0, input: .data(red)))
            worker.offer(.init(peer: peer, source: source, revision: revision, rank: 1, input: .data(red)))
            worker.offer(.init(peer: peer, source: source, revision: revision, rank: 2, input: .data(blue)))
            await worker.probeFlush()
            try require(worker.probeState.writes == written, "successful full avatar was downgraded or repeated")
            for id in 1...3 {
                worker.offer(.init(
                    peer: .init(kind: .basicGroup, id: Int64(id)),
                    source: source,
                    revision: .init(),
                    rank: 0,
                    input: .data(red),
                ))
                await worker.probeFlush()
            }
            let afterEviction = worker.probeState.writes
            worker.offer(.init(peer: peer, source: source, revision: revision, rank: 0, input: .data(red)))
            worker.offer(.init(peer: peer, source: source, revision: revision, rank: 1, input: .data(red)))
            await worker.probeFlush()
            try require(
                worker.probeState.successes == 2 && worker.probeState.writes == afterEviction,
                "dedupe eviction lost the current photo's successful quality watermark",
            )

            // Exact old-photo reference replacement, including an active encoded job.
            let photoGate = Gate()
            cleanup.gates.append(photoGate)
            let photoWorker = RichNotificationAvatarWorker(containerURL: { root })
            cleanup.workers.append(photoWorker)
            photoWorker.probeBeforeCommit = { photoGate.arrive() }
            photoWorker.bind(source)
            var references = RichNotificationAvatarReferences()
            references.bind(source)
            let old = references.replace(peer, fileIDs: [1, 2], source: source)!
            let refreshSequence = references.sequence
            photoWorker.offer(.init(peer: peer, source: source, revision: old, rank: 2, input: .data(red)))
            try await require(photoGate.wait(), "old photo did not reach prewrite gate")
            let fresh = references.replace(peer, fileIDs: [3, 4], source: source)!
            try require(
                references.registrations(for: 1, source: source).isEmpty
                && references.registrations(for: 2, source: source).isEmpty
                && references.registrations(for: 4, source: source).first?.rank == 2
                && references.replace(peer, fileIDs: [3, 4], source: source) === fresh,
                "photo replacement retained old files or duplicated same-photo revision",
            )
            try require(
                references.wasReplaced(peer, after: refreshSequence)
                && !references.wasReplaced(.init(kind: .privateChat, id: 78), after: refreshSequence),
                "delayed refresh missed the replaced destination or rejected an unrelated peer",
            )
            photoWorker.offer(.init(peer: peer, source: source, revision: fresh, rank: 0, input: .data(blue)))
            photoGate.open()
            await photoWorker.probeFlush()
            try require(
                !photoGate.timedOut && photoWorker.probeState.writes == 1 && photoWorker.probeState.failures == 1
                    && RichNotificationCache.avatarData(for: peer, accountID: 101, containerURL: { root })
                        == RichNotificationCache.normalizedJPEG(blue, maximumPixelSize: 256),
                "obsolete encoded photo committed or fresh placeholder was rejected",
            )

            // Nil ownership handoff revokes both active and queued same-source work.
            let sourceGate = Gate()
            cleanup.gates.append(sourceGate)
            let bounded = RichNotificationAvatarWorker(pendingLimit: 3, successLimit: 2, containerURL: { root })
            cleanup.workers.append(bounded)
            bounded.probeBeforeCommit = { sourceGate.arrive() }
            bounded.bind(source)
            bounded.offer(.init(peer: peer, source: source, revision: .init(), rank: 0, input: .data(red)))
            try await require(sourceGate.wait(), "source job did not reach prewrite gate")
            for id in 1...8 {
                bounded.offer(.init(
                    peer: .init(kind: .basicGroup, id: Int64(id)),
                    source: source,
                    revision: .init(),
                    rank: 0,
                    input: .data(red),
                ))
            }
            try require(
                bounded.probeState.pending == 3 && bounded.probeState.dropped == 5,
                "pending descriptor cap did not evict oldest",
            )
            bounded.bind(nil)
            try require(
                bounded.probeState.pending == 0 && bounded.probeState.successes == 0,
                "handoff did not synchronously clear pending state",
            )
            bounded.bind(source) // Same source cannot revive the old generation.
            sourceGate.open()
            await bounded.probeFlush()
            try require(
                !sourceGate.timedOut && bounded.probeState.writes == 0,
                "handoff/source ABA admitted old prewrite",
            )
            for id in 1...4 {
                bounded.offer(.init(
                    peer: .init(kind: .basicGroup, id: Int64(id)),
                    source: source,
                    revision: .init(),
                    rank: 0,
                    input: .data(red),
                ))
                await bounded.probeFlush()
            }
            try require(
                bounded.probeState.successes == 2 && bounded.probeState.writes == 4,
                "success receipt cap or fresh recovery failed",
            )

            let clientGate = Gate()
            cleanup.gates.append(clientGate)
            let replaced = RichNotificationAvatarWorker(containerURL: { root })
            cleanup.workers.append(replaced)
            replaced.probeBeforeCommit = { clientGate.arrive() }
            replaced.bind(source)
            replaced.offer(.init(peer: peer, source: source, revision: .init(), rank: 2, input: .data(red)))
            try await require(clientGate.wait(), "client replacement gate not armed")
            let nextSource = RichNotificationCacheSource(
                updateSource: .init(accountID: source.updateSource.accountID, clientID: 12),
                userID: 101,
            )
            replaced.bind(nextSource)
            replaced.offer(.init(peer: peer, source: nextSource, revision: .init(), rank: 0, input: .data(blue)))
            clientGate.open()
            await replaced.probeFlush()
            try require(
                !clientGate.timedOut && replaced.probeState.writes == 1 && replaced.probeState.failures == 1
                && RichNotificationCache.avatarData(for: peer, accountID: 101, containerURL: { root })
                    == RichNotificationCache.normalizedJPEG(blue, maximumPixelSize: 256),
                "old client prewrite survived replacement",
            )

            // Retain lower-rank candidates until the higher-rank IO really succeeds.
            let fallbackGate = Gate()
            cleanup.gates.append(fallbackGate)
            let fallback = RichNotificationAvatarWorker(containerURL: { root })
            cleanup.workers.append(fallback)
            fallback.probeBeforeCommit = { fallbackGate.arrive() }
            fallback.bind(source)
            fallback.offer(.init(
                peer: .init(kind: .basicGroup, id: 99),
                source: source,
                revision: .init(),
                rank: 0,
                input: .data(red),
            ))
            try await require(fallbackGate.wait(), "fallback staging gate not armed")
            let fallbackRevision = RichNotificationAvatarRevision()
            fallback.offer(.init(peer: peer, source: source, revision: fallbackRevision, rank: 0, input: .data(red)))
            fallback.offer(.init(peer: peer, source: source, revision: fallbackRevision, rank: 1, input: .data(blue)))
            fallback.offer(.init(
                peer: peer,
                source: source,
                revision: fallbackRevision,
                rank: 2,
                input: .path(root.appendingPathComponent("missing.jpg").path),
            ))
            try require(fallback.probeState.pending == 1, "fallback candidates used separate destination slots")
            fallbackGate.open()
            await fallback.probeFlush()
            try require(
                !fallbackGate.timedOut && fallback.probeState.starts == 3 && fallback.probeState.failures == 1
                && fallback.probeState.writes == 2
                && RichNotificationCache.avatarData(for: peer, accountID: 101, containerURL: { root })
                    == RichNotificationCache.normalizedJPEG(blue, maximumPixelSize: 256),
                "missing big file discarded valid small fallback",
            )

            let placeholderGate = Gate()
            cleanup.gates.append(placeholderGate)
            fallback.probeBeforeCommit = { placeholderGate.arrive() } // Previous drain has settled.
            let beforePlaceholder = fallback.probeState
            fallback.offer(.init(
                peer: .init(kind: .basicGroup, id: 100),
                source: source,
                revision: .init(),
                rank: 0,
                input: .data(blue),
            ))
            try await require(placeholderGate.wait(), "placeholder fallback staging gate not armed")
            let placeholderRevision = RichNotificationAvatarRevision()
            fallback.offer(.init(peer: peer, source: source, revision: placeholderRevision, rank: 0, input: .data(red)))
            fallback.offer(.init(
                peer: peer,
                source: source,
                revision: placeholderRevision,
                rank: 1,
                input: .path(root.appendingPathComponent("missing-small.jpg").path),
            ))
            fallback.offer(.init(
                peer: peer,
                source: source,
                revision: placeholderRevision,
                rank: 2,
                input: .data(Data([1, 2, 3])),
            ))
            placeholderGate.open()
            await fallback.probeFlush()
            try require(
                !placeholderGate.timedOut && fallback.probeState.starts == beforePlaceholder.starts + 4
                && fallback.probeState.failures == beforePlaceholder.failures + 2
                && fallback.probeState.writes == beforePlaceholder.writes + 2
                && RichNotificationCache.avatarData(for: peer, accountID: 101, containerURL: { root })
                    == RichNotificationCache.normalizedJPEG(red, maximumPixelSize: 256),
                "failed big/small candidates discarded valid placeholder",
            )

            // Actual failed write must remain retryable; file reads also run in the worker.
            let retryRoot = root.appendingPathComponent("retry", isDirectory: true)
            try red.write(to: retryRoot) // A file cannot serve as the cache's directory.
            let retry = RichNotificationAvatarWorker(containerURL: { retryRoot })
            cleanup.workers.append(retry)
            retry.bind(source)
            let retryRevision = RichNotificationAvatarRevision()
            let file = root.appendingPathComponent("input.png")
            try blue.write(to: file)
            let candidate = RichNotificationAvatarWorker.Candidate(
                peer: peer,
                source: source,
                revision: retryRevision,
                rank: 2,
                input: .path(file.path),
            )
            retry.offer(.init(peer: peer, source: source, revision: retryRevision, rank: 0, input: .data(red)))
            retry.offer(.init(peer: peer, source: source, revision: retryRevision, rank: 1, input: .data(red)))
            retry.offer(candidate)
            await retry.probeFlush()
            try require(retry.probeState.failures == 3 && retry.probeState.successes == 0, "failed IO entered dedupe")
            try FileManager.default.removeItem(at: retryRoot)
            retry.offer(candidate)
            await retry.probeFlush()
            try require(
                retry.probeState.writes == 1 && retry.probeState.successes == 1 && retry.probeState.offMain,
                "same failed candidate did not retry successfully",
            )
            try require(
                RichNotificationCache.avatarData(for: peer, accountID: 101, containerURL: { retryRoot })
                == RichNotificationCache.normalizedJPEG(blue, maximumPixelSize: 256),
                "file-backed retry wrote incorrect bytes",
            )
        }

        private static func image(_ color: UIColor) -> Data {
            UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
        }

        private static func require(_ condition: Bool, _ detail: String) throws {
            if !condition { throw Failure(description: detail) }
        }
    }
#endif

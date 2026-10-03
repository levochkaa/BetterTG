// RichNotificationAvatarWorker.swift

import Foundation

// MARK: - RichNotificationAvatarRevision

/// One current photo's small metadata lease. No image bytes or IO are held by its lock.
final class RichNotificationAvatarRevision {
    let id = UUID()

    private let lock = NSLock()
    private var valid = true
    private var successfulRank = -1

    func invalidate() { lock.lock()
        valid = false
        lock.unlock()
    }

    func recordSuccess(rank: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard valid else { return }
        successfulRank = max(successfulRank, rank)
    }

    func permits(rank: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return valid && rank >= successfulRank
    }
}

// MARK: - RichNotificationAvatarWorker

/// Best-effort prewarming: one utility drain, bounded pending descriptors and
/// successful-candidate receipts. Main never waits for IO or image processing.
final class RichNotificationAvatarWorker {
    enum Input: Equatable {
        case data(Data)
        case path(String)
    }

    struct Candidate {
        let peer: RichNotificationPeerReference
        let source: RichNotificationCacheSource
        let revision: RichNotificationAvatarRevision
        let rank: Int // minithumbnail = 0, small = 1, big = 2
        let input: Input
    }

    private struct Job {
        let candidate: Candidate
        let generation: UUID
    }

    private struct Batch {
        var candidates: [Int: Candidate]
        let generation: UUID
    }

    private struct Receipt: Hashable {
        let revision: UUID
        let rank: Int
    }

    #if DEBUG
        var probeBeforeCommit: (() -> Void)?
        private var starts = 0
        private var writes = 0
        private var failures = 0
        private var dropped = 0
        private var offMain = true

        var probeState: (
            pending: Int,
            successes: Int,
            draining: Bool,
            starts: Int,
            writes: Int,
            failures: Int,
            dropped: Int,
            offMain: Bool,
        ) {
            lock.lock()
            defer { lock.unlock() }
            return (pending.count, successes.count, draining, starts, writes, failures, dropped, offMain)
        }

        func probeFlush() async {
            await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
        }
    #endif

    private let queue = DispatchQueue(label: "BetterTG.notification-avatar-cache", qos: .utility)
    private let lock = NSLock()
    private let pendingLimit: Int
    private let successLimit: Int
    private let containerURL: () -> URL?
    private var source: RichNotificationCacheSource?
    private var generation = UUID()
    private var pending = [RichNotificationPeerReference: Batch]()
    private var order = [RichNotificationPeerReference]()
    private var successes = Set<Receipt>()
    private var successOrder = [Receipt]()
    private var draining = false

    init(
        pendingLimit: Int = 128,
        successLimit: Int = 256,
        containerURL: @escaping () -> URL? = { BetterTGAppGroup.containerURL() },
    ) {
        self.pendingLimit = max(1, pendingLimit)
        self.successLimit = max(1, successLimit)
        self.containerURL = containerURL
    }

    func bind(_ source: RichNotificationCacheSource?) {
        lock.lock()
        defer { lock.unlock() }
        guard self.source != source else { return }
        self.source = source
        generation = UUID()
        pending.removeAll()
        order.removeAll()
        successes.removeAll()
        successOrder.removeAll()
    }

    func offer(_ candidate: Candidate) {
        lock.lock()
        defer { lock.unlock() }
        let receipt = Receipt(revision: candidate.revision.id, rank: candidate.rank)
        guard source == candidate.source, candidate.source.userID > 0, (0...2).contains(candidate.rank),
              candidate.revision.permits(rank: candidate.rank), !successes.contains(receipt) else { return }
        if pending[candidate.peer] == nil {
            if order.count == pendingLimit {
                pending.removeValue(forKey: order.removeFirst())
                #if DEBUG
                    dropped += 1
                #endif
            }
            order.append(candidate.peer)
        }
        if var waiting = pending[candidate.peer], waiting.candidates.values.first?.revision === candidate.revision {
            waiting.candidates[candidate.rank] = candidate
            pending[candidate.peer] = waiting
        } else {
            pending[candidate.peer] = Batch(candidates: [candidate.rank: candidate], generation: generation)
        }
        guard !draining else { return }
        draining = true
        queue.async { [self] in drain() }
    }

    private func take() -> Batch? {
        lock.lock()
        defer { lock.unlock() }
        guard let peer = order.first else { draining = false
            return nil
        }
        order.removeFirst()
        return pending.removeValue(forKey: peer)
    }

    private func isCurrent(_ job: Job) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return source == job.candidate.source && generation == job.generation
            && job.candidate.revision.permits(rank: job.candidate.rank)
    }

    private func drain() {
        while let batch = take() {
            for candidate in batch.candidates.values.sorted(by: { $0.rank > $1.rank }) {
                let job = Job(candidate: candidate, generation: batch.generation)
                if process(job) { break }
            }
        }
    }

    private func process(_ job: Job) -> Bool {
        autoreleasepool {
                #if DEBUG
                    lock.lock()
                    starts += 1
                    offMain = offMain && !Thread.isMainThread
                    lock.unlock()
                #endif
            guard isCurrent(job) else { return false }
            let data: Data? =
                switch job.candidate.input {
                case .data(let value): value
                case .path(let path): try? Data(contentsOf: URL(fileURLWithPath: path))
                }
            guard let data, isCurrent(job) else { record(job, success: false)
                return false
            }
            let success = RichNotificationCache.cacheAvatar(
                data, for: job.candidate.peer, accountID: job.candidate.source.userID,
                containerURL: containerURL,
                shouldWrite: { [self] in
                        #if DEBUG
                            probeBeforeCommit?()
                        #endif
                    // Best-effort cutoff: an atomic write already entered may
                    // finish after revocation, only in the captured account path.
                    return isCurrent(job)
                },
            )
            record(job, success: success)
            return success
        }
    }

    private func record(_ job: Job, success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        #if DEBUG
            if success { writes += 1 } else { failures += 1 }
        #endif
        guard success, source == job.candidate.source, generation == job.generation,
              job.candidate.revision.permits(rank: job.candidate.rank) else { return }
        job.candidate.revision.recordSuccess(rank: job.candidate.rank)
        let receipt = Receipt(revision: job.candidate.revision.id, rank: job.candidate.rank)
        successOrder.removeAll { $0 == receipt }
        successOrder.append(receipt)
        successes.insert(receipt)
        if successOrder.count > successLimit { successes.remove(successOrder.removeFirst()) }
        // Offers received while this exact candidate was active need no second IO.
        if var waiting = pending[job.candidate.peer],
           waiting.candidates.values.first?.revision === job.candidate.revision
        {
            waiting.candidates = waiting.candidates.filter { $0.key > job.candidate.rank }
            if waiting.candidates.isEmpty {
                pending.removeValue(forKey: job.candidate.peer)
                order.removeAll { $0 == job.candidate.peer }
            } else {
                pending[job.candidate.peer] = waiting
            }
        }
    }
}

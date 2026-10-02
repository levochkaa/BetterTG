// FFmpegAnimationTiming.swift

import FFmpegBridge
import Foundation

// MARK: - FFmpegVideoTimeline

struct FFmpegVideoTimeline {
    static let maximumFrames = 65536

    let starts: [TimeInterval]
    let duration: TimeInterval

    func frameIndex(at timestamp: TimeInterval) -> Int {
        guard timestamp.isFinite, duration > 0, starts.count > 1 else { return 0 }
        let phase = max(0, timestamp.truncatingRemainder(dividingBy: duration))
        var lower = 0
        var upper = starts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if starts[middle] <= phase { lower = middle + 1 } else { upper = middle }
        }
        return max(0, lower - 1)
    }
}

// MARK: - FFmpegVideoTimingLoader

/// One asset owns one scan. Releasing the final waiter cancels it; a successor
/// waits for native teardown before restarting. No partial index is published.
actor FFmpegVideoTimingLoader {
    private struct Key: Hashable {
        let path: String
        let size: UInt64
        let inode: UInt64
        let modified: TimeInterval
    }

    private final class WeakLoader {
        weak var value: FFmpegVideoTimingLoader?

        init(_ value: FFmpegVideoTimingLoader) { self.value = value }
    }

    private static let registryLock = NSLock()
    private static var registry = [Key: WeakLoader]()

    private let path: String
    private let maximumFrames: Int
    private var timeline: FFmpegVideoTimeline?
    private var waiters = [UUID: CheckedContinuation<FFmpegVideoTimeline?, Never>]()
    private var scanTask: Task<Void, Never>?
    private var cancellationPending = false

    #if DEBUG
        private var probe: FFmpegAnimationTimingObserver?
        private var registrationGate: FFmpegAnimationWaiterRegistrationGate?

        var debugWaiterCount: Int { waiters.count }
        private(set) var debugUnregisteredCancellationCount = 0

        func observe(with probe: FFmpegAnimationTimingObserver) { self.probe = probe }
        func holdRegistration(with gate: FFmpegAnimationWaiterRegistrationGate) { registrationGate = gate }
    #endif

    init(path: String, maximumFrames: Int = FFmpegVideoTimeline.maximumFrames) {
        self.path = path
        self.maximumFrames = min(FFmpegVideoTimeline.maximumFrames, max(0, maximumFrames))
    }

    /// Called by the repository's file worker. Full account-local path and file
    /// identity prevent numeric-ID collisions; weak entries do not own metadata.
    nonisolated static func shared(path: String) -> FFmpegVideoTimingLoader {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let key = Key(
            path: path,
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            modified: (attributes[.modificationDate] as? Foundation.Date)?.timeIntervalSince1970 ?? 0,
        )
        registryLock.lock()
        defer { registryLock.unlock() }
        registry = registry.filter { $0.value.value != nil }
        if let existing = registry[key]?.value { return existing }
        let loader = FFmpegVideoTimingLoader(path: path)
        registry[key] = WeakLoader(loader)
        return loader
    }

    private nonisolated static func scan(
        path: String,
        maximumFrames: Int,
        probe: FFmpegAnimationTimingObserver? = nil,
    ) -> FFmpegVideoTimeline? {
        #if DEBUG
            probe?.begin()
            defer { probe?.end() }
        #endif
        guard !Task.isCancelled,
              let decoder = path.withCString({ BetterTGFFmpegVideoDecoderCreate($0) })
        else { return nil }
        defer { BetterTGFFmpegVideoDecoderDestroy(decoder) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var starts = [TimeInterval]()
        var origin: TimeInterval?
        var end = TimeInterval.zero
        while !Task.isCancelled, ContinuousClock.now < deadline {
            #if DEBUG
                probe?.read()
            #endif
            guard !Task.isCancelled else { return nil }
            var pts = TimeInterval.zero
            var duration = TimeInterval.zero
            let result = BetterTGFFmpegVideoDecoderReadTiming(decoder, &pts, &duration)
            guard !Task.isCancelled else { return nil }
            if result == 0 {
                guard !starts.isEmpty, end.isFinite, end > 0 else { return nil }
                return FFmpegVideoTimeline(starts: starts, duration: end)
            }
            guard result == 1, starts.count < maximumFrames,
                  duration.isFinite, duration > 0
            else { return nil }
            if origin == nil, pts.isFinite { origin = pts - end }
            let normalized = pts - (origin ?? 0)
            // Broken/missing/duplicate timestamps use the previous decoded end.
            let start = normalized.isFinite && normalized >= 0
                && (starts.last.map { normalized > $0 } ?? true) ? normalized : end
            starts.append(start)
            end = start + duration
        }
        return nil
    }

    func value() async -> FFmpegVideoTimeline? {
        guard !Task.isCancelled else { return nil }
        if let timeline { return timeline }
        let id = UUID()
        return await withTaskCancellationHandler {
            #if DEBUG
                await registrationGate?.wait()
            #endif
            return await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                waiters[id] = continuation
                startIfNeeded()
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        let continuation = waiters.removeValue(forKey: id)
        #if DEBUG
            if continuation == nil { debugUnregisteredCancellationCount += 1 }
        #endif
        continuation?.resume(returning: nil)
        if waiters.isEmpty, scanTask != nil {
            cancellationPending = true
            scanTask?.cancel()
        }
    }

    private func startIfNeeded() {
        guard scanTask == nil, !waiters.isEmpty else { return }
        cancellationPending = false
        let path = path
        let maximumFrames = maximumFrames
        #if DEBUG
            let probe = probe
        #endif
        scanTask = Task.detached(priority: .userInitiated) {
            #if DEBUG
                let result = Self.scan(path: path, maximumFrames: maximumFrames, probe: probe)
            #else
                let result = Self.scan(path: path, maximumFrames: maximumFrames)
            #endif
            await self.finish(result)
        }
    }

    private func finish(_ result: FFmpegVideoTimeline?) {
        scanTask = nil
        if cancellationPending {
            cancellationPending = false
            startIfNeeded()
            return
        }
        timeline = result
        let continuations = Array(waiters.values)
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume(returning: result)
        }
    }
}

#if !DEBUG
    private typealias FFmpegAnimationTimingObserver = Never
#endif

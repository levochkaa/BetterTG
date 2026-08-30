// TDLibVODFFmpegLookahead.swift

import FFmpegBridge
import Foundation

// MARK: - TDLibVODFFmpegLookahead

actor TDLibVODFFmpegLookahead {
    // MARK: Internal

    struct State: Equatable {
        let audioReadableTo: TimeInterval?
        let bytesRead: Int64
        let duration: TimeInterval
        let isEnded: Bool
        let readCallCount: Int
        let seekCallCount: Int
        let seekTime: TimeInterval
        let sizeCallCount: Int
        let targetTime: TimeInterval
        let videoReadableTo: TimeInterval?

        var minimumReadableTo: TimeInterval? {
            switch (audioReadableTo, videoReadableTo) {
            case (.some(let audio), .some(let video)):
                min(audio, video)
            case (.some(let audio), .none):
                audio
            case (.none, .some(let video)):
                video
            case (.none, .none):
                nil
            }
        }
    }

    enum LookaheadError: Swift.Error, Equatable {
        case cancelled
        case couldNotCreateJob
        case ffmpeg(Int32)
        case invalidProof(String)
        case invalidRange
        case range(TDLibVODRangeError)
        case superseded
    }

    // MARK: Private

    private enum ScanDisposition {
        case cancelled
        case running
        case superseded
    }

    private struct ActiveScan {
        let box: TDLibVODFFmpegReadBox
        let continuation: CheckedContinuation<State, Swift.Error>
        var disposition: ScanDisposition
    }

    private let lease: TDLibVODRangeLease
    private let releasesLeaseOnCancellation: Bool
    private var activeScans = [UUID: ActiveScan]()
    private var currentScanID: UUID?
    private var isClosed = false
    private var leaseReleaseTask: Task<Void, Never>?
    private var leaseReleased = false
    private var scanGeneration = UInt64.zero

    init(
        lease: TDLibVODRangeLease,
        releasesLeaseOnCancellation: Bool = true,
    ) {
        self.lease = lease
        self.releasesLeaseOnCancellation = releasesLeaseOnCancellation
    }

    #if DEBUG
        nonisolated static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-vod-ffmpeg") else { return }
            writeDebugProbeResult("VOD FFmpeg lookahead probe started")
            Task { await runDebugProbe() }
        }

        func debugScanGeneration() -> UInt64 {
            scanGeneration
        }
    #endif

    func scan(
        seekTime: TimeInterval,
        currentPlaybackTime: TimeInterval? = nil,
        lookaheadDuration: TimeInterval = 10,
    ) async throws -> State {
        guard !isClosed,
              seekTime.isFinite,
              seekTime >= 0,
              seekTime <= Double(Int64.max - 61_000_000) / 1_000_000,
              lookaheadDuration.isFinite,
              lookaheadDuration >= 0,
              lookaheadDuration <= 60,
              currentPlaybackTime.map({ $0.isFinite && $0 >= 0 }) ?? true
        else { throw LookaheadError.invalidRange }

        scanGeneration &+= 1
        let generation = scanGeneration
        let requestID = UUID()
        supersedeCurrentScan()
        let size = try await resolvedFileSizeRetryingStale(generation: generation)
        if Task.isCancelled {
            if generation == scanGeneration {
                beginTerminalLeaseRelease()
            }
            throw LookaheadError.cancelled
        }
        guard generation == scanGeneration else { throw LookaheadError.superseded }

        let playbackTime = max(seekTime, currentPlaybackTime ?? seekTime)
        let targetTime = playbackTime + lookaheadDuration
        guard targetTime.isFinite, targetTime >= playbackTime else {
            throw LookaheadError.invalidRange
        }
        let effectiveLookahead = max(0, targetTime - seekTime)
        let box = TDLibVODFFmpegReadBox(source: lease.source)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeScans[requestID] = ActiveScan(
                    box: box,
                    continuation: continuation,
                    disposition: .running,
                )
                currentScanID = requestID
                startWorker(
                    requestID: requestID,
                    box: box,
                    fileSize: size,
                    seekTime: seekTime,
                    targetTime: targetTime,
                    effectiveLookahead: effectiveLookahead,
                )
            }
        } onCancel: {
            box.cancel()
            Task { await self.cancel(requestID: requestID, generation: generation) }
        }
    }

    private func supersedeCurrentScan() {
        guard let currentScanID, var active = activeScans[currentScanID] else { return }
        active.disposition = .superseded
        activeScans[currentScanID] = active
        active.box.cancel()
        self.currentScanID = nil
    }

    private func cancel(requestID: UUID, generation: UInt64) {
        guard generation == scanGeneration else { return }
        if var active = activeScans[requestID] {
            active.disposition = .cancelled
            activeScans[requestID] = active
            if currentScanID == requestID {
                currentScanID = nil
            }
            active.box.cancel()
        }
        beginTerminalLeaseRelease()
    }

    private func startWorker(
        requestID: UUID,
        box: TDLibVODFFmpegReadBox,
        fileSize: Int64,
        seekTime: TimeInterval,
        targetTime: TimeInterval,
        effectiveLookahead: TimeInterval,
    ) {
        let thread = Thread { [self] in
            let context = Unmanaged.passRetained(box).toOpaque()
            guard let job = BetterTGFFmpegLookaheadJobCreate(
                context,
                fileSize,
                tdLibVODFFmpegReadCallback,
            ) else {
                Unmanaged<TDLibVODFFmpegReadBox>.fromOpaque(context).release()
                Task { await finish(requestID: requestID, result: .failure(.couldNotCreateJob)) }
                return
            }
            box.install(job: job)
            let runResult = BetterTGFFmpegLookaheadJobRun(job, seekTime, effectiveLookahead)
            let result: Result<State, LookaheadError> = {
                guard runResult == 1 else {
                    if runResult == -1 {
                        return .failure(.cancelled)
                    }
                    if let rangeError = box.rangeError {
                        return .failure(.range(rangeError))
                    }
                    return .failure(.ffmpeg(BetterTGFFmpegLookaheadJobErrorCode(job)))
                }
                let audioReadableTo = BetterTGFFmpegLookaheadJobAudioReadableTo(job)
                let videoReadableTo = BetterTGFFmpegLookaheadJobVideoReadableTo(job)
                return .success(State(
                    audioReadableTo: BetterTGFFmpegLookaheadJobHasAudio(job) != 0
                        && audioReadableTo >= 0 ? audioReadableTo : nil,
                    bytesRead: BetterTGFFmpegLookaheadJobBytesRead(job),
                    duration: BetterTGFFmpegLookaheadJobDuration(job),
                    isEnded: BetterTGFFmpegLookaheadJobIsEnded(job) != 0,
                    readCallCount: Int(BetterTGFFmpegLookaheadJobReadCallCount(job)),
                    seekCallCount: Int(BetterTGFFmpegLookaheadJobSeekCallCount(job)),
                    seekTime: seekTime,
                    sizeCallCount: Int(BetterTGFFmpegLookaheadJobSizeCallCount(job)),
                    targetTime: targetTime,
                    videoReadableTo: BetterTGFFmpegLookaheadJobHasVideo(job) != 0
                        && videoReadableTo >= 0 ? videoReadableTo : nil,
                ))
            }()
            box.clear(job: job)
            BetterTGFFmpegLookaheadJobDestroy(job)
            Unmanaged<TDLibVODFFmpegReadBox>.fromOpaque(context).release()
            Task { await finish(requestID: requestID, result: result) }
        }
        thread.name = "BetterTG VOD FFmpeg Lookahead"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    private func finish(
        requestID: UUID,
        result: Result<State, LookaheadError>,
    ) {
        guard let active = activeScans.removeValue(forKey: requestID) else { return }
        if currentScanID == requestID {
            currentScanID = nil
        }
        switch active.disposition {
        case .cancelled:
            beginTerminalLeaseRelease()
            active.continuation.resume(throwing: LookaheadError.cancelled)
        case .superseded:
            active.continuation.resume(throwing: LookaheadError.superseded)
        case .running:
            if active.box.isCancelled {
                beginTerminalLeaseRelease()
                active.continuation.resume(throwing: LookaheadError.cancelled)
            } else {
                active.continuation.resume(with: result.mapError { $0 })
            }
        }
    }

    private func beginTerminalLeaseRelease() {
        guard releasesLeaseOnCancellation else { return }
        guard !leaseReleased else { return }
        leaseReleased = true
        isClosed = true
        let lease = lease
        leaseReleaseTask = Task { await lease.invalidate() }
    }

    private func resolvedFileSizeRetryingStale(generation: UInt64) async throws -> Int64 {
        while true {
            do {
                return try await lease.source.resolvedFileSize()
            } catch TDLibVODRangeError.staleRequest {
                if Task.isCancelled || generation != scanGeneration {
                    throw LookaheadError.cancelled
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            } catch {
                if Task.isCancelled {
                    if generation == scanGeneration {
                        beginTerminalLeaseRelease()
                    }
                    throw LookaheadError.cancelled
                }
                if let rangeError = error as? TDLibVODRangeError {
                    throw LookaheadError.range(rangeError)
                }
                throw error
            }
        }
    }
}

// MARK: - TDLibVODFFmpegReadBox

private final class TDLibVODFFmpegReadBox: @unchecked Sendable {
    // MARK: Private

    private let source: TDLibVODRangeSource
    private let lock = NSLock()
    private var activeOperation: TDLibVODBlockingReadOperation?
    private var cancelled = false
    private var job: OpaquePointer?
    private var storedRangeError: TDLibVODRangeError?

    // MARK: Internal

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    var rangeError: TDLibVODRangeError? {
        lock.lock()
        defer { lock.unlock() }
        return storedRangeError
    }

    init(source: TDLibVODRangeSource) {
        self.source = source
    }

    func install(job: OpaquePointer) {
        lock.lock()
        self.job = job
        if cancelled {
            BetterTGFFmpegLookaheadJobCancel(job)
        }
        lock.unlock()
    }

    func clear(job: OpaquePointer) {
        lock.lock()
        if self.job == job {
            self.job = nil
        }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        if let job {
            BetterTGFFmpegLookaheadJobCancel(job)
        }
        let operation = activeOperation
        lock.unlock()
        operation?.cancel()
    }

    func read(
        offset: Int64,
        destination: UnsafeMutablePointer<UInt8>,
        capacity: Int,
    ) -> Int32 {
        guard offset >= 0, capacity > 0 else { return -2 }
        let operation = TDLibVODBlockingReadOperation()
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return -1
        }
        activeOperation = operation
        lock.unlock()

        let task = Task.detached(priority: .userInitiated) { [source] in
            while !Task.isCancelled {
                do {
                    let chunk = try await source.serializedRead(offset: offset, count: capacity)
                    operation.finish(with: .success(chunk.data))
                    return
                } catch TDLibVODRangeError.staleRequest {
                    do {
                        try await Task<Never, Never>.sleep(for: .milliseconds(10))
                    } catch {
                        operation.finish(with: .failure(error))
                        return
                    }
                } catch {
                    operation.finish(with: .failure(error))
                    return
                }
            }
            operation.finish(with: .failure(CancellationError()))
        }
        operation.install(task: task)
        let result = operation.wait()

        lock.lock()
        if activeOperation === operation {
            activeOperation = nil
        }
        let wasCancelled = cancelled
        lock.unlock()

        guard !wasCancelled else { return -1 }

        switch result {
        case .success(let data):
            guard data.count <= capacity else { return -2 }
            data.withUnsafeBytes { bytes in
                guard let source = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
                destination.update(from: source, count: data.count)
            }
            return Int32(data.count)
        case .failure(let error):
            if let rangeError = error as? TDLibVODRangeError {
                lock.lock()
                storedRangeError = rangeError
                lock.unlock()
            }
            if wasCancelled
                || error is CancellationError
                || error as? TDLibVODRangeError == .cancelled
                || error as? TDLibVODRangeError == .staleRequest
            {
                return -1
            }
            return -2
        }
    }
}

// MARK: - TDLibVODBlockingReadOperation

private final class TDLibVODBlockingReadOperation: @unchecked Sendable {
    // MARK: Private

    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var cancelled = false
    private var result: Result<Data, Swift.Error>?
    private var task: Task<Void, Never>?

    // MARK: Internal

    func install(task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
        finish(with: .failure(CancellationError()))
    }

    func finish(with result: Result<Data, Swift.Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        lock.unlock()
        semaphore.signal()
    }

    func wait() -> Result<Data, Swift.Error> {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return result ?? .failure(TDLibVODRangeError.readFailed)
    }
}

private func tdLibVODFFmpegReadCallback(
    context: UnsafeMutableRawPointer?,
    offset: Int64,
    destination: UnsafeMutablePointer<UInt8>?,
    destinationCapacity: Int32,
) -> Int32 {
    guard let context, let destination, destinationCapacity > 0 else { return -2 }
    let box = Unmanaged<TDLibVODFFmpegReadBox>.fromOpaque(context).takeUnretainedValue()
    return box.read(
        offset: offset,
        destination: destination,
        capacity: Int(destinationCapacity),
    )
}

#if DEBUG
    private extension TDLibVODFFmpegLookahead {
        static func runDebugProbe() async {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("bettertg-vod-ffmpeg-probe.mp4")
            try? FileManager.default.removeItem(at: url)
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                _ = try await VideoNoteAssetWriter.makeDebugSegment(
                    outputURL: url,
                    duration: 12,
                    frameSeed: 300,
                )
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0 else {
                    throw LookaheadError.invalidRange
                }

                let network = TDLibVODProbeNetwork(available: true)
                let backend = TDLibVODProbeBackend(fileURL: url, fileSize: size, network: network)
                await backend.setAutoFulfill(true)
                let coordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-ffmpeg",
                    client: backend.client,
                    requestTimeout: .seconds(1),
                )
                let lease = await coordinator.acquire(file: backend.file(expectedSize: size * 2))
                let lookahead = TDLibVODFFmpegLookahead(lease: lease)
                let state = try await lookahead.scan(
                    seekTime: 0,
                    currentPlaybackTime: 0,
                    lookaheadDuration: 10,
                )
                let seekState = try await lookahead.scan(
                    seekTime: 6,
                    currentPlaybackTime: 6,
                    lookaheadDuration: 2,
                )
                guard state.audioReadableTo != nil,
                      state.videoReadableTo != nil,
                      state.duration >= 11.5,
                      state.isEnded || (state.minimumReadableTo ?? -1) >= 9.5,
                      state.bytesRead > 0,
                      state.readCallCount > 0,
                      state.sizeCallCount > 0,
                      seekState.isEnded || (seekState.minimumReadableTo ?? -1) >= 7.5,
                      seekState.seekCallCount > 0,
                      seekState.sizeCallCount > 0
                else {
                    throw LookaheadError.invalidProof(
                        "audio=\(String(describing: state.audioReadableTo)), "
                            + "video=\(String(describing: state.videoReadableTo)), "
                            + "duration=\(state.duration), ended=\(state.isEnded), "
                            + "minimum=\(String(describing: state.minimumReadableTo)), "
                            + "bytes=\(state.bytesRead), reads=\(state.readCallCount), "
                            + "seeks/sizes=\(state.seekCallCount)/\(state.sizeCallCount), "
                            + "seek-minimum=\(String(describing: seekState.minimumReadableTo)), "
                            + "seek-calls/sizes=\(seekState.seekCallCount)/\(seekState.sizeCallCount)",
                    )
                }
                await lease.invalidate()

                let supersedeBackend = TDLibVODProbeBackend(
                    fileURL: url,
                    fileSize: size,
                    network: network,
                )
                await supersedeBackend.setAutoFulfill(false)
                let supersedeCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-ffmpeg-supersede",
                    client: supersedeBackend.client,
                    requestTimeout: .seconds(2),
                )
                let supersedeLease = await supersedeCoordinator.acquire(
                    file: supersedeBackend.file(expectedSize: size),
                )
                let supersedingLookahead = TDLibVODFFmpegLookahead(lease: supersedeLease)
                let staleTask = Task {
                    try await supersedingLookahead.scan(seekTime: 0, lookaheadDuration: 10)
                }
                try await waitUntil { await supersedeBackend.downloadCalls.count == 1 }
                let newestTask = Task {
                    try await supersedingLookahead.scan(seekTime: 6, lookaheadDuration: 2)
                }
                try await waitUntil { await supersedingLookahead.debugScanGeneration() == 2 }
                staleTask.cancel()
                await supersedeBackend.addCached(0..<size)
                await supersedeLease.source.update(
                    file: supersedeBackend.file(expectedSize: size),
                    sequence: 1,
                )
                do {
                    _ = try await staleTask.value
                    throw LookaheadError.ffmpeg(-5)
                } catch LookaheadError.superseded {
                    // Expected: delayed cancellation cannot close the newer seek's lease.
                }
                let newestState = try await newestTask.value
                guard newestState.isEnded || (newestState.minimumReadableTo ?? -1) >= 7.5 else {
                    throw LookaheadError.invalidProof("newest seek lost its shared lease")
                }
                await supersedeLease.invalidate()

                let blockedBackend = TDLibVODProbeBackend(
                    fileURL: url,
                    fileSize: size,
                    network: network,
                )
                await blockedBackend.setAutoFulfill(false)
                await blockedBackend.setSuspendCancel(true)
                let blockedCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-ffmpeg-cancel",
                    client: blockedBackend.client,
                    requestTimeout: .seconds(2),
                )
                let blockedLease = await blockedCoordinator.acquire(
                    file: blockedBackend.file(expectedSize: size),
                )
                let blockedLookahead = TDLibVODFFmpegLookahead(lease: blockedLease)
                let blockedTask = Task {
                    try await blockedLookahead.scan(seekTime: 0, lookaheadDuration: 10)
                }
                try await waitUntil { await blockedBackend.downloadCalls.count == 1 }
                blockedTask.cancel()
                do {
                    _ = try await blockedTask.value
                    throw LookaheadError.ffmpeg(-2)
                } catch LookaheadError.cancelled {
                    // Expected: cancel wakes the synchronous AVIO callback and joins its worker.
                }
                try await waitUntil { await blockedBackend.cancelStarted }
                await blockedBackend.resumeCancel()
                try await waitUntil { await blockedBackend.completedCancelCount == 1 }

                let unknownSizeBackend = TDLibVODProbeBackend(
                    fileURL: url,
                    fileSize: size,
                    network: network,
                )
                await unknownSizeBackend.setAutoFulfill(false)
                await unknownSizeBackend.setReportsExactSize(false)
                let unknownSizeCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-ffmpeg-size-cancel",
                    client: unknownSizeBackend.client,
                    requestTimeout: .seconds(2),
                )
                let unknownSizeLease = await unknownSizeCoordinator.acquire(
                    file: unknownSizeBackend.file(expectedSize: size * 2, exactSize: 0),
                )
                let unknownSizeLookahead = TDLibVODFFmpegLookahead(lease: unknownSizeLease)
                let unknownSizeTask = Task {
                    try await unknownSizeLookahead.scan(seekTime: 0, lookaheadDuration: 10)
                }
                try await waitUntil { await unknownSizeBackend.downloadCalls.count == 1 }
                unknownSizeTask.cancel()
                do {
                    _ = try await unknownSizeTask.value
                    throw LookaheadError.ffmpeg(-4)
                } catch LookaheadError.cancelled {
                    // Expected: pre-worker size resolution also releases its last lease.
                }
                try await waitUntil { await unknownSizeBackend.cancelCount == 1 }

                let proof = "VOD FFmpeg probe: avio=64KiB, streams=audio+video, "
                    + "lookahead>=10s, seek/size/read=\(seekState.seekCallCount)/"
                    + "\(seekState.sizeCallCount)/\(state.readCallCount + seekState.readCallCount), "
                    + "bytes=\(state.bytesRead + seekState.bytesRead), "
                    + "stale-seek, blocked/pre-size-cancel+lease=true"
                writeDebugProbeResult(proof)
                log(proof)
            } catch {
                let proof = "VOD FFmpeg lookahead probe failed: \(error)"
                writeDebugProbeResult(proof)
                assertionFailure(proof)
            }
        }

        static func waitUntil(
            _ condition: @escaping @Sendable () async -> Bool,
        ) async throws {
            for _ in 0..<200 {
                if await condition() {
                    return
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            }
            throw LookaheadError.ffmpeg(-3)
        }

        static func writeDebugProbeResult(_ result: String) {
            let documentURLs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            guard let documentsURL = documentURLs.first else { return }
            try? Data(result.utf8).write(
                to: documentsURL.appendingPathComponent("vod-ffmpeg-lookahead-probe.txt"),
                options: .atomic,
            )
        }
    }
#endif

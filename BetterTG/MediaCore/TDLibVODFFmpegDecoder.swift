// TDLibVODFFmpegDecoder.swift

import FFmpegBridge
import Foundation
#if DEBUG
    import CryptoKit
#endif

// MARK: - TDLibVODFFmpegDecoder

actor TDLibVODFFmpegDecoder {
    // MARK: Internal

    struct VideoFrame {
        let bytes: Data
        let bytesPerRow: Int
        let duration: TimeInterval
        let height: Int
        let isKeyFrame: Bool
        let presentationTime: TimeInterval
        let width: Int
    }

    struct AudioFrame {
        let channelCount: Int
        let frameCount: Int
        let presentationTime: TimeInterval
        let sampleRate: Int
        let samples: Data
    }

    struct Metadata: Equatable {
        let audioCodecID: Int32
        let audioEndTime: TimeInterval
        let audioStartTime: TimeInterval
        let duration: TimeInterval
        let hasAudio: Bool
        let hasVideo: Bool
        let timelineOrigin: TimeInterval
        let videoCodecID: Int32
        let videoEndTime: TimeInterval
        let videoStartTime: TimeInterval
    }

    struct Summary: Equatable {
        let audioCodecID: Int32
        let audioDecodedTo: TimeInterval
        let audioFrameCount: Int
        let audioIsOpus: Bool
        let bytesRead: Int64
        let continuationTime: TimeInterval
        let duration: TimeInterval
        let explicitSeekCount: Int
        let isEnded: Bool
        let maximumPendingPacketBytes: Int64
        let maximumPendingPacketCount: Int
        let openCount: Int
        let readCallCount: Int
        let runCount: Int
        let seekCallCount: Int
        let sessionID: UUID
        let sizeCallCount: Int
        let timelineOrigin: TimeInterval
        let videoCodecID: Int32
        let videoDecodedTo: TimeInterval
        let videoFrameCount: Int
        let videoIsVP9: Bool
    }

    enum DecodeError: Swift.Error, Equatable {
        case cancelled
        case closed
        case couldNotCreateJob
        case ffmpeg(Int32)
        case invalidRange
        case range(TDLibVODRangeError)
        case superseded
    }

    enum DecodeMode: Equatable {
        case continueSession
        case oneShot
        case startSession
    }

    // MARK: Private

    private enum DecodeDisposition: Equatable {
        case cancelled
        case running
        case superseded
    }

    private struct ActiveDecode {
        let box: TDLibVODFFmpegDecodeBox
        let continuation: CheckedContinuation<Summary, Swift.Error>
        var disposition: DecodeDisposition
        let id: UUID
        let retainsSessionOnSuccess: Bool
        let session: TDLibVODFFmpegDecodeSession
    }

    private let lease: TDLibVODRangeLease
    private var activeDecodes = [UUID: ActiveDecode]()
    private var currentDecodeID: UUID?
    private var closeWaiters = [CheckedContinuation<Void, Never>]()
    private var decodeGeneration = UInt64.zero
    private var isClosed = false
    private var leaseReleased = false
    private var persistentSession: TDLibVODFFmpegDecodeSession?

    init(lease: TDLibVODRangeLease) {
        self.lease = lease
    }

    deinit {
        activeDecodes.values.forEach { $0.session.invalidate() }
        persistentSession?.invalidate()
    }

    #if DEBUG
        nonisolated static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-vod-ffmpeg-decode") else { return }
            Task { await runDebugProbe() }
        }
    #endif

    func decode(
        seekTime: TimeInterval,
        duration: TimeInterval,
        mode: DecodeMode = .oneShot,
        onMetadata: @escaping @Sendable (Metadata) -> Bool = { _ in true },
        onVideoFrame: @escaping @Sendable (VideoFrame) -> Bool,
        onAudioFrame: @escaping @Sendable (AudioFrame) -> Bool,
    ) async throws -> Summary {
        guard !isClosed else { throw DecodeError.closed }
        guard seekTime.isFinite,
              seekTime >= 0,
              seekTime <= Double(Int64.max - 61_000_000) / 1_000_000,
              duration.isFinite,
              duration > 0,
              duration <= 60,
              (seekTime + duration).isFinite,
              seekTime + duration <= Double(Int64.max - 1_000_000) / 1_000_000
        else { throw DecodeError.invalidRange }

        decodeGeneration &+= 1
        let generation = decodeGeneration
        supersedeActiveDecode()
        if mode != .continueSession {
            invalidatePersistentSession()
        }
        let fileSize: Int64
        do {
            fileSize = try await resolvedFileSizeRetryingStale()
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled {
                invalidatePersistentSession()
                throw DecodeError.cancelled
            }
            throw error
        }
        guard generation == decodeGeneration else { throw DecodeError.superseded }

        let requestID = UUID()
        let retainsSessionOnSuccess = mode != .oneShot
        let session: TDLibVODFFmpegDecodeSession
        let continuesSession: Bool
        if mode == .continueSession,
           let persistentSession,
           persistentSession.updateCallbacks(
               onMetadata: onMetadata,
               onVideoFrame: onVideoFrame,
               onAudioFrame: onAudioFrame,
           )
        {
            session = persistentSession
            continuesSession = true
        } else {
            if mode == .continueSession {
                invalidatePersistentSession()
            }
            session = TDLibVODFFmpegDecodeSession(
                source: lease.source,
                onMetadata: onMetadata,
                onVideoFrame: onVideoFrame,
                onAudioFrame: onAudioFrame,
            )
            continuesSession = false
            if retainsSessionOnSuccess {
                persistentSession = session
            }
        }
        let box = session.box
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeDecodes[requestID] = ActiveDecode(
                    box: box,
                    continuation: continuation,
                    disposition: .running,
                    id: requestID,
                    retainsSessionOnSuccess: retainsSessionOnSuccess,
                    session: session,
                )
                currentDecodeID = requestID
                startWorker(
                    requestID: requestID,
                    generation: generation,
                    session: session,
                    fileSize: fileSize,
                    seekTime: seekTime,
                    duration: duration,
                    isPersistent: retainsSessionOnSuccess,
                    isContinuation: continuesSession,
                )
            }
        } onCancel: {
            box.cancel()
            Task { await self.cancel(requestID: requestID, generation: generation) }
        }
    }

    func close() async {
        if !isClosed {
            isClosed = true
            decodeGeneration &+= 1
            for id in Array(activeDecodes.keys) {
                guard var activeDecode = activeDecodes[id] else { continue }
                activeDecode.disposition = .cancelled
                activeDecodes[id] = activeDecode
                activeDecode.session.invalidate()
            }
            currentDecodeID = nil
            invalidatePersistentSession()
        }
        if !activeDecodes.isEmpty {
            await withCheckedContinuation { continuation in
                closeWaiters.append(continuation)
            }
        }
        await releaseLeaseIfNeeded()
    }

    private func supersedeActiveDecode() {
        guard let currentDecodeID, var activeDecode = activeDecodes[currentDecodeID] else { return }
        activeDecode.disposition = .superseded
        activeDecodes[currentDecodeID] = activeDecode
        activeDecode.session.invalidate()
        if persistentSession === activeDecode.session {
            persistentSession = nil
        }
        self.currentDecodeID = nil
    }

    private func cancel(requestID: UUID, generation: UInt64) {
        guard generation == decodeGeneration,
              var activeDecode = activeDecodes[requestID]
        else { return }
        activeDecode.disposition = .cancelled
        activeDecodes[requestID] = activeDecode
        if currentDecodeID == requestID {
            currentDecodeID = nil
        }
        activeDecode.session.invalidate()
        if persistentSession === activeDecode.session {
            persistentSession = nil
        }
    }

    private func invalidatePersistentSession() {
        persistentSession?.invalidate()
        persistentSession = nil
    }

    private func startWorker(
        requestID: UUID,
        generation: UInt64,
        session: TDLibVODFFmpegDecodeSession,
        fileSize: Int64,
        seekTime: TimeInterval,
        duration: TimeInterval,
        isPersistent: Bool,
        isContinuation: Bool,
    ) {
        let thread = Thread { [self] in
            let box = session.box
            guard let job = session.beginRun(fileSize: fileSize) else {
                let error: DecodeError = box.isCancelled ? .cancelled : .couldNotCreateJob
                Task {
                    await finish(
                        requestID: requestID,
                        generation: generation,
                        result: .failure(error),
                    )
                }
                return
            }
            let runResult =
                if isContinuation {
                    BetterTGFFmpegPlaybackJobContinue(job, duration)
                } else if isPersistent {
                    BetterTGFFmpegPlaybackJobStartPersistent(job, seekTime, duration)
                } else {
                    BetterTGFFmpegPlaybackJobRun(job, seekTime, duration)
                }
            let result: Result<Summary, DecodeError> =
                if runResult == 1 {
                    .success(Summary(
                        audioCodecID: BetterTGFFmpegPlaybackJobAudioCodecID(job),
                        audioDecodedTo: BetterTGFFmpegPlaybackJobAudioDecodedTo(job),
                        audioFrameCount: Int(BetterTGFFmpegPlaybackJobAudioFrameCount(job)),
                        audioIsOpus: BetterTGFFmpegPlaybackJobAudioIsOpus(job) != 0,
                        bytesRead: BetterTGFFmpegPlaybackJobBytesRead(job),
                        continuationTime: BetterTGFFmpegPlaybackJobContinuationTime(job),
                        duration: BetterTGFFmpegPlaybackJobDuration(job),
                        explicitSeekCount: Int(BetterTGFFmpegPlaybackJobExplicitSeekCount(job)),
                        isEnded: BetterTGFFmpegPlaybackJobIsEnded(job) != 0,
                        maximumPendingPacketBytes: BetterTGFFmpegPlaybackJobMaximumPendingPacketBytes(job),
                        maximumPendingPacketCount: Int(BetterTGFFmpegPlaybackJobMaximumPendingPacketCount(job)),
                        openCount: Int(BetterTGFFmpegPlaybackJobOpenCount(job)),
                        readCallCount: Int(BetterTGFFmpegPlaybackJobReadCallCount(job)),
                        runCount: Int(BetterTGFFmpegPlaybackJobRunCount(job)),
                        seekCallCount: Int(BetterTGFFmpegPlaybackJobSeekCallCount(job)),
                        sessionID: session.id,
                        sizeCallCount: Int(BetterTGFFmpegPlaybackJobSizeCallCount(job)),
                        timelineOrigin: BetterTGFFmpegPlaybackJobTimelineOrigin(job),
                        videoCodecID: BetterTGFFmpegPlaybackJobVideoCodecID(job),
                        videoDecodedTo: BetterTGFFmpegPlaybackJobVideoDecodedTo(job),
                        videoFrameCount: Int(BetterTGFFmpegPlaybackJobVideoFrameCount(job)),
                        videoIsVP9: BetterTGFFmpegPlaybackJobVideoIsVP9(job) != 0,
                    ))
                } else if runResult == -1 || box.isCancelled {
                    .failure(.cancelled)
                } else if let rangeError = box.rangeError {
                    rangeError == .cancelled
                        ? .failure(.cancelled)
                        : .failure(.range(rangeError))
                } else {
                    .failure(.ffmpeg(BetterTGFFmpegPlaybackJobErrorCode(job)))
                }
            session.finishRun(job: job)
            Task { await finish(requestID: requestID, generation: generation, result: result) }
        }
        thread.name = "BetterTG VOD FFmpeg Decode"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    private func finish(
        requestID: UUID,
        generation _: UInt64,
        result: Result<Summary, DecodeError>,
    ) {
        guard let activeDecode = activeDecodes.removeValue(forKey: requestID) else { return }
        if currentDecodeID == requestID {
            currentDecodeID = nil
        }
        let resultFailed =
            if case .failure = result {
                true
            } else {
                false
            }
        let resultEnded: Bool =
            if case .success(let summary) = result {
                summary.isEnded
            } else {
                false
            }
        let boxWasCancelled = activeDecode.box.isCancelled
        let shouldInvalidateSession = activeDecode.disposition != .running
            || boxWasCancelled
            || resultFailed
            || resultEnded
            || !activeDecode.retainsSessionOnSuccess
        if shouldInvalidateSession {
            activeDecode.session.invalidate()
            if persistentSession === activeDecode.session {
                persistentSession = nil
            }
        }
        switch activeDecode.disposition {
        case .cancelled:
            activeDecode.continuation.resume(throwing: DecodeError.cancelled)
        case .superseded:
            activeDecode.continuation.resume(throwing: DecodeError.superseded)
        case .running:
            if boxWasCancelled {
                activeDecode.continuation.resume(throwing: DecodeError.cancelled)
            } else {
                activeDecode.continuation.resume(with: result.mapError { $0 })
            }
        }
        if activeDecodes.isEmpty, !closeWaiters.isEmpty {
            let waiters = closeWaiters
            closeWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    private func releaseLeaseIfNeeded() async {
        guard !leaseReleased else { return }
        leaseReleased = true
        await lease.invalidate()
    }

    private func resolvedFileSizeRetryingStale() async throws -> Int64 {
        while true {
            do {
                return try await lease.source.resolvedFileSize()
            } catch TDLibVODRangeError.staleRequest {
                if Task.isCancelled {
                    throw DecodeError.cancelled
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(10))
            } catch {
                if Task.isCancelled {
                    throw DecodeError.cancelled
                }
                if let rangeError = error as? TDLibVODRangeError {
                    throw DecodeError.range(rangeError)
                }
                throw error
            }
        }
    }
}

// MARK: - TDLibVODFFmpegDecodeSession

private final class TDLibVODFFmpegDecodeSession: @unchecked Sendable {
    // MARK: Internal

    let box: TDLibVODFFmpegDecodeBox
    let id = UUID()

    // MARK: Private

    private let lock = NSLock()
    private var invalidated = false
    private var isRunning = false
    private var job: OpaquePointer?
    private var retainedContext: UnsafeMutableRawPointer?

    init(
        source: TDLibVODRangeSource,
        onMetadata: @escaping @Sendable (TDLibVODFFmpegDecoder.Metadata) -> Bool,
        onVideoFrame: @escaping @Sendable (TDLibVODFFmpegDecoder.VideoFrame) -> Bool,
        onAudioFrame: @escaping @Sendable (TDLibVODFFmpegDecoder.AudioFrame) -> Bool,
    ) {
        self.box = TDLibVODFFmpegDecodeBox(
            source: source,
            onMetadata: onMetadata,
            onVideoFrame: onVideoFrame,
            onAudioFrame: onAudioFrame,
        )
    }

    deinit {
        invalidate()
    }

    func updateCallbacks(
        onMetadata: @escaping @Sendable (TDLibVODFFmpegDecoder.Metadata) -> Bool,
        onVideoFrame: @escaping @Sendable (TDLibVODFFmpegDecoder.VideoFrame) -> Bool,
        onAudioFrame: @escaping @Sendable (TDLibVODFFmpegDecoder.AudioFrame) -> Bool,
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !invalidated, !isRunning else { return false }
        return box.updateCallbacks(
            onMetadata: onMetadata,
            onVideoFrame: onVideoFrame,
            onAudioFrame: onAudioFrame,
        )
    }

    func beginRun(fileSize: Int64) -> OpaquePointer? {
        lock.lock()
        defer { lock.unlock() }
        guard !invalidated, !isRunning else { return nil }
        if job == nil {
            let context = Unmanaged.passRetained(box).toOpaque()
            guard let createdJob = BetterTGFFmpegPlaybackJobCreate(
                context,
                fileSize,
                tdLibVODFFmpegDecodeReadCallback,
                tdLibVODFFmpegDecodeMetadataCallback,
                tdLibVODFFmpegDecodeVideoCallback,
                tdLibVODFFmpegDecodeAudioCallback,
            ) else {
                Unmanaged<TDLibVODFFmpegDecodeBox>.fromOpaque(context).release()
                return nil
            }
            retainedContext = context
            job = createdJob
            box.install(job: createdJob)
        }
        isRunning = true
        return job
    }

    func finishRun(job: OpaquePointer) {
        var destroyedJob: OpaquePointer?
        var destroyedContext: UnsafeMutableRawPointer?
        lock.lock()
        if self.job == job {
            isRunning = false
            if invalidated {
                destroyedJob = self.job
                destroyedContext = retainedContext
                self.job = nil
                retainedContext = nil
            }
        }
        lock.unlock()
        destroy(job: destroyedJob, context: destroyedContext)
    }

    func invalidate() {
        var destroyedJob: OpaquePointer?
        var destroyedContext: UnsafeMutableRawPointer?
        lock.lock()
        if !invalidated {
            invalidated = true
            if !isRunning {
                destroyedJob = job
                destroyedContext = retainedContext
                job = nil
                retainedContext = nil
            }
        }
        lock.unlock()
        box.cancel()
        destroy(job: destroyedJob, context: destroyedContext)
    }

    private func destroy(
        job: OpaquePointer?,
        context: UnsafeMutableRawPointer?,
    ) {
        guard let job, let context else { return }
        box.clear(job: job)
        BetterTGFFmpegPlaybackJobDestroy(job)
        Unmanaged<TDLibVODFFmpegDecodeBox>.fromOpaque(context).release()
    }
}

// MARK: - TDLibVODFFmpegDecodeBox

private final class TDLibVODFFmpegDecodeBox: @unchecked Sendable {
    // MARK: Private

    private let source: TDLibVODRangeSource
    private var onMetadata: @Sendable (TDLibVODFFmpegDecoder.Metadata) -> Bool
    private var onVideoFrame: @Sendable (TDLibVODFFmpegDecoder.VideoFrame) -> Bool
    private var onAudioFrame: @Sendable (TDLibVODFFmpegDecoder.AudioFrame) -> Bool
    private let lock = NSLock()
    private var activeOperation: TDLibVODFFmpegDecodeReadOperation?
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

    init(
        source: TDLibVODRangeSource,
        onMetadata: @escaping @Sendable (TDLibVODFFmpegDecoder.Metadata) -> Bool,
        onVideoFrame: @escaping @Sendable (TDLibVODFFmpegDecoder.VideoFrame) -> Bool,
        onAudioFrame: @escaping @Sendable (TDLibVODFFmpegDecoder.AudioFrame) -> Bool,
    ) {
        self.source = source
        self.onMetadata = onMetadata
        self.onVideoFrame = onVideoFrame
        self.onAudioFrame = onAudioFrame
    }

    func updateCallbacks(
        onMetadata: @escaping @Sendable (TDLibVODFFmpegDecoder.Metadata) -> Bool,
        onVideoFrame: @escaping @Sendable (TDLibVODFFmpegDecoder.VideoFrame) -> Bool,
        onAudioFrame: @escaping @Sendable (TDLibVODFFmpegDecoder.AudioFrame) -> Bool,
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, activeOperation == nil else { return false }
        self.onMetadata = onMetadata
        self.onVideoFrame = onVideoFrame
        self.onAudioFrame = onAudioFrame
        storedRangeError = nil
        return true
    }

    func install(job: OpaquePointer) {
        lock.lock()
        self.job = job
        if cancelled {
            BetterTGFFmpegPlaybackJobCancel(job)
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
            BetterTGFFmpegPlaybackJobCancel(job)
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
        let operation = TDLibVODFFmpegDecodeReadOperation()
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
            if error is CancellationError
                || error as? TDLibVODRangeError == .cancelled
                || error as? TDLibVODRangeError == .staleRequest
            {
                return -1
            }
            return -2
        }
    }

    func acceptVideo(
        bytes: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        presentationTime: TimeInterval,
        duration: TimeInterval,
        isKeyFrame: Bool,
    ) -> Int32 {
        lock.lock()
        let callback: (@Sendable (TDLibVODFFmpegDecoder.VideoFrame) -> Bool)? =
            cancelled ? nil : onVideoFrame
        lock.unlock()
        guard let callback,
              width > 0,
              height > 0,
              bytesPerRow >= width * 4,
              height <= Int.max / bytesPerRow
        else { return 0 }
        let frame = TDLibVODFFmpegDecoder.VideoFrame(
            bytes: Data(bytes: bytes, count: bytesPerRow * height),
            bytesPerRow: bytesPerRow,
            duration: duration,
            height: height,
            isKeyFrame: isKeyFrame,
            presentationTime: presentationTime,
            width: width,
        )
        return callback(frame) ? 1 : 0
    }

    func acceptMetadata(
        hasAudio: Bool,
        hasVideo: Bool,
        videoCodecID: Int32,
        audioCodecID: Int32,
        duration: TimeInterval,
        timelineOrigin: TimeInterval,
        videoStartTime: TimeInterval,
        videoEndTime: TimeInterval,
        audioStartTime: TimeInterval,
        audioEndTime: TimeInterval,
    ) -> Int32 {
        lock.lock()
        let callback: (@Sendable (TDLibVODFFmpegDecoder.Metadata) -> Bool)? =
            cancelled ? nil : onMetadata
        lock.unlock()
        guard let callback,
              duration.isFinite,
              duration >= 0,
              timelineOrigin.isFinite,
              videoStartTime.isFinite,
              videoEndTime.isFinite,
              audioStartTime.isFinite,
              audioEndTime.isFinite
        else { return 0 }
        return callback(.init(
            audioCodecID: audioCodecID,
            audioEndTime: audioEndTime,
            audioStartTime: audioStartTime,
            duration: duration,
            hasAudio: hasAudio,
            hasVideo: hasVideo,
            timelineOrigin: timelineOrigin,
            videoCodecID: videoCodecID,
            videoEndTime: videoEndTime,
            videoStartTime: videoStartTime,
        )) ? 1 : 0
    }

    func acceptAudio(
        samples: UnsafePointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Int,
        presentationTime: TimeInterval,
    ) -> Int32 {
        lock.lock()
        let callback: (@Sendable (TDLibVODFFmpegDecoder.AudioFrame) -> Bool)? =
            cancelled ? nil : onAudioFrame
        lock.unlock()
        guard let callback,
              frameCount > 0,
              (1...2).contains(channelCount),
              sampleRate > 0,
              frameCount <= Int.max / channelCount / MemoryLayout<Float>.size
        else { return 0 }
        let byteCount = frameCount * channelCount * MemoryLayout<Float>.size
        let frame = TDLibVODFFmpegDecoder.AudioFrame(
            channelCount: channelCount,
            frameCount: frameCount,
            presentationTime: presentationTime,
            sampleRate: sampleRate,
            samples: Data(bytes: samples, count: byteCount),
        )
        return callback(frame) ? 1 : 0
    }
}

// MARK: - TDLibVODFFmpegDecodeReadOperation

private final class TDLibVODFFmpegDecodeReadOperation: @unchecked Sendable {
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

private func tdLibVODFFmpegDecodeReadCallback(
    context: UnsafeMutableRawPointer?,
    offset: Int64,
    destination: UnsafeMutablePointer<UInt8>?,
    destinationCapacity: Int32,
) -> Int32 {
    guard let context, let destination, destinationCapacity > 0 else { return -2 }
    let box = Unmanaged<TDLibVODFFmpegDecodeBox>.fromOpaque(context).takeUnretainedValue()
    return box.read(
        offset: offset,
        destination: destination,
        capacity: Int(destinationCapacity),
    )
}

private func tdLibVODFFmpegDecodeVideoCallback(
    context: UnsafeMutableRawPointer?,
    bytes: UnsafePointer<UInt8>?,
    width: Int32,
    height: Int32,
    bytesPerRow: Int32,
    presentationTime: Double,
    frameDuration: Double,
    isKeyFrame: Int32,
) -> Int32 {
    guard let context, let bytes else { return 0 }
    let box = Unmanaged<TDLibVODFFmpegDecodeBox>.fromOpaque(context).takeUnretainedValue()
    return box.acceptVideo(
        bytes: bytes,
        width: Int(width),
        height: Int(height),
        bytesPerRow: Int(bytesPerRow),
        presentationTime: presentationTime,
        duration: frameDuration,
        isKeyFrame: isKeyFrame != 0,
    )
}

private func tdLibVODFFmpegDecodeMetadataCallback(
    context: UnsafeMutableRawPointer?,
    hasAudio: Int32,
    hasVideo: Int32,
    videoCodecID: Int32,
    audioCodecID: Int32,
    duration: Double,
    timelineOrigin: Double,
    videoStartTime: Double,
    videoEndTime: Double,
    audioStartTime: Double,
    audioEndTime: Double,
) -> Int32 {
    guard let context else { return 0 }
    let box = Unmanaged<TDLibVODFFmpegDecodeBox>.fromOpaque(context).takeUnretainedValue()
    return box.acceptMetadata(
        hasAudio: hasAudio != 0,
        hasVideo: hasVideo != 0,
        videoCodecID: videoCodecID,
        audioCodecID: audioCodecID,
        duration: duration,
        timelineOrigin: timelineOrigin,
        videoStartTime: videoStartTime,
        videoEndTime: videoEndTime,
        audioStartTime: audioStartTime,
        audioEndTime: audioEndTime,
    )
}

private func tdLibVODFFmpegDecodeAudioCallback(
    context: UnsafeMutableRawPointer?,
    samples: UnsafePointer<Float>?,
    frameCount: Int32,
    channelCount: Int32,
    sampleRate: Int32,
    presentationTime: Double,
) -> Int32 {
    guard let context, let samples else { return 0 }
    let box = Unmanaged<TDLibVODFFmpegDecodeBox>.fromOpaque(context).takeUnretainedValue()
    return box.acceptAudio(
        samples: samples,
        frameCount: Int(frameCount),
        channelCount: Int(channelCount),
        sampleRate: Int(sampleRate),
        presentationTime: presentationTime,
    )
}

#if DEBUG
    private extension TDLibVODFFmpegDecoder {
        final class ProbeRecorder: @unchecked Sendable {
            // MARK: Private

            private let lock = NSLock()
            private var videoFrameCount = 0
            private var audioFrameCount = 0
            private var audioSampleCount = 0
            private var videoTimes = [TimeInterval]()
            private var audioTimes = [TimeInterval]()
            private var videoEnds = [TimeInterval]()
            private var audioEnds = [TimeInterval]()
            private var videoBytesAreValid = true
            private var audioBytesAreValid = true

            // MARK: Internal

            func record(video frame: VideoFrame) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                videoFrameCount += 1
                videoTimes.append(frame.presentationTime)
                videoEnds.append(frame.presentationTime + frame.duration)
                videoBytesAreValid = videoBytesAreValid
                    && frame.bytes.count == frame.bytesPerRow * frame.height
                    && frame.bytesPerRow >= frame.width * 4
                return true
            }

            func record(audio frame: AudioFrame) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                audioFrameCount += 1
                audioSampleCount += frame.frameCount
                audioTimes.append(frame.presentationTime)
                audioEnds.append(
                    frame.presentationTime + TimeInterval(frame.frameCount) / TimeInterval(frame.sampleRate),
                )
                audioBytesAreValid = audioBytesAreValid
                    && frame.sampleRate == 48000
                    && (1...2).contains(frame.channelCount)
                    && frame.samples.count == frame.frameCount * frame.channelCount * MemoryLayout<Float>.size
                return true
            }

            func snapshot() -> (
                videoFrames: Int,
                audioFrames: Int,
                audioSamples: Int,
                firstVideoTime: TimeInterval?,
                firstAudioTime: TimeInterval?,
                videoMonotonic: Bool,
                audioMonotonic: Bool,
                bytesValid: Bool,
            ) {
                lock.lock()
                defer { lock.unlock() }
                return (
                    videoFrameCount,
                    audioFrameCount,
                    audioSampleCount,
                    videoTimes.first,
                    audioTimes.first,
                    zip(videoTimes, videoTimes.dropFirst()).allSatisfy { $0 <= $1 },
                    zip(audioTimes, audioTimes.dropFirst()).allSatisfy { $0 <= $1 },
                    videoBytesAreValid && audioBytesAreValid,
                )
            }

            func continuity() -> (
                videoStrictlyMonotonic: Bool,
                audioStrictlyMonotonic: Bool,
                maximumVideoGap: TimeInterval,
                maximumAudioGap: TimeInterval,
                maximumVideoBoundaryError: TimeInterval,
                maximumAudioBoundaryError: TimeInterval,
            ) {
                lock.lock()
                defer { lock.unlock() }
                let videoGaps = zip(videoTimes, videoTimes.dropFirst()).map { $1 - $0 }
                let audioGaps = zip(audioTimes, audioTimes.dropFirst()).map { $1 - $0 }
                let videoBoundaryErrors = zip(videoEnds, videoTimes.dropFirst()).map { abs($1 - $0) }
                let audioBoundaryErrors = zip(audioEnds, audioTimes.dropFirst()).map { abs($1 - $0) }
                return (
                    videoGaps.allSatisfy { $0 > 0 },
                    audioGaps.allSatisfy { $0 > 0 },
                    videoGaps.max() ?? 0,
                    audioGaps.max() ?? 0,
                    videoBoundaryErrors.max() ?? 0,
                    audioBoundaryErrors.max() ?? 0,
                )
            }
        }

        static func runDebugProbe() async {
            let url = FileManager.default
.temporaryDirectory
                .appendingPathComponent("bettertg-vod-ffmpeg-decode-probe.webm")
            let unequalTracksURL = FileManager.default
                .temporaryDirectory
                .appendingPathComponent("bettertg-vod-ffmpeg-unequal-tracks-probe.webm")
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: unequalTracksURL)
            defer {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: unequalTracksURL)
            }
            let result: String
            var failure: Swift.Error?
            var stage = "fixture"
            do {
                try FFmpegVODProbeFixture.write(to: url)
                let fixtureData = try Data(contentsOf: url)
                let fixtureSHA256 = SHA256.hash(data: fixtureData)
                    .map { String(format: "%02x", $0) }
                    .joined()
                guard fixtureSHA256 == FFmpegVODProbeFixture.sha256 else {
                    throw DecodeError.ffmpeg(-9900)
                }
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0 else {
                    throw DecodeError.invalidRange
                }
                let network = TDLibVODProbeNetwork(available: true)
                let backend = TDLibVODProbeBackend(fileURL: url, fileSize: size, network: network)
                await backend.setAutoFulfill(true)
                let coordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-ffmpeg-decode",
                    client: backend.client,
                    requestTimeout: .seconds(2),
                )
                let decoder = await TDLibVODFFmpegDecoder(
                    lease: coordinator.acquire(file: backend.file(expectedSize: size * 2)),
                )
                stage = "initial VP9/Opus decode"
                let initialRecorder = ProbeRecorder()
                let initial = try await decoder.decode(
                    seekTime: 0,
                    duration: 3,
                    onVideoFrame: { initialRecorder.record(video: $0) },
                    onAudioFrame: { initialRecorder.record(audio: $0) },
                )
                stage = "persistent soft-horizon decode"
                let persistentRecorder = ProbeRecorder()
                let persistentFirst = try await decoder.decode(
                    seekTime: 0,
                    duration: 0.731,
                    mode: .startSession,
                    onVideoFrame: { persistentRecorder.record(video: $0) },
                    onAudioFrame: { persistentRecorder.record(audio: $0) },
                )
                let persistentSecond = try await decoder.decode(
                    seekTime: persistentFirst.continuationTime,
                    duration: 0.618,
                    mode: .continueSession,
                    onVideoFrame: { persistentRecorder.record(video: $0) },
                    onAudioFrame: { persistentRecorder.record(audio: $0) },
                )
                let persistentFinal = try await decoder.decode(
                    seekTime: persistentSecond.continuationTime,
                    duration: 1,
                    mode: .continueSession,
                    onVideoFrame: { persistentRecorder.record(video: $0) },
                    onAudioFrame: { persistentRecorder.record(audio: $0) },
                )
                stage = "WebM seek decode"
                let seekRecorder = ProbeRecorder()
                let seek = try await decoder.decode(
                    seekTime: 1,
                    duration: 0.8,
                    onVideoFrame: { seekRecorder.record(video: $0) },
                    onAudioFrame: { seekRecorder.record(audio: $0) },
                )
                let initialRecorded = initialRecorder.snapshot()
                let initialContinuity = initialRecorder.continuity()
                let persistentRecorded = persistentRecorder.snapshot()
                let persistentContinuity = persistentRecorder.continuity()
                let seekRecorded = seekRecorder.snapshot()
                let downloads = await backend.downloadCalls
                guard initial.videoIsVP9,
                      initial.audioIsOpus,
                      initial.isEnded,
                      initial.videoFrameCount == 24,
                      initial.audioFrameCount > 0,
                      initial.videoDecodedTo >= 1.9,
                      initial.audioDecodedTo >= 1.9,
                      (90000...100_000).contains(initialRecorded.audioSamples),
                      seek.videoIsVP9,
                      seek.audioIsOpus,
                      seek.videoDecodedTo >= 1.7,
                      seek.audioDecodedTo >= 1.7,
                      seekRecorded.firstVideoTime.map({ $0 >= 1 }) == true,
                      seekRecorded.firstAudioTime.map({ $0 >= 1 }) == true,
                      initialRecorded.videoFrames == initial.videoFrameCount,
                      initialRecorded.audioFrames == initial.audioFrameCount,
                      initialRecorded.videoMonotonic,
                      initialRecorded.audioMonotonic,
                      initialRecorded.bytesValid,
                      persistentFirst.sessionID == persistentSecond.sessionID,
                      persistentSecond.sessionID == persistentFinal.sessionID,
                      persistentFirst.openCount == 1,
                      persistentSecond.openCount == 1,
                      persistentFinal.openCount == 1,
                      persistentFirst.runCount == 1,
                      persistentSecond.runCount == 2,
                      persistentFinal.runCount == 3,
                      persistentFinal.explicitSeekCount == 0,
                      persistentFinal.maximumPendingPacketCount <= 4096,
                      persistentFinal.maximumPendingPacketBytes <= 32 * 1024 * 1024,
                      !persistentFirst.isEnded,
                      !persistentSecond.isEnded,
                      persistentFinal.isEnded,
                      persistentRecorded.videoFrames == 24,
                      (90000...100_000).contains(persistentRecorded.audioSamples),
                      abs(persistentRecorded.audioSamples - initialRecorded.audioSamples) <= 48,
                      persistentRecorded.videoFrames == persistentFinal.videoFrameCount,
                      persistentRecorded.audioFrames == persistentFinal.audioFrameCount,
                      persistentContinuity.videoStrictlyMonotonic,
                      persistentContinuity.audioStrictlyMonotonic,
                      persistentContinuity.maximumVideoGap < 0.1,
                      persistentContinuity.maximumAudioGap < 0.1,
                      persistentContinuity.maximumVideoBoundaryError
                      <= initialContinuity.maximumVideoBoundaryError + 0.000001,
                      persistentContinuity.maximumAudioBoundaryError
                      <= initialContinuity.maximumAudioBoundaryError + 1.0 / 48000.0 + 0.000001,
                      seekRecorded.videoFrames == seek.videoFrameCount,
                      seekRecorded.audioFrames == seek.audioFrameCount,
                      seekRecorded.videoMonotonic,
                      seekRecorded.audioMonotonic,
                      seekRecorded.bytesValid,
                      downloads.allSatisfy({ !$0.isFullDownload })
                else {
                    throw ProbeValidationError(details: [
                        "initial=\(initial)",
                        "seek=\(seek)",
                        "initial-recorded=\(initialRecorded)",
                        "initial-continuity=\(initialContinuity)",
                        "persistent-first=\(persistentFirst)",
                        "persistent-second=\(persistentSecond)",
                        "persistent-final=\(persistentFinal)",
                        "persistent-recorded=\(persistentRecorded)",
                        "persistent-continuity=\(persistentContinuity)",
                        "seek-recorded=\(seekRecorded)",
                        "downloads=\(downloads)",
                    ].joined(separator: "; "))
                }
                await decoder.close()

                stage = "unequal track horizons"
                try FFmpegVODUnequalTracksProbeFixture.write(to: unequalTracksURL)
                let unequalData = try Data(contentsOf: unequalTracksURL)
                let unequalSHA256 = SHA256.hash(data: unequalData)
                    .map { String(format: "%02x", $0) }
                    .joined()
                guard unequalSHA256 == FFmpegVODUnequalTracksProbeFixture.sha256 else {
                    throw DecodeError.ffmpeg(-9903)
                }
                let unequalAttributes = try FileManager.default.attributesOfItem(
                    atPath: unequalTracksURL.path,
                )
                guard let unequalSize = (unequalAttributes[.size] as? NSNumber)?.int64Value,
                      unequalSize > 65536
                else { throw DecodeError.invalidRange }
                let unequalBackend = TDLibVODProbeBackend(
                    fileURL: unequalTracksURL,
                    fileSize: unequalSize,
                    network: network,
                )
                await unequalBackend.setAutoFulfill(true)
                let unequalCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-ffmpeg-decode-unequal-tracks",
                    client: unequalBackend.client,
                    requestTimeout: .seconds(2),
                )
                let unequalDecoder = await TDLibVODFFmpegDecoder(
                    lease: unequalCoordinator.acquire(
                        file: unequalBackend.file(expectedSize: unequalSize * 2),
                    ),
                )
                let unequalRecorder = ProbeRecorder()
                let unequalFirst = try await unequalDecoder.decode(
                    seekTime: 0,
                    duration: 6,
                    mode: .startSession,
                    onVideoFrame: { unequalRecorder.record(video: $0) },
                    onAudioFrame: { unequalRecorder.record(audio: $0) },
                )
                let unequalTerminal = try await unequalDecoder.decode(
                    seekTime: unequalFirst.continuationTime,
                    duration: 4.2,
                    mode: .continueSession,
                    onVideoFrame: { unequalRecorder.record(video: $0) },
                    onAudioFrame: { unequalRecorder.record(audio: $0) },
                )
                let unequalTerminalRecorded = unequalRecorder.snapshot()
                let unequalFinal = try await unequalDecoder.decode(
                    seekTime: unequalTerminal.continuationTime,
                    duration: 2.5,
                    mode: .continueSession,
                    onVideoFrame: { unequalRecorder.record(video: $0) },
                    onAudioFrame: { unequalRecorder.record(audio: $0) },
                )
                let unequalRecorded = unequalRecorder.snapshot()
                let unequalContinuity = unequalRecorder.continuity()
                let unequalDownloads = await unequalBackend.downloadCalls
                guard !unequalFirst.isEnded,
                      unequalFirst.videoDecodedTo >= 5.9,
                      (8.0...8.2).contains(unequalFirst.audioDecodedTo),
                      !unequalTerminal.isEnded,
                      unequalTerminal.videoDecodedTo >= 10.1,
                      (9.9...10.1).contains(unequalTerminal.audioDecodedTo),
                      (185_000...195_000).contains(unequalTerminalRecorded.audioSamples),
                      unequalFinal.isEnded,
                      unequalFirst.sessionID == unequalTerminal.sessionID,
                      unequalTerminal.sessionID == unequalFinal.sessionID,
                      unequalFirst.openCount == 1,
                      unequalFinal.openCount == 1,
                      unequalFinal.runCount == 3,
                      unequalFinal.explicitSeekCount == 0,
                      unequalRecorded.videoFrames == 144,
                      (185_000...195_000).contains(unequalRecorded.audioSamples),
                      unequalRecorded.audioSamples == unequalTerminalRecorded.audioSamples,
                      unequalContinuity.videoStrictlyMonotonic,
                      unequalContinuity.audioStrictlyMonotonic,
                      unequalFinal.maximumPendingPacketCount > 0,
                      unequalFinal.maximumPendingPacketCount <= 4096,
                      unequalFinal.maximumPendingPacketBytes > 0,
                      unequalFinal.maximumPendingPacketBytes <= 32 * 1024 * 1024,
                      unequalDownloads.allSatisfy({ !$0.isFullDownload })
                else {
                    throw ProbeValidationError(details: [
                        "unequal-first=\(unequalFirst)",
                        "unequal-terminal=\(unequalTerminal)",
                        "unequal-final=\(unequalFinal)",
                        "unequal-terminal-recorded=\(unequalTerminalRecorded)",
                        "unequal-recorded=\(unequalRecorded)",
                        "unequal-continuity=\(unequalContinuity)",
                        "unequal-downloads=\(unequalDownloads)",
                    ].joined(separator: "; "))
                }
                await unequalDecoder.close()

                stage = "overlapping supersession"
                let supersedeBackend = TDLibVODProbeBackend(fileURL: url, fileSize: size, network: network)
                await supersedeBackend.setAutoFulfill(true)
                await supersedeBackend.setDownloadDelay(.seconds(2))
                let supersedeCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-ffmpeg-decode-supersede",
                    client: supersedeBackend.client,
                    requestTimeout: .seconds(3),
                )
                let supersedeDecoder = await TDLibVODFFmpegDecoder(
                    lease: supersedeCoordinator.acquire(
                        file: supersedeBackend.file(expectedSize: size * 2),
                    ),
                )
                let staleTask = Task {
                    try await supersedeDecoder.decode(
                        seekTime: 0,
                        duration: 2,
                        mode: .startSession,
                        onVideoFrame: { _ in true },
                        onAudioFrame: { _ in true },
                    )
                }
                try await waitUntil { await !supersedeBackend.downloadCalls.isEmpty }
                let newestTask = Task {
                    try await supersedeDecoder.decode(
                        seekTime: 1,
                        duration: 0.8,
                        mode: .startSession,
                        onVideoFrame: { _ in true },
                        onAudioFrame: { _ in true },
                    )
                }
                let staleSuperseded: Bool
                do {
                    _ = try await staleTask.value
                    staleSuperseded = false
                } catch DecodeError.superseded {
                    staleSuperseded = true
                } catch {
                    staleSuperseded = false
                }
                let newestSummary = try await newestTask.value
                guard staleSuperseded,
                      newestSummary.videoDecodedTo >= 1.7,
                      newestSummary.audioDecodedTo >= 1.7
                else { throw DecodeError.superseded }
                await supersedeDecoder.close()

                stage = "cancellation"
                let cancelBackend = TDLibVODProbeBackend(fileURL: url, fileSize: size, network: network)
                await cancelBackend.setAutoFulfill(false)
                let cancelCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-ffmpeg-decode-cancel",
                    client: cancelBackend.client,
                    requestTimeout: .seconds(3),
                )
                let cancelDecoder = await TDLibVODFFmpegDecoder(
                    lease: cancelCoordinator.acquire(file: cancelBackend.file(expectedSize: size)),
                )
                let cancelTask = Task {
                    try await cancelDecoder.decode(
                        seekTime: 0,
                        duration: 2,
                        mode: .startSession,
                        onVideoFrame: { _ in true },
                        onAudioFrame: { _ in true },
                    )
                }
                try await waitUntil { await !cancelBackend.downloadCalls.isEmpty }
                cancelTask.cancel()
                let cancellationWorked: Bool
                do {
                    _ = try await cancelTask.value
                    cancellationWorked = false
                } catch DecodeError.cancelled {
                    cancellationWorked = true
                } catch {
                    cancellationWorked = false
                }
                await cancelDecoder.close()
                try await waitUntil { await cancelBackend.completedCancelCount == 1 }
                guard cancellationWorked else { throw DecodeError.cancelled }

                stage = "close cancellation barrier"
                let closeBackend = TDLibVODProbeBackend(fileURL: url, fileSize: size, network: network)
                await closeBackend.setAutoFulfill(false)
                let closeCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-ffmpeg-decode-close",
                    client: closeBackend.client,
                    requestTimeout: .seconds(3),
                )
                let closeDecoder = await TDLibVODFFmpegDecoder(
                    lease: closeCoordinator.acquire(file: closeBackend.file(expectedSize: size)),
                )
                let blockedDecode = Task {
                    try await closeDecoder.decode(
                        seekTime: 0,
                        duration: 2,
                        mode: .startSession,
                        onVideoFrame: { _ in true },
                        onAudioFrame: { _ in true },
                    )
                }
                try await waitUntil { await !closeBackend.downloadCalls.isEmpty }
                await closeDecoder.close()
                let closeCancelledDecode: Bool
                do {
                    _ = try await blockedDecode.value
                    closeCancelledDecode = false
                } catch DecodeError.cancelled {
                    closeCancelledDecode = true
                } catch {
                    closeCancelledDecode = false
                }
                let closeActiveDownloads = await closeBackend.activeDownloadCount
                let closeCancelCount = await closeBackend.completedCancelCount
                guard closeCancelledDecode,
                      closeActiveDownloads == 0,
                      closeCancelCount == 1
                else { throw DecodeError.cancelled }

                result = "VOD FFmpeg decode probe: fixture-sha256=\(fixtureSHA256), "
                    + "unequal-sha256=\(unequalSHA256), "
                    + "video=vp9/96x54@12, audio=opus/48000x2, "
                    + "video-frames=\(initialRecorded.videoFrames), "
                    + "audio-frames=\(initialRecorded.audioFrames), "
                    + "audio-samples=\(initialRecorded.audioSamples), pts-monotonic=true, "
                    + "persistent-session=true, opens=1, pumps=3, rollover-seeks=0, boundary-gaps=0, "
                    + "pending-fifo=\(persistentFinal.maximumPendingPacketCount)/\(persistentFinal.maximumPendingPacketBytes), "
                    + "unequal-tracks=video12s/audio10s+sparse2-8s, short-track-exhaustion=true, "
                    + "sparse-fifo=\(unequalFinal.maximumPendingPacketCount)/\(unequalFinal.maximumPendingPacketBytes), "
                    + "seek=true, supersede=true, swr-tail=true, bgra/float-valid=true, "
                    + "finite-downloads=true, full-downloads=0, cancel=true, close-waits=true"
            } catch {
                failure = error
                result = "VOD FFmpeg decode probe failed at \(stage): \(error)"
            }
            if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: documentsURL.appendingPathComponent("vod-ffmpeg-decode-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
            if failure != nil {
                assertionFailure(result)
            }
        }

        static func waitUntil(
            timeout: Duration = .seconds(8),
            condition: @escaping () async -> Bool,
        ) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)
            while clock.now < deadline {
                if await condition() {
                    return
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(20))
            }
            throw DecodeError.ffmpeg(-9902)
        }

        struct ProbeValidationError: Swift.Error, CustomStringConvertible {
            let details: String

            var description: String { details }
        }
    }
#endif

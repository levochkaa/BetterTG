import FFmpegBridge
import Foundation
#if DEBUG
    import CryptoKit
#endif

// MARK: - TDLibVODFFmpegDecoder

actor TDLibVODFFmpegDecoder {
    // MARK: Lifecycle

    init(lease: TDLibVODRangeLease) {
        self.lease = lease
    }

    deinit {
        activeDecodes.values.forEach { $0.box.cancel() }
    }

    // MARK: Internal

    struct VideoFrame: Sendable {
        let bytes: Data
        let bytesPerRow: Int
        let duration: TimeInterval
        let height: Int
        let isKeyFrame: Bool
        let presentationTime: TimeInterval
        let width: Int
    }

    struct AudioFrame: Sendable {
        let channelCount: Int
        let frameCount: Int
        let presentationTime: TimeInterval
        let sampleRate: Int
        let samples: Data
    }

    struct Summary: Equatable, Sendable {
        let audioCodecID: Int32
        let audioDecodedTo: TimeInterval
        let audioFrameCount: Int
        let audioIsOpus: Bool
        let bytesRead: Int64
        let duration: TimeInterval
        let isEnded: Bool
        let readCallCount: Int
        let seekCallCount: Int
        let sizeCallCount: Int
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
        case superseded
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
        let fileSize: Int64
        do {
            fileSize = try await lease.source.resolvedFileSize()
        } catch {
            if Task.isCancelled { throw DecodeError.cancelled }
            throw error
        }
        try Task.checkCancellation()
        guard generation == decodeGeneration else { throw DecodeError.superseded }

        let requestID = UUID()
        let box = TDLibVODFFmpegDecodeBox(
            source: lease.source,
            onVideoFrame: onVideoFrame,
            onAudioFrame: onAudioFrame,
        )
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeDecodes[requestID] = ActiveDecode(
                    box: box,
                    continuation: continuation,
                    disposition: .running,
                    id: requestID,
                )
                currentDecodeID = requestID
                startWorker(
                    requestID: requestID,
                    generation: generation,
                    box: box,
                    fileSize: fileSize,
                    seekTime: seekTime,
                    duration: duration,
                )
            }
        } onCancel: {
            box.cancel()
            Task { await self.cancel(requestID: requestID, generation: generation) }
        }
    }

    func close() async {
        guard !isClosed else { return }
        isClosed = true
        decodeGeneration &+= 1
        for id in Array(activeDecodes.keys) {
            guard var activeDecode = activeDecodes[id] else { continue }
            activeDecode.disposition = .cancelled
            activeDecodes[id] = activeDecode
            activeDecode.box.cancel()
        }
        currentDecodeID = nil
        await releaseLeaseIfNeeded()
    }

    // MARK: Private

    private enum DecodeDisposition {
        case cancelled
        case running
        case superseded
    }

    private struct ActiveDecode {
        let box: TDLibVODFFmpegDecodeBox
        let continuation: CheckedContinuation<Summary, Swift.Error>
        var disposition: DecodeDisposition
        let id: UUID
    }

    private let lease: TDLibVODRangeLease
    private var activeDecodes = [UUID: ActiveDecode]()
    private var currentDecodeID: UUID?
    private var decodeGeneration = UInt64.zero
    private var isClosed = false
    private var leaseReleased = false

    private func supersedeActiveDecode() {
        guard let currentDecodeID, var activeDecode = activeDecodes[currentDecodeID] else { return }
        activeDecode.disposition = .superseded
        activeDecodes[currentDecodeID] = activeDecode
        activeDecode.box.cancel()
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
        activeDecode.box.cancel()
    }

    private func startWorker(
        requestID: UUID,
        generation: UInt64,
        box: TDLibVODFFmpegDecodeBox,
        fileSize: Int64,
        seekTime: TimeInterval,
        duration: TimeInterval,
    ) {
        let thread = Thread { [self] in
            let context = Unmanaged.passRetained(box).toOpaque()
            guard let job = BetterTGFFmpegPlaybackJobCreate(
                context,
                fileSize,
                tdLibVODFFmpegDecodeReadCallback,
                tdLibVODFFmpegDecodeVideoCallback,
                tdLibVODFFmpegDecodeAudioCallback,
            ) else {
                Unmanaged<TDLibVODFFmpegDecodeBox>.fromOpaque(context).release()
                Task {
                    await finish(
                        requestID: requestID,
                        generation: generation,
                        result: .failure(.couldNotCreateJob),
                    )
                }
                return
            }
            box.install(job: job)
            let runResult = BetterTGFFmpegPlaybackJobRun(job, seekTime, duration)
            let result: Result<Summary, DecodeError>
            if runResult == 1 {
                result = .success(Summary(
                    audioCodecID: BetterTGFFmpegPlaybackJobAudioCodecID(job),
                    audioDecodedTo: BetterTGFFmpegPlaybackJobAudioDecodedTo(job),
                    audioFrameCount: Int(BetterTGFFmpegPlaybackJobAudioFrameCount(job)),
                    audioIsOpus: BetterTGFFmpegPlaybackJobAudioIsOpus(job) != 0,
                    bytesRead: BetterTGFFmpegPlaybackJobBytesRead(job),
                    duration: BetterTGFFmpegPlaybackJobDuration(job),
                    isEnded: BetterTGFFmpegPlaybackJobIsEnded(job) != 0,
                    readCallCount: Int(BetterTGFFmpegPlaybackJobReadCallCount(job)),
                    seekCallCount: Int(BetterTGFFmpegPlaybackJobSeekCallCount(job)),
                    sizeCallCount: Int(BetterTGFFmpegPlaybackJobSizeCallCount(job)),
                    videoCodecID: BetterTGFFmpegPlaybackJobVideoCodecID(job),
                    videoDecodedTo: BetterTGFFmpegPlaybackJobVideoDecodedTo(job),
                    videoFrameCount: Int(BetterTGFFmpegPlaybackJobVideoFrameCount(job)),
                    videoIsVP9: BetterTGFFmpegPlaybackJobVideoIsVP9(job) != 0,
                ))
            } else if runResult == -1 || box.isCancelled {
                result = .failure(.cancelled)
            } else {
                result = .failure(.ffmpeg(BetterTGFFmpegPlaybackJobErrorCode(job)))
            }
            box.clear(job: job)
            BetterTGFFmpegPlaybackJobDestroy(job)
            Unmanaged<TDLibVODFFmpegDecodeBox>.fromOpaque(context).release()
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
        switch activeDecode.disposition {
        case .cancelled:
            activeDecode.continuation.resume(throwing: DecodeError.cancelled)
        case .superseded:
            activeDecode.continuation.resume(throwing: DecodeError.superseded)
        case .running:
            if activeDecode.box.isCancelled {
                activeDecode.continuation.resume(throwing: DecodeError.cancelled)
            } else {
                activeDecode.continuation.resume(with: result.mapError { $0 })
            }
        }
    }

    private func releaseLeaseIfNeeded() async {
        guard !leaseReleased else { return }
        leaseReleased = true
        await lease.invalidate()
    }
}

// MARK: - TDLibVODFFmpegDecodeBox

private final class TDLibVODFFmpegDecodeBox: @unchecked Sendable {
    init(
        source: TDLibVODRangeSource,
        onVideoFrame: @escaping @Sendable (TDLibVODFFmpegDecoder.VideoFrame) -> Bool,
        onAudioFrame: @escaping @Sendable (TDLibVODFFmpegDecoder.AudioFrame) -> Bool,
    ) {
        self.source = source
        self.onVideoFrame = onVideoFrame
        self.onAudioFrame = onAudioFrame
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
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
        guard !isCancelled,
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
        return onVideoFrame(frame) ? 1 : 0
    }

    func acceptAudio(
        samples: UnsafePointer<Float>,
        frameCount: Int,
        channelCount: Int,
        sampleRate: Int,
        presentationTime: TimeInterval,
    ) -> Int32 {
        guard !isCancelled,
              frameCount > 0,
              (1 ... 2).contains(channelCount),
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
        return onAudioFrame(frame) ? 1 : 0
    }

    private let source: TDLibVODRangeSource
    private let onVideoFrame: @Sendable (TDLibVODFFmpegDecoder.VideoFrame) -> Bool
    private let onAudioFrame: @Sendable (TDLibVODFFmpegDecoder.AudioFrame) -> Bool
    private let lock = NSLock()
    private var activeOperation: TDLibVODFFmpegDecodeReadOperation?
    private var cancelled = false
    private var job: OpaquePointer?
}

// MARK: - TDLibVODFFmpegDecodeReadOperation

private final class TDLibVODFFmpegDecodeReadOperation: @unchecked Sendable {
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

    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var cancelled = false
    private var result: Result<Data, Swift.Error>?
    private var task: Task<Void, Never>?
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
            func record(video frame: VideoFrame) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                videoFrameCount += 1
                videoTimes.append(frame.presentationTime)
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
                audioBytesAreValid = audioBytesAreValid
                    && frame.sampleRate == 48_000
                    && (1 ... 2).contains(frame.channelCount)
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
                bytesValid: Bool
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

            private let lock = NSLock()
            private var videoFrameCount = 0
            private var audioFrameCount = 0
            private var audioSampleCount = 0
            private var videoTimes = [TimeInterval]()
            private var audioTimes = [TimeInterval]()
            private var videoBytesAreValid = true
            private var audioBytesAreValid = true
        }

        static func runDebugProbe() async {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("bettertg-vod-ffmpeg-decode-probe.webm")
            try? FileManager.default.removeItem(at: url)
            defer { try? FileManager.default.removeItem(at: url) }
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
                    throw DecodeError.ffmpeg(-9_900)
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
                let decoder = TDLibVODFFmpegDecoder(
                    lease: await coordinator.acquire(file: backend.file(expectedSize: size * 2)),
                )
                stage = "initial VP9/Opus decode"
                let initialRecorder = ProbeRecorder()
                let initial = try await decoder.decode(
                    seekTime: 0,
                    duration: 3,
                    onVideoFrame: { initialRecorder.record(video: $0) },
                    onAudioFrame: { initialRecorder.record(audio: $0) },
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
                let seekRecorded = seekRecorder.snapshot()
                let downloads = await backend.downloadCalls
                guard initial.videoIsVP9,
                      initial.audioIsOpus,
                      initial.isEnded,
                      initial.videoFrameCount == 24,
                      initial.audioFrameCount > 0,
                      initial.videoDecodedTo >= 1.9,
                      initial.audioDecodedTo >= 1.9,
                      (90_000 ... 100_000).contains(initialRecorded.audioSamples),
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
                        "seek-recorded=\(seekRecorded)",
                        "downloads=\(downloads)",
                    ].joined(separator: "; "))
                }
                await decoder.close()

                stage = "overlapping supersession"
                let supersedeBackend = TDLibVODProbeBackend(fileURL: url, fileSize: size, network: network)
                await supersedeBackend.setAutoFulfill(true)
                await supersedeBackend.setDownloadDelay(.seconds(2))
                let supersedeCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-ffmpeg-decode-supersede",
                    client: supersedeBackend.client,
                    requestTimeout: .seconds(3),
                )
                let supersedeDecoder = TDLibVODFFmpegDecoder(
                    lease: await supersedeCoordinator.acquire(
                        file: supersedeBackend.file(expectedSize: size * 2),
                    ),
                )
                let staleTask = Task {
                    try await supersedeDecoder.decode(
                        seekTime: 0,
                        duration: 2,
                        onVideoFrame: { _ in true },
                        onAudioFrame: { _ in true },
                    )
                }
                try await waitUntil { await supersedeBackend.downloadCalls.count > 0 }
                let newestTask = Task {
                    try await supersedeDecoder.decode(
                        seekTime: 1,
                        duration: 0.8,
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
                let cancelDecoder = TDLibVODFFmpegDecoder(
                    lease: await cancelCoordinator.acquire(file: cancelBackend.file(expectedSize: size)),
                )
                let cancelTask = Task {
                    try await cancelDecoder.decode(
                        seekTime: 0,
                        duration: 2,
                        onVideoFrame: { _ in true },
                        onAudioFrame: { _ in true },
                    )
                }
                try await waitUntil { await cancelBackend.downloadCalls.count > 0 }
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

                result = "VOD FFmpeg decode probe: fixture-sha256=\(fixtureSHA256), "
                    + "video=vp9/96x54@12, audio=opus/48000x2, "
                    + "video-frames=\(initialRecorded.videoFrames), "
                    + "audio-frames=\(initialRecorded.audioFrames), "
                    + "audio-samples=\(initialRecorded.audioSamples), pts-monotonic=true, "
                    + "seek=true, supersede=true, swr-tail=true, bgra/float-valid=true, "
                    + "finite-downloads=true, full-downloads=0, cancel=true"
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
                if await condition() { return }
                try await Task<Never, Never>.sleep(for: .milliseconds(20))
            }
            throw DecodeError.ffmpeg(-9_902)
        }

        struct ProbeValidationError: Swift.Error, CustomStringConvertible {
            let details: String

            var description: String { details }
        }
    }
#endif

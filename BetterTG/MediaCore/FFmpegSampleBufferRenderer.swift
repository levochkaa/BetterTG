// FFmpegSampleBufferRenderer.swift

import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import UIKit

// MARK: - FFmpegSampleBufferSurfaceView

@MainActor final class FFmpegSampleBufferSurfaceView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        guard let layer = layer as? AVSampleBufferDisplayLayer else {
            preconditionFailure("FFmpeg sample-buffer surface has an unexpected layer type")
        }
        return layer
    }

    var videoGravity: AVLayerVideoGravity {
        get { displayLayer.videoGravity }
        set { displayLayer.videoGravity = newValue }
    }
}

// MARK: - FFmpegSampleBufferRenderer

final class FFmpegSampleBufferRenderer: @unchecked Sendable {
    // MARK: Internal

    enum RenderError: Swift.Error, Equatable {
        case audioBufferCreationFailed(OSStatus)
        case invalidAudioFrame
        case invalidTime
        case invalidVideoFrame
        case pixelBufferCreationFailed(CVReturn)
        case videoBufferCreationFailed(OSStatus)
    }

    struct Snapshot: Equatable {
        let audioAcceptedUntil: TimeInterval
        let audioEnqueuedCount: Int
        let audioEnqueuedUntil: TimeInterval
        let audioError: String?
        let audioFirstPresentationTime: TimeInterval?
        let audioInputIsFinished: Bool
        let audioRendererIsAttached: Bool
        let audioQueuedBytes: Int
        let audioQueuedCount: Int
        let currentTime: TimeInterval
        let generation: UInt64
        let hasAudioInput: Bool
        let hasVideoInput: Bool
        let isDisplayReady: Bool
        let isFeedingEnabled: Bool
        let isInvalidated: Bool
        let rate: Float
        let streamHasAudio: Bool
        let streamHasVideo: Bool
        let streamTopologyIsKnown: Bool
        let videoAcceptedUntil: TimeInterval
        let videoEnqueuedCount: Int
        let videoEnqueuedUntil: TimeInterval
        let videoError: String?
        let videoFirstPresentationTime: TimeInterval?
        let videoInputIsFinished: Bool
        let videoQueuedBytes: Int
        let videoQueuedCount: Int
    }

    // MARK: Private

    private enum EnqueueDisposition: Equatable {
        case current
        case discard
        case failed
    }

    private enum Stream {
        case audio
        case video
    }

    private static let mediaTimescale = CMTimeScale(60000)

    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private let videoRenderer: AVSampleBufferVideoRenderer
    private let audioRenderer: AVSampleBufferAudioRenderer
    private let synchronizer: AVSampleBufferRenderSynchronizer
    private let sampleFactory = FFmpegSampleBufferFactory()
    private let videoQueue = FFmpegBoundedSampleBufferQueue(
        maximumByteCount: 64 * 1024 * 1024,
        maximumItemCount: 90,
    )
    private let audioQueue = FFmpegBoundedSampleBufferQueue(
        maximumByteCount: 8 * 1024 * 1024,
        maximumItemCount: 256,
    )
    private let feedQueue = DispatchQueue(label: "BetterTG VOD Sample Buffer Feed", qos: .userInitiated)
    private let stateLock = NSLock()
    private let snapshotSubject = PassthroughSubject<Snapshot, Never>()
    private var currentGeneration = UInt64.zero
    private var failedGeneration: UInt64?
    private var monitoredGeneration: UInt64?
    private var isInvalidated = false
    private var audioError: Swift.Error?
    private var videoError: Swift.Error?
    private var hasAudioInput = false
    private var hasVideoInput = false
    private var streamHasAudio = false
    private var streamHasVideo = false
    private var streamTopologyIsKnown = false
    private var audioRendererIsAttached = false
    private var isFeedingEnabled = true
    private var videoRequestGeneration: UInt64?
    private var audioRequestGeneration: UInt64?
    private var videoEnqueuedCount = 0
    private var audioEnqueuedCount = 0
    private var videoFirstPresentationTime: TimeInterval?
    private var audioFirstPresentationTime: TimeInterval?
    private var videoEnqueuedUntil = TimeInterval.zero
    private var audioEnqueuedUntil = TimeInterval.zero
    private var failureMonitor: DispatchSourceTimer?

    var snapshotPublisher: AnyPublisher<Snapshot, Never> {
        // Playback gating may repeat pause while consuming a snapshot. Keep the
        // transport command authoritative without feeding identical state back forever.
        snapshotSubject.removeDuplicates().eraseToAnyPublisher()
    }

    @MainActor var currentTime: TimeInterval {
        Self.finiteNonnegative(synchronizer.currentTime().seconds)
    }

    @MainActor var rate: Float { synchronizer.rate }

    @MainActor var isReadyForDisplay: Bool { displayLayer?.isReadyForDisplay == true }

    @MainActor var pictureInPictureDisplayLayer: AVSampleBufferDisplayLayer? { displayLayer }

    @MainActor init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        self.videoRenderer = displayLayer.sampleBufferRenderer
        self.audioRenderer = AVSampleBufferAudioRenderer()
        self.synchronizer = AVSampleBufferRenderSynchronizer()
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = true
        synchronizer.setRate(0, time: .zero)
        synchronizer.addRenderer(videoRenderer)
        startFailureMonitor()
    }

    deinit {
        failureMonitor?.setEventHandler {}
        failureMonitor?.cancel()
        videoQueue.close()
        audioQueue.close()
        videoRenderer.stopRequestingMediaData()
        audioRenderer.stopRequestingMediaData()
        let teardownState = stateLock.withLock { (isInvalidated, audioRendererIsAttached) }
        let wasInvalidated = teardownState.0
        let audioRendererWasAttached = teardownState.1
        guard !wasInvalidated else { return }
        let videoRenderer = videoRenderer
        let audioRenderer = audioRenderer
        let synchronizer = synchronizer
        let teardown = {
            synchronizer.setRate(0, time: .invalid)
            videoRenderer.flush()
            audioRenderer.flush()
            synchronizer.removeRenderer(videoRenderer, at: .invalid)
            if audioRendererWasAttached {
                synchronizer.removeRenderer(audioRenderer, at: .invalid)
            }
            Self.retainRenderersDuringAsynchronousRemoval(
                videoRenderer: videoRenderer,
                audioRenderer: audioRenderer,
                synchronizer: synchronizer,
            )
        }
        if Thread.isMainThread {
            teardown()
        } else {
            DispatchQueue.main.async(execute: teardown)
        }
    }

    #if DEBUG
        @MainActor static func runDebugProbeIfRequested(in window: UIWindow) {
            guard ProcessInfo.processInfo.arguments.contains("-media-probe-vod-sample-buffer") else { return }
            Task { @MainActor in await runDebugProbe(in: window) }
        }
    #endif

    private static func mediaTime(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: finiteNonnegative(seconds), preferredTimescale: mediaTimescale)
    }

    private static func finiteNonnegative(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? max(0, value) : 0
    }

    private static func retainRenderersDuringAsynchronousRemoval(
        videoRenderer: AVSampleBufferVideoRenderer,
        audioRenderer: AVSampleBufferAudioRenderer,
        synchronizer: AVSampleBufferRenderSynchronizer,
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withExtendedLifetime((videoRenderer, audioRenderer, synchronizer)) {}
        }
    }

    private static func errorDescription(_ error: Swift.Error?) -> String? {
        error.map(String.init(describing:))
    }

    @discardableResult @MainActor func reset(at time: TimeInterval) -> UInt64 {
        let target = Self.finiteNonnegative(time)
        let resetState = stateLock.withLock { () -> (generation: UInt64, shouldReset: Bool) in
            guard !isInvalidated else { return (currentGeneration, false) }
            currentGeneration &+= 1
            failedGeneration = nil
            monitoredGeneration = nil
            audioError = nil
            videoError = nil
            hasAudioInput = false
            hasVideoInput = false
            streamHasAudio = false
            streamHasVideo = false
            streamTopologyIsKnown = false
            return (currentGeneration, true)
        }
        guard resetState.shouldReset else { return resetState.generation }
        let generation = resetState.generation
        videoQueue.reset(generation: generation, initialTime: target)
        audioQueue.reset(generation: generation, initialTime: target)
        feedQueue.sync {
            stopFeedRequests()
            videoEnqueuedCount = 0
            audioEnqueuedCount = 0
            videoFirstPresentationTime = nil
            audioFirstPresentationTime = nil
            videoEnqueuedUntil = target
            audioEnqueuedUntil = target
        }
        synchronizer.setRate(0, time: Self.mediaTime(target))
        videoRenderer.flush()
        audioRenderer.flush()
        stateLock.withLock {
            if !isInvalidated, failedGeneration == nil, currentGeneration == generation {
                monitoredGeneration = generation
            }
        }
        publishSnapshot()
        return generation
    }

    func enqueue(
        video frame: TDLibVODFFmpegDecoder.VideoFrame,
        generation: UInt64,
    ) -> Bool {
        switch enqueueDisposition(generation: generation) {
        case .discard:
            return true
        case .failed:
            return false
        case .current:
            break
        }
        switch markInput(stream: .video, generation: generation) {
        case .current:
            break
        case .discard:
            return true
        case .failed:
            return false
        }
        let sampleBuffer: CMSampleBuffer
        do {
            sampleBuffer = try sampleFactory.makeVideoSampleBuffer(frame)
        } catch {
            fail(generation: generation, stream: .video, error: error)
            return false
        }
        let appendResult = videoQueue.append(
            .init(
                byteCount: frame.bytes.count,
                endTime: frame.presentationTime + frame.duration,
                presentationTime: frame.presentationTime,
                sampleBuffer: sampleBuffer,
            ),
            generation: generation,
        )
        switch appendResult {
        case .accepted:
            break
        case .discarded:
            return true
        case .failed:
            return false
        }
        scheduleVideoFeed(generation: generation)
        return true
    }

    func enqueue(
        audio frame: TDLibVODFFmpegDecoder.AudioFrame,
        generation: UInt64,
    ) -> Bool {
        switch enqueueDisposition(generation: generation) {
        case .discard:
            return true
        case .failed:
            return false
        case .current:
            break
        }
        switch markInput(stream: .audio, generation: generation) {
        case .current:
            break
        case .discard:
            return true
        case .failed:
            return false
        }
        switch attachAudioRendererIfNeeded(generation: generation) {
        case .current:
            break
        case .discard:
            return true
        case .failed:
            return false
        }
        let sampleBuffer: CMSampleBuffer
        do {
            sampleBuffer = try sampleFactory.makeAudioSampleBuffer(frame)
        } catch {
            fail(generation: generation, stream: .audio, error: error)
            return false
        }
        let appendResult = audioQueue.append(
            .init(
                byteCount: frame.samples.count,
                endTime: frame.presentationTime + Double(frame.frameCount) / Double(frame.sampleRate),
                presentationTime: frame.presentationTime,
                sampleBuffer: sampleBuffer,
            ),
            generation: generation,
        )
        switch appendResult {
        case .accepted:
            break
        case .discarded:
            return true
        case .failed:
            return false
        }
        scheduleAudioFeed(generation: generation)
        return true
    }

    func finish(generation: UInt64) {
        guard accepts(generation: generation) else { return }
        videoQueue.finish(generation: generation)
        audioQueue.finish(generation: generation)
        scheduleVideoFeed(generation: generation)
        scheduleAudioFeed(generation: generation)
        publishSnapshotFromBackground()
    }

    func setStreamTopology(
        hasAudio: Bool,
        hasVideo: Bool,
        attachAudioRenderer: Bool,
        generation: UInt64,
    ) -> Bool {
        let result = stateLock.withLock { () -> EnqueueDisposition in
            if isInvalidated || generation != currentGeneration {
                return .discard
            }
            guard failedGeneration != generation else { return .failed }
            streamHasAudio = hasAudio
            streamHasVideo = hasVideo
            streamTopologyIsKnown = true
            return .current
        }
        switch result {
        case .current:
            if hasAudio, attachAudioRenderer,
               attachAudioRendererIfNeeded(generation: generation) != .current
            {
                return false
            }
            publishSnapshotFromBackground()
            return true
        case .discard:
            return true
        case .failed:
            return false
        }
    }

    @MainActor func play(
        rate: Float = 1,
        waitForSufficientMediaData: Bool = true,
    ) {
        let canPlay = stateLock.withLock {
            !isInvalidated && failedGeneration != currentGeneration
        }
        guard canPlay else { return }
        let boundedRate = min(2, max(0.5, rate))
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = waitForSufficientMediaData
        synchronizer.setRate(boundedRate, time: .invalid)
        publishSnapshot()
    }

    @MainActor func pause() {
        guard !stateLock.withLock({ isInvalidated }) else { return }
        synchronizer.setRate(0, time: .invalid)
        publishSnapshot()
    }

    @MainActor func setMuted(_ isMuted: Bool) {
        audioRenderer.isMuted = isMuted
    }

    @MainActor func setFeedingEnabled(_ isEnabled: Bool) {
        let generation = stateLock.withLock { () -> UInt64? in
            guard !isInvalidated else { return nil }
            isFeedingEnabled = isEnabled
            return currentGeneration
        }
        guard let generation else { return }
        if isEnabled {
            scheduleVideoFeed(generation: generation)
            scheduleAudioFeed(generation: generation)
        } else {
            feedQueue.sync { stopFeedRequests() }
        }
        publishSnapshot()
    }

    @MainActor func snapshot() -> Snapshot {
        makeSnapshot()
    }

    @MainActor func invalidate() {
        let shouldInvalidate = stateLock.withLock { () -> Bool in
            guard !isInvalidated else { return false }
            isInvalidated = true
            currentGeneration &+= 1
            monitoredGeneration = nil
            return true
        }
        guard shouldInvalidate else { return }
        videoQueue.close()
        audioQueue.close()
        feedQueue.sync {
            failureMonitor?.setEventHandler {}
            failureMonitor?.cancel()
            failureMonitor = nil
            stopFeedRequests()
        }
        synchronizer.setRate(0, time: .invalid)
        videoRenderer.flush()
        audioRenderer.flush()
        synchronizer.removeRenderer(videoRenderer, at: .invalid)
        if stateLock.withLock({ audioRendererIsAttached }) {
            synchronizer.removeRenderer(audioRenderer, at: .invalid)
        }
        Self.retainRenderersDuringAsynchronousRemoval(
            videoRenderer: videoRenderer,
            audioRenderer: audioRenderer,
            synchronizer: synchronizer,
        )
        publishSnapshot()
    }

    private func enqueueDisposition(generation: UInt64) -> EnqueueDisposition {
        stateLock.withLock {
            if isInvalidated || generation != currentGeneration {
                return .discard
            }
            return failedGeneration == generation ? .failed : .current
        }
    }

    private func accepts(generation: UInt64) -> Bool {
        enqueueDisposition(generation: generation) == .current
    }

    private func fail(generation: UInt64, stream: Stream, error: Swift.Error) {
        let shouldFail = stateLock.withLock { () -> Bool in
            guard !isInvalidated,
                  generation == currentGeneration,
                  failedGeneration != generation
            else { return false }
            failedGeneration = generation
            monitoredGeneration = nil
            switch stream {
            case .audio:
                audioError = error
            case .video:
                videoError = error
            }
            return true
        }
        guard shouldFail else { return }
        videoQueue.fail(generation: generation)
        audioQueue.fail(generation: generation)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  stateLock.withLock({ self.failedGeneration == generation })
            else { return }
            synchronizer.setRate(0, time: .invalid)
            publishSnapshot()
        }
    }

    private func markInput(stream: Stream, generation: UInt64) -> EnqueueDisposition {
        stateLock.withLock {
            if isInvalidated || generation != currentGeneration {
                return .discard
            }
            guard failedGeneration != generation else { return .failed }
            switch stream {
            case .audio:
                hasAudioInput = true
            case .video:
                hasVideoInput = true
            }
            return .current
        }
    }

    private func attachAudioRendererIfNeeded(generation: UInt64) -> EnqueueDisposition {
        let disposition = enqueueDisposition(generation: generation)
        guard disposition == .current else { return disposition }
        if stateLock.withLock({ audioRendererIsAttached }) {
            return .current
        }

        let attach = { [weak self] in
            guard let self, accepts(generation: generation) else { return }
            let shouldAttach = stateLock.withLock { () -> Bool in
                guard !self.audioRendererIsAttached else { return false }
                self.audioRendererIsAttached = true
                return true
            }
            if shouldAttach {
                synchronizer.addRenderer(audioRenderer)
            }
        }
        if Thread.isMainThread {
            attach()
        } else {
            DispatchQueue.main.sync(execute: attach)
        }
        return enqueueDisposition(generation: generation)
    }

    private func scheduleVideoFeed(generation: UInt64) {
        feedQueue.async { [weak self] in self?.startVideoFeedIfNeeded(generation: generation) }
    }

    private func scheduleAudioFeed(generation: UInt64) {
        feedQueue.async { [weak self] in self?.startAudioFeedIfNeeded(generation: generation) }
    }

    private func startFailureMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: feedQueue)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.checkRendererFailures() }
        failureMonitor = timer
        timer.resume()
    }

    private func checkRendererFailures() {
        let generation = stateLock.withLock { () -> UInt64? in
            guard !isInvalidated,
                  failedGeneration != currentGeneration,
                  monitoredGeneration == currentGeneration
            else { return nil }
            return monitoredGeneration
        }
        guard let generation else { return }
        if videoRenderer.status == .failed {
            fail(
                generation: generation,
                stream: .video,
                error: videoRenderer.error ?? RenderError.videoBufferCreationFailed(-1),
            )
        } else if audioRenderer.status == .failed {
            fail(
                generation: generation,
                stream: .audio,
                error: audioRenderer.error ?? RenderError.audioBufferCreationFailed(-1),
            )
        }
    }

    private func startVideoFeedIfNeeded(generation: UInt64) {
        guard accepts(generation: generation), feedingIsEnabled(), videoRequestGeneration == nil else { return }
        videoRequestGeneration = generation
        videoRenderer.requestMediaDataWhenReady(on: feedQueue) { [weak self] in
            self?.drainVideo(generation: generation)
        }
    }

    private func startAudioFeedIfNeeded(generation: UInt64) {
        guard accepts(generation: generation),
              feedingIsEnabled(),
              stateLock.withLock({ audioRendererIsAttached }),
              audioRequestGeneration == nil
        else { return }
        audioRequestGeneration = generation
        audioRenderer.requestMediaDataWhenReady(on: feedQueue) { [weak self] in
            self?.drainAudio(generation: generation)
        }
    }

    private func drainVideo(generation: UInt64) {
        guard accepts(generation: generation), feedingIsEnabled(), videoRequestGeneration == generation else {
            videoRenderer.stopRequestingMediaData()
            videoRequestGeneration = nil
            return
        }
        while videoRenderer.isReadyForMoreMediaData {
            guard videoRenderer.status != .failed else {
                fail(
                    generation: generation,
                    stream: .video,
                    error: videoRenderer.error ?? RenderError.videoBufferCreationFailed(-1),
                )
                videoRenderer.stopRequestingMediaData()
                videoRequestGeneration = nil
                return
            }
            guard let item = videoQueue.pop(generation: generation) else {
                videoRenderer.stopRequestingMediaData()
                videoRequestGeneration = nil
                if videoQueue.hasItems(generation: generation) {
                    startVideoFeedIfNeeded(generation: generation)
                }
                publishSnapshotFromBackground()
                return
            }
            videoRenderer.enqueue(item.sampleBuffer)
            if videoRenderer.status == .failed {
                fail(
                    generation: generation,
                    stream: .video,
                    error: videoRenderer.error ?? RenderError.videoBufferCreationFailed(-1),
                )
                videoRenderer.stopRequestingMediaData()
                videoRequestGeneration = nil
                return
            }
            if videoFirstPresentationTime == nil {
                videoFirstPresentationTime = item.presentationTime
            }
            videoEnqueuedUntil = max(videoEnqueuedUntil, item.endTime)
            videoEnqueuedCount += 1
        }
        DispatchQueue.main.async { [weak self] in self?.publishSnapshot() }
    }

    private func drainAudio(generation: UInt64) {
        guard accepts(generation: generation), feedingIsEnabled(), audioRequestGeneration == generation else {
            audioRenderer.stopRequestingMediaData()
            audioRequestGeneration = nil
            return
        }
        while audioRenderer.isReadyForMoreMediaData {
            guard audioRenderer.status != .failed else {
                fail(
                    generation: generation,
                    stream: .audio,
                    error: audioRenderer.error ?? RenderError.audioBufferCreationFailed(-1),
                )
                audioRenderer.stopRequestingMediaData()
                audioRequestGeneration = nil
                return
            }
            guard let item = audioQueue.pop(generation: generation) else {
                audioRenderer.stopRequestingMediaData()
                audioRequestGeneration = nil
                if audioQueue.hasItems(generation: generation) {
                    startAudioFeedIfNeeded(generation: generation)
                }
                publishSnapshotFromBackground()
                return
            }
            audioRenderer.enqueue(item.sampleBuffer)
            if audioRenderer.status == .failed {
                fail(
                    generation: generation,
                    stream: .audio,
                    error: audioRenderer.error ?? RenderError.audioBufferCreationFailed(-1),
                )
                audioRenderer.stopRequestingMediaData()
                audioRequestGeneration = nil
                return
            }
            if audioFirstPresentationTime == nil {
                audioFirstPresentationTime = item.presentationTime
            }
            audioEnqueuedUntil = max(audioEnqueuedUntil, item.endTime)
            audioEnqueuedCount += 1
        }
        publishSnapshotFromBackground()
    }

    private func stopFeedRequests() {
        videoRenderer.stopRequestingMediaData()
        audioRenderer.stopRequestingMediaData()
        videoRequestGeneration = nil
        audioRequestGeneration = nil
    }

    private func publishSnapshotFromBackground() {
        DispatchQueue.main.async { [weak self] in self?.publishSnapshot() }
    }

    private func feedingIsEnabled() -> Bool {
        stateLock.withLock { isFeedingEnabled }
    }

    @MainActor private func makeSnapshot() -> Snapshot {
        let state = stateLock.withLock {
            (
                currentGeneration,
                isInvalidated,
                audioError,
                videoError,
                hasAudioInput,
                hasVideoInput,
                isFeedingEnabled,
                streamHasAudio,
                streamHasVideo,
                streamTopologyIsKnown,
                audioRendererIsAttached,
            )
        }
        let feed = feedQueue.sync {
            (
                videoEnqueuedCount,
                audioEnqueuedCount,
                videoFirstPresentationTime,
                audioFirstPresentationTime,
                videoEnqueuedUntil,
                audioEnqueuedUntil,
            )
        }
        let video = videoQueue.snapshot()
        let audio = audioQueue.snapshot()
        return Snapshot(
            audioAcceptedUntil: audio.acceptedUntil,
            audioEnqueuedCount: feed.1,
            audioEnqueuedUntil: feed.5,
            audioError: audioRenderer.error?.localizedDescription ?? Self.errorDescription(state.2),
            audioFirstPresentationTime: feed.3,
            audioInputIsFinished: audio.isFinished,
            audioRendererIsAttached: state.10,
            audioQueuedBytes: audio.byteCount,
            audioQueuedCount: audio.itemCount,
            currentTime: Self.finiteNonnegative(synchronizer.currentTime().seconds),
            generation: state.0,
            hasAudioInput: state.4,
            hasVideoInput: state.5,
            isDisplayReady: displayLayer?.isReadyForDisplay == true,
            isFeedingEnabled: state.6,
            isInvalidated: state.1,
            rate: synchronizer.rate,
            streamHasAudio: state.7,
            streamHasVideo: state.8,
            streamTopologyIsKnown: state.9,
            videoAcceptedUntil: video.acceptedUntil,
            videoEnqueuedCount: feed.0,
            videoEnqueuedUntil: feed.4,
            videoError: videoRenderer.error?.localizedDescription ?? Self.errorDescription(state.3),
            videoFirstPresentationTime: feed.2,
            videoInputIsFinished: video.isFinished,
            videoQueuedBytes: video.byteCount,
            videoQueuedCount: video.itemCount,
        )
    }

    @MainActor private func publishSnapshot() {
        snapshotSubject.send(makeSnapshot())
    }
}

// MARK: - FFmpegSampleBufferFactory

private final class FFmpegSampleBufferFactory: @unchecked Sendable {
    // MARK: Private

    private struct VideoKey: Hashable {
        let height: Int
        let width: Int
    }

    private struct AudioKey: Hashable {
        let channelCount: Int
        let sampleRate: Int
    }

    private let lock = NSLock()
    private var pixelBufferPools = [VideoKey: CVPixelBufferPool]()
    private var audioFormatDescriptions = [AudioKey: CMAudioFormatDescription]()

    // MARK: Internal

    func makeVideoSampleBuffer(
        _ frame: TDLibVODFFmpegDecoder.VideoFrame,
    ) throws -> CMSampleBuffer {
        guard frame.width > 0,
              frame.height > 0,
              frame.width <= 4096,
              frame.height <= 4096,
              frame.width <= Int.max / 4,
              frame.bytesPerRow >= frame.width * 4,
              frame.height <= Int.max / frame.bytesPerRow,
              frame.bytes.count == frame.bytesPerRow * frame.height,
              frame.presentationTime.isFinite,
              frame.presentationTime >= 0,
              frame.duration.isFinite,
              frame.duration > 0
        else { throw FFmpegSampleBufferRenderer.RenderError.invalidVideoFrame }

        let pool = try pixelBufferPool(width: frame.width, height: frame.height)
        var output: CVPixelBuffer?
        let createStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output)
        guard createStatus == kCVReturnSuccess, let pixelBuffer = output else {
            throw FFmpegSampleBufferRenderer.RenderError.pixelBufferCreationFailed(createStatus)
        }

        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard lockStatus == kCVReturnSuccess else {
            throw FFmpegSampleBufferRenderer.RenderError.pixelBufferCreationFailed(lockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let destination = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw FFmpegSampleBufferRenderer.RenderError.invalidVideoFrame
        }
        let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let copiedBytesPerRow = frame.width * 4
        guard destinationBytesPerRow >= copiedBytesPerRow else {
            throw FFmpegSampleBufferRenderer.RenderError.invalidVideoFrame
        }
        let copied = frame.bytes.withUnsafeBytes { rawBuffer -> Bool in
            guard let source = rawBuffer.baseAddress else { return false }
            for row in 0..<frame.height {
                memcpy(
                    destination.advanced(by: row * destinationBytesPerRow),
                    source.advanced(by: row * frame.bytesPerRow),
                    copiedBytesPerRow,
                )
            }
            return true
        }
        guard copied else { throw FFmpegSampleBufferRenderer.RenderError.invalidVideoFrame }

        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription,
        )
        guard formatStatus == noErr, let formatDescription else {
            throw FFmpegSampleBufferRenderer.RenderError.videoBufferCreationFailed(formatStatus)
        }
        var timing = try CMSampleTimingInfo(
            duration: mediaTime(frame.duration),
            presentationTimeStamp: mediaTime(frame.presentationTime),
            decodeTimeStamp: .invalid,
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer,
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw FFmpegSampleBufferRenderer.RenderError.videoBufferCreationFailed(sampleStatus)
        }
        return sampleBuffer
    }

    func makeAudioSampleBuffer(
        _ frame: TDLibVODFFmpegDecoder.AudioFrame,
    ) throws -> CMSampleBuffer {
        guard frame.frameCount > 0,
              (1...2).contains(frame.channelCount),
              frame.sampleRate == 48000,
              frame.presentationTime.isFinite,
              frame.presentationTime >= 0,
              frame.frameCount <= 1_000_000,
              frame.frameCount <= Int.max / frame.channelCount / MemoryLayout<Float>.size
        else { throw FFmpegSampleBufferRenderer.RenderError.invalidAudioFrame }
        let bytesPerFrame = frame.channelCount * MemoryLayout<Float>.size
        let byteCount = frame.frameCount * bytesPerFrame
        guard byteCount <= 8 * 1024 * 1024,
              frame.samples.count == byteCount
        else {
            throw FFmpegSampleBufferRenderer.RenderError.invalidAudioFrame
        }

        let formatDescription = try audioFormatDescription(
            channelCount: frame.channelCount,
            sampleRate: frame.sampleRate,
        )
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer,
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
            throw FFmpegSampleBufferRenderer.RenderError.audioBufferCreationFailed(blockStatus)
        }
        let copyStatus = frame.samples.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let source = rawBuffer.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferReplaceDataBytes(
                with: source,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: byteCount,
            )
        }
        guard copyStatus == kCMBlockBufferNoErr else {
            throw FFmpegSampleBufferRenderer.RenderError.audioBufferCreationFailed(copyStatus)
        }
        var timing = try CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(frame.sampleRate)),
            presentationTimeStamp: mediaTime(
                frame.presentationTime,
                preferredTimescale: CMTimeScale(frame.sampleRate),
            ),
            decodeTimeStamp: .invalid,
        )
        var sampleSize = bytesPerFrame
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: frame.frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer,
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw FFmpegSampleBufferRenderer.RenderError.audioBufferCreationFailed(sampleStatus)
        }
        return sampleBuffer
    }

    private func pixelBufferPool(width: Int, height: Int) throws -> CVPixelBufferPool {
        let key = VideoKey(height: height, width: width)
        return try lock.withLock {
            if let existing = pixelBufferPools[key] {
                return existing
            }
            if pixelBufferPools.count >= 4 {
                pixelBufferPools.removeAll(keepingCapacity: true)
            }
            let attributes: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
            ]
            var pool: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                nil,
                attributes as CFDictionary,
                &pool,
            )
            guard status == kCVReturnSuccess, let pool else {
                throw FFmpegSampleBufferRenderer.RenderError.pixelBufferCreationFailed(status)
            }
            pixelBufferPools[key] = pool
            return pool
        }
    }

    private func audioFormatDescription(
        channelCount: Int,
        sampleRate: Int,
    ) throws -> CMAudioFormatDescription {
        let key = AudioKey(channelCount: channelCount, sampleRate: sampleRate)
        return try lock.withLock {
            if let existing = audioFormatDescriptions[key] {
                return existing
            }
            let bytesPerFrame = UInt32(channelCount * MemoryLayout<Float>.size)
            var description = AudioStreamBasicDescription(
                mSampleRate: Float64(sampleRate),
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked,
                mBytesPerPacket: bytesPerFrame,
                mFramesPerPacket: 1,
                mBytesPerFrame: bytesPerFrame,
                mChannelsPerFrame: UInt32(channelCount),
                mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
                mReserved: 0,
            )
            var formatDescription: CMAudioFormatDescription?
            let status = CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &description,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &formatDescription,
            )
            guard status == noErr, let formatDescription else {
                throw FFmpegSampleBufferRenderer.RenderError.audioBufferCreationFailed(status)
            }
            audioFormatDescriptions[key] = formatDescription
            return formatDescription
        }
    }

    private func mediaTime(
        _ seconds: TimeInterval,
        preferredTimescale: CMTimeScale = 60000,
    ) throws -> CMTime {
        guard seconds.isFinite, seconds >= 0 else {
            throw FFmpegSampleBufferRenderer.RenderError.invalidTime
        }
        let value = CMTime(seconds: seconds, preferredTimescale: preferredTimescale)
        guard value.isValid, !value.isIndefinite else {
            throw FFmpegSampleBufferRenderer.RenderError.invalidTime
        }
        return value
    }
}

// MARK: - FFmpegBoundedSampleBufferQueue

private final class FFmpegBoundedSampleBufferQueue: @unchecked Sendable {
    // MARK: Internal

    enum AppendResult {
        case accepted
        case discarded
        case failed
    }

    struct Item {
        let byteCount: Int
        let endTime: TimeInterval
        let presentationTime: TimeInterval
        let sampleBuffer: CMSampleBuffer
    }

    // MARK: Private

    private let condition = NSCondition()
    private let maximumByteCount: Int
    private let maximumItemCount: Int
    private var currentGeneration = UInt64.zero
    private var failedGeneration: UInt64?
    private var finishedGeneration: UInt64?
    private var items = [Item]()
    private var byteCount = 0
    private var acceptedUntil = TimeInterval.zero
    private var isClosed = false

    init(maximumByteCount: Int, maximumItemCount: Int) {
        self.maximumByteCount = maximumByteCount
        self.maximumItemCount = maximumItemCount
    }

    func append(_ item: Item, generation: UInt64) -> AppendResult {
        condition.lock()
        defer { condition.unlock() }
        while !isClosed,
              generation == currentGeneration,
              generation != failedGeneration,
              !items.isEmpty,
              items.count >= maximumItemCount || byteCount > maximumByteCount - min(item.byteCount, maximumByteCount)
        {
            condition.wait()
        }
        guard !isClosed, generation == currentGeneration else { return .discarded }
        guard failedGeneration != generation else { return .failed }
        items.append(item)
        byteCount += item.byteCount
        acceptedUntil = max(acceptedUntil, item.endTime)
        condition.broadcast()
        return .accepted
    }

    func pop(generation: UInt64) -> Item? {
        condition.lock()
        defer { condition.unlock() }
        guard !isClosed, generation == currentGeneration, !items.isEmpty else { return nil }
        let item = items.removeFirst()
        byteCount -= item.byteCount
        condition.broadcast()
        return item
    }

    func hasItems(generation: UInt64) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return !isClosed && generation == currentGeneration && !items.isEmpty
    }

    func finish(generation: UInt64) {
        condition.lock()
        if !isClosed, generation == currentGeneration {
            finishedGeneration = generation
        }
        condition.broadcast()
        condition.unlock()
    }

    func fail(generation: UInt64) {
        condition.lock()
        if !isClosed, generation == currentGeneration {
            failedGeneration = generation
            finishedGeneration = nil
            items.removeAll(keepingCapacity: true)
            byteCount = 0
        }
        condition.broadcast()
        condition.unlock()
    }

    func reset(generation: UInt64, initialTime: TimeInterval) {
        condition.lock()
        currentGeneration = generation
        failedGeneration = nil
        finishedGeneration = nil
        items.removeAll(keepingCapacity: true)
        byteCount = 0
        acceptedUntil = initialTime
        condition.broadcast()
        condition.unlock()
    }

    func close() {
        condition.lock()
        isClosed = true
        items.removeAll(keepingCapacity: false)
        byteCount = 0
        condition.broadcast()
        condition.unlock()
    }

    func snapshot() -> (acceptedUntil: TimeInterval, byteCount: Int, isFinished: Bool, itemCount: Int) {
        condition.lock()
        defer { condition.unlock() }
        return (acceptedUntil, byteCount, finishedGeneration == currentGeneration, items.count)
    }
}

#if DEBUG

    // MARK: - Runtime probe

    private extension FFmpegSampleBufferRenderer {
        @MainActor static func runDebugProbe(in window: UIWindow) async {
            let resultURL = FileManager.default
.urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("vod-sample-buffer-probe.txt")
            let fixtureURL = FileManager.default
.temporaryDirectory
                .appendingPathComponent("bettertg-vod-sample-buffer-probe.webm")
            try? FileManager.default.removeItem(at: fixtureURL)
            defer { try? FileManager.default.removeItem(at: fixtureURL) }

            let result: String
            var failure: Swift.Error?
            var renderer: FFmpegSampleBufferRenderer?
            var surface: FFmpegSampleBufferSurfaceView?
            var decoder: TDLibVODFFmpegDecoder?
            do {
                let probeSurface = FFmpegSampleBufferSurfaceView(
                    frame: CGRect(x: 8, y: max(8, window.safeAreaInsets.top + 8), width: 192, height: 108),
                )
                probeSurface.backgroundColor = .black
                probeSurface.isUserInteractionEnabled = false
                probeSurface.videoGravity = .resizeAspect
                window.addSubview(probeSurface)
                surface = probeSurface

                let probeRenderer = FFmpegSampleBufferRenderer(displayLayer: probeSurface.displayLayer)
                probeRenderer.setMuted(true)
                renderer = probeRenderer
                let snapshotRecorder = ProbeSnapshotRecorder(publisher: probeRenderer.snapshotPublisher)

                try FFmpegVODProbeFixture.write(to: fixtureURL)
                let attributes = try FileManager.default.attributesOfItem(atPath: fixtureURL.path)
                guard let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0 else {
                    throw RenderError.invalidVideoFrame
                }
                let network = TDLibVODProbeNetwork(available: true)
                let backend = TDLibVODProbeBackend(fileURL: fixtureURL, fileSize: size, network: network)
                await backend.setAutoFulfill(true)
                let coordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-vod-sample-buffer",
                    client: backend.client,
                    requestTimeout: .seconds(2),
                )
                let probeDecoder = await TDLibVODFFmpegDecoder(
                    lease: coordinator.acquire(file: backend.file(expectedSize: size * 2)),
                )
                decoder = probeDecoder

                let initialGeneration = probeRenderer.reset(at: 0)
                probeRenderer.play()
                let initial = try await probeDecoder.decode(
                    seekTime: 0,
                    duration: 3,
                    onVideoFrame: { probeRenderer.enqueue(video: $0, generation: initialGeneration) },
                    onAudioFrame: { probeRenderer.enqueue(audio: $0, generation: initialGeneration) },
                )
                probeRenderer.finish(generation: initialGeneration)
                try await waitUntil {
                    let snapshot = probeRenderer.snapshot()
                    return snapshot.isDisplayReady
                        && snapshot.currentTime >= 0.25
                        && snapshot.videoEnqueuedCount == initial.videoFrameCount
                        && snapshot.audioEnqueuedCount == initial.audioFrameCount
                        && snapshotRecorder.sawFinished(generation: initialGeneration)
                }
                probeRenderer.pause()
                let pausedTime = probeRenderer.currentTime
                try await Task<Never, Never>.sleep(for: .milliseconds(200))
                let pauseStable = abs(probeRenderer.currentTime - pausedTime) < 0.05

                var pauseFeedbackCount = 0
                let pauseFeedback = probeRenderer.snapshotPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak probeRenderer] _ in
                        pauseFeedbackCount += 1
                        // Model the production player's paused gate, but bound a
                        // regression so the probe can report it instead of spinning.
                        guard pauseFeedbackCount <= 32 else { return }
                        probeRenderer?.pause()
                    }
                probeRenderer.pause()
                try await Task<Never, Never>.sleep(for: .milliseconds(200))
                pauseFeedback.cancel()
                guard pauseFeedbackCount == 1 else {
                    throw ProbeError.pausedSnapshotFeedback(pauseFeedbackCount)
                }

                let seekGeneration = probeRenderer.reset(at: 1)
                let staleVideoWasDropped = probeRenderer.enqueue(
                    video: TDLibVODFFmpegDecoder.VideoFrame(
                        bytes: Data([0, 0, 0, 255]),
                        bytesPerRow: 4,
                        duration: 1.0 / 30.0,
                        height: 1,
                        isKeyFrame: true,
                        presentationTime: 0,
                        width: 1,
                    ),
                    generation: initialGeneration,
                )
                let staleAudioWasDropped = probeRenderer.enqueue(
                    audio: TDLibVODFFmpegDecoder.AudioFrame(
                        channelCount: 1,
                        frameCount: 1,
                        presentationTime: 0,
                        sampleRate: 48000,
                        samples: Data(count: MemoryLayout<Float>.size),
                    ),
                    generation: initialGeneration,
                )
                probeRenderer.play(rate: 1.5)
                let seek = try await probeDecoder.decode(
                    seekTime: 1,
                    duration: 0.8,
                    onVideoFrame: { probeRenderer.enqueue(video: $0, generation: seekGeneration) },
                    onAudioFrame: { probeRenderer.enqueue(audio: $0, generation: seekGeneration) },
                )
                probeRenderer.finish(generation: seekGeneration)
                try await waitUntil {
                    let snapshot = probeRenderer.snapshot()
                    return snapshot.currentTime >= 1.2
                        && snapshot.videoEnqueuedCount == seek.videoFrameCount
                        && snapshot.audioEnqueuedCount == seek.audioFrameCount
                        && snapshotRecorder.sawFinished(generation: seekGeneration)
                }
                probeRenderer.pause()
                let finalSnapshot = probeRenderer.snapshot()
                let downloads = await backend.downloadCalls
                guard pauseStable,
                      staleVideoWasDropped,
                      staleAudioWasDropped,
                      initial.videoIsVP9,
                      initial.audioIsOpus,
                      initial.isEnded,
                      finalSnapshot.generation == seekGeneration,
                      finalSnapshot.videoError == nil,
                      finalSnapshot.audioError == nil,
                      finalSnapshot.isDisplayReady,
                      finalSnapshot.videoInputIsFinished,
                      finalSnapshot.audioInputIsFinished,
                      finalSnapshot.videoFirstPresentationTime.map({ $0 >= 1 }) == true,
                      finalSnapshot.audioFirstPresentationTime.map({ $0 >= 1 }) == true,
                      finalSnapshot.currentTime >= 1.2,
                      downloads.allSatisfy({ !$0.isFullDownload })
                else { throw RenderError.invalidTime }

                result = "VOD sample-buffer probe: surface-ready=true, video=\(initial.videoFrameCount), "
                    + "audio=\(initial.audioFrameCount), pause-stable=true, seek-generation=true, "
                    + "pause-feedback-events=\(pauseFeedbackCount), "
                    + "stale-drop=true, seek-first-pts>=1=true, input-finished=true, combine-finish=true, "
                    + "rate=1.5, current=\(finalSnapshot.currentTime), bgra-pool=true, float-pcm=true, "
                    + "renderer-errors=0, finite-downloads=true, full-downloads=0"
            } catch {
                failure = error
                result = "VOD sample-buffer probe failed: \(error)"
            }

            if let decoder {
                await decoder.close()
            }
            renderer?.invalidate()
            surface?.removeFromSuperview()
            if let resultURL {
                try? Data(result.utf8).write(to: resultURL, options: .atomic)
            }
            log(result)
            if failure != nil {
                assertionFailure(result)
            }
        }

        @MainActor static func waitUntil(
            timeout: Duration = .seconds(8),
            condition: () -> Bool,
        ) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)
            while clock.now < deadline {
                if condition() {
                    return
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(20))
            }
            throw RenderError.invalidTime
        }

        enum ProbeError: Swift.Error {
            case pausedSnapshotFeedback(Int)
        }

        final class ProbeSnapshotRecorder {
            // MARK: Private

            private var cancellable: AnyCancellable?
            private var snapshots = [Snapshot]()

            init(publisher: AnyPublisher<Snapshot, Never>) {
                self.cancellable = publisher.sink { [weak self] snapshot in
                    self?.snapshots.append(snapshot)
                }
            }

            // MARK: Internal

            func sawFinished(generation: UInt64) -> Bool {
                snapshots.contains {
                    $0.generation == generation
                        && $0.videoInputIsFinished
                        && $0.audioInputIsFinished
                }
            }
        }
    }
#endif

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

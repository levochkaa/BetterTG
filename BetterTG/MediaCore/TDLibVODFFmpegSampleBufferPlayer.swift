// TDLibVODFFmpegSampleBufferPlayer.swift

import AVFoundation
import Combine
import UIKit
#if DEBUG
    import CryptoKit
#endif

// MARK: - TDLibVODFFmpegSampleBufferPlayer

@MainActor final class TDLibVODFFmpegSampleBufferPlayer {
    // MARK: Internal

    enum Failure: Swift.Error, Equatable {
        case decoding(String)
        case offline
        case renderer(String)
        case retryable(String)
        case terminal(String)
    }

    // MARK: Private

    private struct PendingSeekCompletion {
        let operationGeneration: UInt64
        let target: TimeInterval
        let value: () -> Void
    }

    private enum DecodeLoopDecision {
        case next(TimeInterval)
        case stop
    }

    // Keep one FFmpeg job alive for the bridge's full bounded window. Renderer
    // backpressure limits decoded lookahead while avoiding per-chunk reopen gaps.
    private static let decodeWindow = TimeInterval(60)
    private static let lowWaterDuration = TimeInterval(1)
    private static let resumeBufferDuration = TimeInterval(1)
    private static let endTolerance = TimeInterval(0.05)
    private static let maximumAudioGap = TimeInterval(3)
    private static let audioGapTimeout = TimeInterval(3)

    let surfaceView: FFmpegSampleBufferSurfaceView

    private(set) var isPlaybackRequested = false
    private(set) var isPlaybackVisible = false

    private let lease: TDLibVODRangeLease
    private let decodeWindowDuration: TimeInterval
    private let decoder: TDLibVODFFmpegDecoder
    private let lookahead: TDLibVODFFmpegLookahead
    private let renderer: FFmpegSampleBufferRenderer
    private let itemIdentity = NSObject()
    private let stateSubject = CurrentValueSubject<LocalMediaPlayer.State, Never>(.idle)
    private let timeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let bufferedRangesSubject = CurrentValueSubject<[LocalMediaPlayer.BufferedRange], Never>([])
    private let streamingStatusSubject = CurrentValueSubject<TDLibVODResourceLoaderStatus, Never>(.idle)
    private let failureSubject = CurrentValueSubject<Failure?, Never>(nil)
    private let readyForDisplaySubject = CurrentValueSubject<Bool, Never>(false)
    private var rendererCancellable: AnyCancellable?
    private var decodeTask: Task<Void, Never>?
    private var bufferingTask: Task<Void, Never>?
    private var videoWatchdogTask: Task<Void, Never>?
    private var audioWatchdogTask: Task<Void, Never>?
    private var demandSuspendTask: Task<Void, Never>?
    private var timeTimer: Timer?
    private var operationGeneration = UInt64.zero
    private var rendererGeneration = UInt64.zero
    private var metadataOperationGeneration: UInt64?
    private var nextWindowStart = TimeInterval.zero
    private var bufferStart = TimeInterval.zero
    private var terminalEnd = TimeInterval.zero
    private var timelineOrigin = TimeInterval.zero
    private var audioStartTime = TimeInterval.zero
    private var audioEndTime = TimeInterval.zero
    private var videoStartTime = TimeInterval.zero
    private var videoEndTime = TimeInterval.zero
    private var hasExplicitDuration = false
    private var inputEnded = false
    private var isStalledForBuffering = false
    private var hasStartedPlayback = false
    private var audioGapBeganAt: TimeInterval?
    private var audioDegradedToSilence = false
    private var sourceAudioReadableTo: TimeInterval?
    private var sourceVideoReadableTo: TimeInterval?
    private var sourceLookaheadEnded = false
    private var lookaheadScanInProgress = false
    private var isPrepared = false
    private var isClosed = false
    private var playbackRate = Float(1)
    private var muted = false
    private var latestSnapshot: FFmpegSampleBufferRenderer.Snapshot?
    private var pendingSeekCompletion: PendingSeekCompletion?
    #if DEBUG
        private var debugDecoderSummaries = [TDLibVODFFmpegDecoder.Summary]()
    #endif

    var statePublisher: AnyPublisher<LocalMediaPlayer.State, Never> {
        stateSubject.removeDuplicates().eraseToAnyPublisher()
    }

    var timePublisher: AnyPublisher<TimeInterval, Never> {
        timeSubject.removeDuplicates().eraseToAnyPublisher()
    }

    var durationPublisher: AnyPublisher<TimeInterval, Never> {
        durationSubject.removeDuplicates().eraseToAnyPublisher()
    }

    var bufferedRangesPublisher: AnyPublisher<[LocalMediaPlayer.BufferedRange], Never> {
        bufferedRangesSubject.removeDuplicates().eraseToAnyPublisher()
    }

    var streamingStatusPublisher: AnyPublisher<TDLibVODResourceLoaderStatus, Never> {
        streamingStatusSubject.removeDuplicates().eraseToAnyPublisher()
    }

    var failurePublisher: AnyPublisher<Failure?, Never> {
        failureSubject.removeDuplicates().eraseToAnyPublisher()
    }

    var readyForDisplayPublisher: AnyPublisher<Bool, Never> {
        readyForDisplaySubject.removeDuplicates().eraseToAnyPublisher()
    }

    var hasItem: Bool { isPrepared && !isClosed }

    var currentItemIdentifier: ObjectIdentifier? {
        hasItem ? ObjectIdentifier(itemIdentity) : nil
    }

    var state: LocalMediaPlayer.State { stateSubject.value }

    var currentTime: TimeInterval { timeSubject.value }

    var duration: TimeInterval { durationSubject.value }

    var rate: Float { playbackRate }

    var isMuted: Bool { muted }

    var isReadyForDisplay: Bool { readyForDisplaySubject.value }

    var pictureInPictureDisplayLayer: AVSampleBufferDisplayLayer? {
        renderer.pictureInPictureDisplayLayer
    }

    convenience init(lease: TDLibVODRangeLease) {
        self.init(lease: lease, decodeWindowDuration: 60)
    }

    init(
        lease: TDLibVODRangeLease,
        decodeWindowDuration: TimeInterval,
    ) {
        precondition(
            decodeWindowDuration.isFinite
                && decodeWindowDuration > 0
                && decodeWindowDuration <= Self.decodeWindow,
        )
        self.lease = lease
        self.decodeWindowDuration = decodeWindowDuration
        self.decoder = TDLibVODFFmpegDecoder(lease: lease)
        self.lookahead = TDLibVODFFmpegLookahead(
            lease: lease,
            releasesLeaseOnCancellation: false,
        )
        self.surfaceView = FFmpegSampleBufferSurfaceView()
        self.renderer = FFmpegSampleBufferRenderer(displayLayer: surfaceView.displayLayer)
        surfaceView.videoGravity = .resizeAspect
        renderer.setMuted(false)
        self.rendererCancellable = renderer.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.consume(snapshot: snapshot) }
        startTimeTimer()
    }

    deinit {
        decodeTask?.cancel()
        bufferingTask?.cancel()
        videoWatchdogTask?.cancel()
        audioWatchdogTask?.cancel()
        demandSuspendTask?.cancel()
        timeTimer?.invalidate()
        rendererCancellable?.cancel()
        let renderer = renderer
        let decoder = decoder
        Task { @MainActor in
            renderer.invalidate()
            await decoder.close()
        }
    }

    #if DEBUG
        @MainActor static func runDebugProbeIfRequested(in window: UIWindow) {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-media-probe-vod-ffmpeg-controller") {
                Task { @MainActor in await runDebugProbe(in: window) }
            } else if arguments.contains("-media-probe-vod-main-track") {
                Task { @MainActor in await runMainTrackProbe(in: window) }
            } else if arguments.contains("-media-probe-vod-partial-coverage") {
                Task { @MainActor in await TDLibVODPartialCoverageProbe.run(in: window) }
            }
        }
    #endif

    func prepare(autoplay: Bool, initialTime: TimeInterval = 0) {
        guard !isClosed else { return }
        isPrepared = true
        isPlaybackRequested = autoplay
        durationSubject.send(0)
        failureSubject.send(nil)
        streamingStatusSubject.send(.loading)
        beginOperation(at: normalized(time: initialTime), completion: nil)
    }

    func play() {
        guard isPrepared, !isClosed else { return }
        isPlaybackRequested = true
        if stateSubject.value == .ended {
            beginOperation(at: 0, completion: nil)
            return
        }
        startDecodeIfNeeded()
        updatePlaybackGate()
    }

    func pause() {
        guard isPrepared, !isClosed else { return }
        isPlaybackRequested = false
        isStalledForBuffering = false
        cancelBufferingTransition()
        renderer.pause()
        if stateSubject.value != .failed, stateSubject.value != .ended {
            stateSubject.send(.paused)
        }
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        guard !isClosed, isPlaybackVisible != isVisible else { return }
        isPlaybackVisible = isVisible
        if isVisible {
            demandSuspendTask?.cancel()
            demandSuspendTask = nil
            renderer.setFeedingEnabled(true)
            startDecodeIfNeeded()
        } else {
            renderer.pause()
            isStalledForBuffering = false
            cancelBufferingTransition()
            if decodeTask != nil {
                suspendDecodeForOffscreen()
            } else {
                renderer.setFeedingEnabled(false)
            }
        }
        updatePlaybackGate()
    }

    func setMuted(_ isMuted: Bool) {
        muted = isMuted
        renderer.setMuted(isMuted)
    }

    func setRate(_ rate: Float) {
        playbackRate = min(2, max(0.5, rate))
        if stateSubject.value == .playing,
           !isStalledForBuffering,
           isPlaybackRequested,
           isPlaybackVisible
        {
            renderer.play(rate: playbackRate, waitForSufficientMediaData: false)
        }
    }

    func seek(
        to time: TimeInterval,
        completion: (() -> Void)? = nil,
    ) {
        guard isPrepared, !isClosed else { return }
        beginOperation(at: normalized(time: time), completion: completion)
    }

    func jump(by interval: TimeInterval) {
        seek(to: currentTime + interval)
    }

    func retry() {
        guard isPrepared, !isClosed, failureSubject.value != nil else { return }
        failureSubject.send(nil)
        streamingStatusSubject.send(.retrying)
        beginOperation(at: currentTime, completion: nil)
    }

    func close() async {
        guard !isClosed else { return }
        isClosed = true
        operationGeneration &+= 1
        decodeTask?.cancel()
        decodeTask = nil
        bufferingTask?.cancel()
        bufferingTask = nil
        videoWatchdogTask?.cancel()
        videoWatchdogTask = nil
        audioWatchdogTask?.cancel()
        audioWatchdogTask = nil
        demandSuspendTask?.cancel()
        demandSuspendTask = nil
        timeTimer?.invalidate()
        timeTimer = nil
        rendererCancellable?.cancel()
        rendererCancellable = nil
        renderer.pause()
        renderer.invalidate()
        isPrepared = false
        isPlaybackRequested = false
        stateSubject.send(.idle)
        streamingStatusSubject.send(.idle)
        await decoder.close()
        await lease.invalidate()
    }

    private func normalized(time: TimeInterval) -> TimeInterval {
        let nonnegative = time.isFinite ? max(0, time) : 0
        return duration > 0 && (hasExplicitDuration || inputEnded)
            ? min(nonnegative, duration)
            : nonnegative
    }

    private func beginOperation(
        at target: TimeInterval,
        completion: (() -> Void)?,
    ) {
        operationGeneration &+= 1
        let operation = operationGeneration
        decodeTask?.cancel()
        decodeTask = nil
        cancelBufferingTransition()
        videoWatchdogTask?.cancel()
        videoWatchdogTask = nil
        audioWatchdogTask?.cancel()
        audioWatchdogTask = nil
        demandSuspendTask?.cancel()
        demandSuspendTask = nil
        renderer.pause()
        rendererGeneration = renderer.reset(at: target)
        metadataOperationGeneration = nil
        renderer.setFeedingEnabled(isPlaybackVisible)
        latestSnapshot = renderer.snapshot()
        nextWindowStart = target
        bufferStart = target
        terminalEnd = target
        timelineOrigin = 0
        audioStartTime = 0
        audioEndTime = 0
        videoStartTime = 0
        videoEndTime = 0
        hasExplicitDuration = false
        inputEnded = false
        isStalledForBuffering = false
        hasStartedPlayback = false
        audioGapBeganAt = nil
        audioDegradedToSilence = false
        sourceAudioReadableTo = nil
        sourceVideoReadableTo = nil
        sourceLookaheadEnded = false
        lookaheadScanInProgress = false
        #if DEBUG
            debugDecoderSummaries.removeAll()
        #endif
        timeSubject.send(target)
        bufferedRangesSubject.send([])
        readyForDisplaySubject.send(false)
        failureSubject.send(nil)
        streamingStatusSubject.send(.loading)
        stateSubject.send(.preparing)
        pendingSeekCompletion = completion.map {
            PendingSeekCompletion(operationGeneration: operation, target: target, value: $0)
        }
        consume(snapshot: latestSnapshot!)
        startDecodeIfNeeded()
    }

    private func startDecodeIfNeeded() {
        guard isPrepared,
              !isClosed,
              isPlaybackVisible,
              !inputEnded,
              decodeTask == nil,
              failureSubject.value == nil
        else { return }
        renderer.setFeedingEnabled(true)
        let operation = operationGeneration
        let rendererGeneration = rendererGeneration
        let start = nextWindowStart
        lookaheadScanInProgress = true
        let decoder = decoder
        let lookahead = lookahead
        let renderer = renderer
        let decodeWindowDuration = decodeWindowDuration
        decodeTask = Task { @MainActor [weak self, decoder, lookahead, renderer] in
            var windowStart = start
            var decodeMode = TDLibVODFFmpegDecoder.DecodeMode.startSession
            var needsLookahead = true
            while !Task.isCancelled {
                do {
                    let decodeStart = windowStart
                    let endTolerance = Self.endTolerance
                    if needsLookahead {
                        let sourceState = try await lookahead.scan(
                            seekTime: decodeStart,
                            currentPlaybackTime: decodeStart,
                            lookaheadDuration: 2,
                        )
                        guard !Task.isCancelled,
                              self?.consume(
                                  lookahead: sourceState,
                                  operation: operation,
                                  rendererGeneration: rendererGeneration,
                              ) == true
                        else { return }
                    } else {
                        self?.lookaheadScanInProgress = false
                    }
                    let summary = try await decoder.decode(
                        seekTime: decodeStart,
                        duration: decodeWindowDuration,
                        mode: decodeMode,
                        onMetadata: { [weak self] metadata in
                            let accepted = renderer.setStreamTopology(
                                hasAudio: metadata.hasAudio,
                                hasVideo: metadata.hasVideo,
                                attachAudioRenderer: metadata.hasAudio
                                    && decodeStart >= metadata.audioStartTime - endTolerance
                                    && decodeStart < metadata.audioEndTime - endTolerance,
                                generation: rendererGeneration,
                            )
                            Task { @MainActor [weak self] in
                                self?.consume(
                                    metadata: metadata,
                                    operation: operation,
                                    rendererGeneration: rendererGeneration,
                                )
                            }
                            return accepted && metadata.hasVideo
                        },
                        onVideoFrame: { renderer.enqueue(video: $0, generation: rendererGeneration) },
                        onAudioFrame: { renderer.enqueue(audio: $0, generation: rendererGeneration) },
                    )
                    guard !Task.isCancelled,
                          let decision = self?.consume(
                              summary: summary,
                              windowStart: decodeStart,
                              operation: operation,
                              rendererGeneration: rendererGeneration,
                          )
                    else { return }
                    switch decision {
                    case .next(let nextWindowStart):
                        windowStart = nextWindowStart
                        decodeMode = .continueSession
                        needsLookahead = false
                    case .stop:
                        return
                    }
                } catch {
                    self?.lookaheadScanInProgress = false
                    guard !Task.isCancelled, let self else { return }
                    guard operation == operationGeneration,
                          rendererGeneration == self.rendererGeneration
                    else { return }
                    await handleDecodeFailure(error, operation: operation)
                    return
                }
            }
        }
        startVideoWatchdog(operation: operation)
    }

    private func suspendDecodeForOffscreen() {
        decodeTask?.cancel()
        decodeTask = nil
        videoWatchdogTask?.cancel()
        videoWatchdogTask = nil
        audioWatchdogTask?.cancel()
        audioWatchdogTask = nil
        lookaheadScanInProgress = false
        rendererGeneration = renderer.reset(at: currentTime)
        metadataOperationGeneration = nil
        renderer.setFeedingEnabled(false)
        latestSnapshot = renderer.snapshot()
        nextWindowStart = currentTime
        bufferStart = currentTime
        terminalEnd = max(currentTime, duration)
        inputEnded = false
        hasStartedPlayback = false
        audioGapBeganAt = nil
        audioDegradedToSilence = false
        bufferedRangesSubject.send([])
        readyForDisplaySubject.send(false)
        stateSubject.send(.paused)
        let lease = lease
        demandSuspendTask = Task {
            guard !Task.isCancelled else { return }
            await lease.suspendDemand()
        }
    }

    private func consume(
        lookahead state: TDLibVODFFmpegLookahead.State,
        operation: UInt64,
        rendererGeneration: UInt64,
    ) -> Bool {
        guard !isClosed,
              operation == operationGeneration,
              rendererGeneration == self.rendererGeneration
        else { return false }
        lookaheadScanInProgress = false
        if let audioReadableTo = state.audioReadableTo {
            sourceAudioReadableTo = max(sourceAudioReadableTo ?? bufferStart, audioReadableTo)
        }
        if let videoReadableTo = state.videoReadableTo {
            sourceVideoReadableTo = max(sourceVideoReadableTo ?? bufferStart, videoReadableTo)
        }
        sourceLookaheadEnded = sourceLookaheadEnded || state.isEnded
        consume(snapshot: renderer.snapshot())
        return true
    }

    private func consume(
        summary: TDLibVODFFmpegDecoder.Summary,
        windowStart: TimeInterval,
        operation: UInt64,
        rendererGeneration: UInt64,
    ) -> DecodeLoopDecision {
        guard operation == operationGeneration,
              rendererGeneration == self.rendererGeneration,
              !isClosed
        else { return .stop }
        #if DEBUG
            debugDecoderSummaries.append(summary)
        #endif
        if summary.isEnded, !summary.hasFinalDuration {
            transitionToFailure(.decoding("The main track ended without a verified duration."), status: .failed)
            return .stop
        }
        let decodedEnd = summary.videoDecodedTo
        let decodedDuration = summary.hasExplicitDuration || summary.hasFinalDuration
            ? summary.duration
            : max(durationSubject.value, max(summary.duration, decodedEnd))
        if decodedDuration.isFinite, decodedDuration > 0 {
            durationSubject.send(decodedDuration)
        }
        terminalEnd = durationSubject.value > 0 ? durationSubject.value : decodedEnd
        if summary.isEnded {
            inputEnded = true
            videoWatchdogTask?.cancel()
            videoWatchdogTask = nil
            audioWatchdogTask?.cancel()
            audioWatchdogTask = nil
            renderer.finish(generation: rendererGeneration)
            decodeTask = nil
            streamingStatusSubject.send(.ready)
            consume(snapshot: renderer.snapshot())
            return .stop
        }

        guard decodedEnd > windowStart + 0.001 else {
            transitionToFailure(.decoding("FFmpeg made no forward progress."), status: .failed)
            return .stop
        }
        let next = summary.continuationTime
        guard next.isFinite, next > windowStart + 0.001 else {
            transitionToFailure(.decoding("FFmpeg session horizon made no forward progress."), status: .failed)
            return .stop
        }
        nextWindowStart = next
        consume(snapshot: renderer.snapshot())
        guard isPlaybackVisible else {
            renderer.setFeedingEnabled(false)
            decodeTask = nil
            return .stop
        }
        return .next(next)
    }

    private func handleDecodeFailure(_ error: Swift.Error, operation: UInt64) async {
        let directRangeError: TDLibVODRangeError? =
            if let decodeError = error as? TDLibVODFFmpegDecoder.DecodeError,
            case .range(let rangeError) = decodeError {
                rangeError
            } else if let lookaheadError = error as? TDLibVODFFmpegLookahead.LookaheadError,
                      case .range(let rangeError) = lookaheadError
            {
                rangeError
            } else {
                error as? TDLibVODRangeError
            }
        if let rangeError = directRangeError {
            guard !isClosed, operation == operationGeneration else { return }
            decodeTask = nil
            switch rangeError {
            case .offline:
                transitionToFailure(.offline, status: .offline)
            case .missingLocalPath, .readFailed, .timedOut:
                transitionToFailure(.retryable(String(describing: rangeError)), status: .retrying)
            case .invalidRange, .unknownSize:
                transitionToFailure(.terminal(String(describing: rangeError)), status: .failed)
            case .cancelled, .staleRequest:
                break
            }
            return
        }
        let rangeState = await lease.source.state
        guard !isClosed, operation == operationGeneration else { return }
        decodeTask = nil
        switch rangeState {
        case .offlineMissingRange:
            transitionToFailure(.offline, status: .offline)
        case .retryableFailure(let details):
            transitionToFailure(.retryable(details), status: .retrying)
        case .terminalFailure(let details):
            transitionToFailure(.terminal(details), status: .failed)
        case .buffering:
            transitionToFailure(.retryable(String(describing: error)), status: .retrying)
        case .cachedReady, .idle:
            transitionToFailure(.decoding(String(describing: error)), status: .failed)
        case .cancelled:
            if error as? TDLibVODFFmpegDecoder.DecodeError != .cancelled {
                transitionToFailure(.decoding(String(describing: error)), status: .failed)
            }
        }
    }

    private func transitionToFailure(
        _ failure: Failure,
        status: TDLibVODResourceLoaderStatus,
    ) {
        guard !isClosed else { return }
        operationGeneration &+= 1
        decodeTask?.cancel()
        decodeTask = nil
        cancelBufferingTransition()
        pendingSeekCompletion = nil
        renderer.pause()
        isStalledForBuffering = false
        videoWatchdogTask?.cancel()
        videoWatchdogTask = nil
        audioWatchdogTask?.cancel()
        audioWatchdogTask = nil
        demandSuspendTask?.cancel()
        demandSuspendTask = nil
        lookaheadScanInProgress = false
        failureSubject.send(failure)
        streamingStatusSubject.send(status)
        rendererGeneration = renderer.reset(at: currentTime)
        metadataOperationGeneration = nil
        renderer.setFeedingEnabled(false)
        latestSnapshot = renderer.snapshot()
        sourceAudioReadableTo = nil
        sourceVideoReadableTo = nil
        sourceLookaheadEnded = false
        bufferedRangesSubject.send([])
        readyForDisplaySubject.send(false)
        stateSubject.send(.failed)
        let lease = lease
        demandSuspendTask = Task {
            guard !Task.isCancelled else { return }
            await lease.suspendDemand()
        }
    }

    private func consume(snapshot: FFmpegSampleBufferRenderer.Snapshot) {
        guard !isClosed, snapshot.generation == rendererGeneration else { return }
        latestSnapshot = snapshot
        if metadataOperationGeneration == operationGeneration, !hasExplicitDuration, !inputEnded,
           snapshot.hasVideoInput, snapshot.videoAcceptedUntil > durationSubject.value
        {
            durationSubject.send(snapshot.videoAcceptedUntil)
            terminalEnd = max(terminalEnd, snapshot.videoAcceptedUntil)
        }
        if snapshot.hasVideoInput {
            sourceVideoReadableTo = max(
                sourceVideoReadableTo ?? bufferStart,
                snapshot.videoAcceptedUntil,
            )
        }
        if snapshot.hasAudioInput {
            sourceAudioReadableTo = max(
                sourceAudioReadableTo ?? bufferStart,
                snapshot.audioAcceptedUntil,
            )
        }
        if snapshot.hasVideoInput {
            videoWatchdogTask?.cancel()
            videoWatchdogTask = nil
        }
        if snapshot.hasAudioInput {
            audioWatchdogTask?.cancel()
            audioWatchdogTask = nil
        }
        readyForDisplaySubject.send(snapshot.isDisplayReady)
        if let details = snapshot.videoError ?? snapshot.audioError {
            transitionToFailure(.renderer(details), status: .failed)
            return
        }
        publishBufferedRange(snapshot: snapshot)
        updateTime(snapshot.currentTime)
        updatePlaybackGate()
        fulfillSeekIfReady(snapshot: snapshot)
    }

    private func consume(
        metadata: TDLibVODFFmpegDecoder.Metadata,
        operation: UInt64,
        rendererGeneration: UInt64,
    ) {
        guard !isClosed,
              operation == operationGeneration,
              rendererGeneration == self.rendererGeneration
        else { return }
        metadataOperationGeneration = operation
        hasExplicitDuration = metadata.hasExplicitDuration
        if !inputEnded, metadata.duration.isFinite, metadata.duration > 0 {
            let resolvedDuration = hasExplicitDuration
                ? metadata.duration
                : max(durationSubject.value, metadata.duration)
            durationSubject.send(resolvedDuration)
            terminalEnd = resolvedDuration
        }
        timelineOrigin = metadata.timelineOrigin
        audioStartTime = metadata.audioStartTime
        audioEndTime = metadata.audioEndTime
        videoStartTime = metadata.videoStartTime
        videoEndTime = metadata.videoEndTime
        let effectiveDuration = durationSubject.value
        if hasExplicitDuration, effectiveDuration > 0, timeSubject.value > effectiveDuration {
            let completion = pendingSeekCompletion?.value
            beginOperation(at: effectiveDuration, completion: completion)
            return
        }
        guard metadata.hasVideo else {
            transitionToFailure(.decoding("The media has no video stream."), status: .failed)
            return
        }
        consume(snapshot: renderer.snapshot())
    }

    private func publishBufferedRange(snapshot: FFmpegSampleBufferRenderer.Snapshot) {
        guard snapshot.hasVideoInput else {
            bufferedRangesSubject.send([])
            return
        }
        let end = normalized(time: sourceBufferedEnd())
        guard end > bufferStart else {
            bufferedRangesSubject.send([])
            return
        }
        bufferedRangesSubject.send([.init(end: end, start: bufferStart)])
    }

    private func commonBufferedEnd(snapshot: FFmpegSampleBufferRenderer.Snapshot) -> TimeInterval {
        guard metadataOperationGeneration == operationGeneration,
              snapshot.streamTopologyIsKnown,
              snapshot.streamHasVideo,
              snapshot.hasVideoInput
        else { return bufferStart }
        if snapshot.streamHasAudio, audioIsRequired(at: timeSubject.value) {
            guard snapshot.hasAudioInput else {
                return inputEnded ? snapshot.videoAcceptedUntil : bufferStart
            }
            return min(snapshot.videoAcceptedUntil, snapshot.audioAcceptedUntil)
        }
        return snapshot.videoAcceptedUntil
    }

    private func sourceBufferedEnd() -> TimeInterval {
        guard metadataOperationGeneration == operationGeneration,
              let videoEnd = sourceVideoReadableTo
        else { return bufferStart }
        if audioIsRequired(at: timeSubject.value) {
            guard let audioEnd = sourceAudioReadableTo else { return bufferStart }
            return min(videoEnd, audioEnd)
        }
        return videoEnd
    }

    private func sourceHasReachedKnownEnd() -> Bool {
        if sourceLookaheadEnded {
            return true
        }
        let knownEnd = durationSubject.value
        return hasExplicitDuration && knownEnd > 0 && sourceBufferedEnd() >= knownEnd - Self.endTolerance
    }

    private func fulfillSeekIfReady(snapshot: FFmpegSampleBufferRenderer.Snapshot) {
        guard let completion = pendingSeekCompletion,
              completion.operationGeneration == operationGeneration,
              metadataOperationGeneration == operationGeneration
        else { return }
        let videoReady = snapshot.videoFirstPresentationTime.map { $0 >= completion.target } == true
        let audioReady = !snapshot.streamHasAudio
            || !audioIsRequired(at: completion.target)
            || snapshot.audioFirstPresentationTime.map { $0 >= completion.target } == true
        guard inputEnded || videoReady && audioReady else { return }
        pendingSeekCompletion = nil
        completion.value()
    }

    private func updateTime(_ rawTime: TimeInterval) {
        guard rawTime.isFinite else { return }
        let time = normalized(time: rawTime)
        timeSubject.send(time)
    }

    private func updatePlaybackGate() {
        guard isPrepared,
              !isClosed,
              failureSubject.value == nil,
              let snapshot = latestSnapshot,
              snapshot.generation == rendererGeneration
        else { return }

        guard metadataOperationGeneration == operationGeneration else {
            // Initial lookahead may be waiting for an uncached seek range before
            // the decoder can publish metadata. That wait is buffering too.
            if isPlaybackRequested, isPlaybackVisible, decodeTask != nil {
                requestBufferingTransition()
            }
            return
        }

        let current = timeSubject.value
        let rawBufferedEnd = commonBufferedEnd(snapshot: snapshot)
        let rawBufferedAhead = max(0, rawBufferedEnd - current)
        let sourceEnd = sourceBufferedEnd()
        let sourceBufferedAhead = max(0, sourceEnd - current)
        let end = durationSubject.value > 0
            ? durationSubject.value
            : max(terminalEnd, snapshot.videoAcceptedUntil)
        if inputEnded,
           snapshot.videoInputIsFinished,
           snapshot.audioInputIsFinished,
           end > 0,
           current >= end - Self.endTolerance
        {
            cancelBufferingTransition()
            renderer.pause()
            timeSubject.send(end)
            durationSubject.send(end)
            isPlaybackRequested = false
            stateSubject.send(.ended)
            streamingStatusSubject.send(.ready)
            fulfillSeekIfReady(snapshot: snapshot)
            return
        }

        guard isPlaybackVisible else {
            cancelBufferingTransition()
            renderer.pause()
            isStalledForBuffering = false
            stateSubject.send(.paused)
            return
        }
        guard isPlaybackRequested else {
            cancelBufferingTransition()
            renderer.pause()
            isStalledForBuffering = false
            stateSubject.send(.paused)
            return
        }
        guard snapshot.streamTopologyIsKnown,
              snapshot.streamHasVideo,
              snapshot.hasVideoInput
        else {
            renderer.pause()
            requestBufferingTransition()
            return
        }

        updateAudioWatchdog(snapshot: snapshot)
        if detectTerminalAudioGap(snapshot: snapshot) {
            return
        }

        let sourceIsReady = sourceBufferedAhead >= Self.resumeBufferDuration || sourceHasReachedKnownEnd()
        let rawHasCurrentFrame = rawBufferedEnd > current + 0.001
        let isReady = sourceIsReady && rawHasCurrentFrame
            || inputEnded && end > current + 0.001
        if !hasStartedPlayback, !isReady {
            renderer.pause()
            requestBufferingTransition()
            return
        }
        if isStalledForBuffering {
            if isReady {
                isStalledForBuffering = false
                cancelBufferingTransition()
                renderer.play(
                    rate: playbackRate,
                    waitForSufficientMediaData: !snapshot.audioRendererIsAttached
                        || audioIsRequired(at: current),
                )
                hasStartedPlayback = true
                stateSubject.send(.playing)
                streamingStatusSubject.send(.ready)
            } else {
                renderer.pause()
                requestBufferingTransition()
            }
            return
        }

        if stateSubject.value == .playing {
            let sourceIsLow = !sourceHasReachedKnownEnd() && sourceBufferedAhead < Self.lowWaterDuration
            let rawIsEmpty = rawBufferedAhead < Self.endTolerance
            if !inputEnded, sourceIsLow || rawIsEmpty {
                isStalledForBuffering = true
                renderer.pause()
                requestBufferingTransition()
            } else if renderer.rate != playbackRate {
                renderer.play(rate: playbackRate, waitForSufficientMediaData: false)
            }
            return
        }

        if isReady {
            isStalledForBuffering = false
            cancelBufferingTransition()
            renderer.play(
                rate: playbackRate,
                waitForSufficientMediaData: !snapshot.audioRendererIsAttached
                    || audioIsRequired(at: current),
            )
            hasStartedPlayback = true
            stateSubject.send(.playing)
            streamingStatusSubject.send(.ready)
        } else {
            renderer.pause()
            requestBufferingTransition()
        }
    }

    private func requestBufferingTransition() {
        guard bufferingTask == nil,
              stateSubject.value != .buffering,
              stateSubject.value != .failed
        else { return }
        let operation = operationGeneration
        bufferingTask = Task { @MainActor [weak self] in
            try? await Task<Never, Never>.sleep(for: .milliseconds(300))
            guard let self,
                  !Task.isCancelled,
                  operation == operationGeneration,
                  isPlaybackRequested,
                  isPlaybackVisible,
                  failureSubject.value == nil
            else { return }
            bufferingTask = nil
            stateSubject.send(.buffering)
        }
    }

    private func detectTerminalAudioGap(
        snapshot: FFmpegSampleBufferRenderer.Snapshot,
    ) -> Bool {
        guard snapshot.streamHasAudio,
              !inputEnded,
              audioIsRequired(at: timeSubject.value)
        else {
            audioGapBeganAt = nil
            return false
        }
        let audioEnd = snapshot.hasAudioInput ? snapshot.audioAcceptedUntil : bufferStart
        let gap = snapshot.videoAcceptedUntil - audioEnd
        guard gap >= Self.maximumAudioGap else {
            audioGapBeganAt = nil
            return false
        }
        let now = CACurrentMediaTime()
        if let gapBeganAt = audioGapBeganAt {
            guard now - gapBeganAt >= Self.audioGapTimeout else { return false }
            audioDegradedToSilence = true
            audioWatchdogTask?.cancel()
            audioWatchdogTask = nil
            isStalledForBuffering = false
            audioGapBeganAt = nil
            return false
        }
        audioGapBeganAt = now
        return false
    }

    private func audioIsRequired(at time: TimeInterval) -> Bool {
        !audioDegradedToSilence
            && audioEndTime > audioStartTime
            && time >= audioStartTime - Self.endTolerance
            && time < audioEndTime - Self.endTolerance
            && (!hasExplicitDuration || time < duration - Self.endTolerance)
    }

    private func cancelBufferingTransition() {
        bufferingTask?.cancel()
        bufferingTask = nil
    }

    private func startTimeTimer() {
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isClosed, self.isPrepared else { return }
                self.consume(snapshot: self.renderer.snapshot())
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        timeTimer = timer
    }

    private func startVideoWatchdog(operation: UInt64) {
        guard videoWatchdogTask == nil else { return }
        videoWatchdogTask = Task { @MainActor [weak self] in
            try? await Task<Never, Never>.sleep(for: .seconds(12))
            guard let self,
                  !Task.isCancelled,
                  operation == operationGeneration,
                  latestSnapshot?.hasVideoInput != true,
                  failureSubject.value == nil
            else { return }
            videoWatchdogTask = nil
            transitionToFailure(.decoding("No video frame arrived before the decode deadline."), status: .failed)
        }
    }

    private func startAudioWatchdog(
        operation: UInt64,
        rendererGeneration: UInt64,
    ) {
        guard audioWatchdogTask == nil else { return }
        audioWatchdogTask = Task { @MainActor [weak self] in
            try? await Task<Never, Never>.sleep(for: .seconds(5))
            guard let self,
                  !Task.isCancelled,
                  operation == operationGeneration,
                  rendererGeneration == self.rendererGeneration,
                  latestSnapshot?.streamHasAudio == true,
                  latestSnapshot?.hasAudioInput != true,
                  audioIsRequired(at: timeSubject.value),
                  !inputEnded,
                  failureSubject.value == nil
            else { return }
            audioWatchdogTask = nil
            audioDegradedToSilence = true
            isStalledForBuffering = false
            updatePlaybackGate()
        }
    }

    private func updateAudioWatchdog(snapshot: FFmpegSampleBufferRenderer.Snapshot) {
        if !audioDegradedToSilence,
           snapshot.streamHasAudio,
           !snapshot.hasAudioInput,
           !inputEnded,
           audioIsRequired(at: timeSubject.value)
        {
            startAudioWatchdog(
                operation: operationGeneration,
                rendererGeneration: rendererGeneration,
            )
        } else {
            audioWatchdogTask?.cancel()
            audioWatchdogTask = nil
        }
    }
}

#if DEBUG

    // MARK: - Controller runtime probe

    private extension TDLibVODFFmpegSampleBufferPlayer {
        @MainActor final class ProbeRecorder {
            // MARK: Internal

            private(set) var maximumBufferedAhead = TimeInterval.zero
            private(set) var firstPlayingBufferedAhead: TimeInterval?
            private(set) var states = [LocalMediaPlayer.State]()

            // MARK: Private

            private var stateCancellable: AnyCancellable?
            private var rangeCancellable: AnyCancellable?
            private var lastBufferedEnd = TimeInterval.zero

            init(player: TDLibVODFFmpegSampleBufferPlayer) {
                self.stateCancellable = player.statePublisher.sink { [weak self] state in
                    guard let self else { return }
                    states.append(state)
                    if state == .playing, firstPlayingBufferedAhead == nil {
                        self.firstPlayingBufferedAhead = max(0, lastBufferedEnd - player.currentTime)
                    }
                }
                self.rangeCancellable = player.bufferedRangesPublisher.sink { [weak self] ranges in
                    guard let self, let range = ranges.first else { return }
                    self.lastBufferedEnd = range.end
                    self.maximumBufferedAhead = max(maximumBufferedAhead, range.end - player.currentTime)
                }
            }
        }

        @MainActor static func runDebugProbe(in window: UIWindow) async {
            let resultURL = FileManager.default
.urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("vod-ffmpeg-controller-probe.txt")
            let fixtureURL = FileManager.default
.temporaryDirectory
                .appendingPathComponent("bettertg-vod-ffmpeg-controller-probe.webm")
            try? FileManager.default.removeItem(at: fixtureURL)
            defer { try? FileManager.default.removeItem(at: fixtureURL) }

            let result: String
            var failure: Swift.Error?
            var player: TDLibVODFFmpegSampleBufferPlayer?
            do {
                try FFmpegVODOriginProbeFixture.write(to: fixtureURL)
                let fixtureData = try Data(contentsOf: fixtureURL)
                let fixtureSHA256 = SHA256.hash(data: fixtureData)
                    .map { String(format: "%02x", $0) }
                    .joined()
                guard fixtureSHA256 == FFmpegVODOriginProbeFixture.sha256 else {
                    throw Failure.decoding("Origin fixture checksum mismatch")
                }
                let attributes = try FileManager.default.attributesOfItem(atPath: fixtureURL.path)
                guard let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0 else {
                    throw Failure.decoding("Missing fixture size")
                }
                let network = TDLibVODProbeNetwork(available: true)
                let backend = TDLibVODProbeBackend(fileURL: fixtureURL, fileSize: size, network: network)
                await backend.setAutoFulfill(true)
                await backend.setDownloadDelay(.milliseconds(450))
                let coordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-vod-ffmpeg-controller",
                    client: backend.client,
                    requestTimeout: .seconds(2),
                )
                let probePlayer = await TDLibVODFFmpegSampleBufferPlayer(
                    lease: coordinator.acquire(file: backend.file(expectedSize: size * 2)),
                    decodeWindowDuration: 1,
                )
                player = probePlayer
                probePlayer.surfaceView.frame = CGRect(
                    x: 8,
                    y: max(8, window.safeAreaInsets.top + 8),
                    width: 192,
                    height: 108,
                )
                probePlayer.surfaceView.backgroundColor = .black
                probePlayer.surfaceView.isUserInteractionEnabled = false
                window.addSubview(probePlayer.surfaceView)
                let recorder = ProbeRecorder(player: probePlayer)

                probePlayer.setMuted(true)
                probePlayer.prepare(autoplay: true)
                try await Task<Never, Never>.sleep(for: .milliseconds(200))
                let deferredDownload = await backend.downloadCalls.isEmpty
                probePlayer.setPlaybackVisible(true)
                try await waitUntil {
                    probePlayer.state == .playing && probePlayer.currentTime >= 0.25
                }
                let normalizedSnapshot = probePlayer.renderer.snapshot()
                let originNormalized = abs(probePlayer.timelineOrigin - 5) < 0.01
                    && (10.9...11.3).contains(probePlayer.duration)
                    && probePlayer.videoStartTime < 0.01
                    && (10.9...11.3).contains(probePlayer.videoEndTime)
                    && probePlayer.audioStartTime < 0.02
                    && (10.9...11.3).contains(probePlayer.audioEndTime)
                    && normalizedSnapshot.videoFirstPresentationTime.map { $0 < 0.01 } == true
                    && normalizedSnapshot.audioFirstPresentationTime.map { $0 < 0.02 } == true
                let unequalTrackEnds = abs(probePlayer.videoEndTime - probePlayer.audioEndTime) > 0.001
                let initialGateWorked = recorder.firstPlayingBufferedAhead.map { $0 >= 0.95 } == true

                probePlayer.pause()
                let pausedTime = probePlayer.currentTime
                try await Task<Never, Never>.sleep(for: .milliseconds(200))
                let pauseStable = abs(probePlayer.currentTime - pausedTime) < 0.05
                probePlayer.setRate(1.5)
                probePlayer.play()
                try await waitUntil { probePlayer.currentTime >= pausedTime + 0.2 }

                probePlayer.setPlaybackVisible(false)
                let offscreenIntent = probePlayer.isPlaybackRequested
                let offscreenTime = probePlayer.currentTime
                try await Task<Never, Never>.sleep(for: .milliseconds(200))
                let offscreenPaused = abs(probePlayer.currentTime - offscreenTime) < 0.05
                probePlayer.setPlaybackVisible(true)

                var staleSeekCompletionCount = 0
                var currentSeekCompletionCount = 0
                probePlayer.seek(to: 0.25) { staleSeekCompletionCount += 1 }
                probePlayer.seek(to: 1) { currentSeekCompletionCount += 1 }
                try await waitUntil {
                    currentSeekCompletionCount == 1
                        && probePlayer.currentTime >= 1.15
                        && probePlayer.state == .playing
                }
                let seekSnapshot = probePlayer.renderer.snapshot()
                let lastSeekWon = staleSeekCompletionCount == 0
                    && seekSnapshot.videoFirstPresentationTime.map { $0 >= 1 } == true
                    && seekSnapshot.audioFirstPresentationTime.map { $0 >= 1 } == true

                try await waitUntil(timeout: .seconds(12)) { probePlayer.state == .ended }
                let endedTime = probePlayer.currentTime
                try await Task<Never, Never>.sleep(for: .milliseconds(200))
                let noLoop = probePlayer.state == .ended
                    && abs(probePlayer.currentTime - endedTime) < 0.05
                let sessionSummaries = probePlayer.debugDecoderSummaries
                let sessionIDs = Set(sessionSummaries.map(\.sessionID))
                let maximumPendingPacketCount = sessionSummaries.map(\.maximumPendingPacketCount).max() ?? 0
                let maximumPendingPacketBytes = sessionSummaries.map(\.maximumPendingPacketBytes).max() ?? 0
                let pendingFIFOWithinBounds = maximumPendingPacketCount <= 4096
                    && maximumPendingPacketBytes <= 32 * 1024 * 1024
                let persistentSessionReused = sessionSummaries.count >= 3
                    && sessionIDs.count == 1
                    && sessionSummaries.allSatisfy { $0.openCount == 1 }
                    && sessionSummaries.map(\.runCount) == Array(1...sessionSummaries.count)
                    && sessionSummaries.allSatisfy { $0.explicitSeekCount == 1 }
                    && zip(
                        sessionSummaries.map(\.continuationTime),
                        sessionSummaries.dropFirst().map(\.continuationTime),
                    ).allSatisfy { $0.1 > $0.0 }
                probePlayer.setPlaybackVisible(false)
                await probePlayer.close()
                probePlayer.surfaceView.removeFromSuperview()
                let downloads = await backend.downloadCalls

                let cancelBackend = TDLibVODProbeBackend(
                    fileURL: fixtureURL,
                    fileSize: size,
                    network: network,
                )
                await cancelBackend.setAutoFulfill(false)
                let cancelCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-vod-ffmpeg-controller-offscreen",
                    client: cancelBackend.client,
                    requestTimeout: .seconds(2),
                )
                let cancelPlayer = await TDLibVODFFmpegSampleBufferPlayer(
                    lease: cancelCoordinator.acquire(file: cancelBackend.file(expectedSize: size)),
                )
                cancelPlayer.setPlaybackVisible(true)
                cancelPlayer.prepare(autoplay: true)
                try await waitUntil { await !cancelBackend.downloadCalls.isEmpty }
                cancelPlayer.setPlaybackVisible(false)
                try await waitUntil { await cancelBackend.completedCancelCount == 1 }
                let offscreenActiveDownloads = await cancelBackend.activeDownloadCount
                let offscreenCompletedCancels = await cancelBackend.completedCancelCount
                let offscreenRequestCancelled = offscreenActiveDownloads == 0
                    && offscreenCompletedCancels == 1
                await cancelPlayer.close()

                let offlineNetwork = TDLibVODProbeNetwork(available: false)
                let offlineBackend = TDLibVODProbeBackend(
                    fileURL: fixtureURL,
                    fileSize: size,
                    network: offlineNetwork,
                )
                await offlineBackend.setAutoFulfill(true)
                let offlineCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-vod-ffmpeg-controller-offline",
                    client: offlineBackend.client,
                    requestTimeout: .seconds(2),
                )
                let offlinePlayer = await TDLibVODFFmpegSampleBufferPlayer(
                    lease: offlineCoordinator.acquire(file: offlineBackend.file(expectedSize: size)),
                )
                offlinePlayer.setPlaybackVisible(true)
                offlinePlayer.prepare(autoplay: true)
                try await waitUntil { offlinePlayer.failureSubject.value == .offline }
                let offlinePlayhead = offlinePlayer.currentTime
                offlineNetwork.available = true
                offlinePlayer.retry()
                try await waitUntil { offlinePlayer.state == .playing }
                let offlineRetryWorked = abs(offlinePlayhead) < 0.01
                    && offlinePlayer.failureSubject.value == nil
                await offlinePlayer.close()

                let clampBackend = TDLibVODProbeBackend(
                    fileURL: fixtureURL,
                    fileSize: size,
                    network: network,
                )
                await clampBackend.setAutoFulfill(true)
                let clampCoordinator = TDLibVODRangeCoordinator(
                    accountID: "probe-vod-ffmpeg-controller-clamp",
                    client: clampBackend.client,
                    requestTimeout: .seconds(2),
                )
                let clampPlayer = await TDLibVODFFmpegSampleBufferPlayer(
                    lease: clampCoordinator.acquire(file: clampBackend.file(expectedSize: size)),
                )
                clampPlayer.setPlaybackVisible(true)
                clampPlayer.prepare(autoplay: true, initialTime: 100)
                try await waitUntil { clampPlayer.state == .ended }
                let outOfRangeClamped = (10.9...11.3).contains(clampPlayer.duration)
                    && abs(clampPlayer.currentTime - clampPlayer.duration) < 0.05
                    && clampPlayer.failureSubject.value == nil
                await clampPlayer.close()
                let cancelDownloads = await cancelBackend.downloadCalls
                let offlineDownloads = await offlineBackend.downloadCalls
                let clampDownloads = await clampBackend.downloadCalls
                let allDownloads = downloads + cancelDownloads + offlineDownloads + clampDownloads
                let mainTrackProof = try await verifyMainTrackTimeline(in: window)

                guard deferredDownload,
                      originNormalized,
                      unequalTrackEnds,
                      initialGateWorked,
                      pauseStable,
                      offscreenIntent,
                      offscreenPaused,
                      offscreenRequestCancelled,
                      offlineRetryWorked,
                      outOfRangeClamped,
                      lastSeekWon,
                      noLoop,
                      persistentSessionReused,
                      pendingFIFOWithinBounds,
                      recorder.states.contains(.preparing) || recorder.states.contains(.buffering),
                      recorder.states.contains(.playing),
                      recorder.states.contains(.ended),
                      allDownloads.allSatisfy({ !$0.isFullDownload })
                else {
                    throw Failure.decoding(
                        "deferred=\(deferredDownload), origin=\(originNormalized), unequal-ends=\(unequalTrackEnds), gate=\(initialGateWorked), "
                            + "pause=\(pauseStable), offscreen-intent=\(offscreenIntent), "
                            + "offscreen-pause=\(offscreenPaused), seek=\(lastSeekWon), "
                            + "offscreen-cancel=\(offscreenRequestCancelled), "
                            + "offline-retry=\(offlineRetryWorked), "
                            + "seek-clamp=\(outOfRangeClamped), "
                            + "persistent-session=\(persistentSessionReused)/windows=\(sessionSummaries.count), "
                            + "pending-fifo=\(maximumPendingPacketCount)/\(maximumPendingPacketBytes), "
                            + "no-loop=\(noLoop), states=\(recorder.states), "
                            + "full-downloads=\(allDownloads.filter(\.isFullDownload).count)",
                    )
                }

                result = "VOD FFmpeg controller probe: fixture-sha256=\(fixtureSHA256), "
                    + "origin=5->0, unequal-track-ends=true, deferred-download=true, initial-gate>=1=true, "
                    + "window<=60s, autoplay=true, loading-visible=true, pause-stable=true, rate=1.5, "
                    + "offscreen-rate=0, offscreen-cancel=true, intent-preserved=true, last-seek-wins=true, "
                    + "persistent-session=true, opens=1, windows=\(sessionSummaries.count), rollover-seeks=0, "
                    + "pending-fifo=\(maximumPendingPacketCount)/\(maximumPendingPacketBytes), "
                    + "seek-first-pts>=1=true, eof-ended=true, no-loop=true, "
                    + "offline=true, retry=true, seek-clamp=true, renderer-errors=0, finite-downloads=true, "
                    + "full-downloads=0, cleanup=true; \(mainTrackProof)"
            } catch {
                failure = error
                result = "VOD FFmpeg controller probe failed: \(error)"
                if let player {
                    await player.close()
                    player.surfaceView.removeFromSuperview()
                }
            }

            if let resultURL {
                try? Data(result.utf8).write(to: resultURL, options: .atomic)
            }
            log(result)
            if failure != nil {
                assertionFailure(result)
            }
        }

        @MainActor static func runMainTrackProbe(in window: UIWindow) async {
            let result: String
            do {
                result = try await "VOD main-track probe: \(verifyMainTrackTimeline(in: window))"
            } catch {
                result = "VOD main-track probe failed: \(error)"
            }
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? Data(result.utf8).write(
                    to: directory.appendingPathComponent("vod-main-track-probe.txt"),
                    options: .atomic,
                )
            }
            log(result)
        }

        @MainActor static func verifyMainTrackTimeline(in window: UIWindow) async throws -> String {
            let fixtureURL = FileManager.default
.temporaryDirectory
                .appendingPathComponent("bettertg-vod-main-track-\(UUID().uuidString).webm")
            defer { try? FileManager.default.removeItem(at: fixtureURL) }
            try FFmpegVODShortVideoProbeFixture.write(to: fixtureURL)
            let fixtureData = try Data(contentsOf: fixtureURL)
            let checksum = SHA256.hash(data: fixtureData).map { String(format: "%02x", $0) }.joined()
            guard checksum == FFmpegVODShortVideoProbeFixture.sha256 else {
                throw Failure.decoding("Short-video fixture checksum mismatch")
            }
            let size = Int64(fixtureData.count)
            let network = TDLibVODProbeNetwork(available: true)
            let backend = TDLibVODProbeBackend(fileURL: fixtureURL, fileSize: size, network: network)
            await backend.setAutoFulfill(true)
            let coordinator = TDLibVODRangeCoordinator(
                accountID: "probe-vod-main-track",
                client: backend.client,
                requestTimeout: .seconds(2),
            )
            var activePlayer: TDLibVODFFmpegSampleBufferPlayer?
            do {
                let player = await TDLibVODFFmpegSampleBufferPlayer(
                    lease: coordinator.acquire(file: backend.file(expectedSize: size)),
                    decodeWindowDuration: 0.731,
                )
                activePlayer = player
                player.surfaceView.frame = CGRect(x: 8, y: window.safeAreaInsets.top + 8, width: 192, height: 108)
                player.surfaceView.isUserInteractionEnabled = false
                window.addSubview(player.surfaceView)
                let recorder = ProbeRecorder(player: player)
                player.setMuted(true)
                player.setPlaybackVisible(true)
                player.prepare(autoplay: true)
                try await waitUntil { player.state == .ended || player.failureSubject.value != nil }
                let snapshot = player.renderer.snapshot()
                let summaries = player.debugDecoderSummaries
                let naturalEnd = player.state == .ended
                    && player.failureSubject.value == nil
                    && recorder.states.contains(.playing)
                    && abs(player.duration - 2) < 0.01
                    && abs(player.currentTime - 2) < 0.01
                    && player.audioEndTime > 10
                    && abs(player.videoEndTime - 2) < 0.01
                    && abs(snapshot.videoAcceptedUntil - 2) < 0.001
                    && abs(snapshot.audioAcceptedUntil - 2) < 0.001
                    && summaries.count >= 2
                    && Set(summaries.map(\.sessionID)).count == 1
                    && summaries.allSatisfy { $0.openCount == 1 && $0.explicitSeekCount == 0 }
                    && summaries.last?.isEnded == true
                    && summaries.last?.videoFrameCount == 20
                    && summaries.allSatisfy {
                        $0.maximumPendingPacketCount <= 4096
                            && $0.maximumPendingPacketBytes <= 32 * 1024 * 1024
                    }
                guard naturalEnd else {
                    throw Failure.decoding(
                        "Short video natural end: state=\(player.state), time=\(player.currentTime), "
                        + "duration=\(player.duration), snapshot=\(snapshot), summaries=\(summaries)",
                    )
                }
                var seekCompletions = 0
                player.seek(to: 6) { seekCompletions += 1 }
                try await waitUntil {
                    seekCompletions == 1 && player.state == .ended || player.failureSubject.value != nil
                }
                guard seekCompletions == 1, player.state == .ended,
                      player.failureSubject.value == nil, abs(player.currentTime - 2) < 0.01,
                      abs(player.duration - 2) < 0.01
                else { throw Failure.decoding("Known-duration seek did not clamp to video end") }
                await player.close()
                player.surfaceView.removeFromSuperview()

                let initialSeekPlayer = await TDLibVODFFmpegSampleBufferPlayer(
                    lease: coordinator.acquire(file: backend.file(expectedSize: size)),
                )
                activePlayer = initialSeekPlayer
                initialSeekPlayer.setPlaybackVisible(true)
                initialSeekPlayer.prepare(autoplay: true, initialTime: 6)
                try await waitUntil {
                    initialSeekPlayer.state == .ended || initialSeekPlayer.failureSubject.value != nil
                }
                guard initialSeekPlayer.state == .ended, initialSeekPlayer.failureSubject.value == nil,
                      initialSeekPlayer.videoWatchdogTask == nil,
                      abs(initialSeekPlayer.duration - 2) < 0.01,
                      abs(initialSeekPlayer.currentTime - 2) < 0.01
                else { throw Failure.decoding("Initial unknown-duration seek did not clamp to video end") }
                await initialSeekPlayer.close()
                activePlayer = nil
                let downloads = await backend.downloadCalls
                guard downloads.allSatisfy({ !$0.isFullDownload }) else {
                    throw Failure.decoding("Main-track probe requested a full download")
                }
                let fallbackProof = try await verifyEstimatedMainTrackTimeline(in: window)
                let overestimateProof = try await verifyEstimatedMainTrackTimeline(
                    in: window,
                    estimatedDuration: 20,
                )
                let beyondEOFProof = try await verifyEstimatedMainTrackTimeline(
                    in: window,
                    estimatedDuration: 20,
                    initialTime: 25,
                )
                return "main-track=video, fixture-sha256=\(checksum), video=2s/audio=10.008s, "
                    + "natural-end=2s, video-frames=20, audio-tail-clipped=true, "
                    + "known-seek6->2=true, initial-seek6->2=true, persistent-session=true, "
                    + "bounded-queues=true, finite-downloads=true, cleanup=true; "
                    + "\(fallbackProof); \(overestimateProof); \(beyondEOFProof)"
            } catch {
                if let activePlayer {
                    await activePlayer.close()
                    activePlayer.surfaceView.removeFromSuperview()
                }
                throw error
            }
        }

        @MainActor static func verifyEstimatedMainTrackTimeline(
            in window: UIWindow,
            estimatedDuration: TimeInterval = 8,
            initialTime: TimeInterval = 9,
        ) async throws -> String {
            let fixtureURL = FileManager.default
.temporaryDirectory
                .appendingPathComponent("bettertg-vod-estimated-duration-\(UUID().uuidString).webm")
            defer { try? FileManager.default.removeItem(at: fixtureURL) }
            try FFmpegVODUnknownDurationProbeFixture.write(to: fixtureURL, estimatedDuration: estimatedDuration)
            let fixtureData = try Data(contentsOf: fixtureURL)
            let checksum = SHA256.hash(data: fixtureData).map { String(format: "%02x", $0) }.joined()
            let expectedChecksum = estimatedDuration == 8
                ? FFmpegVODUnknownDurationProbeFixture.sha256
                : FFmpegVODUnknownDurationProbeFixture.overestimatedSHA256
            guard checksum == expectedChecksum else {
                throw Failure.decoding("Unknown-duration fixture checksum mismatch")
            }
            let size = Int64(fixtureData.count)
            let backend = TDLibVODProbeBackend(
                fileURL: fixtureURL,
                fileSize: size,
                network: TDLibVODProbeNetwork(available: true),
            )
            await backend.setAutoFulfill(true)
            let coordinator = TDLibVODRangeCoordinator(
                accountID: "probe-vod-estimated-duration",
                client: backend.client,
                requestTimeout: .seconds(2),
            )
            let player = await TDLibVODFFmpegSampleBufferPlayer(
                lease: coordinator.acquire(file: backend.file(expectedSize: size)),
                decodeWindowDuration: 0.731,
            )
            player.surfaceView.frame = CGRect(x: 8, y: window.safeAreaInsets.top + 8, width: 192, height: 108)
            player.surfaceView.isUserInteractionEnabled = false
            window.addSubview(player.surfaceView)
            do {
                let recorder = ProbeRecorder(player: player)
                player.setMuted(true)
                player.setRate(2)
                player.setPlaybackVisible(true)
                player.prepare(autoplay: true, initialTime: initialTime)
                try await waitUntil { player.state == .ended || player.failureSubject.value != nil }
                let snapshot = player.renderer.snapshot()
                let summaries = player.debugDecoderSummaries
                let expectsFrames = initialTime < 12
                let receivedExpectedFrames = expectsFrames
                    ? recorder.states.contains(.playing)
                        && snapshot.videoFirstPresentationTime.map { $0 >= initialTime } == true
                        && abs(snapshot.videoAcceptedUntil - 12) < 0.01
                        && summaries.count >= 2
                    : !snapshot.hasVideoInput && summaries.last?.videoFrameCount == 0
                guard player.state == .ended, player.failureSubject.value == nil,
                      player.videoWatchdogTask == nil,
                      receivedExpectedFrames, !player.hasExplicitDuration,
                      abs(player.videoEndTime - estimatedDuration) < 0.01,
                      abs(player.duration - 12) < 0.01, abs(player.currentTime - 12) < 0.01,
                      Set(summaries.map(\.sessionID)).count == 1,
                      summaries.allSatisfy({ !$0.hasExplicitDuration && $0.openCount == 1 }),
                      summaries.last?.isEnded == true,
                      summaries.last?.hasFinalDuration == true,
                      summaries.last.map({ abs($0.duration - 12) < 0.01 }) == true
                else {
                    throw Failure.decoding("Unknown main duration: state=\(player.state), time=\(player.currentTime), "
                        + "duration=\(player.duration), snapshot=\(snapshot), summaries=\(summaries)")
                }
                await player.close()
                player.surfaceView.removeFromSuperview()
                guard await backend.downloadCalls.allSatisfy({ !$0.isFullDownload }) else {
                    throw Failure.decoding("Unknown-duration probe requested a full download")
                }
                return "unknown-video-duration=true, mixed-fixture-sha256=\(checksum), "
                    + "fallback=\(estimatedDuration)->12s, initial-seek=\(initialTime), "
                    + "verified-eof=12s, expected-frames=\(expectsFrames), cleanup=true"
            } catch {
                await player.close()
                player.surfaceView.removeFromSuperview()
                throw error
            }
        }

        @MainActor static func waitUntil(
            timeout: Duration = .seconds(8),
            condition: () async -> Bool,
        ) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)
            while clock.now < deadline {
                if await condition() {
                    return
                }
                try await Task<Never, Never>.sleep(for: .milliseconds(20))
            }
            throw Failure.decoding("Controller probe timed out")
        }
    }
#endif

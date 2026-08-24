// LocalMediaPlayer.swift

import AVFoundation
import Combine
import UIKit

// MARK: - LocalMediaPlayer

final class LocalMediaPlayer {
    // MARK: Lifecycle

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        self.timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main,
        ) { [weak self] time in
            guard time.seconds.isFinite else { return }
            self?.timeSubject.send(max(0, time.seconds))
            self?.updateVODBufferingState()
        }
        player.publisher(for: \.timeControlStatus, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.update(timeControlStatus: status) }
            .store(in: &cancellables)
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        compositionLease = nil
        vodSession?.invalidate()
        vodSession = nil
    }

    // MARK: Internal

    enum State: Equatable {
        case idle
        case preparing
        case buffering
        case playing
        case paused
        case ended
        case failed
    }

    var statePublisher: AnyPublisher<State, Never> {
        stateSubject.removeDuplicates().eraseToAnyPublisher()
    }

    var timePublisher: AnyPublisher<TimeInterval, Never> {
        timeSubject.eraseToAnyPublisher()
    }

    var loopPublisher: AnyPublisher<Void, Never> {
        loopSubject.eraseToAnyPublisher()
    }

    var hasItem: Bool {
        player.currentItem != nil
    }

    var isPlaybackRequested: Bool {
        shouldAutoplay
    }

    var currentItemIdentifier: ObjectIdentifier? {
        player.currentItem.map(ObjectIdentifier.init)
    }

    var duration: TimeInterval {
        guard let seconds = player.currentItem?.duration.seconds, seconds.isFinite else { return 0 }
        return max(0, seconds)
    }

    func attach(to layer: AVPlayerLayer) {
        layer.player = player
    }

    func load(
        url: URL,
        autoplay: Bool,
        loops: Bool = false,
        prefersFFmpegAudioFallback: Bool = false,
        initialTime: TimeInterval = 0,
    ) {
        prepareForLoad(autoplay: autoplay, loops: loops, playbackRange: nil)
        if initialTime.isFinite, initialTime > 0 {
            pendingSeek = (initialTime, 0, false, nil)
            timeSubject.send(initialTime)
        }

        let requestIdentifier = UUID()
        currentRequestIdentifier = requestIdentifier
        guard prefersFFmpegAudioFallback else {
            installItem(url: url)
            return
        }
        preparationTask = Task { @MainActor [weak self] in
            let playableURL = await FFmpegAudioPlaybackCache.shared.playableURL(for: url)
            guard let self,
                  !Task.isCancelled,
                  currentRequestIdentifier == requestIdentifier
            else { return }
            installItem(url: playableURL)
            preparationTask = nil
        }
    }

    func load(
        composition: VideoNoteCompositionResult,
        autoplay: Bool,
        loops: Bool = false,
        playbackRange: Range<TimeInterval>? = nil,
    ) {
        prepareForLoad(autoplay: autoplay, loops: loops, playbackRange: playbackRange)
        currentRequestIdentifier = UUID()
        compositionLease = composition
        installItem(asset: composition.asset)
    }

    func load(
        vodSession: TDLibVODResourceLoaderSession,
        autoplay: Bool,
        loops: Bool = false,
        initialTime: TimeInterval = 0,
    ) {
        prepareForLoad(autoplay: autoplay, loops: loops, playbackRange: nil)
        currentRequestIdentifier = UUID()
        usesExplicitVODBuffering = true
        player.automaticallyWaitsToMinimizeStalling = false
        self.vodSession = vodSession
        if initialTime.isFinite, initialTime > 0 {
            pendingSeek = (initialTime, 0, false, nil)
            timeSubject.send(initialTime)
        }
        let item = AVPlayerItem(asset: vodSession.asset)
        item.preferredForwardBufferDuration = 10
        installItem(item)
    }

    func play() {
        shouldAutoplay = true
        guard hasItem else { return }
        if stateSubject.value == .ended {
            shouldApplyReadyStateAfterSeek = true
            seek(to: playbackRange?.lowerBound ?? 0, tolerance: 0)
            return
        }
        if usesExplicitVODBuffering {
            updateVODBufferingState()
            return
        }
        if let playbackRange {
            let current = player.currentTime().seconds
            if !current.isFinite
                || current < playbackRange.lowerBound - 0.001
                || current >= playbackRange.upperBound - 0.001
            {
                shouldApplyReadyStateAfterSeek = true
                seek(to: playbackRange.lowerBound, tolerance: 0)
                return
            }
        }
        player.play()
    }

    func pause() {
        shouldAutoplay = false
        guard hasItem else { return }
        if usesExplicitVODBuffering {
            player.cancelPendingPrerolls()
            vodPrerollIdentifier = nil
        }
        player.pause()
        if stateSubject.value != .failed, stateSubject.value != .ended {
            stateSubject.send(.paused)
        }
    }

    func play(from time: TimeInterval, tolerance: TimeInterval = 0) {
        shouldAutoplay = true
        shouldApplyReadyStateAfterSeek = true
        seek(to: time, tolerance: tolerance)
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    func stop() {
        preparationTask?.cancel()
        preparationTask = nil
        currentRequestIdentifier = nil
        pendingSeek = nil
        shouldAutoplay = false
        shouldLoop = false
        playbackRange = nil
        currentSeekIdentifier = nil
        vodPrerollIdentifier = nil
        shouldApplyReadyStateAfterSeek = false
        player.cancelPendingPrerolls()
        player.pause()
        player.replaceCurrentItem(with: nil)
        compositionLease = nil
        vodSession?.invalidate()
        vodSession = nil
        usesExplicitVODBuffering = false
        player.automaticallyWaitsToMinimizeStalling = true
        resetItemObservers()
        timeSubject.send(0)
        stateSubject.send(.idle)
    }

    func seek(
        to time: TimeInterval,
        tolerance: TimeInterval = 0.05,
        constrainedToPlaybackRange: Bool = true,
        completion: (() -> Void)? = nil,
    ) {
        let nonnegativeTime = max(0, time)
        let boundedToRange =
            if constrainedToPlaybackRange {
                playbackRange.map {
                    min($0.upperBound, max($0.lowerBound, nonnegativeTime))
                } ?? nonnegativeTime
            } else {
                nonnegativeTime
            }
        guard let item = player.currentItem, item.status == .readyToPlay else {
            pendingSeek = (
                boundedToRange,
                max(0, tolerance),
                constrainedToPlaybackRange,
                completion,
            )
            return
        }
        let boundedTime = duration > 0 ? min(boundedToRange, duration) : boundedToRange
        let seekIdentifier = UUID()
        currentSeekIdentifier = seekIdentifier
        item.cancelPendingSeeks()
        if usesExplicitVODBuffering, shouldAutoplay {
            player.cancelPendingPrerolls()
            vodPrerollIdentifier = nil
            shouldApplyReadyStateAfterSeek = true
            player.pause()
            stateSubject.send(.buffering)
        }
        let seekTolerance = CMTime(seconds: max(0, tolerance), preferredTimescale: 600)
        player.seek(
            to: CMTime(seconds: boundedTime, preferredTimescale: 600),
            toleranceBefore: seekTolerance,
            toleranceAfter: seekTolerance,
        ) { [weak self, weak item] _ in
            DispatchQueue.main.async {
                guard let self,
                      item === self.player.currentItem,
                      self.currentSeekIdentifier == seekIdentifier
                else { return }
                self.currentSeekIdentifier = nil
                completion?()
                if self.shouldApplyReadyStateAfterSeek {
                    self.shouldApplyReadyStateAfterSeek = false
                    self.applyReadyPlaybackState()
                }
            }
        }
    }

    func setPlaybackRange(_ range: Range<TimeInterval>?) {
        playbackRange = normalizedPlaybackRange(range)
        applyPlaybackRange(to: player.currentItem)
    }

    func jump(by interval: TimeInterval) {
        let current = player.currentTime().seconds
        seek(to: (current.isFinite ? current : 0) + interval)
    }

    // MARK: Private

    private let player = AVPlayer()
    private let stateSubject = CurrentValueSubject<State, Never>(.idle)
    private let timeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let loopSubject = PassthroughSubject<Void, Never>()
    private var shouldAutoplay = false
    private var shouldLoop = false
    private var shouldApplyReadyStateAfterSeek = false
    private var playbackRange: Range<TimeInterval>?
    private var timeObserver: Any?
    private var preparationTask: Task<Void, Never>?
    private var currentRequestIdentifier: UUID?
    private var compositionLease: VideoNoteCompositionResult?
    private var vodSession: TDLibVODResourceLoaderSession?
    private var usesExplicitVODBuffering = false
    private var vodPrerollIdentifier: UUID?
    private var pendingSeek: (
        time: TimeInterval,
        tolerance: TimeInterval,
        constrainedToPlaybackRange: Bool,
        completion: (() -> Void)?,
    )?
    private var currentSeekIdentifier: UUID?
    private var itemCancellables = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()

    private var hasSufficientVODBuffer: Bool {
        guard let item = player.currentItem else { return false }
        let current = player.currentTime().seconds
        guard current.isFinite else { return false }
        var bufferedEnd = current
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = range.end.seconds
            guard start.isFinite, end.isFinite,
                  start <= current + 0.05,
                  end >= current - 0.05
            else { continue }
            bufferedEnd = max(bufferedEnd, end)
        }
        let duration = item.duration.seconds
        let bufferedUntilEnd = duration.isFinite
            && duration > 0
            && bufferedEnd >= duration - 0.05
        return bufferedUntilEnd || max(0, bufferedEnd - current) >= 1
    }

    private func observe(item: AVPlayerItem) {
        item.publisher(for: \.status, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard let self, item === player.currentItem else { return }
                switch status {
                case .unknown:
                    stateSubject.send(.preparing)
                case .readyToPlay:
                    if let pendingSeek {
                        self.pendingSeek = nil
                        shouldApplyReadyStateAfterSeek = true
                        seek(
                            to: pendingSeek.time,
                            tolerance: pendingSeek.tolerance,
                            constrainedToPlaybackRange: pendingSeek.constrainedToPlaybackRange,
                        ) { [weak self, weak item] in
                            guard let self, item === player.currentItem else { return }
                            pendingSeek.completion?()
                        }
                    } else {
                        applyReadyPlaybackState()
                    }
                case .failed:
                    shouldAutoplay = false
                    stateSubject.send(.failed)
                @unknown default:
                    shouldAutoplay = false
                    stateSubject.send(.failed)
                }
            }
            .store(in: &itemCancellables)

        item.publisher(for: \.loadedTimeRanges, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                guard let self, item === player.currentItem else { return }
                updateVODBufferingState()
            }
            .store(in: &itemCancellables)

        item.publisher(for: \.isPlaybackBufferEmpty, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                guard let self, item === player.currentItem else { return }
                updateVODBufferingState()
            }
            .store(in: &itemCancellables)

        item.publisher(for: \.isPlaybackLikelyToKeepUp, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                guard let self, item === player.currentItem else { return }
                updateVODBufferingState()
            }
            .store(in: &itemCancellables)

        NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                guard let self, item === player.currentItem else { return }
                if shouldLoop {
                    loopSubject.send()
                    shouldApplyReadyStateAfterSeek = true
                    seek(to: playbackRange?.lowerBound ?? 0, tolerance: 0)
                } else {
                    shouldAutoplay = false
                    stateSubject.send(.ended)
                }
            }
            .store(in: &itemCancellables)

        NotificationCenter.default
            .publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                guard let self, item === player.currentItem else { return }
                shouldAutoplay = false
                stateSubject.send(.failed)
            }
            .store(in: &itemCancellables)
    }

    private func installItem(url: URL) {
        installItem(AVPlayerItem(url: url))
    }

    private func installItem(asset: AVAsset) {
        installItem(AVPlayerItem(asset: asset))
    }

    private func installItem(_ item: AVPlayerItem) {
        applyPlaybackRange(to: item)
        observe(item: item)
        player.replaceCurrentItem(with: item)
    }

    private func prepareForLoad(
        autoplay: Bool,
        loops: Bool,
        playbackRange: Range<TimeInterval>?,
    ) {
        preparationTask?.cancel()
        preparationTask = nil
        pendingSeek = nil
        currentSeekIdentifier = nil
        vodPrerollIdentifier = nil
        shouldApplyReadyStateAfterSeek = false
        resetItemObservers()
        player.currentItem?.cancelPendingSeeks()
        player.cancelPendingPrerolls()
        player.pause()
        player.replaceCurrentItem(with: nil)
        compositionLease = nil
        vodSession?.invalidate()
        vodSession = nil
        usesExplicitVODBuffering = false
        player.automaticallyWaitsToMinimizeStalling = true
        shouldAutoplay = autoplay
        shouldLoop = loops
        self.playbackRange = normalizedPlaybackRange(playbackRange)
        if let playbackRange = self.playbackRange, playbackRange.lowerBound > 0 {
            pendingSeek = (playbackRange.lowerBound, 0, true, nil)
        }
        timeSubject.send(self.playbackRange?.lowerBound ?? 0)
        stateSubject.send(.preparing)
    }

    private func normalizedPlaybackRange(
        _ range: Range<TimeInterval>?,
    ) -> Range<TimeInterval>? {
        guard let range,
              range.lowerBound.isFinite,
              range.upperBound.isFinite,
              range.lowerBound >= 0,
              range.upperBound > range.lowerBound
        else { return nil }
        return range
    }

    private func applyPlaybackRange(to item: AVPlayerItem?) {
        guard let item else { return }
        item.forwardPlaybackEndTime = playbackRange.map {
            CMTime(seconds: $0.upperBound, preferredTimescale: 600)
        } ?? .invalid
    }

    private func applyReadyPlaybackState() {
        if shouldAutoplay {
            if usesExplicitVODBuffering {
                updateVODBufferingState()
            } else {
                player.play()
            }
        } else {
            stateSubject.send(.paused)
        }
    }

    private func resetItemObservers() {
        itemCancellables.removeAll()
    }

    private func update(timeControlStatus: AVPlayer.TimeControlStatus) {
        guard player.currentItem != nil else { return }
        switch timeControlStatus {
        case .paused:
            if usesExplicitVODBuffering, shouldAutoplay, player.currentItem?.status == .readyToPlay {
                if !hasSufficientVODBuffer {
                    stateSubject.send(.buffering)
                }
            } else if stateSubject.value != .preparing,
                      stateSubject.value != .ended,
                      stateSubject.value != .failed
            {
                stateSubject.send(.paused)
            }
        case .waitingToPlayAtSpecifiedRate:
            if stateSubject.value != .failed {
                stateSubject.send(.buffering)
            }
        case .playing:
            stateSubject.send(.playing)
        @unknown default:
            break
        }
    }

    private func updateVODBufferingState() {
        guard usesExplicitVODBuffering,
              let item = player.currentItem,
              item.status == .readyToPlay,
              stateSubject.value != .failed,
              stateSubject.value != .ended
        else { return }
        guard shouldAutoplay else {
            if stateSubject.value != .paused {
                stateSubject.send(.paused)
            }
            return
        }
        if hasSufficientVODBuffer {
            player.cancelPendingPrerolls()
            vodPrerollIdentifier = nil
            if player.timeControlStatus != .playing {
                player.play()
            }
        } else {
            if player.timeControlStatus == .playing {
                player.pause()
            }
            stateSubject.send(.buffering)
            beginVODPrerollIfNeeded(item: item)
        }
    }

    private func beginVODPrerollIfNeeded(item: AVPlayerItem) {
        guard shouldAutoplay, vodPrerollIdentifier == nil else { return }
        let identifier = UUID()
        vodPrerollIdentifier = identifier
        player.preroll(atRate: 1) { [weak self, weak item] finished in
            DispatchQueue.main.async {
                guard let self,
                      item === self.player.currentItem,
                      self.vodPrerollIdentifier == identifier
                else { return }
                self.vodPrerollIdentifier = nil
                if finished {
                    self.updateVODBufferingState()
                }
            }
        }
    }
}

// MARK: - LocalVideoSurfaceView

final class LocalVideoSurfaceView: UIView {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            preconditionFailure("LocalVideoSurfaceView must be backed by AVPlayerLayer")
        }
        return layer
    }
}

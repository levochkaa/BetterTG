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

    var hasItem: Bool {
        player.currentItem != nil
    }

    var isPlaybackRequested: Bool {
        shouldAutoplay
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
    ) {
        prepareForLoad(autoplay: autoplay, loops: loops, playbackRange: nil)

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

    func play() {
        shouldAutoplay = true
        guard hasItem else { return }
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
        shouldApplyReadyStateAfterSeek = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        compositionLease = nil
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
        let boundedToRange = if constrainedToPlaybackRange {
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
    private var shouldAutoplay = false
    private var shouldLoop = false
    private var shouldApplyReadyStateAfterSeek = false
    private var playbackRange: Range<TimeInterval>?
    private var timeObserver: Any?
    private var preparationTask: Task<Void, Never>?
    private var currentRequestIdentifier: UUID?
    private var compositionLease: VideoNoteCompositionResult?
    private var pendingSeek: (
        time: TimeInterval,
        tolerance: TimeInterval,
        constrainedToPlaybackRange: Bool,
        completion: (() -> Void)?
    )?
    private var currentSeekIdentifier: UUID?
    private var itemCancellables = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()

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

        NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                guard let self, item === player.currentItem else { return }
                if shouldLoop {
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
        shouldApplyReadyStateAfterSeek = false
        resetItemObservers()
        player.currentItem?.cancelPendingSeeks()
        player.pause()
        player.replaceCurrentItem(with: nil)
        compositionLease = nil
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
            player.play()
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
            if stateSubject.value != .preparing,
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

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

    var duration: TimeInterval {
        guard let seconds = player.currentItem?.duration.seconds, seconds.isFinite else { return 0 }
        return max(0, seconds)
    }

    func attach(to layer: AVPlayerLayer) {
        layer.player = player
    }

    func load(url: URL, autoplay: Bool, loops: Bool = false) {
        resetItemObservers()
        shouldAutoplay = autoplay
        shouldLoop = loops
        timeSubject.send(0)
        stateSubject.send(.preparing)

        let item = AVPlayerItem(url: url)
        observe(item: item)
        player.replaceCurrentItem(with: item)
    }

    func play() {
        guard hasItem else { return }
        shouldAutoplay = true
        player.play()
    }

    func pause() {
        guard hasItem else { return }
        shouldAutoplay = false
        player.pause()
        if stateSubject.value != .failed, stateSubject.value != .ended {
            stateSubject.send(.paused)
        }
    }

    func stop() {
        shouldAutoplay = false
        shouldLoop = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        resetItemObservers()
        timeSubject.send(0)
        stateSubject.send(.idle)
    }

    func seek(to time: TimeInterval, completion: (() -> Void)? = nil) {
        guard hasItem else {
            completion?()
            return
        }
        let nonnegativeTime = max(0, time)
        let boundedTime = duration > 0 ? min(nonnegativeTime, duration) : nonnegativeTime
        player.seek(
            to: CMTime(seconds: boundedTime, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.05, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600),
        ) { _ in
            DispatchQueue.main.async { completion?() }
        }
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
    private var timeObserver: Any?
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
                    if shouldAutoplay {
                        player.play()
                    } else {
                        stateSubject.send(.paused)
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
                    seek(to: 0) { [weak self] in self?.play() }
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

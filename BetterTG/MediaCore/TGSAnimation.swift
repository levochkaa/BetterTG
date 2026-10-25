// TGSAnimation.swift

import Combine
import Foundation
import Lottie
import QuartzCore
import TDLibKit
import UIKit

// MARK: - TGSAnimationRepository

enum TGSAnimationRepository {
    // MARK: Private

    private static let cache: NSCache<NSString, LottieAnimation> = {
        let cache = NSCache<NSString, LottieAnimation>()
        cache.countLimit = 64
        return cache
    }()

    // MARK: Internal

    static func animation(at path: String) async -> LottieAnimation? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let decodeTask = Task.detached(priority: .userInitiated) { () -> LottieAnimation? in
            guard !Task.isCancelled,
                  let compressed = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
                  !Task.isCancelled,
                  let json = try? decompressTGS(compressed),
                  !Task.isCancelled,
                  let animation = try? LottieAnimation.from(data: json, strategy: .legacyCodable)
            else { return nil }
            cache.setObject(animation, forKey: key)
            return animation
        }

        return await withTaskCancellationHandler {
            await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }
    }
}

// MARK: - TGSStickerView

final class TGSStickerView: UIControl, AnimatedFileView {
    /// How the sticker plays once loaded. Dice use the play-once and still-end modes, as Telegram's
    /// ManagedDiceAnimationNode plays a fresh roll once and shows an old roll at its last frame.
    enum PlaybackMode: Equatable {
        case loop
        /// Plays from the point the roll reached since `startedAt` (a `CACurrentMediaTime` value) to the end and
        /// holds the last frame.
        case once(startedAt: CFTimeInterval)
        case stillEnd
    }

    // MARK: Internal

    var onFirstFrameReady: (() -> Void)?

    var energySaving: EnergySavingRole? {
        didSet { energySavingChanged() }
    }

    var playbackMode = PlaybackMode.loop {
        didSet {
            guard playbackMode != oldValue, let animation = animationView.animation else { return }
            animationView.stop()
            animationView.currentProgress = initialProgress(for: animation)
            animationView.forceDisplayUpdate()
            updatePlayback()
        }
    }

    // MARK: Private

    private let thumbnailView = TDImageLoadingView()
    private let animationView = LottieAnimationView(configuration: LottieConfiguration(
        renderingEngine: .automatic,
        decodingStrategy: .legacyCodable,
    ))
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 180)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 180)
    private var representedFileID: Int?
    private var loadedPath: String?
    private var playbackVisible = false
    /// A looping sticker held to one pass by Power Saving has played it.
    private var energyPassPlayed = false
    private var onTap: (() -> Void)?
    private var fileRequest: AnimatedFileDownload?
    private var decodeTask: Task<Void, Never>?
    /// The layer time a hold stopped the animation at.
    private var frozenClockTime: CFTimeInterval?

    /// The decoded animation's frames per second, once it has loaded.
    var framerate: Double? {
        animationView.animation?.framerate
    }

    private var playbackEnabled: Bool {
        UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFit
        addSubview(thumbnailView)

        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.contentMode = .scaleAspectFit
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.isHidden = true
        animationView.isUserInteractionEnabled = false
        addSubview(animationView)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor),
            animationView.topAnchor.constraint(equalTo: topAnchor),
            animationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: trailingAnchor),
            animationView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityLabel = L10n.telegram("VoiceOver.Chat.AnimatedSticker")
        accessibilityTraits = .image
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackHoldChanged),
            name: TGSPlaybackHold.didChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(energySavingChanged),
            name: EnergyUsage.didChange,
            object: nil,
        )
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        decodeTask?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    func configure(
        file: File,
        client: TDLibClient,
        thumbnail: Thumbnail?,
        displaySize: CGSize?,
        onTap: (() -> Void)?,
    ) {
        prepareForReuse()
        guard let request = AnimatedFileDownload(fileID: file.id, client: client) else { return }
        fileRequest = request
        representedFileID = file.id
        self.onTap = onTap
        isUserInteractionEnabled = onTap != nil
        apply(displaySize: displaySize)

        if let thumbnail {
            thumbnailView.load(file: thumbnail.file, accountID: request.source.accountID, client: client)
        }

        request.start(file: file, onFile: { [weak self, weak request] file in
            guard let self, let request, fileRequest === request else { return }
            update(file: file)
        }, onInvalidated: { [weak self, weak request] in
            guard let self, let request, fileRequest === request else { return }
            prepareForReuse()
        })
    }

    func prepareForReuse() {
        fileRequest?.cancel()
        fileRequest = nil
        representedFileID = nil
        loadedPath = nil
        onTap = nil
        onFirstFrameReady = nil
        isUserInteractionEnabled = false
        playbackVisible = false

        decodeTask?.cancel()
        decodeTask = nil

        thawAnimationClock()
        animationView.stop()
        animationView.animation = nil
        energyPassPlayed = false
        playbackMode = .loop
        animationView.isHidden = true
        thumbnailView.isHidden = false
        thumbnailView.cancel()
        thumbnailView.image = nil

        widthConstraint.isActive = false
        heightConstraint.isActive = false
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        playbackVisible = isVisible
        updatePlayback()
    }

    private func apply(displaySize: CGSize?) {
        guard let displaySize else { return }
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
        widthConstraint.isActive = true
        heightConstraint.isActive = true
    }

    private func update(file: File) {
        guard let request = fileRequest, request.isCurrent,
              representedFileID == file.id,
              file.local.isDownloadingCompleted,
              !file.local.path.isEmpty,
              loadedPath != file.local.path
        else { return }

        loadedPath = file.local.path
        let fileID = file.id
        decodeTask?.cancel()
        decodeTask = Task { [weak self] in
            let animation = await TGSAnimationRepository.animation(at: file.local.path)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled, request.isCurrent,
                      let self, self.fileRequest === request,
                      self.representedFileID == fileID, self.loadedPath == file.local.path
                else { return }
                self.show(animation: animation)
            }
        }
    }

    private func show(animation: LottieAnimation?) {
        guard let animation else {
            animationView.stop()
            animationView.animation = nil
            animationView.isHidden = true
            thumbnailView.isHidden = false
            return
        }

        animationView.animation = animation
        animationView.currentProgress = initialProgress(for: animation)
        animationView.forceDisplayUpdate()
        animationView.isHidden = false
        thumbnailView.isHidden = true
        onFirstFrameReady?()
        onFirstFrameReady = nil
        updatePlayback()
    }

    private func updatePlayback() {
        if case .stillEnd = playbackMode {
            animationView.pause()
            return
        }
        if case .once = playbackMode, !playbackEnabled, animationView.animation != nil {
            // With autoplay off the result stays readable at the roll's last frame.
            animationView.pause()
            animationView.currentProgress = 1
            return
        }
        let shouldPlay = fileRequest?.isCurrent == true && playbackVisible && window != nil
            && playbackEnabled && animationView.animation != nil && !TGSPlaybackHold.isActive
        if case .loop = playbackMode, let limit = energySaving?.limit {
            // Power Saving: a single pass from the first frame, or the first frame alone.
            guard shouldPlay, limit == .once, !energyPassPlayed else {
                animationView.pause()
                return
            }
            guard !animationView.isAnimationPlaying else { return }
            animationView.play(
                fromProgress: animationView.currentProgress,
                toProgress: 1,
                loopMode: .playOnce,
            ) { [weak self] finished in
                guard finished, let self else { return }
                energyPassPlayed = true
            }
            return
        }
        if shouldPlay {
            guard !animationView.isAnimationPlaying else { return }
            if case .once = playbackMode {
                playOnce()
            } else {
                playSynchronized()
            }
        } else {
            animationView.pause()
        }
    }

    private func playOnce() {
        guard animationView.currentProgress < 1 else { return }
        animationView.play(
            fromProgress: animationView.currentProgress,
            toProgress: 1,
            loopMode: .playOnce,
        ) { [weak self] finished in
            guard finished, let self, case .once = playbackMode else { return }
            animationView.currentProgress = 1
        }
    }

    private func initialProgress(for animation: LottieAnimation) -> AnimationProgressTime {
        switch playbackMode {
        case .loop:
            return energySaving?.limit == nil ? synchronizedProgress(for: animation) : 0
        case .stillEnd:
            return 1
        case .once(let startedAt):
            guard animation.duration.isFinite, animation.duration > 0 else { return 1 }
            return min(1, max(0, (CACurrentMediaTime() - startedAt) / animation.duration))
        }
    }

    private func playSynchronized() {
        guard fileRequest?.isCurrent == true, let animation = animationView.animation,
              playbackVisible,
              window != nil,
              playbackEnabled
        else { return }

        // One looping animation starting at the shared phase keeps equal stickers in step. Restarting a play-once
        // animation every cycle rebuilt the Core Animation tree on the main thread each time, and a chat with many
        // animated emoji fell to about 20 frames per second.
        animationView.currentProgress = synchronizedProgress(for: animation)
        animationView.play(fromProgress: 0, toProgress: 1, loopMode: .loop)
    }

    private func synchronizedProgress(for animation: LottieAnimation) -> AnimationProgressTime {
        guard animation.duration.isFinite, animation.duration > 0 else { return 0 }
        return CACurrentMediaTime().truncatingRemainder(dividingBy: animation.duration) / animation.duration
    }

    @objc private func tapped() {
        onTap?()
    }

    /// A role or setting change starts over: the first frame while held, the shared phase while looping.
    @objc private func energySavingChanged() {
        energyPassPlayed = false
        guard case .loop = playbackMode, let animation = animationView.animation else { return }
        animationView.stop()
        animationView.currentProgress = initialProgress(for: animation)
        animationView.forceDisplayUpdate()
        updatePlayback()
    }

    /// Stops the animation's clock on its current frame without telling Lottie. Its Core Animation engine, which
    /// plays most stickers on the render server, rebuilds the whole animation on the main thread to pause and again
    /// to resume; stopping the layer's time costs nothing and resumes on the same frame.
    private func freezeAnimationClock() {
        guard frozenClockTime == nil else { return }
        let layer = animationView.layer
        let time = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = time
        frozenClockTime = time
    }

    private func thawAnimationClock() {
        guard let frozenTime = frozenClockTime else { return }
        frozenClockTime = nil
        let layer = animationView.layer
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - frozenTime
    }

    /// Resumes after a hold, one sticker per frame, so the chat doesn't rebuild every animation in one frame. A hold
    /// that pauses playback stops a playing sticker on its current frame.
    @objc private func playbackHoldChanged() {
        if TGSPlaybackHold.pausesPlayback {
            freezeAnimationClock()
            return
        }
        thawAnimationClock()
        guard !TGSPlaybackHold.isActive, window != nil, playbackVisible, animationView.animation != nil,
              !animationView.isAnimationPlaying
        else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + TGSPlaybackHold.nextResumeDelay()) { [weak self] in
            self?.updatePlayback()
        }
    }
}

// MARK: - TGSPlaybackHold

/// Keeps animated stickers and emoji that start playing on their current frame while a hold is active. Lottie's Core
/// Animation engine builds each animation on the main thread when it starts, and a chat coming back under a closing
/// gallery restarted all of them at once, which delayed the drag and slowed it to about 30 Hz. Telegram renders them
/// off the main thread; here the chat stays on its frames until the gallery has landed.
@MainActor final class TGSPlaybackHold {
    // MARK: Internal

    static let didChange = Notification.Name("TGSPlaybackHoldDidChange")

    // MARK: Private

    private static var activeCount = 0
    private static var pausingCount = 0
    private static var resumeOrder = 0

    static var isActive: Bool { activeCount > 0 }

    /// Whether stickers already playing stop on their current frame too, not only those about to start.
    static var pausesPlayback: Bool { pausingCount > 0 }

    private let pausesPlaying: Bool
    private var isReleased = false

    init(pausesPlaying: Bool = false) {
        self.pausesPlaying = pausesPlaying
        if Self.activeCount == 0 { Self.resumeOrder = 0 }
        Self.activeCount += 1
        guard pausesPlaying else { return }
        Self.pausingCount += 1
        if Self.pausingCount == 1 { NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }

    /// A transition that ends without releasing (for example, a torn-down context) must not freeze stickers.
    isolated deinit { release() }

    /// Spreads resumptions over frames, one per 1/60 s.
    static func nextResumeDelay() -> TimeInterval {
        defer { resumeOrder += 1 }
        return TimeInterval(resumeOrder) / 60
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        if pausesPlaying { Self.pausingCount -= 1 }
        Self.activeCount -= 1
        guard Self.activeCount == 0 else { return }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

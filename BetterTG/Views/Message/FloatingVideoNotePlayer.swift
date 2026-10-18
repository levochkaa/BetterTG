// FloatingVideoNotePlayer.swift

import Combine
import TDLibKit
import UIKit

// MARK: - FloatingVideoNotePlayer

/// Telegram's OverlayInstantVideoNode in the OverlayMediaController: a round video the user started keeps playing in a
/// floating circle once its bubble leaves the screen (scrolled away, or its chat closed or covered), and goes back to
/// the bubble when the bubble shows again, as UniversalVideoManager gives the embedded node priority over the overlay.
/// A tap pauses or resumes it, a drag moves it between the four corners, and a fling off the screen stops it
/// (OverlayMediaControllerNode).
@MainActor final class FloatingVideoNotePlayer {
    // MARK: Internal

    struct Handoff {
        let item: VideoNotePlaybackView.PlaylistItem
        let url: URL
        let time: TimeInterval
        let duration: TimeInterval
        let thumbnail: UIImage?
        let backend: VideoNotePlaybackBackend
    }

    /// Where the bubble picks the video up: the position, and whether it was playing.
    struct Reclaimed {
        let time: TimeInterval
        let isPlaying: Bool
    }

    static let shared = FloatingVideoNotePlayer()

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// The round video in the circle.
    private(set) var item: VideoNotePlaybackView.PlaylistItem?

    // MARK: Private

    private let player = LocalMediaPlayer()
    private let proximityControl = VideoNoteProximityControl()
    private lazy var circle = FloatingVideoNoteView(player: player)
    private var window: FloatingVideoNoteWindow?
    private var backend: VideoNotePlaybackBackend?
    /// OverlayMediaControllerNode's location: x and y are 0 for left and top, 1 for right and bottom. Telegram
    /// starts at the top right and keeps the last corner (`locationByGroup`).
    private var location = CGPoint(x: 1, y: 0)
    private var duration: TimeInterval = 0
    private var hasStartedPlayback = false
    private var keyboardHeight: CGFloat = 0
    private var dragStartOrigin = CGPoint.zero
    private var bindings = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()

    /// The app's own window, whose bounds and insets place the circle.
    private var hostWindow: UIWindow? {
        guard let scene = window?.windowScene ?? Self.activeScene else { return nil }
        return scene.keyWindow.flatMap { $0 is FloatingVideoNoteWindow ? nil : $0 }
            ?? scene.windows.first { !($0 is FloatingVideoNoteWindow) && !$0.isHidden }
    }

    private init() {
        player.setMuted(false)
        player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(state) }
            .store(in: &cancellables)
        player.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self, item != nil, duration > 0 else { return }
                circle.setProgress(time / duration)
            }
            .store(in: &cancellables)
        // A voice note or music taking the shared player replaces the instant video (SharedMediaPlayer).
        Media.shared
            .$isPlaying
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard isPlaying else { return }
                self?.stop(unless: nil)
            }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: .voiceRecordingWillStart)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pause() }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.keyboardChanged(note) }
            .store(in: &cancellables)
        circle.onTap = { [weak self] in self?.togglePlayback() }
        circle.onClose = { [weak self] in self?.tearDown(animated: true) }
        circle.onPan = { [weak self] recognizer in self?.handlePan(recognizer) }
    }

    /// Takes over a round video whose bubble left the screen while it played.
    func adopt(_ handoff: Handoff) {
        guard handoff.backend.isCurrent(), let scene = Self.activeScene else { return }
        if item != nil { tearDown(animated: false) }
        item = handoff.item
        duration = handoff.duration
        backend = handoff.backend
        observe(handoff.backend, item: handoff.item)
        hasStartedPlayback = false
        circle.configure(thumbnail: handoff.thumbnail)
        circle.setProgress(handoff.duration > 0 ? handoff.time / handoff.duration : 0)
        player.load(url: handoff.url, autoplay: false, loops: false)
        player.play(from: handoff.time)
        proximityControl.begin(player: player)
        present(in: scene)
    }

    /// The bubble showing this video again takes it back; nil when the circle holds another one.
    func reclaim(_ item: VideoNotePlaybackView.PlaylistItem) -> Reclaimed? {
        guard self.item == item else { return nil }
        let reclaimed = Reclaimed(time: player.currentTime, isPlaying: player.isPlaybackRequested)
        tearDown(animated: true)
        return reclaimed
    }

    func holds(_ item: VideoNotePlaybackView.PlaylistItem) -> Bool {
        self.item == item
    }

    /// Another round video started in its bubble: Telegram's single media player drops this one.
    func stop(unless item: VideoNotePlaybackView.PlaylistItem?) {
        guard self.item != nil, self.item != item else { return }
        tearDown(animated: true)
    }

    /// Another player takes the audio.
    func pause() {
        guard item != nil else { return }
        proximityControl.end()
        player.pause()
    }

    /// Pauses or resumes the round video in the circle, as a tap on it does.
    func togglePlayback() {
        guard item != nil else { return }
        if player.isPlaybackRequested {
            player.pause()
        } else {
            backend?.takePlayback()
            player.play()
        }
    }

    private func observe(_ backend: VideoNotePlaybackBackend, item: VideoNotePlaybackView.PlaylistItem) {
        bindings.removeAll()
        let accepts: (TdUpdateSource) -> Bool = { [weak self] source in
            self?.item == item && source == item.source && backend.isCurrent()
        }
        backend.observe(&bindings, for: .updateDeleteMessages) { [weak self] event in
            guard accepts(event.source), event.value.chatId == item.chatID,
                  event.value.messageIds.contains(item.messageID) else { return }
            self?.tearDown(animated: true)
        }
        backend.observe(&bindings, for: .updateMessageContent) { [weak self] event in
            guard accepts(event.source), event.value.chatId == item.chatID,
                  event.value.messageId == item.messageID else { return }
            self?.tearDown(animated: true)
        }
        backend.clientChanges
            .sink { [weak self] _ in
                guard let self, self.item == item, !backend.isCurrent() else { return }
                tearDown(animated: false)
            }
            .store(in: &bindings)
    }

    private func render(_ state: LocalMediaPlayer.State) {
        guard let item else { return }
        circle.setPlaying(state == .playing)
        switch state {
        case .playing:
            hasStartedPlayback = true
        case .ended:
            guard hasStartedPlayback else { return }
            // The chat, if still open, continues its playlist (ChatView.playNextPlaylistItem).
            VideoNotePlaybackView.playbackFinished.send(item)
            tearDown(animated: true)
        case .failed:
            tearDown(animated: true)
        default:
            break
        }
    }

    // MARK: Layout

    private func present(in scene: UIWindowScene) {
        let window: FloatingVideoNoteWindow
        if let existing = self.window {
            window = existing
        } else {
            window = FloatingVideoNoteWindow(windowScene: scene)
            window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
            window.backgroundColor = .clear
            let root = UIViewController()
            root.view.backgroundColor = .clear
            window.rootViewController = root
            root.view.addSubview(circle)
            self.window = window
        }
        window.layer.removeAllAnimations()
        window.frame = frame(hidden: true)
        circle.frame = CGRect(origin: .zero, size: window.bounds.size)
        circle.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.isHidden = false
        UIView.animate(
            withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
        ) { window.frame = self.frame(hidden: false) }
    }

    private func tearDown(animated: Bool) {
        proximityControl.end()
        item = nil
        backend = nil
        bindings.removeAll()
        hasStartedPlayback = false
        player.stop()
        guard let window else { return }
        let finish = { [weak self] in
            guard let self, item == nil else { return }
            window.isHidden = true
            circle.configure(thumbnail: nil)
        }
        guard animated, !window.isHidden else {
            finish()
            return
        }
        UIView.animate(
            withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0,
            options: [.beginFromCurrentState],
            animations: { window.frame = self.frame(hidden: true) },
            completion: { _ in finish() },
        )
    }

    /// OverlayInstantVideoNode.preferredSizeForOverlayDisplay.
    private func circleSide(in bounds: CGRect) -> CGFloat {
        min(bounds.width, bounds.height) > 320 ? 150 : 120
    }

    /// OverlayMediaControllerNode.nodePosition: below the status bar and a navigation bar, above the input and 48 pt,
    /// 4 pt from the side; a hidden circle waits just past its side.
    private func frame(hidden: Bool, at location: CGPoint? = nil) -> CGRect {
        guard let host = hostWindow else { return .zero }
        let location = location ?? self.location
        let bounds = host.bounds
        let side = circleSide(in: bounds)
        let insets = host.safeAreaInsets
        let statusBar = host.windowScene?.statusBarManager?.statusBarFrame.height ?? insets.top
        let top = statusBar + 44
        let bottom = max(insets.bottom, keyboardHeight) + 48
        let inset = 4 + insets.left
        let x =
            if location.x == 0 {
                hidden ? -side - inset : inset
            } else {
                hidden ? bounds.width + inset : bounds.width - inset - side
            }
        let y = location.y == 0 ? top + inset : bounds.height - bottom - inset - side
        return CGRect(x: x, y: y, width: side, height: side)
    }

    private func keyboardChanged(_ note: Foundation.Notification) {
        guard let host = hostWindow,
              let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        keyboardHeight = max(0, host.bounds.maxY - host.convert(end, from: nil).minY)
        guard let window, !window.isHidden, item != nil else { return }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState]) {
            window.frame = self.frame(hidden: false)
        }
    }

    private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let window, let host = hostWindow, item != nil else { return }
        switch recognizer.state {
        case .began:
            window.layer.removeAllAnimations()
            dragStartOrigin = window.frame.origin
        case .changed:
            let translation = recognizer.translation(in: host)
            window.frame.origin = CGPoint(x: dragStartOrigin.x + translation.x, y: dragStartOrigin.y + translation.y)
        case .cancelled, .ended, .failed:
            let (updated, shouldHide) = locationForPosition(
                CGPoint(x: window.frame.midX, y: window.frame.midY),
                velocity: recognizer.velocity(in: host),
                in: host,
            )
            location = updated
            if shouldHide {
                // OverlayInstantVideoNode isn't minimizeable, so a fling off the screen dismisses it.
                tearDown(animated: true)
                return
            }
            UIView.animate(
                withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
            ) { window.frame = self.frame(hidden: false) }
        default:
            break
        }
    }

    /// OverlayMediaControllerNode.nodeLocationForPosition: the nearest corner, or, for a fling of at least 500 pt/s,
    /// the corner it points to; a fling pointing away from every other corner hides the circle.
    private func locationForPosition(
        _ position: CGPoint,
        velocity: CGPoint,
        in host: UIWindow,
    ) -> (CGPoint, Bool) {
        let bounds = host.bounds
        let statusBar = host.windowScene?.statusBarManager?.statusBarFrame.height ?? host.safeAreaInsets.top
        let top = statusBar + 44
        let bottom = max(host.safeAreaInsets.bottom, keyboardHeight) + 48
        var result = CGPoint(
            x: position.x < bounds.width / 2 ? 0 : 1,
            y: position.y < top + (bounds.height - bottom - top) / 2 ? 0 : 1,
        )
        let current = result
        let epsilon: CGFloat = 30
        var shouldHide = false
        guard velocity.x * velocity.x + velocity.y * velocity.y >= 500 * 500 else { return (result, false) }
        var angle = atan2(velocity.y, velocity.x) * 180 / .pi * -1
        if angle < 0 { angle += 360 }
        switch (current.x == 0, current.y == 0) {
        case (true, true):
            if (angle > 0 && angle < 90 - epsilon) || angle > 360 - epsilon {
                result = CGPoint(x: 1, y: 0)
            } else if angle > 180 + epsilon, angle < 270 + epsilon {
                result = CGPoint(x: 0, y: 1)
            } else if angle > 270 + epsilon, angle < 360 - epsilon {
                result = CGPoint(x: 1, y: 1)
            } else {
                shouldHide = true
            }
        case (false, true):
            if angle > 90 + epsilon, angle < 180 + epsilon {
                result = CGPoint(x: 0, y: 0)
            } else if angle > 270 - epsilon, angle < 360 - epsilon {
                result = CGPoint(x: 1, y: 1)
            } else if angle > 180 + epsilon, angle < 270 - epsilon {
                result = CGPoint(x: 0, y: 1)
            } else {
                shouldHide = true
            }
        case (true, false):
            if angle > 90 - epsilon, angle < 180 - epsilon {
                result = CGPoint(x: 0, y: 0)
            } else if angle < epsilon || angle > 270 + epsilon {
                result = CGPoint(x: 1, y: 1)
            } else if angle > epsilon, angle < 90 - epsilon {
                result = CGPoint(x: 1, y: 0)
            } else {
                shouldHide = true
            }
        case (false, false):
            if angle > epsilon, angle < 90 + epsilon {
                result = CGPoint(x: 1, y: 0)
            } else if angle > 180 - epsilon, angle < 270 - epsilon {
                result = CGPoint(x: 0, y: 1)
            } else if angle > 90 + epsilon, angle < 180 - epsilon {
                result = CGPoint(x: 0, y: 0)
            } else {
                shouldHide = true
            }
        }
        return (result, shouldHide)
    }
}

// MARK: - FloatingVideoNoteWindow

/// A window the size of the circle, so it takes no touches around it and leaves the status bar to the app.
private final class FloatingVideoNoteWindow: UIWindow {}

// MARK: - FloatingVideoNoteView

/// OverlayInstantVideoDecoration: the round video with a shadow and the radial progress.
private final class FloatingVideoNoteView: UIView {
    // MARK: Internal

    var onTap: (() -> Void)?
    var onClose: (() -> Void)?
    var onPan: ((UIPanGestureRecognizer) -> Void)?

    // MARK: Private

    private let contentView = UIView()
    private let thumbnailView = UIImageView()
    private let surface = LocalVideoSurfaceView()
    private let progressLayer = CAShapeLayer()
    private let playIcon = UIImageView()
    private var cancellables = Set<AnyCancellable>()

    init(player: LocalMediaPlayer) {
        super.init(frame: .zero)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)

        contentView.clipsToBounds = true
        contentView.backgroundColor = .black
        contentView.isUserInteractionEnabled = false
        addSubview(contentView)
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        contentView.addSubview(thumbnailView)
        surface.playerLayer.videoGravity = .resizeAspectFill
        surface.isUserInteractionEnabled = false
        player.attach(to: surface.playerLayer)
        contentView.addSubview(surface)
        surface.playerLayer
            .publisher(for: \.isReadyForDisplay, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in self?.surface.alpha = isReady ? 1 : 0 }
            .store(in: &cancellables)

        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.white.withAlphaComponent(0.6).cgColor
        progressLayer.lineWidth = 3
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        layer.addSublayer(progressLayer)

        playIcon.image = UIImage(systemName: "play.fill")
        playIcon.tintColor = .white
        playIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
        playIcon.isHidden = true
        addSubview(playIcon)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = L10n.telegram("VoiceOver.Chat.VideoMessage")
        accessibilityHint = L10n.betterTG("Accessibility.PlayPauseHint")
        accessibilityCustomActions =
            [UIAccessibilityCustomAction(name: L10n.telegram("Common.Close")) { [weak self] _ in
                self?.onClose?()
                return true
            }]
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = bounds
        contentView.layer.cornerRadius = bounds.width / 2
        thumbnailView.frame = contentView.bounds
        surface.frame = contentView.bounds.insetBy(dx: -0.5, dy: -0.5)
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
        // Bounds and position: a rotated layer's frame is undefined.
        progressLayer.bounds = bounds
        progressLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        progressLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).cgPath
        progressLayer.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 2))
        playIcon.sizeToFit()
        playIcon.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func accessibilityActivate() -> Bool {
        onTap?()
        return true
    }

    func configure(thumbnail: UIImage?) {
        thumbnailView.image = thumbnail
        surface.alpha = surface.playerLayer.isReadyForDisplay ? 1 : 0
    }

    func setProgress(_ value: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = min(1, max(0, value))
        CATransaction.commit()
    }

    func setPlaying(_ isPlaying: Bool) {
        playIcon.isHidden = isPlaying
        accessibilityValue = L10n.betterTG(isPlaying ? "Accessibility.Playing" : "Accessibility.Paused")
    }

    @objc private func tapped() {
        onTap?()
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        onPan?(recognizer)
    }
}

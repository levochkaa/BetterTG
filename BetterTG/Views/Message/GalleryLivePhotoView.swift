// GalleryLivePhotoView.swift

import AVFoundation
import Combine
import TDLibKit
import UIKit

/// Telegram's UniversalVideoGalleryItem displays the still image over the motion
/// track: one muted autoplay, then a looping Live toggle or press-and-hold.
/// Pair reconstruction belongs to camera-roll export, not gallery playback.
final class GalleryLivePhotoView: UIView, GalleryMediaView, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let mediaContainer = UIView()
    private let preview = TDImageLoadingView()
    private let player = LocalMediaPlayer()
    private let playerSurface = LocalVideoSurfaceView()
    private let liveButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var task: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var playbackVisible = false
    private var didAutoplay = false
    private var isAutoplaying = false
    private var isUserPlaybackActive = false
    private var generation = UUID()
    private var motionURL: URL?
    private var retry: (() -> Void)?
    private var elapsed: TimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.delegate = self
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        pin(scroll, to: self)
        mediaContainer.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(mediaContainer)
        NSLayoutConstraint.activate([
            mediaContainer.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            mediaContainer.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            mediaContainer.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            mediaContainer.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            mediaContainer.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            mediaContainer.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        preview.contentMode = .scaleAspectFit
        preview.isUserInteractionEnabled = false
        pin(preview, to: mediaContainer)
        playerSurface.alpha = 0
        playerSurface.isUserInteractionEnabled = false
        pin(playerSurface, to: mediaContainer)
        player.attach(to: playerSurface.playerLayer)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(named: "Gallery/LivePhotoPlay")
        configuration.title = "LIVE"
        configuration.imagePadding = 4
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 11)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.systemFont(ofSize: 12)
            return attributes
        }
        liveButton.configuration = configuration
        liveButton.tintColor = .white
        liveButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        liveButton.layer.cornerRadius = 14
        liveButton.accessibilityLabel = "Play Live Photo"
        liveButton.accessibilityIdentifier = "gallery-live-photo-play"
        liveButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        addSubview(liveButton)
        spinner.color = .white
        addSubview(spinner)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.2
        mediaContainer.addGestureRecognizer(hold)
        player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updatePlayback(state)
            }
            .store(in: &cancellables)
        player.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.elapsed = time
                self?.updateButton()
            }
            .store(in: &cancellables)
        playerSurface.playerLayer
            .publisher(for: \.isReadyForDisplay)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateVideoVisibility() }
            .store(in: &cancellables)
        Media.shared
            .$isPlaying
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                if playing { self?.stopMotion() }
            }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.stopMotion() }
            .store(in: &cancellables)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        task?.cancel()
        player.stop()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        liveButton.frame = CGRect(
            // 8 pt badge inset + 8 pt content inset + half of the 16 pt icon = Back's center (24 pt).
            x: safeAreaInsets.left + 8,
            y: safeAreaInsets.top + 54,
            width: liveButton.sizeThatFits(CGSize(width: 200, height: 30)).width,
            height: 30,
        )
        spinner.center = CGPoint(x: liveButton.frame.maxX + 18, y: liveButton.center.y)
    }

    func configure(_ content: MessagePhoto) {
        prepareForReuse()
        preview.load(photo: content.photo, preferredSize: .yBox, maximumPixelSize: 2048)
        guard let motion = content.video, !content.isSecret else { return }
        let client = TDLib.shared.activeClient
        let requestGeneration = generation
        retry = { [weak self] in self?.load(video: motion.video, client: client, generation: requestGeneration) }
        retry?()
    }

    func prepareForReuse() {
        generation = UUID()
        task?.cancel()
        task = nil
        stopMotion()
        player.stop()
        motionURL = nil
        preview.cancel()
        scroll.setZoomScale(1, animated: false)
        didAutoplay = false
        playbackVisible = false
        retry = nil
    }

    func makeTransitionSnapshot() -> UIView? { preview.makeImageSnapshot(contentMode: .scaleAspectFit) }
    func viewForZooming(in _: UIScrollView) -> UIView? { mediaContainer }

    func setPlaybackVisible(_ visible: Bool) {
        playbackVisible = visible
        if visible { autoplayIfNeeded() } else { stopMotion() }
    }

    func setGalleryChromeVisible(_ visible: Bool, animated: Bool) {
        let update = { self.liveButton.alpha = visible ? 1 : 0 }
        if animated { UIView.animate(withDuration: 0.2, animations: update) } else { update() }
    }

    func canBeginInteractiveDismissal(at point: CGPoint) -> Bool {
        scroll.zoomScale <= 1.001 && !scroll.isZooming && !scroll.isDecelerating && !liveButton.frame.contains(point)
    }

    func setInteractiveDismissalActive(_ active: Bool) {
        scroll.panGestureRecognizer.isEnabled = !active
        scroll.pinchGestureRecognizer?.isEnabled = !active
        if active { stopMotion() }
    }

    func performPlaybackCommand(_ command: GalleryPlaybackCommand) {
        if command == .togglePlayback { togglePlayback() }
    }

    private func load(video: File, client: TDLibClient, generation: UUID) {
        guard self.generation == generation, TDLib.shared.activeClient.id == client.id else { return }
        task?.cancel()
        spinner.startAnimating()
        liveButton.isEnabled = false
        task = Task { [weak self] in
            do {
                let file = try await client.downloadFile(
                    fileId: video.id,
                    limit: 0,
                    offset: 0,
                    priority: 16,
                    synchronous: true,
                )
                try Task.checkCancellation()
                guard file.local.isDownloadingCompleted else { throw CocoaError(.fileReadUnknown) }
                guard let self, self.generation == generation, TDLib.shared.activeClient.id == client.id else { return }
                let url = URL(fileURLWithPath: file.local.path)
                motionURL = url
                player.load(url: url, autoplay: false, loops: false)
                spinner.stopAnimating()
                liveButton.isEnabled = true
                setLiveButtonTitle("LIVE")
                autoplayIfNeeded()
            } catch {
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                spinner.stopAnimating()
                liveButton.isEnabled = true
                setLiveButtonTitle("Retry")
            }
        }
    }

    private func autoplayIfNeeded() {
        guard playbackVisible, !didAutoplay, motionURL != nil else { return }
        didAutoplay = true
        isAutoplaying = true
        player.setMuted(true)
        player.play()
        updateVideoVisibility()
    }

    private func updatePlayback(_ state: LocalMediaPlayer.State) {
        switch state {
        case .ended:
            if isUserPlaybackActive, playbackVisible {
                player.play(from: 0)
            } else {
                stopMotion()
            }
        case .failed:
            isUserPlaybackActive = false
            isAutoplaying = false
            setLiveButtonTitle("Retry")
        default: break
        }
        updateVideoVisibility()
        updateButton()
    }

    private func updateVideoVisibility() {
        let showVideo = playbackVisible && (isUserPlaybackActive || isAutoplaying) && playerSurface.playerLayer
            .isReadyForDisplay
        let alpha: CGFloat = showVideo ? 1 : 0
        guard playerSurface.alpha != alpha else { return }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.playerSurface.alpha = alpha
        }
    }

    private func setLiveButtonTitle(_ title: String) {
        var configuration = liveButton.configuration
        configuration?.title = title
        liveButton.configuration = configuration
        setNeedsLayout()
    }

    private func updateButton() {
        var configuration = liveButton.configuration
        configuration?.image = UIImage(named: isUserPlaybackActive
            ? "Gallery/LivePhotoPlaying"
            : "Gallery/LivePhotoPlay")
        liveButton.configuration = configuration
        liveButton.tintColor = .white
        liveButton.accessibilityLabel = isUserPlaybackActive ? "Stop Live Photo" : "Play Live Photo"
        liveButton.accessibilityValue = player.state == .playing
            ? String(format: "Playing %.1f seconds", elapsed)
            : "Stopped"
    }

    private func stopMotion() {
        isUserPlaybackActive = false
        isAutoplaying = false
        player.pause()
        updateVideoVisibility()
        updateButton()
    }

    private func startMotion() {
        guard motionURL != nil, playbackVisible else { return }
        Media.shared.beginExclusivePlayback()
        isAutoplaying = false
        isUserPlaybackActive = true
        player.setMuted(false)
        player.play(from: 0)
        updateVideoVisibility()
        updateButton()
    }

    @objc private func togglePlayback() {
        if motionURL == nil || player.state == .failed { retry?() }
        else if isUserPlaybackActive { stopMotion() }
        else { startMotion() }
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began: startMotion()
        case .cancelled, .ended, .failed: stopMotion()
        default: break
        }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if scroll.zoomScale > 1 { scroll.setZoomScale(1, animated: true) }
        else {
            let point = gesture.location(in: mediaContainer)
            let size = CGSize(width: bounds.width / 3, height: bounds.height / 3)
            scroll.zoom(
                to: CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height,
                ),
                animated: true,
            )
        }
    }

    private func pin(_ child: UIView, to parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }
}

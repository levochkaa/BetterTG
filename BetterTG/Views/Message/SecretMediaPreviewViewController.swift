// SecretMediaPreviewViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - SecretMediaPreviewViewController

/// Telegram's SecretMediaPreviewController: a self-destructing photo, video or GIF opens alone over black with its
/// title and the self-destruct timer at the top right, and offers no sharing, saving or scrubbing. TDLib deletes a
/// view-once file once its content is opened, so the media is first read into memory (a photo) or copied into a
/// private temporary file (a video or GIF), and only then does openMessageContent run on the message's own client.
/// Media that fails to load is not opened. A photo closes when its message expires; a video or view-once media stays
/// until it is closed, as in Telegram. The content hides while the screen is captured or the app is inactive, so
/// recordings and the app switcher snapshot don't show it.
final class SecretMediaPreviewViewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    // MARK: Internal

    enum Kind { case photo, video, animation }

    // MARK: Private

    private static let tooltipCountKey = "SecretMedia.ViewOnceTooltipCount"

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    private let message: Message
    private let kind: Kind
    private let backend: VideoNotePlaybackBackend
    private let permit: MediaRevealPermit
    private let peerTitle: String
    private let player = LocalMediaPlayer()
    private let backgroundView = UIView()
    private let contentView = UIView()
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let videoSurface = LocalVideoSurfaceView()
    private let topBar = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let timerView = SecretMediaTimerView(diameter: 28)
    private let timerButton = UIButton(type: .custom)
    private let tooltipView = UIView()
    private let tooltipLabel = UILabel()
    private let footerView = UIView()
    private let footerLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var privateFileURL: URL?
    private var preparationTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var tooltipTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isFinished = false
    private var isMediaReady = false
    /// The message expired or was deleted while its media stayed on screen (`currentMessageIsDismissed`).
    private var isMessageGone = false

    private var isViewOnce: Bool {
        if case .messageSelfDestructTypeImmediately = message.selfDestructType { return true }
        return false
    }

    private var timeout: TimeInterval {
        if case .messageSelfDestructTypeTimer(let timer) = message.selfDestructType {
            return TimeInterval(timer.selfDestructTime)
        }
        return 0
    }

    private var mediaDuration: TimeInterval {
        switch message.content {
        case .messageVideo(let value): TimeInterval(value.video.duration)
        case .messageAnimation(let value): TimeInterval(value.animation.duration)
        default: 0
        }
    }

    /// Showing may continue only while this preview, the message's client and an unrecorded foreground screen last.
    private var admitsShowing: Bool {
        !Task.isCancelled && !isFinished && backend.isCurrent() && viewIfLoaded?.window != nil
    }

    /// Opening the media also needs the chat route that showed it: the reveal permit for its current revision.
    private var admitsOpening: Bool {
        admitsShowing && permit.matches(message) && traitCollection.sceneCaptureState != .active
            && UIApplication.shared.applicationState == .active
    }

    private var isContentConcealed: Bool {
        traitCollection.sceneCaptureState == .active || UIApplication.shared.applicationState != .active
    }

    init?(message: Message, backend: VideoNotePlaybackBackend, permit: MediaRevealPermit, peerTitle: String) {
        switch message.content {
        case .messagePhoto: self.kind = .photo
        case .messageVideo: self.kind = .video
        case .messageAnimation: self.kind = .animation
        default: return nil
        }
        self.message = message
        self.backend = backend
        self.permit = permit
        self.peerTitle = peerTitle
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        modalPresentationCapturesStatusBarAppearance = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        preparationTask?.cancel()
        deadlineTask?.cancel()
        tooltipTask?.cancel()
        if let privateFileURL { try? FileManager.default.removeItem(at: privateFileURL) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        observe()
        configureTimer(started: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard preparationTask == nil, !isFinished else { return }
        preparationTask = Task { [weak self] in await self?.prepareAndShow() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scrollView.zoomScale == scrollView.minimumZoomScale { imageView.frame = scrollView.bounds }
    }

    override func accessibilityPerformEscape() -> Bool {
        finish()
        return true
    }

    // MARK: Internal

    /// Telegram's preview titles (SecretImage.Title, SecretVideo.ViewOnce.Title, SecretGif.Title and the rest).
    static func title(for message: Message) -> String {
        let isViewOnce =
            if case .messageSelfDestructTypeImmediately = message.selfDestructType {
                true
            } else {
                false
            }
        switch message.content {
        case .messageVideo:
            return L10n.telegram(isViewOnce ? "SecretVideo.ViewOnce.Title" : "SecretVideo.Title")
        case .messageAnimation:
            return L10n.telegram("SecretGif.Title")
        default:
            return L10n.telegram(isViewOnce ? "SecretImage.ViewOnce.Title" : "SecretImage.Title")
        }
    }

    private static func mediaFile(of message: Message) -> File? {
        switch message.content {
        case .messagePhoto(let value):
            value.photo.sizes.max { $0.width * $0.height < $1.width * $1.height }?.photo
        case .messageVideo(let value):
            value.video.video
        case .messageAnimation(let value):
            value.animation.animation
        default:
            nil
        }
    }

    private static func fileExtension(of message: Message) -> String {
        let (mimeType, fileName) =
            switch message.content {
            case .messageVideo(let value): (value.video.mimeType, value.video.fileName)
            case .messageAnimation(let value): (value.animation.mimeType, value.animation.fileName)
            default: ("", "")
            }
        if mimeType.contains("quicktime") { return "mov" }
        let named = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return named.isEmpty || mimeType.contains("mp4") ? "mp4" : named
    }

    private static func decodeImage(at url: URL) async throws -> UIImage {
        let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
        guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        return await image.byPreparingForDisplay() ?? image
    }

    private static func copyPrivately(_ source: URL, to destination: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: source, to: destination)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: destination.path,
            )
        }.value
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
        kind == .photo ? imageView : nil
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x) && scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01
    }

    private func configureViews() {
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        backgroundView.backgroundColor = .black
        backgroundView.frame = view.bounds
        backgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundView)

        contentView.frame = view.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(contentView)
        scrollView.frame = contentView.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = kind == .photo ? 3 : 1
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        contentView.addSubview(scrollView)
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = Self.title(for: message)
        imageView.accessibilityTraits = .image
        scrollView.addSubview(imageView)
        videoSurface.frame = contentView.bounds
        videoSurface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoSurface.playerLayer.videoGravity = .resizeAspect
        videoSurface.isHidden = kind == .photo
        videoSurface.isAccessibilityElement = kind != .photo
        videoSurface.accessibilityLabel = Self.title(for: message)
        player.attach(to: videoSurface.playerLayer)
        contentView.addSubview(videoSurface)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        dismissPan.delegate = self
        view.addGestureRecognizer(dismissPan)

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        // The gallery's top bar (MediaGalleryViewController): Back on the left, the title in the middle and, in
        // SecretMediaPreviewControllerNode's place, the 28 pt timer 9 pt from the right edge.
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.accessibilityLabel = L10n.telegram("Common.Back")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        topBar.addSubview(backButton)
        titleLabel.text = Self.title(for: message)
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        titleLabel.accessibilityTraits = .header
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(titleLabel)
        timerView.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(timerView)
        timerButton.translatesAutoresizingMaskIntoConstraints = false
        timerButton.isAccessibilityElement = isViewOnce
        timerButton.accessibilityLabel = L10n.telegram(
            kind == .photo ? "Gallery.ViewOncePhotoTooltip" : "Gallery.ViewOnceVideoTooltip",
        )
        timerButton.addTarget(self, action: #selector(timerTapped), for: .touchUpInside)
        topBar.addSubview(timerButton)

        // TooltipScreen with the view-once explanation under the timer.
        tooltipView.backgroundColor = UIColor(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1A / 255, alpha: 1)
        tooltipView.layer.cornerRadius = 8
        tooltipView.alpha = 0
        tooltipView.isUserInteractionEnabled = false
        tooltipView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tooltipView)
        tooltipLabel.text = timerButton.accessibilityLabel
        tooltipLabel.textColor = .white
        tooltipLabel.font = .systemFont(ofSize: 14)
        tooltipLabel.numberOfLines = 0
        tooltipLabel.textAlignment = .center
        tooltipLabel.translatesAutoresizingMaskIntoConstraints = false
        tooltipView.addSubview(tooltipLabel)

        footerView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        footerView.isHidden = true
        footerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footerView)
        footerLabel.textColor = .white
        footerLabel.font = .systemFont(ofSize: 15)
        footerLabel.textAlignment = .center
        footerLabel.numberOfLines = 0
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(footerLabel)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 2),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            timerView.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            timerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -9),
            timerView.widthAnchor.constraint(equalToConstant: 28),
            timerView.heightAnchor.constraint(equalToConstant: 28),
            timerButton.centerXAnchor.constraint(equalTo: timerView.centerXAnchor),
            timerButton.centerYAnchor.constraint(equalTo: timerView.centerYAnchor),
            timerButton.widthAnchor.constraint(equalToConstant: 44),
            timerButton.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timerButton.leadingAnchor, constant: -4),
            tooltipView.topAnchor.constraint(equalTo: timerView.bottomAnchor, constant: 10),
            tooltipView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            tooltipView.widthAnchor.constraint(lessThanOrEqualToConstant: 226),
            tooltipLabel.topAnchor.constraint(equalTo: tooltipView.topAnchor, constant: 8),
            tooltipLabel.bottomAnchor.constraint(equalTo: tooltipView.bottomAnchor, constant: -8),
            tooltipLabel.leadingAnchor.constraint(equalTo: tooltipView.leadingAnchor, constant: 8),
            tooltipLabel.trailingAnchor.constraint(equalTo: tooltipView.trailingAnchor, constant: -8),
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerLabel.topAnchor.constraint(equalTo: footerView.topAnchor, constant: 12),
            footerLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            footerLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            footerLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    private func observe() {
        player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, isMediaReady else { return }
                switch state {
                case .ended:
                    playbackEnded()
                case .failed:
                    finish(failed: true)
                default:
                    break
                }
            }
            .store(in: &cancellables)
        // Another player taking the audio pauses the video.
        Media.shared
            .$isPlaying
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard isPlaying, let self, kind == .video else { return }
                player.pause()
            }
            .store(in: &cancellables)
        backend.clientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !backend.isCurrent() else { return }
                finish()
            }
            .store(in: &cancellables)
        let chatID = message.chatId
        let messageID = message.id
        backend.observe(&cancellables, for: .updateDeleteMessages) { [weak self] event in
            guard let self, event.source == backend.source, event.value.chatId == chatID,
                  event.value.messageIds.contains(messageID) else { return }
            messageGone()
        }
        backend.observe(&cancellables, for: .updateMessageContent) { [weak self] event in
            guard let self, event.source == backend.source, event.value.chatId == chatID,
                  event.value.messageId == messageID else { return }
            messageGone()
        }
        NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateConcealment() }
            .store(in: &cancellables)
        registerForTraitChanges([UITraitSceneCaptureState.self]) {
            (controller: SecretMediaPreviewViewController, _) in
            controller.updateConcealment()
        }
    }

    private func prepareAndShow() async {
        do {
            guard admitsOpening else { return finish() }
            let latest = try await backend.message(message.chatId, message.id)
            // An expired or edited message no longer holds the media the user tapped.
            guard admitsOpening, isSameMedia(latest), var file = Self.mediaFile(of: latest) else { return finish() }
            if !file.local.isDownloadingCompleted {
                file = try await backend.download(file.id, true)
            }
            guard admitsOpening, file.local.isDownloadingCompleted, !file.local.path.isEmpty else {
                return finish(failed: true)
            }
            let source = URL(fileURLWithPath: file.local.path)
            var image: UIImage?
            if kind == .photo {
                image = try await Self.decodeImage(at: source)
            } else {
                let copy = FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent("secret-media-\(UUID().uuidString)")
                    .appendingPathExtension(Self.fileExtension(of: latest))
                privateFileURL = copy
                try await Self.copyPrivately(source, to: copy)
            }
            guard admitsOpening else { return finish() }
            let checked = try await backend.message(message.chatId, message.id)
            guard admitsOpening, isSameMedia(checked) else { return finish() }
            var started: TimeInterval?
            // Telegram consumes the media once it is shown (markMessageContentAsConsumedInteractively); the sender's
            // own
            // media is not consumed.
            if !message.isOutgoing {
                let openedAt = backend.now()
                try await backend.open(message.chatId, message.id)
                guard admitsShowing else { return finish() }
                if timeout > 0 {
                    let opened = try? await backend.message(message.chatId, message.id)
                    let left = opened.map(\.selfDestructIn).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? timeout
                    started = openedAt + left
                    SelfDestructDeadlines.record(openedAt + left, clientID: backend.source.clientID, message: message)
                }
            } else {
                started = SelfDestructDeadlines.deadline(clientID: backend.source.clientID, message: checked)
            }
            guard admitsShowing else { return finish() }
            show(image: image, started: started)
        } catch is CancellationError {
            finish()
        } catch {
            finish(failed: true)
        }
    }

    private func show(image: UIImage?, started deadline: TimeInterval?) {
        spinner.stopAnimating()
        isMediaReady = true
        if let image {
            imageView.image = image
            imageView.frame = scrollView.bounds
        } else if let privateFileURL {
            if kind == .video {
                VideoNotePlaybackView.pauseActivePlayback()
                backend.takePlayback()
            }
            player.setMuted(kind == .animation)
            player.load(url: privateFileURL, autoplay: !isContentConcealed, loops: false)
        }
        configureTimer(started: deadline)
        if message.isOutgoing, deadline == nil, !isViewOnce {
            footerView.isHidden = false
            let key =
                switch kind {
                case .photo: "SecretImage.NotViewedYet"
                case .video: "SecretVideo.NotViewedYet"
                case .animation: "SecretGIF.NotViewedYet"
                }
            footerLabel.text = L10n.telegram(key, peerTitle)
        }
        if isViewOnce {
            let count = UserDefaults.standard.integer(forKey: Self.tooltipCountKey)
            UserDefaults.standard.set(count + 1, forKey: Self.tooltipCountKey)
            if count < 2 { showTooltip() }
        }
        updateConcealment()
        UIAccessibility.post(notification: .screenChanged, argument: kind == .photo ? imageView : videoSurface)
    }

    /// SecretMediaPreviewControllerNode's timer: the view-once mark, a static flame for sent media nobody opened yet,
    /// or the countdown. A timed video counts down from the longer of its length and its timer.
    private func configureTimer(started deadline: TimeInterval?) {
        if isViewOnce {
            timerView.configure(icon: .viewOnce, countdown: nil)
            return
        }
        guard let deadline, timeout > 0 else {
            timerView.configure(icon: .flame, countdown: nil)
            return
        }
        let countdown: SecretMediaTimerView.Countdown =
            if kind == .video, mediaDuration > timeout {
                .init(deadline: SelfDestructDeadlines.now + mediaDuration, timeout: mediaDuration)
            } else {
                .init(deadline: deadline, timeout: timeout)
            }
        timerView.configure(icon: .flame, countdown: countdown)
        guard kind == .photo else { return }
        // A timed photo closes when its time is up, even before TDLib reports the deletion.
        deadlineTask?.cancel()
        let backend = backend
        deadlineTask = Task { [weak self] in
            do {
                try await backend.sleep(max(0, deadline - backend.now()))
            } catch {
                return
            }
            self?.finish()
        }
    }

    private func playbackEnded() {
        // Telegram replays view-once media, GIFs and videos under 30 s while the message lasts; a longer video closes.
        if isViewOnce || kind == .animation || (mediaDuration < 30 && !isMessageGone) {
            player.play(from: 0)
        } else {
            finish()
        }
    }

    private func messageGone() {
        isMessageGone = true
        // Telegram closes an expired photo, and lets a video or view-once media stay until it is closed.
        guard kind == .photo, !isViewOnce else { return }
        finish()
    }

    /// Telegram's secret gallery layer is left out of screenshots and recordings; UIKit has no such layer, so the media
    /// hides while the screen is captured and while the app is inactive, which also keeps it out of the app switcher.
    private func updateConcealment() {
        guard !isFinished else { return }
        let concealed = isContentConcealed
        contentView.isHidden = concealed
        guard isMediaReady, kind != .photo else { return }
        if concealed {
            player.pause()
        } else if !player.isPlaybackRequested {
            player.play()
        }
    }

    private func isSameMedia(_ latest: Message) -> Bool {
        MediaRevealSession.Key(message: latest) == MediaRevealSession.Key(message: message)
            && latest.selfDestructType == message.selfDestructType && latest.isOutgoing == message.isOutgoing
    }

    private func showTooltip() {
        tooltipTask?.cancel()
        UIView.animate(withDuration: 0.2) { self.tooltipView.alpha = 1 }
        tooltipTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.hideTooltip()
        }
    }

    private func hideTooltip() {
        tooltipTask?.cancel()
        tooltipTask = nil
        UIView.animate(withDuration: 0.2) { self.tooltipView.alpha = 0 }
    }

    @objc private func timerTapped() {
        guard isViewOnce else { return }
        showTooltip()
    }

    @objc private func toggleZoom(_ recognizer: UITapGestureRecognizer) {
        guard kind == .photo, imageView.image != nil else { return }
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
            scrollView.zoom(
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

    /// The gallery's swipe to dismiss: the media follows the finger and the black fades.
    @objc private func handleDismissPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)
        let progress = min(1, abs(translation.y) / max(1, view.bounds.height / 2))
        switch recognizer.state {
        case .began:
            hideTooltip()
        case .changed:
            contentView.transform = CGAffineTransform(translationX: 0, y: translation.y)
            backgroundView.alpha = 1 - progress
            topBar.alpha = 1 - progress
            footerView.alpha = 1 - progress
        case .cancelled,
             .ended,
             .failed:
            let velocity = recognizer.velocity(in: view).y
            if recognizer.state == .ended, abs(translation.y) > 100 || abs(velocity) > 1000 {
                let direction: CGFloat = translation.y + velocity * 0.1 >= 0 ? 1 : -1
                UIView.animate(withDuration: 0.2) {
                    self.contentView.transform = CGAffineTransform(
                        translationX: 0,
                        y: direction * self.view.bounds.height,
                    )
                    self.backgroundView.alpha = 0
                }
                finish(animated: false)
            } else {
                UIView.animate(
                    withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                    options: [.allowUserInteraction],
                ) {
                    self.contentView.transform = .identity
                    self.backgroundView.alpha = 1
                    self.topBar.alpha = 1
                    self.footerView.alpha = 1
                }
            }
        default:
            break
        }
    }

    @objc private func close() {
        finish()
    }

    private func finish(failed: Bool = false, animated: Bool = true) {
        guard !isFinished else { return }
        isFinished = true
        preparationTask?.cancel()
        deadlineTask?.cancel()
        tooltipTask?.cancel()
        player.stop()
        if let privateFileURL {
            try? FileManager.default.removeItem(at: privateFileURL)
            self.privateFileURL = nil
        }
        let presenter = presentingViewController
        let completion = { [weak self] in
            self?.imageView.image = nil
            if failed { presenter?.presentChatListActionFailure() }
        }
        guard presenter != nil, !isBeingDismissed else { return completion() }
        if animated {
            dismiss(animated: true, completion: completion)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.dismiss(animated: false, completion: completion)
            }
        }
    }
}

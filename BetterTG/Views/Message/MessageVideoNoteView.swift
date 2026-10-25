// MessageVideoNoteView.swift

import AVFoundation
import Combine
import TDLibKit
import UIKit

final class VideoNotePlaybackView: UIControl, ReusableMediaView {
    #if DEBUG
        struct ProbeSnapshot {
            let held: Bool
            let acknowledged: Bool
            let visiblePixels: Bool
            let playerItem: Bool
            let playbackRequested: Bool
            let thumbnail: Bool
            let deadline: TimeInterval?
            let path: String?
        }

        var probeSnapshot: ProbeSnapshot {
            ProbeSnapshot(
                held: secretHoldID != nil, acknowledged: secretAcknowledged,
                visiblePixels: !playerSurface.isHidden && (!isSecret || secretBlurView.isHidden),
                playerItem: player.currentItemIdentifier != nil, playbackRequested: player.isPlaybackRequested,
                thumbnail: thumbnailView.image != nil, deadline: secretDeadline, path: representedPath,
            )
        }

        func beginHoldForProbe() { revealSecretAndPlay() }
        func releaseHoldForProbe() { concealSecret() }
        func tapForProbe() { tapped() }
    #endif

    /// An instant video of Telegram's voice playlist (PeerMessagesMediaPlaylist, `.voice` takes voice notes and
    /// instant videos).
    struct PlaylistItem: Equatable {
        let source: TdUpdateSource
        let chatID: Int64
        let messageID: Int64
    }

    /// An instant video that played to its end, so its chat can continue the playlist.
    static let playbackFinished = PassthroughSubject<PlaylistItem, Never>()

    private weak static var activePlaybackView: VideoNotePlaybackView?

    /// The instant video the playlist plays next; it starts once its view shows it with the file loaded.
    private static var playlistRequest: (item: PlaylistItem, expiresAt: TimeInterval)?
    private static let playlistRequests = PassthroughSubject<Void, Never>()
    /// How long a request waits for its view to appear and its file to load.
    private static let playlistRequestLifetime: TimeInterval = 15

    private let player = LocalMediaPlayer()
    private let proximityControl = VideoNoteProximityControl()
    private let thumbnailView = TDImageLoadingView()
    private let playerSurface = LocalVideoSurfaceView()
    /// ChatMessageInteractiveInstantVideoNode's automatic playback: the downloaded note loops silently until a tap
    /// plays it with sound.
    private let autoplayView = MutedVideoLoopView()
    private let playIcon = UIImageView()
    private let downloadStatus = MediaDownloadStatusView()
    /// The video message auto-download left for a tap, and whether that tap asked it to play once downloaded.
    private var deferredDownload: DeferredMediaDownload?
    private var playsWhenDownloaded = false
    private let durationLabel = UILabel()
    private let secretBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let progressLayer = CAShapeLayer()
    private lazy var sideConstraint = widthAnchor.constraint(equalToConstant: 220)
    private var videoNote: VideoNote?
    private var representedPath: String?
    private var isSecret = false
    /// False until the note is watched; the first play of an incoming note marks it viewed.
    private var isViewed = true
    private var message: Message?
    private var backend: VideoNotePlaybackBackend?
    private var configurationID = UUID()
    private var isRevoked = false
    private var secretHoldID: UUID?
    private var secretAcknowledged = false
    private var secretDeadline: TimeInterval?
    private var secretDeadlineTask: Task<Void, Never>?
    private var playbackVisible = false
    private var hasStartedPlayback = false
    private var downloadTask: Task<Void, Never>?
    private var downloadRequestID: UUID?
    private var ownsDownload = false
    private var secretOpenTask: Task<Void, Never>?
    private var bindings = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()

    private var currentPlayerState = LocalMediaPlayer.State.idle

    private var supportsSecretHold: Bool {
        guard let message, backend != nil, !isRevoked, !message.isOutgoing,
              case .messageSelfDestructTypeTimer(let timer) = message.selfDestructType,
              (1...60).contains(timer.selfDestructTime) else { return false }
        return Self.isSecret(message)
    }

    private var permitsSecretDisplay: Bool {
        window != nil && traitCollection.sceneCaptureState == .inactive
    }

    /// The playlist identity of this note, for the floating player.
    private var playlistItem: PlaylistItem? {
        guard let message, let backend, !isSecret else { return nil }
        return PlaylistItem(source: backend.source, chatID: message.chatId, messageID: message.id)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        observePlayer()
        registerForTraitChanges([UITraitSceneCaptureState.self]) { (view: VideoNotePlaybackView, _) in
            view.concealIfCaptureUnavailable()
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        downloadTask?.cancel()
        secretOpenTask?.cancel()
        secretDeadlineTask?.cancel()
        player.stop()
        if ownsDownload, let backend, let fileID = videoNote?.video.id {
            Task { await backend.cancelDownload(fileID) }
        }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isSecret else { return super.beginTracking(touch, with: event) }
        revealSecretAndPlay()
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if isSecret {
            concealSecret()
        } else {
            super.endTracking(touch, with: event)
        }
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if isSecret, !bounds.contains(touch.location(in: self)) {
            concealSecret()
            return false
        }
        return super.continueTracking(touch, with: event)
    }

    override func cancelTracking(with event: UIEvent?) {
        if isSecret {
            concealSecret()
        }
        super.cancelTracking(with: event)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        thumbnailView.layer.cornerRadius = bounds.width / 2
        playerSurface.layer.cornerRadius = bounds.width / 2
        autoplayView.layer.cornerRadius = bounds.width / 2
        secretBlurView.layer.cornerRadius = bounds.width / 2
        progressLayer.frame = bounds
        progressLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).cgPath
        progressLayer.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 2))
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            setPlaybackVisible(false)
        } else if let item = playlistItem, FloatingVideoNotePlayer.shared.holds(item) {
            // Back from a screen pushed over the chat: the bubble takes its video back from the circle.
            setPlaybackVisible(true)
        }
        concealIfCaptureUnavailable()
    }

    /// Pauses the video note playing in the timeline, for another player that takes the audio.
    static func pauseActivePlayback() {
        activePlaybackView?.pauseForCompetingPlayback()
        FloatingVideoNotePlayer.shared.pause()
    }

    static func requestPlaylistPlayback(_ item: PlaylistItem) {
        playlistRequest = (item, ProcessInfo.processInfo.systemUptime + playlistRequestLifetime)
        playlistRequests.send()
    }

    private static func isSecret(_ message: Message) -> Bool {
        guard case .messageVideoNote(let value) = message.content else { return false }
        return value.isSecret
    }

    func configure(message: Message, client: TDLibClient, context: MediaGalleryPlaybackContext?) {
        let acceptsContext = context.map { $0.isCurrent && $0.location.matches(message: message) }
            ?? !Self.isSecret(message)
        let keptPlayback = configure(
            message: message,
            backend: acceptsContext
                ? VideoNotePlaybackBackend.captured(client: client, context: context)
                : nil,
        )
        // The same note keeps its thumbnail too; reloading it would cancel the load and blank the image.
        guard !keptPlayback, backend?.isCurrent() == true, !isRevoked else { return }
        if !isSecret, let thumbnail = videoNote?.thumbnail {
            thumbnailView.load(file: thumbnail.file, placeholderData: videoNote?.minithumbnail?.data, client: client)
        }
    }

    /// Returns true when it reconfigured the note it already shows and kept its playback.
    @discardableResult func configure(message: Message, backend: VideoNotePlaybackBackend?) -> Bool {
        guard case .messageVideoNote(let value) = message.content else {
            prepareForReuse()
            return false
        }
        // A reconfigure of the same note keeps its playback, progress and download.
        if let current = self.message, current.chatId == message.chatId, current.id == message.id,
           videoNote?.video.id == value.videoNote.video.id, isSecret == value.isSecret,
           self.backend?.isCurrent() == true, backend?.isCurrent() == true
        {
            videoNote = value.videoNote
            self.message = message
            if value.isViewed { isViewed = true }
            update(file: value.videoNote.video)
            return true
        }
        prepareForReuse()
        let videoNote = value.videoNote
        self.videoNote = videoNote
        self.message = message
        self.backend = backend
        isSecret = value.isSecret
        isViewed = value.isViewed
        sideConstraint.constant = min(260, max(180, CGFloat(videoNote.length)))
        durationLabel.text = format(videoNote.duration)
        secretBlurView.isHidden = !isSecret
        accessibilityLabel = "\(L10n.telegram("VoiceOver.Chat.VideoMessage")), \(format(videoNote.duration))"
        accessibilityHint = isSecret
            ? (supportsSecretHold
                ? L10n.betterTG("Accessibility.HoldToOpenHint")
                : L10n.betterTG("Accessibility.ProtectedMessageUnavailable"))
            : L10n.betterTG("Accessibility.PlayPauseHint")
        guard let backend, backend.isCurrent(), !isSecret || supportsSecretHold else { return false }
        if !isSecret, let data = videoNote.minithumbnail?.data {
            thumbnailView.image = UIImage(data: data)
        }
        observeBinding(backend)
        update(file: videoNote.video)
        if !isSecret, representedPath == nil,
           !TDMediaPrefetcher.allowsAutoDownload(of: message, client: TDLib.shared.activeClient)
        {
            // Auto-download's video setting leaves the note to a tap on the download arrow, which then plays it.
            deferredDownload = DeferredMediaDownload(
                file: videoNote.video,
                client: TDLib.shared.activeClient,
                status: downloadStatus,
            ) { [weak self] file in
                guard let self else { return }
                deferredDownload = nil
                update(file: file)
                if playsWhenDownloaded {
                    playsWhenDownloaded = false
                    tapped()
                }
            }
        }
        if !isSecret { startDownloadIfNeeded() }
        renderPlayerState(.idle)
        return false
    }

    func prepareForReuse() {
        configurationID = UUID()
        proximityControl.end()
        concealSecret()
        cancelDownload()
        player.stop()
        bindings.removeAll()
        if Self.activePlaybackView === self {
            Self.activePlaybackView = nil
        }
        deferredDownload = nil
        playsWhenDownloaded = false
        downloadStatus.hide()
        autoplayView.setFile(path: nil)
        playerSurface.isHidden = true
        thumbnailView.cancel()
        thumbnailView.image = nil
        representedPath = nil
        videoNote = nil
        isSecret = false
        isViewed = true
        message = nil
        backend = nil
        isRevoked = false
        secretDeadline = nil
        playbackVisible = false
        progressLayer.strokeEnd = 0
        progressLayer.isHidden = true
        hasStartedPlayback = false
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        if !isVisible { handOffToFloatingPlayer() }
        applyPlaybackVisibility(isVisible)
        if isVisible { reclaimFromFloatingPlayer() }
    }

    /// Telegram's overlay instant video: a note that plays when its bubble leaves the screen keeps playing in the
    /// floating circle (OverlayInstantVideoNode, SharedMediaPlayer).
    private func handOffToFloatingPlayer() {
        guard player.isPlaybackRequested, currentPlayerState == .playing || currentPlayerState == .buffering,
              !isRevoked, let item = playlistItem, let backend, backend.isCurrent(), let path = representedPath,
              let videoNote else { return }
        proximityControl.end()
        FloatingVideoNotePlayer.shared.adopt(.init(
            item: item,
            url: URL(filePath: path),
            time: player.currentTime,
            duration: Double(videoNote.duration),
            thumbnail: thumbnailView.image,
            backend: backend,
        ))
        player.pause()
        if Self.activePlaybackView === self { Self.activePlaybackView = nil }
    }

    /// The bubble shows again with its file: the video comes back from the circle where it left off.
    private func reclaimFromFloatingPlayer() {
        guard playbackVisible, !isRevoked, representedPath != nil, let item = playlistItem,
              let backend, backend.isCurrent(), let reclaimed = FloatingVideoNotePlayer.shared.reclaim(item)
        else { return }
        hasStartedPlayback = true
        if reclaimed.isPlaying {
            guard beginExclusivePlayback() else { return }
            player.play(from: reclaimed.time)
        } else {
            player.seek(to: reclaimed.time)
            playIcon.isHidden = false
        }
    }

    private func applyPlaybackVisibility(_ isVisible: Bool) {
        playbackVisible = isVisible
        defer { updateAutoplay() }
        if !isVisible {
            if isSecret {
                concealSecret()
            } else {
                player.pause()
            }
            cancelDownload()
        } else if !isSecret {
            startDownloadIfNeeded()
            startRequestedPlaylistPlayback()
        }
    }

    private func concealIfCaptureUnavailable() {
        guard isSecret, !permitsSecretDisplay else { return }
        // Ending capture does not restore this hold or extend its existing deadline.
        concealSecret()
    }

    private func configureViews() {
        clipsToBounds = false
        backgroundColor = .black
        isAccessibilityElement = true
        accessibilityTraits = [.button]

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        addSubview(thumbnailView)

        playerSurface.translatesAutoresizingMaskIntoConstraints = false
        playerSurface.playerLayer.videoGravity = .resizeAspectFill
        playerSurface.clipsToBounds = true
        playerSurface.isUserInteractionEnabled = false
        playerSurface.isHidden = true
        player.attach(to: playerSurface.playerLayer)
        player.setMuted(false)
        addSubview(playerSurface)
        autoplayView.translatesAutoresizingMaskIntoConstraints = false
        autoplayView.clipsToBounds = true
        addSubview(autoplayView)
        NSLayoutConstraint.activate([
            autoplayView.topAnchor.constraint(equalTo: topAnchor),
            autoplayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            autoplayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            autoplayView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        playerSurface.playerLayer
            .publisher(for: \.isReadyForDisplay, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                self?.setPlayerSurfaceReady(isReady)
            }
            .store(in: &cancellables)

        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.white.withAlphaComponent(0.82).cgColor
        progressLayer.lineWidth = 3
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0

        playIcon.translatesAutoresizingMaskIntoConstraints = false
        playIcon.image = UIImage(systemName: "play.fill")
        playIcon.tintColor = .white
        playIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
        addSubview(playIcon)
        addSubview(downloadStatus)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        durationLabel.layer.cornerRadius = 9
        durationLabel.clipsToBounds = true
        durationLabel.textAlignment = .center
        addSubview(durationLabel)

        secretBlurView.translatesAutoresizingMaskIntoConstraints = false
        secretBlurView.clipsToBounds = true
        secretBlurView.isUserInteractionEnabled = false
        secretBlurView.contentView.backgroundColor = .secondarySystemBackground
        addSubview(secretBlurView)

        NSLayoutConstraint.activate([
            sideConstraint,
            heightAnchor.constraint(equalTo: widthAnchor),
            thumbnailView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playerSurface.topAnchor.constraint(equalTo: topAnchor),
            playerSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerSurface.bottomAnchor.constraint(equalTo: bottomAnchor),
            playIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            downloadStatus.centerXAnchor.constraint(equalTo: centerXAnchor),
            downloadStatus.centerYAnchor.constraint(equalTo: centerYAnchor),
            durationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            durationLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 38),
            durationLabel.heightAnchor.constraint(equalToConstant: 18),
            secretBlurView.topAnchor.constraint(equalTo: topAnchor),
            secretBlurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            secretBlurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            secretBlurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        layer.addSublayer(progressLayer)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    private func observePlayer() {
        player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.renderPlayerState(state) }
            .store(in: &cancellables)
        player.timePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self, let videoNote, videoNote.duration > 0 else { return }
                progressLayer.strokeEnd = min(1, max(0, time / Double(videoNote.duration)))
                durationLabel.text = format(max(0, videoNote.duration - Int(time)))
            }
            .store(in: &cancellables)
        Media.shared
            .$isPlaying
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard isPlaying else { return }
                self?.pauseForCompetingPlayback()
            }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: .voiceRecordingWillStart)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pauseForCompetingPlayback() }
            .store(in: &cancellables)
        Self.playlistRequests
            .sink { [weak self] in self?.startRequestedPlaylistPlayback() }
            .store(in: &cancellables)
    }

    private func observeBinding(_ backend: VideoNotePlaybackBackend) {
        let bindingID = configurationID
        let accepts: (TdUpdateSource) -> Bool = { [weak self] source in
            self?.configurationID == bindingID && backend.source == source && backend.isCurrent()
                && self?.isRevoked == false
        }
        backend.observe(&bindings, for: .updateFile) { [weak self] event in
            guard accepts(event.source) else { return }
            self?.update(file: event.value.file)
        }
        backend.observe(&bindings, for: .updateMessageContent) { [weak self] event in
            guard let self, accepts(event.source), event.value.chatId == message?.chatId,
                  event.value.messageId == message?.id else { return }
            guard case .messageVideoNote(let value) = event.value.newContent,
                  value.isSecret == isSecret, value.videoNote.video.id == videoNote?.video.id
            else {
                revoke()
                return
            }
        }
        backend.observe(&bindings, for: .updateMessageEdited) { [weak self] event in
            guard let self, accepts(event.source), event.value.chatId == message?.chatId,
                  event.value.messageId == message?.id, event.value.editDate != message?.editDate else { return }
            revoke()
        }
        backend.observe(&bindings, for: .updateDeleteMessages) { [weak self] event in
            guard let self, accepts(event.source), event.value.chatId == message?.chatId,
                  let id = message?.id, event.value.messageIds.contains(id) else { return }
            revoke()
        }
        backend.clientChanges
            .sink { [weak self] _ in
                guard let self, configurationID == bindingID, !backend.isCurrent() else { return }
                revoke()
            }
            .store(in: &bindings)
        backend.lifecycle
            .sink { [weak self] event in
                guard let self, configurationID == bindingID else { return }
                // Going to the background pauses in place; the floating player is for leaving the screen.
                applyPlaybackVisibility(event.name == UIApplication.didBecomeActiveNotification && window != nil)
            }
            .store(in: &bindings)
    }

    private func startDownloadIfNeeded() {
        guard let backend, backend.isCurrent(), !isRevoked,
              !isSecret,
              deferredDownload == nil,
              playbackVisible || window != nil,
              representedPath == nil,
              downloadTask == nil,
              let videoFileID = videoNote?.video.id
        else { return }
        let requestID = UUID()
        downloadRequestID = requestID
        downloadTask = Task { [weak self] in
            guard !Task.isCancelled, backend.isCurrent(), self?.downloadRequestID == requestID else { return }
            self?.ownsDownload = true
            let downloaded = try? await backend.download(videoFileID, false)
            guard let self, downloadRequestID == requestID else { return }
            downloadTask = nil
            downloadRequestID = nil
            guard let downloaded, !Task.isCancelled, backend.isCurrent() else { return }
            update(file: downloaded)
        }
    }

    private func update(file: File) {
        guard backend?.isCurrent() == true, !isRevoked, videoNote?.video.id == file.id else { return }
        if isSecret {
            if secretAcknowledged, !file.local.isDownloadingCompleted { revoke() }
            return
        }
        guard
            file.local.isDownloadingCompleted,
            !file.local.path.isEmpty
        else { return }
        ownsDownload = false
        guard representedPath != file.local.path else { return }
        representedPath = file.local.path
        player.load(url: URL(filePath: file.local.path), autoplay: false, loops: false)
        autoplayView.setFile(path: file.local.path)
        updateAutoplay()
        startRequestedPlaylistPlayback()
        reclaimFromFloatingPlayer()
    }

    /// The silent loop runs while the note shows and isn't playing, or paused, with sound.
    private func updateAutoplay() {
        autoplayView.setActive(
            playbackVisible && !isSecret && !isRevoked && !hasStartedPlayback && !player.isPlaybackRequested,
        )
    }

    private func renderPlayerState(_ state: LocalMediaPlayer.State) {
        if case .ended = state, hasStartedPlayback, !isSecret, let message, let backend, backend.isCurrent() {
            Self.playbackFinished.send(PlaylistItem(
                source: backend.source,
                chatID: message.chatId,
                messageID: message.id,
            ))
        }
        currentPlayerState = state
        progressLayer.isHidden = state != .playing
        switch state {
        case .playing:
            Self.activePlaybackView = self
            hasStartedPlayback = true
            playIcon.isHidden = true
            accessibilityValue = L10n.betterTG("Accessibility.Playing")
        case .buffering,
             .preparing:
            playIcon.image = UIImage(systemName: "clock.fill")
            playIcon.isHidden = false
            accessibilityValue = L10n.betterTG("Accessibility.Loading")
        case .failed:
            playIcon.image = UIImage(systemName: "exclamationmark.circle.fill")
            playIcon.isHidden = false
            accessibilityValue = L10n.betterTG("Accessibility.PlaybackFailed")
        case .paused:
            if Self.activePlaybackView === self { Self.activePlaybackView = nil }
            playIcon.image = UIImage(systemName: "play.fill")
            playIcon.isHidden = isSecret || !hasStartedPlayback
            accessibilityValue = representedPath == nil
                ? L10n.betterTG("Accessibility.Downloading")
                : L10n.betterTG("Accessibility.Paused")
        case .ended,
             .idle:
            proximityControl.end()
            if Self.activePlaybackView === self { Self.activePlaybackView = nil }
            hasStartedPlayback = false
            playIcon.isHidden = true
            progressLayer.strokeEnd = 0
            accessibilityValue = representedPath == nil
                ? L10n.betterTG("Accessibility.Downloading")
                : L10n.betterTG("Accessibility.ReadyToPlay")
        }
        updateAutoplay()
    }

    private func revealSecretAndPlay() {
        guard supportsSecretHold, playbackVisible, permitsSecretDisplay, secretHoldID == nil,
              let backend, let message, backend.isCurrent() else { return }
        let token = UUID()
        secretHoldID = token
        secretOpenTask = Task { [weak self] in
            defer {
                if let self, secretHoldID == token {
                    secretOpenTask = nil
                    if !secretAcknowledged { concealSecret() }
                }
            }
            do {
                guard self?.isCurrentHold(token) == true else { return }
                let requestedAt = backend.now()
                let latest = try await backend.message(message.chatId, message.id)
                guard self?.isCurrentHold(token) == true, self?.matches(latest) == true,
                      self?.acceptDeadline(latest, requestedAt: requestedAt, token: token) == true,
                      case .messageVideoNote(let value) = latest.content else { return }
                var file = value.videoNote.video
                if !file.local.isDownloadingCompleted {
                    self?.ownsDownload = true
                    file = try await backend.download(file.id, true)
                    if self?.secretHoldID == token { self?.ownsDownload = false }
                }
                guard self?.isCurrentHold(token) == true, file.id == value.videoNote.video.id,
                      file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return }
                let checkedAt = backend.now()
                let checked = try await backend.message(message.chatId, message.id)
                guard self?.isCurrentHold(token) == true, self?.matches(checked) == true,
                      self?.acceptDeadline(checked, requestedAt: checkedAt, token: token) == true else { return }
                try await backend.open(message.chatId, message.id)
                guard self?.isCurrentHold(token) == true else { return }
                let openedAt = backend.now()
                let opened = try await backend.message(message.chatId, message.id)
                guard let self, isCurrentHold(token), matches(opened), opened.selfDestructIn > 0,
                      acceptDeadline(opened, requestedAt: openedAt, token: token) else { return }
                secretOpenTask = nil
                secretAcknowledged = true
                representedPath = file.local.path
                player.load(url: URL(filePath: file.local.path), autoplay: false, loops: false)
                guard beginExclusivePlayback(), isCurrentHold(token) else { concealSecret()
                    return
                }
                player.play()
            } catch {
                guard self?.secretHoldID == token else { return }
                self?.concealSecret()
                self?.accessibilityValue = L10n.betterTG("Accessibility.CouldNotOpen")
            }
        }
    }

    private func concealSecret() {
        secretHoldID = nil
        secretAcknowledged = false
        secretOpenTask?.cancel()
        secretOpenTask = nil
        secretDeadlineTask?.cancel()
        secretDeadlineTask = nil
        if isSecret {
            cancelDownload()
            player.stop()
            representedPath = nil
            playerSurface.isHidden = true
            playerSurface.alpha = 0
        }
        secretBlurView.isHidden = false
    }

    private func matches(_ latest: Message) -> Bool {
        guard let message, case .messageVideoNote(let value) = latest.content else { return false }
        return latest.chatId == message.chatId && latest.id == message.id && latest.editDate == message.editDate
            && latest.topicId == message.topicId && latest.selfDestructType == message.selfDestructType && !latest
            .isOutgoing
            && value.isSecret && value.videoNote.video.id == videoNote?.video.id
    }

    private func isCurrentHold(_ token: UUID) -> Bool {
        !Task.isCancelled && secretHoldID == token && !isRevoked && playbackVisible && backend?.isCurrent() == true
            && permitsSecretDisplay
            && (secretDeadline.map { $0 > (backend?.now() ?? .infinity) } ?? true)
    }

    private func acceptDeadline(_ value: Message, requestedAt: TimeInterval, token: UUID) -> Bool {
        guard value.selfDestructIn.isFinite, value.selfDestructIn >= 0, let backend else { return false }
        if value.selfDestructIn > 0 {
            secretDeadline = min(secretDeadline ?? .infinity, requestedAt + value.selfDestructIn)
            secretDeadlineTask?.cancel()
            secretDeadlineTask = Task { [weak self] in
                do {
                    try await backend.sleep(max(0, (self?.secretDeadline ?? 0) - backend.now()))
                } catch {
                    return
                }
                guard let self, secretHoldID == token, !Task.isCancelled else { return }
                revoke()
            }
        }
        return isCurrentHold(token)
    }

    private func cancelDownload() {
        downloadRequestID = nil
        downloadTask?.cancel()
        downloadTask = nil
        guard ownsDownload, let backend, let fileID = videoNote?.video.id else { return }
        ownsDownload = false
        Task { [weak self] in
            if let self, self.backend?.source == backend.source, videoNote?.video.id == fileID,
               downloadRequestID != nil || secretHoldID != nil { return }
            await backend.cancelDownload(fileID)
        }
    }

    private func revoke() {
        proximityControl.end()
        concealSecret()
        cancelDownload()
        isRevoked = true
        player.stop()
        thumbnailView.cancel()
        thumbnailView.image = nil
        representedPath = nil
        playerSurface.isHidden = true
        accessibilityValue = L10n.betterTG("Accessibility.ProtectedMessageUnavailable")
    }

    private func setPlayerSurfaceReady(_ isReady: Bool) {
        guard isReady, playerSurface.playerLayer.isReadyForDisplay, representedPath != nil,
              backend?.isCurrent() == true, !isRevoked,
              !isSecret || (secretHoldID.map(isCurrentHold) == true && secretAcknowledged)
        else {
            playerSurface.isHidden = true
            playerSurface.alpha = 0
            return
        }
        if isSecret { secretBlurView.isHidden = true }
        guard playerSurface.isHidden else { return }
        playerSurface.alpha = 0
        playerSurface.isHidden = false
        UIView.animate(withDuration: 0.16) {
            self.playerSurface.alpha = 1
        }
    }

    private func format(_ duration: Int) -> String {
        let duration = max(0, duration)
        return String(format: "%d:%02d", duration / 60, duration % 60)
    }

    @objc private func tapped() {
        if let deferredDownload, !isSecret {
            if deferredDownload.isDownloading {
                playsWhenDownloaded = false
                deferredDownload.cancel()
            } else {
                playsWhenDownloaded = true
                deferredDownload.start()
            }
            return
        }
        guard !isSecret, representedPath != nil, playbackVisible, backend?.isCurrent() == true,
              !isRevoked else { return }
        if player.isPlaybackRequested {
            player.pause()
        } else if case .ended = currentPlayerState {
            guard beginExclusivePlayback() else { return }
            markViewed()
            let bindingID = configurationID
            player.seek(to: 0) { [weak self] in
                guard let self, configurationID == bindingID, backend?.isCurrent() == true,
                      !isRevoked, playbackVisible else { return }
                player.play()
            }
        } else {
            guard beginExclusivePlayback() else { return }
            markViewed()
            player.play()
        }
    }

    /// Telegram marks an instant video consumed when its playback starts. TDLib's openMessageContent on the message's
    /// own client marks it viewed, which the sender sees.
    private func markViewed() {
        guard !isViewed, !isSecret, let message, !message.isOutgoing, let backend, backend.isCurrent() else { return }
        isViewed = true
        let bindingID = configurationID
        Task { [weak self] in
            do {
                try await backend.open(message.chatId, message.id)
            } catch {
                guard let self, configurationID == bindingID else { return }
                isViewed = false
            }
        }
    }

    private func beginExclusivePlayback() -> Bool {
        let bindingID = configurationID
        if let active = Self.activePlaybackView, active !== self {
            active.pauseForCompetingPlayback()
        }
        FloatingVideoNotePlayer.shared.stop(unless: playlistItem)
        Self.activePlaybackView = self
        backend?.takePlayback()
        if !isSecret { proximityControl.begin(player: player) }
        return configurationID == bindingID && backend?.isCurrent() == true && !isRevoked
    }

    /// Starts the playlist's requested instant video once this view shows it with its file loaded.
    private func startRequestedPlaylistPlayback() {
        guard let request = Self.playlistRequest else { return }
        guard request.expiresAt > ProcessInfo.processInfo.systemUptime else {
            Self.playlistRequest = nil
            return
        }
        guard let message, let backend, backend.isCurrent(), backend.source == request.item.source,
              message.chatId == request.item.chatID, message.id == request.item.messageID,
              !isSecret, !isRevoked, representedPath != nil, playbackVisible || window != nil
        else { return }
        Self.playlistRequest = nil
        guard !player.isPlaybackRequested, beginExclusivePlayback() else { return }
        markViewed()
        if case .ended = currentPlayerState {
            let bindingID = configurationID
            player.seek(to: 0) { [weak self] in
                guard let self, configurationID == bindingID, backend.isCurrent(), !isRevoked else { return }
                player.play()
            }
        } else {
            player.play()
        }
    }

    private func pauseForCompetingPlayback() {
        guard Self.activePlaybackView === self else { return }
        proximityControl.end()
        if isSecret { concealSecret() } else { player.pause() }
        Self.activePlaybackView = nil
    }
}

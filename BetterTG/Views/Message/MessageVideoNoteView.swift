// MessageVideoNoteView.swift

import AVFoundation
import Combine
import TDLibKit
import UIKit

final class VideoNotePlaybackView: UIControl, ReusableMediaView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        observePlayer()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        downloadTask?.cancel()
        secretOpenTask?.cancel()
        player.stop()
    }

    func configure(
        videoNote: VideoNote,
        isSecret: Bool,
        chatID: Int64,
        messageID: Int64,
    ) {
        prepareForReuse()
        self.videoNote = videoNote
        self.isSecret = isSecret
        self.chatID = chatID
        self.messageID = messageID
        sideConstraint.constant = min(260, max(180, CGFloat(videoNote.length)))
        durationLabel.text = format(videoNote.duration)
        if let thumbnail = videoNote.thumbnail {
            thumbnailView.load(
                file: thumbnail.file,
                placeholderData: videoNote.minithumbnail?.data,
                maximumPixelSize: 520,
            )
        } else {
            if let data = videoNote.minithumbnail?.data {
                thumbnailView.image = UIImage(data: data)
            }
        }
        secretBlurView.isHidden = !isSecret
        accessibilityLabel = "Video message, \(format(videoNote.duration))"
        accessibilityHint = isSecret ? "Touch and hold to open" : "Double-tap to play or pause"
        update(file: videoNote.video)
        fileCancellable = nc.publisher(for: .updateFile)
            .receive(on: DispatchQueue.main)
            .filter { $0.file.id == videoNote.video.id }
            .sink { [weak self] update in self?.update(file: update.file) }
        startDownloadIfNeeded()
        renderPlayerState(.idle)
    }

    func prepareForReuse() {
        let fileID = videoNote?.video.id
        downloadRequestID = nil
        downloadTask?.cancel()
        downloadTask = nil
        fileCancellable?.cancel()
        fileCancellable = nil
        player.stop()
        secretOpenTask?.cancel()
        secretOpenTask = nil
        if Self.activePlaybackView === self {
            Self.activePlaybackView = nil
        }
        playerSurface.isHidden = true
        thumbnailView.cancel()
        thumbnailView.image = nil
        representedPath = nil
        videoNote = nil
        isSecret = false
        isSecretTouchActive = false
        hasOpenedSecret = false
        chatID = nil
        messageID = nil
        playbackVisible = false
        progressLayer.strokeEnd = 0
        if let fileID {
            Task { try? await td.cancelDownloadFile(fileId: fileID, onlyIfPending: true) }
        }
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        playbackVisible = isVisible
        if !isVisible {
            if isSecret {
                concealSecret()
            } else {
                player.pause()
            }
            downloadRequestID = nil
            downloadTask?.cancel()
            downloadTask = nil
            if let fileID = videoNote?.video.id, representedPath == nil {
                Task { try? await td.cancelDownloadFile(fileId: fileID, onlyIfPending: true) }
            }
        } else {
            startDownloadIfNeeded()
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
        secretBlurView.layer.cornerRadius = bounds.width / 2
        progressLayer.frame = bounds
        progressLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).cgPath
        progressLayer.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 2))
    }

    private let player = LocalMediaPlayer()
    private static weak var activePlaybackView: VideoNotePlaybackView?
    private let thumbnailView = TDImageLoadingView()
    private let playerSurface = LocalVideoSurfaceView()
    private let playIcon = UIImageView()
    private let durationLabel = UILabel()
    private let secretBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let progressLayer = CAShapeLayer()
    private lazy var sideConstraint = widthAnchor.constraint(equalToConstant: 220)
    private var videoNote: VideoNote?
    private var representedPath: String?
    private var isSecret = false
    private var isSecretTouchActive = false
    private var hasOpenedSecret = false
    private var chatID: Int64?
    private var messageID: Int64?
    private var playbackVisible = false
    private var downloadTask: Task<Void, Never>?
    private var downloadRequestID: UUID?
    private var fileCancellable: AnyCancellable?
    private var secretOpenTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private func configureViews() {
        clipsToBounds = true
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
        playerSurface.isHidden = true
        player.attach(to: playerSurface.playerLayer)
        player.setMuted(false)
        addSubview(playerSurface)
        playerSurface.playerLayer.publisher(for: \.isReadyForDisplay, options: [.initial, .new])
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
            durationLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            durationLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
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
                durationLabel.text = "\(format(Int(time))) / \(format(videoNote.duration))"
            }
            .store(in: &cancellables)
        Media.shared.$isPlaying
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard isPlaying else { return }
                self?.pauseForCompetingPlayback()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setPlaybackVisible(false) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, window != nil else { return }
                setPlaybackVisible(true)
            }
            .store(in: &cancellables)
    }

    private func startDownloadIfNeeded() {
        guard playbackVisible || window != nil,
              representedPath == nil,
              downloadTask == nil,
              let videoFileID = videoNote?.video.id
        else { return }
        let requestID = UUID()
        downloadRequestID = requestID
        downloadTask = Task { [weak self] in
            let downloaded = await withTaskCancellationHandler {
                try? await td.downloadFile(
                    fileId: videoFileID,
                    limit: 0,
                    offset: 0,
                    priority: 2,
                    synchronous: false,
                )
            } onCancel: {
                Task { try? await td.cancelDownloadFile(fileId: videoFileID, onlyIfPending: true) }
            }
            guard let self, downloadRequestID == requestID else { return }
            downloadTask = nil
            downloadRequestID = nil
            guard let downloaded, !Task.isCancelled else { return }
            update(file: downloaded)
        }
    }

    private func update(file: File) {
        guard videoNote?.video.id == file.id,
              file.local.isDownloadingCompleted,
              !file.local.path.isEmpty
        else { return }
        representedPath = file.local.path
        player.load(url: URL(filePath: file.local.path), autoplay: false, loops: false)
    }

    private func renderPlayerState(_ state: LocalMediaPlayer.State) {
        currentPlayerState = state
        switch state {
        case .playing:
            Self.activePlaybackView = self
            playIcon.image = UIImage(systemName: "pause.fill")
            playIcon.isHidden = isSecret
            accessibilityValue = "Playing"
        case .buffering, .preparing:
            playIcon.image = UIImage(systemName: "clock.fill")
            playIcon.isHidden = false
            accessibilityValue = "Loading"
        case .failed:
            playIcon.image = UIImage(systemName: "exclamationmark.circle.fill")
            playIcon.isHidden = false
            accessibilityValue = "Playback failed"
        case .ended, .idle, .paused:
            if Self.activePlaybackView === self {
                Self.activePlaybackView = nil
            }
            playIcon.image = UIImage(systemName: "play.fill")
            playIcon.isHidden = isSecret
            accessibilityValue = representedPath == nil ? "Downloading" : "Paused"
        }
    }

    private func revealSecretAndPlay() {
        guard representedPath != nil, playbackVisible else { return }
        isSecretTouchActive = true
        if hasOpenedSecret {
            revealOpenedSecret()
            return
        }
        guard secretOpenTask == nil, let chatID, let messageID else { return }
        secretOpenTask = Task { [weak self] in
            do {
                _ = try await td.openMessageContent(chatId: chatID, messageId: messageID)
                try Task.checkCancellation()
                guard let self else { return }
                secretOpenTask = nil
                hasOpenedSecret = true
                guard isSecretTouchActive else { return }
                revealOpenedSecret()
            } catch is CancellationError {
                self?.secretOpenTask = nil
                return
            } catch {
                self?.secretOpenTask = nil
                self?.accessibilityValue = "Couldn’t open"
            }
        }
    }

    private func concealSecret() {
        isSecretTouchActive = false
        player.pause()
        player.seek(to: 0)
        secretBlurView.isHidden = false
    }

    private func revealOpenedSecret() {
        secretBlurView.isHidden = true
        beginExclusivePlayback()
        player.play()
    }

    private func setPlayerSurfaceReady(_ isReady: Bool) {
        guard isReady, representedPath != nil else {
            playerSurface.isHidden = true
            playerSurface.alpha = 0
            return
        }
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
        guard !isSecret, representedPath != nil, playbackVisible else { return }
        if player.isPlaybackRequested {
            player.pause()
        } else if case .ended = currentPlayerState {
            beginExclusivePlayback()
            player.seek(to: 0) { [weak self] in self?.player.play() }
        } else {
            beginExclusivePlayback()
            player.play()
        }
    }

    private func beginExclusivePlayback() {
        if let active = Self.activePlaybackView, active !== self {
            active.player.pause()
        }
        Self.activePlaybackView = self
        Media.shared.beginExclusivePlayback()
    }

    private func pauseForCompetingPlayback() {
        guard Self.activePlaybackView === self else { return }
        player.pause()
        Self.activePlaybackView = nil
    }

    private var currentPlayerState: LocalMediaPlayer.State = .idle
}

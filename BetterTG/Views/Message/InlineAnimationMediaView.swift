// InlineAnimationMediaView.swift

import AVFoundation
import TDLibKit
import UIKit

/// Telegram's MP4 animations loop silently inside the message, without gallery controls.
final class InlineAnimationMediaView: UIView, ReusableMediaView {
    private let thumbnailView = TDImageLoadingView()
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    private var downloadTask: Task<Void, Never>?
    private var generation = UUID()
    private var playbackVisible = false
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 180)
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 180)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityLabel = L10n.telegram("Message.Animation")
        accessibilityTraits = .image
        thumbnailView.contentMode = .scaleAspectFit
        addSubview(thumbnailView)
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        thumbnailView.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    func configure(animation: Animation, displaySize: CGSize, client: TDLibClient) {
        prepareForReuse()
        widthConstraint.constant = displaySize.width
        heightConstraint.constant = displaySize.height
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])
        if let thumbnail = animation.thumbnail {
            thumbnailView.load(file: thumbnail.file, placeholderData: animation.minithumbnail?.data, client: client)
        } else {
            thumbnailView.loadPlaceholder(data: animation.minithumbnail?.data, client: client)
        }
        let file = animation.animation
        if file.local.isDownloadingCompleted, !file.local.path.isEmpty {
            installPlayer(path: file.local.path)
            return
        }
        let generation = generation
        downloadTask = Task { [weak self] in
            guard let downloaded = try? await client.downloadFile(
                fileId: file.id, limit: 0, offset: 0, priority: 2, synchronous: true,
            ), !Task.isCancelled,
            let self, self.generation == generation,
            downloaded.local.isDownloadingCompleted, !downloaded.local.path.isEmpty
            else { return }
            installPlayer(path: downloaded.local.path)
        }
    }

    func prepareForReuse() {
        generation = UUID()
        downloadTask?.cancel()
        downloadTask = nil
        readyObservation = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        playerLayer.player = nil
        player = nil
        playbackVisible = false
        thumbnailView.cancel()
        thumbnailView.isHidden = false
        NSLayoutConstraint.deactivate([widthConstraint, heightConstraint])
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        playbackVisible = isVisible
        updatePlayback()
    }

    private func installPlayer(path: String) {
        let player = AVQueuePlayer()
        player.isMuted = true
        self.player = player
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: URL(fileURLWithPath: path)))
        playerLayer.player = player
        let generation = generation
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                thumbnailView.isHidden = ready
            }
        }
        updatePlayback()
    }

    private func updatePlayback() {
        let animationsEnabled = UserDefaults.standard.object(forKey: "animatedMediaEnabled") as? Bool ?? true
        if playbackVisible, window != nil, animationsEnabled {
            player?.play()
        } else {
            player?.pause()
        }
    }
}

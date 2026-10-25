// InlineAnimationMediaView.swift

import AVFoundation
import TDLibKit
import UIKit

/// Telegram's MP4 animations loop silently inside the message, without gallery controls.
final class InlineAnimationMediaView: UIView, ReusableMediaView {
    /// Crop to fill instead of fitting, as the GIF panel's square cells do.
    var fillsBounds = false {
        didSet {
            playerLayer.videoGravity = fillsBounds ? .resizeAspectFill : .resizeAspect
            thumbnailView.contentMode = fillsBounds ? .scaleAspectFill : .scaleAspectFit
        }
    }

    private let thumbnailView = TDImageLoadingView()
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    /// The shared demand cancels a pending download once no view wants the file, so scrolling the GIF panel
    /// doesn't leave downloads running for cells that left.
    private var fileRequest: AnimatedFileDownload?
    private var generation = UUID()
    private var playbackVisible = false
    private var energyObserver: NSObjectProtocol?
    /// A bubble opens the gallery on tap, as Telegram's `ChatMessageInteractiveMediaNode` does; panel cells pass nil.
    private var onTap: (() -> Void)?
    private lazy var tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapped))
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
        self.energyObserver = NotificationCenter.default.addObserver(
            forName: EnergyUsage.didChange,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePlayback() }
        }
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

    override func accessibilityActivate() -> Bool {
        guard let onTap else { return false }
        onTap()
        return true
    }

    /// Without a display size the owner sizes the view.
    func configure(animation: Animation, displaySize: CGSize?, client: TDLibClient, onTap: (() -> Void)? = nil) {
        prepareForReuse()
        self.onTap = onTap
        if onTap != nil, tapRecognizer.view == nil { addGestureRecognizer(tapRecognizer) }
        tapRecognizer.isEnabled = onTap != nil
        isUserInteractionEnabled = onTap != nil
        accessibilityTraits = onTap == nil ? .image : [.image, .button]
        if let displaySize {
            widthConstraint.constant = displaySize.width
            heightConstraint.constant = displaySize.height
            NSLayoutConstraint.activate([widthConstraint, heightConstraint])
        }
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
        guard let request = AnimatedFileDownload(fileID: file.id, client: client) else { return }
        fileRequest = request
        request.start(file: file, onFile: { [weak self, weak request] file in
            guard let self, let request, fileRequest === request, player == nil,
                  file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return }
            installPlayer(path: file.local.path)
        }, onInvalidated: { [weak self, weak request] in
            guard let self, let request, fileRequest === request else { return }
            fileRequest = nil
        })
    }

    func prepareForReuse() {
        generation = UUID()
        fileRequest?.cancel()
        fileRequest = nil
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

    @objc private func tapped() { onTap?() }

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
        // Power Saving's Autoplay GIFs: off, a GIF shows its first frame until the gallery opens it.
        if playbackVisible, window != nil, animationsEnabled, EnergyUsage.shared.allows(.autoplayGif) {
            player?.play()
        } else {
            player?.pause()
        }
    }
}

// MutedVideoLoopView.swift

import AVFoundation
import UIKit

// MARK: - MutedVideoLoopView

/// Telegram's automatic playback of a downloaded video message in the chat: the file loops silently
/// while its bubble shows and Power Saving's Autoplay Videos allows it, and the view stays clear until its first
/// frame is ready, so the thumbnail under it shows until then.
final class MutedVideoLoopView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    /// Whether a frame shows, so the owner can hide what this view covers.
    var onReadyChange: ((Bool) -> Void)?

    private(set) var isReady = false

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    private var energyObserver: NSObjectProtocol?
    private var path: String?
    private var isActive = false

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private var shouldPlay: Bool {
        isActive && window != nil && path != nil && EnergyUsage.shared.allows(.autoplayVideo)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspectFill
        isHidden = true
        self.energyObserver = NotificationCenter.default.addObserver(
            forName: EnergyUsage.didChange,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        update()
    }

    /// The downloaded file to loop; nil stops and clears.
    func setFile(path: String?) {
        guard path != self.path else { return }
        self.path = path
        teardown()
        update()
    }

    /// Whether the owner wants the loop now: its bubble shows and nothing else plays the file.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        update()
    }

    private func update() {
        guard shouldPlay, let path else {
            player?.pause()
            setReady(false)
            return
        }
        if player == nil {
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: URL(fileURLWithPath: path)))
            playerLayer.player = player
            self.player = player
            readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [
                .initial,
                .new,
            ]) { [weak self] layer, _ in
                let ready = layer.isReadyForDisplay
                Task { @MainActor [weak self] in
                    guard let self, self.player === player else { return }
                    setReady(ready && shouldPlay)
                }
            }
        }
        player?.play()
        setReady(playerLayer.isReadyForDisplay)
    }

    private func setReady(_ ready: Bool) {
        isHidden = !ready
        guard ready != isReady else { return }
        isReady = ready
        onReadyChange?(ready)
    }

    private func teardown() {
        readyObservation = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        playerLayer.player = nil
        player = nil
        setReady(false)
    }
}

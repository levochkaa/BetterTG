// VideoEditViewController.swift

import AVFoundation
import Combine
import Photos
import UIKit

// MARK: - VideoEditViewController

/// TGMediaPickerGalleryVideoItemView's editing of a picked video, opened from the attachment sheet: the scrubber with
/// the trim on top, the player with its play button, the mute button that sends the video as a GIF, and Cancel and
/// Done in TGPhotoEditorController's toolbar. Done hands back the trim and mute, or nothing for the video as it was;
/// Cancel asks before it drops changes.
final class VideoEditViewController: UIViewController {
    // MARK: Private

    /// `TGPhotoEditorToolbarSize`.
    private static let toolbarHeight: CGFloat = 49
    private static let playButtonSide: CGFloat = 60
    /// TGMediaPickerGalleryInterfaceView's mute button.
    private static let muteButtonSide: CGFloat = 40
    /// The app's tint for Done and the muted state, where Telegram uses its accent.
    private static let activeColor = UIColor.systemBlue
    /// `play` starts over from the trim's start this close to its end.
    private static let restartThreshold = 0.5

    override var prefersStatusBarHidden: Bool {
        true
    }

    // MARK: Internal

    /// The finished edit; `nil` when the whole video goes with its sound.
    var onDone: ((VideoEditAdjustments?) -> Void)?

    private let asset: AVAsset
    private let initialAdjustments: VideoEditAdjustments
    private var allowsTrimming: Bool
    private var sendsAsGIF: Bool
    private let player = AVPlayer()
    private let playerView = LocalVideoSurfaceView()
    private let scrubber = VideoScrubberView()
    private let playButton = UIButton(type: .custom)
    private let muteButton = UIButton(type: .custom)
    private let toolbarView = UIView()
    private let cancelButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private var duration: Double = 0
    /// The edit as the editor first showed it, for Cancel's test.
    private var loadedAdjustments: VideoEditAdjustments?
    private var isPlaying = false
    private var wasPlayingBeforeScrubbing = false
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    /// `_chaseTime`: the latest seek target while earlier seeks finish.
    private var chaseTarget = CMTime.invalid
    private var isChasingTime = false

    private var currentAdjustments: VideoEditAdjustments {
        var adjustments = VideoEditAdjustments()
        if scrubber.hasTrimming, scrubber.trimStart < scrubber.trimEnd {
            adjustments.trimRange = scrubber.trimStart...scrubber.trimEnd
        }
        adjustments.sendsAsGIF = sendsAsGIF
        return adjustments
    }

    private var hasChanges: Bool {
        guard let loadedAdjustments else { return false }
        return currentAdjustments != loadedAdjustments
    }

    /// `allowsTrimming` is false for slow-motion videos, which Telegram doesn't trim (`itemIsHighFramerateVideo`).
    init(asset: AVAsset, adjustments: VideoEditAdjustments?, allowsTrimming: Bool = true) {
        self.asset = asset
        self.initialAdjustments = adjustments ?? VideoEditAdjustments()
        self.allowsTrimming = allowsTrimming
        self.sendsAsGIF = adjustments?.sendsAsGIF ?? false
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
        modalPresentationCapturesStatusBarAppearance = true
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        playerView.playerLayer.player = player
        playerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(videoTapped)))
        view.addSubview(playerView)
        configureScrubber()
        configurePlayButton()
        configureMuteButton()
        configureToolbar()
        loadVideo()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let safeArea = view.safeAreaInsets
        let toolbarTop = bounds.height - safeArea.bottom - Self.toolbarHeight
        toolbarView.frame = CGRect(
            x: 0,
            y: toolbarTop,
            width: bounds.width,
            height: Self.toolbarHeight + safeArea.bottom,
        )
        cancelButton.frame = CGRect(x: 0, y: 0, width: Self.toolbarHeight, height: Self.toolbarHeight)
        doneButton.frame = CGRect(
            x: bounds.width - Self.toolbarHeight,
            y: 0,
            width: Self.toolbarHeight,
            height: Self.toolbarHeight,
        )
        // The scrubber sits in TGMediaPickerScrubberHeaderView's panel at the top.
        scrubber.frame = CGRect(
            x: safeArea.left,
            y: safeArea.top,
            width: bounds.width - safeArea.left - safeArea.right,
            height: VideoScrubberView.preferredHeight,
        )
        let videoTop = scrubber.frame.maxY + 8
        playerView.frame = CGRect(
            x: safeArea.left,
            y: videoTop,
            width: bounds.width - safeArea.left - safeArea.right,
            height: max(0, toolbarTop - 8 - videoTop),
        )
        playButton.bounds = CGRect(x: 0, y: 0, width: Self.playButtonSide, height: Self.playButtonSide)
        playButton.center = CGPoint(x: playerView.frame.midX, y: playerView.frame.midY)
        // `_muteButtonFrameForOrientation:`: the video's bottom left corner, above the toolbar.
        muteButton.frame = CGRect(
            x: safeArea.left + 12,
            y: toolbarTop - Self.muteButtonSide - 12,
            width: Self.muteButtonSide,
            height: Self.muteButtonSide,
        )
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    /// The library video as the Photos app plays it, edits included, read from iCloud when needed.
    static func loadAsset(for asset: PHAsset, completion: @escaping (AVAsset?) -> Void) {
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { video, _, info in
            if video == nil {
                log("Could not read the video to edit: \(String(describing: info?[PHImageErrorKey]))")
            }
            DispatchQueue.main.async {
                completion(video)
            }
        }
    }

    private func configureScrubber() {
        scrubber.isHidden = true
        scrubber.onBeginScrubbing = { [weak self] in
            guard let self else { return }
            wasPlayingBeforeScrubbing = isPlaying
            pause()
            setPlayButtonHidden(true, animated: false)
        }
        scrubber.onScrub = { [weak self] position in
            self?.seek(to: position)
        }
        scrubber.onEndScrubbing = { [weak self] in
            guard let self else { return }
            if wasPlayingBeforeScrubbing {
                play()
            } else {
                setPlayButtonHidden(false, animated: true)
            }
        }
        scrubber.onBeginTrimming = { [weak self] in
            guard let self else { return }
            pause()
            setPlayButtonHidden(true, animated: false)
        }
        scrubber.onTrimEdgeChanged = { [weak self] position in
            self?.seek(to: position)
        }
        scrubber.onEndTrimming = { [weak self] in
            guard let self else { return }
            updatePlayerRange()
            setPlayButtonHidden(false, animated: true)
        }
        view.addSubview(scrubber)
    }

    private func configurePlayButton() {
        playButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        playButton.layer.cornerRadius = Self.playButtonSide / 2
        playButton.setImage(
            UIImage(
                systemName: "play.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular),
            ),
            for: .normal,
        )
        playButton.tintColor = .white
        playButton.accessibilityLabel = L10n.telegram("VoiceOver.Media.PlaybackPlay")
        playButton.addTarget(self, action: #selector(playPressed), for: .touchUpInside)
        playButton.isHidden = true
        view.addSubview(playButton)
    }

    /// TGMediaPickerGalleryInterfaceView's mute button: the speaker on a dark circle, crossed out in the accent
    /// while the video goes as a GIF.
    private func configureMuteButton() {
        let configuration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        muteButton.setImage(
            UIImage(systemName: "speaker.wave.2.fill", withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal),
            for: .normal,
        )
        let mutedImage = UIImage(systemName: "speaker.slash.fill", withConfiguration: configuration)?
            .withTintColor(Self.activeColor, renderingMode: .alwaysOriginal)
        muteButton.setImage(mutedImage, for: .selected)
        muteButton.setImage(mutedImage, for: [.selected, .highlighted])
        muteButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        muteButton.layer.cornerRadius = Self.muteButtonSide / 2
        muteButton.accessibilityLabel = L10n.betterTG("Accessibility.VideoEditor.Mute")
        muteButton.addTarget(self, action: #selector(mutePressed), for: .touchUpInside)
        muteButton.isHidden = true
        updateMuteButton()
        view.addSubview(muteButton)
    }

    private func configureToolbar() {
        toolbarView.backgroundColor = .black
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let items: [(button: UIButton, symbol: String, label: String, action: Selector)] = [
            (cancelButton, "xmark", L10n.telegram("Common.Cancel"), #selector(cancelPressed)),
            (doneButton, "checkmark", L10n.telegram("Common.Done"), #selector(donePressed)),
        ]
        for item in items {
            item.button.setImage(UIImage(systemName: item.symbol, withConfiguration: symbolConfiguration), for: .normal)
            item.button.tintColor = .white
            item.button.accessibilityLabel = item.label
            item.button.addTarget(self, action: item.action, for: .touchUpInside)
            toolbarView.addSubview(item.button)
        }
        doneButton.tintColor = Self.activeColor
        view.addSubview(toolbarView)
    }

    // MARK: Loading

    private func loadVideo() {
        let asset = asset
        Task { [weak self] in
            do {
                let duration = try await asset.load(.duration).seconds
                var aspectRatio: CGFloat = 1
                if let track = try await asset.loadTracks(withMediaType: .video).first {
                    let naturalSize = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let presented = CGRect(origin: .zero, size: naturalSize).applying(transform).size
                    if presented.height > 0 {
                        aspectRatio = presented.width / presented.height
                    }
                }
                self?.didLoad(duration: duration, aspectRatio: aspectRatio)
            } catch {
                log("Could not read the video to edit: \(error)")
            }
        }
    }

    /// `preparePlayerAndPlay:` without playing: the player starts at the trim and stops at its end.
    private func didLoad(duration: Double, aspectRatio: CGFloat) {
        guard duration.isFinite, duration > 0 else { return }
        self.duration = duration
        // `allowsTrimming`: videos shorter than `TGVideoEditMinimumTrimmableDuration` aren't trimmed.
        allowsTrimming = allowsTrimming && duration >= VideoEditAdjustments.minimumTrimmableDuration
        scrubber.allowsTrimming = allowsTrimming
        scrubber.configure(
            asset: asset,
            duration: duration,
            aspectRatio: aspectRatio,
            trimRange: allowsTrimming ? initialAdjustments.trimRange : nil,
        )
        scrubber.isHidden = false
        loadedAdjustments = currentAdjustments
        let item = AVPlayerItem(asset: asset)
        player.actionAtItemEnd = .none
        player.replaceCurrentItem(with: item)
        player.isMuted = sendsAsGIF
        NotificationCenter.default
            .publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.playerItemDidPlayToEnd() }
            .store(in: &cancellables)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main,
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.playerTimeChanged(time) }
        }
        updatePlayerRange()
        seek(to: scrubber.trimStart)
        muteButton.isHidden = false
        // A muted video plays at once, as Telegram's gallery loops a GIF.
        if sendsAsGIF {
            play()
        } else {
            setPlayButtonHidden(false, animated: false)
        }
    }

    // MARK: Playback

    private func playerTimeChanged(_ time: CMTime) {
        guard isPlaying, time.seconds.isFinite else { return }
        scrubber.setPlaybackPosition(time.seconds)
    }

    /// `play`: near the trim's end it starts over from the trim's start.
    private func play() {
        guard player.currentItem != nil else { return }
        isPlaying = true
        setPlayButtonHidden(true, animated: true)
        let current = player.currentTime().seconds
        if !current.isFinite || abs(scrubber.trimEnd - current) < Self.restartThreshold {
            seek(to: scrubber.trimStart)
            scrubber.setPlaybackPosition(scrubber.trimStart)
        }
        player.play()
    }

    private func pause() {
        isPlaying = false
        player.pause()
    }

    /// `playerItemDidPlayToEndTime:`: a GIF loops; a video stops with its play button at the trim's start.
    private func playerItemDidPlayToEnd() {
        if sendsAsGIF {
            scrubber.setPlaybackPosition(scrubber.trimStart)
        } else {
            pause()
            setPlayButtonHidden(false, animated: true)
            scrubber.resetToStart()
        }
        seek(to: scrubber.trimStart)
    }

    /// `updatePlayerRange:`: playback ends at the trim's end.
    private func updatePlayerRange() {
        guard let item = player.currentItem else { return }
        item.forwardPlaybackEndTime = scrubber.trimEnd < duration - 0.001
            ? CMTime(seconds: scrubber.trimEnd, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            : .invalid
    }

    /// `_seekToPosition:`: exact seeks, one at a time, ending at the latest target.
    private func seek(to position: Double) {
        guard player.currentItem != nil, position.isFinite else { return }
        let target = CMTime(seconds: max(0, position), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        guard target != chaseTarget else { return }
        chaseTarget = target
        if !isChasingTime {
            chaseTime()
        }
    }

    private func chaseTime() {
        guard let item = player.currentItem, chaseTarget.isValid else {
            isChasingTime = false
            return
        }
        isChasingTime = true
        let target = chaseTarget
        Task { [weak self] in
            _ = await item.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            guard let self else { return }
            if chaseTarget == target {
                isChasingTime = false
                chaseTarget = .invalid
            } else {
                chaseTime()
            }
        }
    }

    private func setPlayButtonHidden(_ hidden: Bool, animated: Bool) {
        guard animated else {
            playButton.isHidden = hidden
            playButton.alpha = hidden ? 0 : 1
            return
        }
        playButton.isHidden = false
        UIView.animate(withDuration: 0.15) {
            self.playButton.alpha = hidden ? 0 : 1
        } completion: { finished in
            if finished {
                self.playButton.isHidden = hidden || self.isPlaying
            }
        }
    }

    private func updateMuteButton() {
        muteButton.isSelected = sendsAsGIF
        muteButton.accessibilityTraits = sendsAsGIF ? [.button, .selected] : .button
    }

    @objc private func videoTapped() {
        guard player.currentItem != nil else { return }
        if isPlaying {
            pause()
            setPlayButtonHidden(false, animated: true)
        } else {
            play()
        }
    }

    @objc private func playPressed() {
        play()
    }

    /// `toggleSendAsGif`: muting shows what it does and plays the video.
    @objc private func mutePressed() {
        sendsAsGIF.toggle()
        updateMuteButton()
        player.isMuted = sendsAsGIF
        guard sendsAsGIF else { return }
        TelegramUndoToast.show(
            text: L10n.telegram("MediaPicker.VideoMuteDescription"),
            in: view,
            bottomInset: Self.toolbarHeight + Self.muteButtonSide + 24,
            undo: nil,
        )
        if !isPlaying {
            play()
        }
    }

    /// `dismissEditor`: changes are dropped only after Discard Changes.
    @objc private func cancelPressed() {
        guard !scrubber.isTrimming, !scrubber.isScrubbing else { return }
        guard hasChanges else {
            dismiss(animated: true)
            return
        }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(
            title: L10n.telegram("PhotoEditor.DiscardChanges"),
            style: .destructive,
        ) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = cancelButton
        sheet.popoverPresentationController?.sourceRect = cancelButton.bounds
        present(sheet, animated: true)
    }

    /// The trim and mute go with the video; an untouched video hands back nothing (`isDefaultValues`).
    @objc private func donePressed() {
        guard !scrubber.isTrimming, !scrubber.isScrubbing else { return }
        guard loadedAdjustments != nil else {
            dismiss(animated: true)
            return
        }
        let adjustments = currentAdjustments
        onDone?(adjustments.isDefault ? nil : adjustments)
        dismiss(animated: true)
    }
}

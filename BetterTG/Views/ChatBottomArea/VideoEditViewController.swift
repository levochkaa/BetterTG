// VideoEditViewController.swift

import AVFoundation
import Combine
import Photos
import UIKit

// MARK: - VideoEditorTab

/// The video editor's tabs: TGMediaPickerGalleryVideoItemView's trim and mute, and the crop of
/// TGPhotoEditorController's video intent (TGPhotoCropController with `forVideo`).
enum VideoEditorTab {
    case video
    case crop
}

// MARK: - VideoEditViewController

/// TGMediaPickerGalleryVideoItemView's editing of a picked video, opened from the attachment sheet, with the crop of
/// TGPhotoEditorController's video intent, switched at the top like the photo editor's tabs. The Video tab has the
/// scrubber with the trim on top, the player showing the crop turned and mirrored (`_layoutPlayerViewWithCropRect:`)
/// with its play button, and the mute button that sends the video as a GIF. The Crop tab is TGPhotoCropController for
/// video: the crop view over the playing video without the straightening dial, RESET, and Rotate, Mirror and Aspect
/// Ratio; a tap plays or pauses, and moving the crop pauses the video until it settles. Done hands back the trim,
/// mute and crop, or nothing for the video as it was; Cancel asks before it drops changes. Where the chat takes a
/// cover, a video of a minute or more has TGMediaPickerGalleryInterfaceView's Edit Cover: Select Frame stops the
/// video and swaps the trim for the cover picker, and Save Cover keeps the frame under its handle.
final class VideoEditViewController: UIViewController {
    // MARK: Private

    /// `TGPhotoEditorToolbarSize`.
    private static let toolbarHeight: CGFloat = 49
    private static let playButtonSide: CGFloat = 60
    /// TGMediaPickerGalleryInterfaceView's mute button.
    private static let muteButtonSide: CGFloat = 40
    /// The app's tint for Done and the applied states, where Telegram uses its accent.
    private static let activeColor = PhotoEditorColors.accent
    /// `play` starts over from the trim's start this close to its end.
    private static let restartThreshold = 0.5
    /// The strip at the top with the Video and Crop tabs, as in the photo editor.
    private static let tabBarHeight: CGFloat = 44
    /// TGPhotoEditorButton's size; the touch area is larger.
    private static let tabSide: CGFloat = 33
    private static let tabTouchSide: CGFloat = 44
    /// `TGPhotoCropButtonsWrapperSize`: RESET's strip right above the toolbar.
    private static let buttonsWrapperHeight: CGFloat = 61
    /// `TGPhotoCropAreaInsetSize`.
    private static let areaInset: CGFloat = 9
    /// `photoContainerFrameForParentViewFrame` without the dial: `TGPhotoEditorPanelSize` less 55.
    private static let cropPanelHeight: CGFloat = 60
    /// The still frame under the crop, at TGPhotoEditorController's screen image size.
    private static let frameImageSide: CGFloat = 1280
    /// TGMediaPickerCoverButton's frame width; the pill inside is narrower.
    private static let coverButtonWidth: CGFloat = 180
    /// The saved cover in the pill's 24 pt circle.
    private static let coverThumbnailSide: CGFloat = 96
    /// `_saveCoverButton`'s height and its inset from the edges.
    private static let saveCoverHeight: CGFloat = 50
    private static let saveCoverInset: CGFloat = 16

    override var prefersStatusBarHidden: Bool {
        true
    }

    // MARK: Internal

    /// The finished edit; `nil` when the whole video goes with its sound and frame.
    var onDone: ((VideoEditAdjustments?) -> Void)?

    private let asset: AVAsset
    private let initialAdjustments: VideoEditAdjustments
    private var allowsTrimming: Bool
    /// LegacyMediaPickerGallery's `hasCoverButton`: broadcast channels and Saved Messages.
    private let allowsCover: Bool
    private var sendsAsGIF: Bool
    /// TGMediaEditingContext's `coverPositionForItem:`.
    private var coverTime: Double?
    private var editorTab: VideoEditorTab
    private let player = AVPlayer()
    /// The crop's box; the whole frame turns and mirrors inside it.
    private let playerClipView = UIView()
    private let playerView = LocalVideoSurfaceView()
    private let scrubber = VideoScrubberView()
    private let playButton = UIButton(type: .custom)
    private let muteButton = UIButton(type: .custom)
    private let resetButton = UIButton(type: .system)
    private let tabBarView = UIView()
    private let videoTabButton = UIButton(type: .system)
    private let cropTabButton = UIButton(type: .system)
    private let tabSelectionView = PhotoCropViewController.makeSelectionView()
    private let toolbarView = UIView()
    private let cancelButton = UIButton(type: .system)
    private let rotateButton = UIButton(type: .system)
    private let mirrorButton = UIButton(type: .system)
    private let aspectRatioButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let coverButton = VideoCoverButton()
    /// `_coverScrubberView`, read once the cover is first edited.
    private let coverScrubber = VideoScrubberView()
    private let coverTitleLabel = UILabel()
    private let coverCancelButton = UIButton(type: .system)
    private let saveCoverButton = UIButton(type: .system)
    /// `_isCoverEditing`.
    private var isCoverEditing = false
    private var isCoverScrubberLoaded = false
    /// TGPhotoCropView for video, made once the displayed frame's size is known.
    private var cropView: PhotoCropView?
    /// The displayed frame's size, which the crop is measured in.
    private var presentedSize = CGSize.zero
    /// Reads the frame on screen for the crop's quarter turn.
    private var frameGenerator: AVAssetImageGenerator?
    private var isFetchingFrame = false
    /// TGPhotoAvatarPreviewController's `_wasPlayingBeforeCropping`.
    private var wasPlayingBeforeCropping = false
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

    /// The crop the video goes with: none for the whole frame without a locked ratio (`hasDefaultCropping`).
    private var currentCrop: PhotoCropAdjustments? {
        guard let cropView else { return initialAdjustments.crop }
        guard !cropView.adjustments.hasDefaultCropping || cropView.isAspectRatioLocked else { return nil }
        return cropView.adjustments
    }

    /// The crop the player shows, the whole frame without one.
    private var displayedCrop: PhotoCropAdjustments {
        cropView?.adjustments ?? PhotoCropAdjustments(originalSize: presentedSize)
    }

    private var currentAdjustments: VideoEditAdjustments {
        var adjustments = VideoEditAdjustments()
        if scrubber.hasTrimming, scrubber.trimStart < scrubber.trimEnd {
            adjustments.trimRange = scrubber.trimStart...scrubber.trimEnd
        }
        adjustments.sendsAsGIF = sendsAsGIF
        adjustments.crop = currentCrop
        adjustments.coverTime = coverTime
        return adjustments
    }

    private var hasChanges: Bool {
        guard let loadedAdjustments else { return false }
        return currentAdjustments != loadedAdjustments
    }

    private var isCropBusy: Bool {
        guard let cropView else { return false }
        return cropView.isTracking || cropView.isAnimating
    }

    /// `canHaveCover`: the chat takes a cover and the video is a minute or more (`originalDuration`).
    private var canHaveCover: Bool {
        allowsCover && duration >= VideoEditCover.minimumDuration
    }

    /// `allowsTrimming` is false for slow-motion videos, which Telegram doesn't trim (`itemIsHighFramerateVideo`).
    /// `allowsCover` offers the cover where the chat takes one, and `initialTab` is the tab the editor opens in.
    init(
        asset: AVAsset,
        adjustments: VideoEditAdjustments?,
        allowsTrimming: Bool = true,
        allowsCover: Bool = false,
        initialTab: VideoEditorTab = .video,
    ) {
        self.asset = asset
        self.initialAdjustments = adjustments ?? VideoEditAdjustments()
        self.allowsTrimming = allowsTrimming
        self.allowsCover = allowsCover
        self.sendsAsGIF = adjustments?.sendsAsGIF ?? false
        self.coverTime = adjustments?.coverTime
        self.editorTab = initialTab
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
        playerView.playerLayer.videoGravity = .resize
        playerView.isUserInteractionEnabled = false
        playerClipView.clipsToBounds = true
        playerClipView.addSubview(playerView)
        playerClipView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(videoTapped)))
        view.addSubview(playerClipView)
        configureScrubber()
        configurePlayButton()
        configureMuteButton()
        configureCover()
        configureResetButton()
        configureTabBar()
        configureToolbar()
        applyVisibility()
        updateTabs()
        loadVideo()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let safeArea = view.safeAreaInsets
        let toolbarTop = bounds.height - safeArea.bottom - Self.toolbarHeight
        let contentWidth = bounds.width - safeArea.left - safeArea.right
        toolbarView.frame = CGRect(
            x: 0,
            y: toolbarTop,
            width: bounds.width,
            height: Self.toolbarHeight + safeArea.bottom,
        )
        layoutToolbar()
        tabBarView.frame = CGRect(x: 0, y: safeArea.top, width: bounds.width, height: Self.tabBarHeight)
        layoutTabBar()
        let contentTop = safeArea.top + Self.tabBarHeight
        // The scrubber sits in TGMediaPickerScrubberHeaderView's panel at the top.
        scrubber.frame = CGRect(
            x: safeArea.left,
            y: contentTop,
            width: contentWidth,
            height: VideoScrubberView.preferredHeight,
        )
        coverScrubber.frame = scrubber.frame
        // Save Cover spans the bottom while the cover is chosen, and the video ends above it.
        let saveCoverFrame = CGRect(
            x: safeArea.left + Self.saveCoverInset,
            y: bounds.height - safeArea.bottom - Self.saveCoverHeight - Self.saveCoverInset,
            width: max(0, contentWidth - Self.saveCoverInset * 2),
            height: Self.saveCoverHeight,
        )
        saveCoverButton.frame = saveCoverFrame
        let videoBottom = isCoverEditing ? saveCoverFrame.minY - 8 : toolbarTop - 8
        let videoTop = scrubber.frame.maxY + 8
        layoutPlayer(in: CGRect(
            x: safeArea.left,
            y: videoTop,
            width: contentWidth,
            height: max(0, videoBottom - videoTop),
        ))
        playButton.bounds = CGRect(x: 0, y: 0, width: Self.playButtonSide, height: Self.playButtonSide)
        playButton.center = CGPoint(x: playerClipView.frame.midX, y: playerClipView.frame.midY)
        // `_muteButtonFrameForOrientation:`: the video's bottom left corner, above the toolbar.
        muteButton.frame = CGRect(
            x: safeArea.left + 12,
            y: toolbarTop - Self.muteButtonSide - 12,
            width: Self.muteButtonSide,
            height: Self.muteButtonSide,
        )
        // `_coverButtonFrameForOrientation:`: centered above the toolbar, here level with the mute button, as no
        // caption panel sits between them.
        let coverWidth = max(Self.coverButtonWidth, coverButton.intrinsicContentSize.width)
        coverButton.frame = CGRect(
            x: ((bounds.width - coverWidth) / 2).rounded(.down),
            y: muteButton.frame.minY,
            width: coverWidth,
            height: Self.muteButtonSide,
        )
        // Select Frame and its Cancel take the tabs' strip.
        let stripCenterY = safeArea.top + Self.tabBarHeight / 2
        coverTitleLabel.sizeToFit()
        coverTitleLabel.center = CGPoint(x: bounds.midX, y: stripCenterY)
        coverCancelButton.sizeToFit()
        coverCancelButton.frame.origin = CGPoint(
            x: safeArea.left + 16,
            y: stripCenterY - coverCancelButton.bounds.height / 2,
        )
        // RESET at 20 pt into its strip above the toolbar, reaching 10 pt further for touches.
        let resetWidth = ceil(resetButton.titleLabel?.intrinsicContentSize.width ?? 0)
        let resetFrame = CGRect(
            x: (bounds.width - resetWidth) / 2,
            y: toolbarTop - Self.buttonsWrapperHeight + 20,
            width: resetWidth,
            height: 24,
        )
        resetButton.frame = resetFrame.insetBy(dx: -10, dy: -10)
        // The crop tab's container under the tabs, with the smaller panel of a crop without the dial.
        let container = CGRect(
            x: safeArea.left,
            y: contentTop,
            width: contentWidth,
            height: max(0, toolbarTop - Self.cropPanelHeight - contentTop),
        )
        cropView?.frame = container.insetBy(dx: Self.areaInset, dy: Self.areaInset)
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

    /// TGMediaAssetImageSignals' exact frames, upright, at the editor's screen size.
    private static func makeFrameGenerator(for asset: AVAsset) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: frameImageSide, height: frameImageSide)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return generator
    }

    /// A black frame until the video's first frame is read.
    private static func placeholderFrame() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    private static func setVisible(_ view: UIView, _ isVisible: Bool) {
        view.alpha = isVisible ? 1 : 0
        view.isUserInteractionEnabled = isVisible
    }

    private static func setSelected(_ button: UIButton, _ isSelected: Bool) {
        button.tintColor = isSelected ? activeColor : .white
        button.accessibilityTraits = isSelected ? [.button, .selected] : .button
    }

    // MARK: Configuration

    private func configureScrubber() {
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
            updateTabs()
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
        updateMuteButton()
        view.addSubview(muteButton)
    }

    private func configureResetButton() {
        resetButton.setTitle(L10n.telegram("PhotoEditor.CropReset"), for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 13)
        resetButton.tintColor = .white
        resetButton.addTarget(self, action: #selector(resetPressed), for: .touchUpInside)
        view.addSubview(resetButton)
    }

    /// TGMediaPickerGalleryInterfaceView's cover editing: the Edit Cover pill, and while the cover is chosen, Select
    /// Frame with Cancel at the top, the cover picker in the trim scrubber's place, and Save Cover across the bottom
    /// in the app's tint. Moving the picker shows its frame and keeps the trim scrubber's playhead with it
    /// (`videoScrubber:valueDidChange:`).
    private func configureCover() {
        coverButton.addTarget(self, action: #selector(coverButtonPressed), for: .touchUpInside)
        view.addSubview(coverButton)
        coverScrubber.isCoverPicker = true
        coverScrubber.onBeginScrubbing = { [weak self] in
            self?.pause()
        }
        coverScrubber.onScrub = { [weak self] position in
            guard let self else { return }
            seek(to: position)
            scrubber.setPlaybackPosition(position)
        }
        view.addSubview(coverScrubber)
        coverTitleLabel.text = L10n.telegram("Media.SelectFrame")
        coverTitleLabel.font = .boldSystemFont(ofSize: 17)
        coverTitleLabel.textColor = .white
        coverTitleLabel.accessibilityTraits = .header
        view.addSubview(coverTitleLabel)
        coverCancelButton.setTitle(L10n.telegram("Common.Cancel"), for: .normal)
        coverCancelButton.titleLabel?.font = .systemFont(ofSize: 17)
        coverCancelButton.tintColor = .white
        coverCancelButton.addTarget(self, action: #selector(cancelCoverPressed), for: .touchUpInside)
        view.addSubview(coverCancelButton)
        saveCoverButton.setTitle(L10n.telegram("Media.SaveCover"), for: .normal)
        saveCoverButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        saveCoverButton.tintColor = .white
        saveCoverButton.backgroundColor = Self.activeColor
        saveCoverButton.layer.cornerRadius = 10
        saveCoverButton.layer.cornerCurve = .continuous
        saveCoverButton.clipsToBounds = true
        saveCoverButton.addTarget(self, action: #selector(saveCoverPressed), for: .touchUpInside)
        view.addSubview(saveCoverButton)
    }

    /// The photo editor's tab strip with the Video and Crop tabs.
    private func configureTabBar() {
        tabBarView.addSubview(tabSelectionView)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let items: [(button: UIButton, symbol: String, label: String, action: Selector)] = [
            (videoTabButton, "video", L10n.betterTG("Accessibility.VideoEditor.Video"), #selector(videoTabPressed)),
            (cropTabButton, "crop.rotate", L10n.betterTG("Accessibility.PhotoEditor.Crop"), #selector(cropTabPressed)),
        ]
        for item in items {
            item.button.setImage(UIImage(systemName: item.symbol, withConfiguration: symbolConfiguration), for: .normal)
            item.button.accessibilityLabel = item.label
            item.button.addTarget(self, action: item.action, for: .touchUpInside)
            tabBarView.addSubview(item.button)
        }
        view.addSubview(tabBarView)
    }

    private func configureToolbar() {
        toolbarView.backgroundColor = .black
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let items: [(button: UIButton, symbol: String, label: String, action: Selector)] = [
            (cancelButton, "xmark", L10n.telegram("Common.Cancel"), #selector(cancelPressed)),
            (rotateButton, "rotate.left", L10n.betterTG("Accessibility.PhotoEditor.Rotate"), #selector(rotatePressed)),
            (
                mirrorButton,
                "flip.horizontal",
                L10n.betterTG("Accessibility.PhotoEditor.Mirror"),
                #selector(mirrorPressed),
            ),
            (
                aspectRatioButton,
                "aspectratio",
                L10n.betterTG("Accessibility.PhotoEditor.AspectRatio"),
                #selector(aspectRatioPressed),
            ),
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

    /// TGPhotoCropView without the dial over the playing video: player layers sharing the editor's player show the
    /// frame, the still frame staying under them for the quarter turn. Moving the crop pauses the video until it
    /// settles, and a tap plays or pauses (TGPhotoAvatarPreviewController's `interactionBegan`, `interactionEnded`
    /// and `tapped`).
    private func makeCropView(frame: UIImage?, crop: PhotoCropAdjustments?) {
        let cropView = PhotoCropView(
            image: frame ?? Self.placeholderFrame(),
            adjustments: crop ?? PhotoCropAdjustments(originalSize: presentedSize),
            hasArbitraryRotation: false,
        )
        let player = player
        cropView.setContentViews {
            let surface = LocalVideoSurfaceView()
            surface.playerLayer.videoGravity = .resize
            surface.playerLayer.player = player
            return surface
        }
        cropView.onCroppingChanged = { [weak self] in
            self?.updateTabs()
        }
        cropView.onInteractionBegan = { [weak self] in
            guard let self else { return }
            wasPlayingBeforeCropping = isPlaying || wasPlayingBeforeCropping
            pause()
        }
        cropView.onInteractionEnded = { [weak self] in
            guard let self, wasPlayingBeforeCropping else { return }
            wasPlayingBeforeCropping = false
            play()
        }
        cropView.onTap = { [weak self] in
            self?.videoTapped()
        }
        view.insertSubview(cropView, aboveSubview: playerClipView)
        self.cropView = cropView
    }

    // MARK: Layout

    /// TGPhotoToolbarView's portrait layout: Cancel and Done in 49 pt squares at the ends, and the crop's three tools
    /// at a quarter, half and three quarters of the width between them, the outer ones 5 pt further out.
    private func layoutToolbar() {
        let width = toolbarView.bounds.width
        let side = Self.toolbarHeight
        cancelButton.frame = CGRect(x: 0, y: 0, width: side, height: side)
        doneButton.frame = CGRect(x: width - side, y: 0, width: side, height: side)
        let available = width - side * 2
        let sideOffset: CGFloat = 5
        let centers = [
            side + available / 4 - sideOffset,
            side + available / 2,
            side + available * 3 / 4 + sideOffset,
        ]
        for (button, centerX) in zip([rotateButton, mirrorButton, aspectRatioButton], centers) {
            button.bounds = CGRect(x: 0, y: 0, width: Self.tabTouchSide, height: Self.tabTouchSide)
            button.center = CGPoint(x: centerX, y: 8 + Self.tabSide / 2)
        }
    }

    private func layoutTabBar() {
        let width = tabBarView.bounds.width
        let centerY = Self.tabBarHeight / 2
        for (button, offset) in [(videoTabButton, -30), (cropTabButton, 30)] as [(UIButton, CGFloat)] {
            button.bounds = CGRect(x: 0, y: 0, width: Self.tabTouchSide, height: Self.tabTouchSide)
            button.center = CGPoint(x: width / 2 + offset, y: centerY)
        }
        tabSelectionView.center = (editorTab == .video ? videoTabButton : cropTabButton).center
    }

    /// `_layoutPlayerViewWithCropRect:`: the crop fitted into the area, with the whole frame turned and mirrored
    /// behind it so only the crop shows.
    private func layoutPlayer(in area: CGRect) {
        guard presentedSize.width > 0, presentedSize.height > 0 else {
            playerClipView.frame = area
            return
        }
        let crop = displayedCrop
        let size = PhotoCropAdjustments.scaleToSize(crop.croppedSize, area.size)
        playerClipView.frame = CGRect(
            x: area.midX - size.width / 2,
            y: area.midY - size.height / 2,
            width: size.width,
            height: size.height,
        )
        let placement = crop.contentPlacement(in: size)
        playerView.bounds = CGRect(origin: .zero, size: presentedSize)
        playerView.center = placement.center
        playerView.transform = placement.transform
    }

    /// What each tab shows: the scrubber, player, mute and Edit Cover, or the crop with RESET and its tools. Choosing
    /// a cover hides the tabs, the toolbar and the trim behind Select Frame (`setAllInterfaceHidden:keepHeader:`).
    private func applyVisibility() {
        let isCrop = editorTab == .crop
        let isLoaded = loadedAdjustments != nil
        let isCover = isCoverEditing
        Self.setVisible(scrubber, !isCrop && isLoaded && !isCover)
        Self.setVisible(muteButton, !isCrop && isLoaded && !isCover)
        Self.setVisible(coverButton, !isCrop && isLoaded && !isCover && canHaveCover)
        for coverView in [coverScrubber, coverTitleLabel, coverCancelButton, saveCoverButton] as [UIView] {
            Self.setVisible(coverView, isCover)
        }
        Self.setVisible(toolbarView, !isCover)
        Self.setVisible(playerClipView, !isCrop)
        if let cropView {
            Self.setVisible(cropView, isCrop)
        }
        Self.setVisible(resetButton, isCrop && cropView != nil)
        for button in [rotateButton, mirrorButton, aspectRatioButton] {
            Self.setVisible(button, isCrop && cropView != nil)
        }
        Self.setVisible(tabBarView, cropView != nil && !isCover)
    }

    /// `highlightedTabs`: Mirror while mirrored, Aspect Ratio while a ratio is locked, and a tab while its edit
    /// applies.
    private func updateTabs() {
        Self.setSelected(mirrorButton, cropView?.adjustments.isMirrored == true)
        Self.setSelected(aspectRatioButton, cropView?.isAspectRatioLocked == true)
        PhotoCropViewController.style(
            videoTabButton,
            isSelected: editorTab == .video,
            isApplied: scrubber.hasTrimming || sendsAsGIF,
        )
        PhotoCropViewController.style(
            cropTabButton,
            isSelected: editorTab == .crop,
            isApplied: currentCrop.map { !$0.hasDefaultCropping } ?? false,
        )
        tabSelectionView.center = (editorTab == .video ? videoTabButton : cropTabButton).center
    }

    /// `presentTab`: the crop settles before the player shows it, and the scrubber's frames take its shape
    /// (`croppingChanged`'s `updateThumbnails`).
    private func setTab(_ newTab: VideoEditorTab) {
        guard newTab != editorTab, let cropView, !isCropBusy, !scrubber.isTrimming, !scrubber.isScrubbing,
              !isCoverEditing
        else {
            return
        }
        cropView.commitPendingChanges()
        editorTab = newTab
        updatePlayerMuting()
        switch newTab {
        case .video:
            scrubber.setCrop(currentCrop)
            // The cover goes cut as the video is, so its circle follows a changed crop.
            if coverTime != nil {
                updateCoverImage()
            }
        case .crop:
            refreshCropFrame()
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
        updateTabs()
        setPlayButtonHidden(isPlaying, animated: false)
        UIView.animate(withDuration: 0.2) { self.applyVisibility() }
    }

    // MARK: Loading

    private func loadVideo() {
        let asset = asset
        let start = CMTime(seconds: initialAdjustments.trimRange?.lowerBound ?? 0, preferredTimescale: 600)
        Task { [weak self] in
            do {
                let duration = try await asset.load(.duration).seconds
                var presentedSize = CGSize.zero
                if let track = try await asset.loadTracks(withMediaType: .video).first {
                    let naturalSize = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    // Measured as the sent video measures its frame, so the crop needs no rescaling.
                    presentedSize = CGRect(origin: .zero, size: naturalSize).applying(transform).size
                }
                let generator = Self.makeFrameGenerator(for: asset)
                let frame = try? await generator.image(at: start).image
                self?.didLoad(duration: duration, presentedSize: presentedSize, generator: generator, frame: frame)
            } catch {
                log("Could not read the video to edit: \(error)")
            }
        }
    }

    /// `preparePlayerAndPlay:` without playing: the player starts at the trim and stops at its end, and the crop
    /// is measured in the displayed frame.
    private func didLoad(duration: Double, presentedSize: CGSize, generator: AVAssetImageGenerator, frame: CGImage?) {
        guard duration.isFinite, duration > 0 else { return }
        self.duration = duration
        self.presentedSize = presentedSize
        frameGenerator = generator
        // `allowsTrimming`: videos shorter than `TGVideoEditMinimumTrimmableDuration` aren't trimmed.
        allowsTrimming = allowsTrimming && duration >= VideoEditAdjustments.minimumTrimmableDuration
        let hasFrame = presentedSize.width > 0 && presentedSize.height > 0
        let initialCrop = hasFrame ? initialAdjustments.crop(inFrameOf: presentedSize) : nil
        scrubber.allowsTrimming = allowsTrimming
        scrubber.configure(
            asset: asset,
            duration: duration,
            frameSize: presentedSize,
            trimRange: allowsTrimming ? initialAdjustments.trimRange : nil,
        )
        scrubber.setCrop(initialCrop)
        if hasFrame {
            makeCropView(frame: frame.map { UIImage(cgImage: $0) }, crop: initialCrop)
        } else {
            editorTab = .video
        }
        // A video too short for a cover, or a chat without covers, keeps none.
        if !canHaveCover {
            coverTime = nil
        }
        updateCoverImage()
        loadedAdjustments = currentAdjustments
        let item = AVPlayerItem(asset: asset)
        player.actionAtItemEnd = .none
        player.replaceCurrentItem(with: item)
        updatePlayerMuting()
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
        applyVisibility()
        updateTabs()
        view.setNeedsLayout()
        // A muted video plays at once, as Telegram's gallery loops a GIF, and so does the crop the editor opens in
        // (the crop's `finishedTransitionIn` starts playback on the initial appearance).
        if sendsAsGIF || editorTab == .crop {
            play()
        } else {
            setPlayButtonHidden(false, animated: false)
        }
    }

    /// The frame on screen, for the crop's still frame.
    private func currentFrame() async -> UIImage? {
        guard let frameGenerator else { return nil }
        let time = player.currentTime()
        guard let image = try? await frameGenerator.image(at: time.isValid ? time : .zero).image else { return nil }
        return UIImage(cgImage: image)
    }

    /// The crop's still frame follows the video to where it stopped.
    private func refreshCropFrame() {
        guard !isFetchingFrame else { return }
        isFetchingFrame = true
        Task { [weak self] in
            let frame = await self?.currentFrame()
            guard let self else { return }
            isFetchingFrame = false
            if let frame {
                cropView?.setImage(frame)
            }
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

    /// `playerItemDidPlayToEndTime:`: a GIF loops, and so does the video under the crop; otherwise the video stops
    /// with its play button at the trim's start.
    private func playerItemDidPlayToEnd() {
        if sendsAsGIF || editorTab == .crop {
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

    /// The play button shows over the paused video in the Video tab; the Crop tab plays and pauses by a tap.
    private func setPlayButtonHidden(_ requestedHidden: Bool, animated: Bool) {
        let hidden = requestedHidden || editorTab == .crop || isCoverEditing
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
                self.playButton.isHidden = hidden || self.isPlaying || self.editorTab == .crop || self.isCoverEditing
            }
        }
    }

    private func updateMuteButton() {
        muteButton.isSelected = sendsAsGIF
        muteButton.accessibilityTraits = sendsAsGIF ? [.button, .selected] : .button
    }

    /// The sound plays in the Video tab unless the video goes as a GIF; the crop plays without it, as
    /// TGPhotoEditorController's muted player does.
    private func updatePlayerMuting() {
        player.isMuted = sendsAsGIF || editorTab == .crop
    }

    @objc private func videoTapped() {
        guard player.currentItem != nil, !isCoverEditing else { return }
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
        updateTabs()
        updatePlayerMuting()
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

    // MARK: Cover

    /// `coverButtonPressed` with `prepareForCoverEditing`: the video stops, and the cover picker takes the trim
    /// scrubber's place at the saved cover, or where the video stands, its tap kept inside the trim.
    @objc private func coverButtonPressed() {
        guard canHaveCover, !isCoverEditing, editorTab == .video, !scrubber.isTrimming, !scrubber.isScrubbing else {
            return
        }
        isCoverEditing = true
        pause()
        if !isCoverScrubberLoaded {
            isCoverScrubberLoaded = true
            coverScrubber.configure(asset: asset, duration: duration, frameSize: presentedSize, trimRange: nil)
        }
        coverScrubber.setTrimRange(scrubber.trimStart...max(scrubber.trimStart, scrubber.trimEnd))
        coverScrubber.setCrop(currentCrop)
        let current = player.currentTime().seconds
        let position = coverTime ?? (current.isFinite ? current : scrubber.trimStart)
        coverScrubber.setPlaybackPosition(position)
        if coverTime != nil {
            seek(to: position)
            scrubber.setPlaybackPosition(position)
        }
        setPlayButtonHidden(true, animated: true)
        UIView.animate(withDuration: 0.2) {
            self.applyVisibility()
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }

    /// `saveCoverButtonPressed`: the frame under the handle becomes the cover (`currentPosition`).
    @objc private func saveCoverPressed() {
        guard isCoverEditing, !coverScrubber.isScrubbing else { return }
        coverTime = coverScrubber.value
        updateCoverImage()
        endCoverEditing()
    }

    /// `cancelCoverButtonPressed`: the cover stays as it was.
    @objc private func cancelCoverPressed() {
        guard isCoverEditing, !coverScrubber.isScrubbing else { return }
        endCoverEditing()
    }

    /// `coverEditorTransitionOut` with `returnFromCoverEditing`: the editor comes back with the play button.
    private func endCoverEditing() {
        isCoverEditing = false
        setPlayButtonHidden(isPlaying, animated: true)
        UIView.animate(withDuration: 0.3) {
            self.applyVisibility()
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
    }

    /// The pill's circle shows the saved cover as it will go, cut by the crop (`coverImageSignalForItem:`).
    private func updateCoverImage() {
        guard let coverTime else {
            coverButton.setImage(nil)
            view.setNeedsLayout()
            return
        }
        var edit = VideoEditAdjustments()
        edit.crop = currentCrop
        let asset = asset
        Task { [weak self] in
            let image = await VideoEditCover.image(
                at: coverTime,
                of: asset,
                edit: edit,
                maximumSide: Self.coverThumbnailSide,
            )
            guard let self, self.coverTime == coverTime else { return }
            coverButton.setImage(image)
            view.setNeedsLayout()
        }
    }

    // MARK: Crop

    @objc private func videoTabPressed() {
        setTab(.video)
    }

    @objc private func cropTabPressed() {
        setTab(.crop)
    }

    /// `cropReset`: the whole frame, upright and unmirrored, without a locked ratio.
    @objc private func resetPressed() {
        cropView?.reset(animated: true)
    }

    /// `rotate`: the quarter turn's snapshot is the frame on screen.
    @objc private func rotatePressed() {
        guard let cropView, !isCropBusy, !isFetchingFrame else { return }
        isFetchingFrame = true
        Task { [weak self] in
            let frame = await self?.currentFrame()
            guard let self else { return }
            isFetchingFrame = false
            if let frame {
                cropView.setImage(frame)
            }
            cropView.rotate90DegreesCounterclockwise()
        }
    }

    @objc private func mirrorPressed() {
        cropView?.mirror()
    }

    /// `aspectRatioButtonPressedWithSourceView`: a locked ratio unlocks; otherwise the crop settles and the photo
    /// editor's sheet offers the frame's own ratio, a square and six more turned to the crop's longer side.
    @objc private func aspectRatioPressed() {
        guard let cropView, !cropView.isAnimating else { return }
        if cropView.isAspectRatioLocked {
            cropView.unlockAspectRatio()
            return
        }
        cropView.performConfirm(animated: true)
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for choice in PhotoCropViewController.aspectRatioChoices(for: cropView.adjustments) {
            let ratio = choice.ratio
            sheet.addAction(UIAlertAction(title: choice.title, style: .default) { [weak self] _ in
                // Telegram lets the sheet go first on iPhone.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.cropView?.setLockedAspectRatio(ratio, animated: true)
                }
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = aspectRatioButton
        sheet.popoverPresentationController?.sourceRect = aspectRatioButton.bounds
        present(sheet, animated: true)
    }

    // MARK: Finishing

    /// `dismissEditor`: changes are dropped only after Discard Changes.
    @objc private func cancelPressed() {
        guard !scrubber.isTrimming, !scrubber.isScrubbing, !isCropBusy, !isCoverEditing else { return }
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

    /// The trim, mute, crop and cover go with the video; a waiting crop change settles first, and an untouched video
    /// hands back nothing (`isDefaultValues`).
    @objc private func donePressed() {
        guard !scrubber.isTrimming, !scrubber.isScrubbing, cropView?.isTracking != true, !isCoverEditing else {
            return
        }
        guard loadedAdjustments != nil else {
            dismiss(animated: true)
            return
        }
        cropView?.commitPendingChanges()
        let adjustments = currentAdjustments
        onDone?(adjustments.isDefault ? nil : adjustments)
        dismiss(animated: true)
    }
}

// StoryCamera.swift

import AVFoundation
import Photos
import UIKit

// MARK: - StoryCameraViewController

/// CameraScreen for a story: the 9:16 viewfinder with 30 pt corners under the status bar (or from the top where the
/// screen is too short for it and 30 pt more), Close at the top right and the flash 50 pt before it, then
/// CaptureControlsComponent: the 68 pt ring around the 60 pt shutter in the middle, and under it the 48 pt round
/// gallery button showing the newest photo 16 pt in, ModeComponent's VIDEO and PHOTO, and the 48 pt glass flip
/// button. The shutter takes a photo in photo mode and starts or stops a video in video mode; held 0.3 s in either, it
/// records while held. Recording hides the top row and the bottom row, shows the length in a red tag at the top and
/// the flip button beside the shutter, and stops at a minute. A camera the app may not use shows Telegram's access
/// placeholder with Open Settings; a device without a camera shows Telegram's camera placeholder picture.
final class StoryCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate,
    AVCaptureFileOutputRecordingDelegate
{
    /// CaptureControlsComponent.SwipeHint.
    private enum SwipeHint {
        case none
        case zoom
        case lock
        case releaseLock
        case flip

        var text: String {
            switch self {
            case .none: " "
            case .zoom: L10n.telegram("Story.Camera.SwipeUpToZoom")
            case .lock: L10n.telegram("Story.Camera.SwipeLeftToLock")
            case .releaseLock: L10n.telegram("Story.Camera.SwipeLeftRelease")
            case .flip: L10n.telegram("Story.Camera.SwipeRightToFlip")
            }
        }
    }

    /// CameraState.Recording.
    private enum Recording {
        case none
        case holding
        case handsFree
    }

    /// storyMaxVideoDuration; the camera stops past 59 seconds.
    private static let maxDuration: Double = 60

    override var prefersStatusBarHidden: Bool {
        true
    }

    var onPhoto: ((UIImage) -> Void)?
    var onVideo: ((URL) -> Void)?
    var onGallery: (() -> Void)?

    /// The session and its outputs, set up and started on `sessionQueue`.
    private let captureSession = StoryCaptureSession()

    private let previewView = StoryCameraPreviewView()
    private let placeholderView = UIImageView(image: UIImage(named: "MediaEditor/CameraPlaceholder"))
    private let closeButton = UIButton(type: .custom)
    private let flashButton = UIButton(type: .custom)
    private let shutterButton = StoryShutterButton()
    private let galleryButton = UIButton(type: .custom)
    private let modeControl = StoryCameraModeControl()
    /// The bottom row's flip button, in tinted glass.
    private let flipGlass = UIVisualEffectView()
    private let flipButton = UIButton(type: .custom)
    /// The flip button beside the shutter while a video records.
    private let recordingFlipButton = UIButton(type: .custom)
    /// The 60 pt lines either side of the shutter while it is held.
    private let leftGuide = UIView()
    private let rightGuide = UIView()
    /// LockContentComponent: the lock 28 pt in on the shutter's row while it is held.
    private let lockView = UIImageView(image: UIImage(named: "MediaEditor/CameraLockIcon"))
    private let hintLabel = UILabel()
    private var swipeHint = SwipeHint.none
    private var isBanding: Bool?
    private var didFlip = false
    private var zoomFraction: CGFloat = 0
    private let timeBackground = UIView()
    private let timeLabel = UILabel()
    private let accessView = UIStackView()
    private var position = AVCaptureDevice.Position.back
    private var flashMode = AVCaptureDevice.FlashMode.off
    private var mode = StoryCameraModeControl.Mode.photo
    private var recording = Recording.none
    private var recordingStart: CFTimeInterval = 0
    private var recordingTimer: Timer?
    private var hasCamera = true
    private let sessionQueue = DispatchQueue(label: "bettertg.story.camera")

    private var session: AVCaptureSession {
        captureSession.session
    }

    private var photoOutput: AVCapturePhotoOutput {
        captureSession.photoOutput
    }

    private var recordingDuration: Double {
        recording == .none ? 0 : CACurrentMediaTime() - recordingStart
    }

    private var recordingProgress: CGFloat {
        CGFloat(min(1, recordingDuration / Self.maxDuration))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        previewView.layer.cornerRadius = 30
        previewView.layer.cornerCurve = .continuous
        previewView.clipsToBounds = true
        previewView.backgroundColor = UIColor(white: 0.1, alpha: 1)
        previewView.previewLayer.session = session
        previewView.previewLayer.videoGravity = .resizeAspectFill
        view.addSubview(previewView)
        placeholderView.contentMode = .scaleAspectFill
        placeholderView.isHidden = true
        previewView.addSubview(placeholderView)

        configure(
            closeButton,
            image: UIImage(named: "MediaEditor/CameraCloseIcon"),
            label: L10n.telegram("Common.Close"),
        )
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        configure(flashButton, image: nil, label: "Flash")
        flashButton.addAction(UIAction { [weak self] _ in self?.toggleFlash() }, for: .touchUpInside)
        configure(recordingFlipButton, image: UIImage(named: "MediaEditor/CameraFlipIcon"), label: "Flip")
        recordingFlipButton.addAction(UIAction { [weak self] _ in self?.flip() }, for: .touchUpInside)
        shutterButton.addAction(UIAction { [weak self] _ in self?.shutterTapped() }, for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(shutterHeld(_:)))
        hold.minimumPressDuration = 0.3
        shutterButton.addGestureRecognizer(hold)
        view.addSubview(shutterButton)
        galleryButton.clipsToBounds = true
        galleryButton.layer.cornerRadius = 24
        galleryButton.backgroundColor = UIColor(white: 1, alpha: 0.2)
        galleryButton.imageView?.contentMode = .scaleAspectFill
        galleryButton.accessibilityLabel = L10n.telegram("Attachment.Gallery")
        galleryButton.addAction(UIAction { [weak self] _ in self?.onGallery?() }, for: .touchUpInside)
        view.addSubview(galleryButton)
        modeControl.onSelect = { [weak self] mode in self?.select(mode) }
        view.addSubview(modeControl)
        configureFlipGlass()
        timeBackground.backgroundColor = StoryShutterButton.videoRed
        timeBackground.layer.cornerRadius = 4
        timeLabel.font = UIFont(name: "SFCamera-Regular", size: 21) ?? .monospacedDigitSystemFont(
            ofSize: 21,
            weight: .regular,
        )
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        timeLabel.layer.shadowColor = UIColor.black.cgColor
        timeLabel.layer.shadowOpacity = 0.2
        timeLabel.layer.shadowRadius = 1
        timeLabel.layer.shadowOffset = .zero
        view.addSubview(timeBackground)
        view.addSubview(timeLabel)
        for guide in [leftGuide, rightGuide] {
            guide.backgroundColor = UIColor(white: 1, alpha: 0.2)
            guide.isUserInteractionEnabled = false
            view.insertSubview(guide, belowSubview: shutterButton)
        }
        lockView.tintColor = .white
        lockView.contentMode = .center
        view.insertSubview(lockView, belowSubview: shutterButton)
        hintLabel.textAlignment = .center
        view.addSubview(hintLabel)
        setSwipeHint(.none)
        updateFlashIcon()
        updateControls(animated: false)
        loadNewestPhoto()
        configureAccessView()
        startCamera()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentingViewController == nil else { return }
        recordingTimer?.invalidate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let safe = view.safeAreaInsets
        let previewSize = CGSize(width: bounds.width, height: (bounds.width * 1.77778).rounded(.down))
        // The viewfinder starts under the status bar unless the screen has no 30 pt to spare for it.
        let isShort = bounds.height < previewSize.height + 30
        let topInset: CGFloat = isShort ? 0 : safe.top + 5
        // Below the viewfinder, or above the home indicator where the viewfinder runs past the screen.
        let bottomInset = max(bounds.height - previewSize.height - topInset, safe.bottom, 0)
        previewView.frame = CGRect(origin: CGPoint(x: 0, y: topInset), size: previewSize)
        placeholderView.frame = previewView.bounds
        accessView.frame = previewView.frame.insetBy(dx: 32, dy: 0)
        let controlsBottomInset: CGFloat = isShort ? -70 : 0
        let topRowTop = max(safe.top + 5, topInset + 12)
        let rightInset = 9 + safe.right
        closeButton.frame = CGRect(x: bounds.width - rightInset - 40, y: topRowTop, width: 40, height: 40)
        flashButton.frame = CGRect(x: closeButton.frame.minX - 50, y: topRowTop, width: 40, height: 40)
        let shutterCenterY = bounds.height - 48 - bottomInset - 5 + (controlsBottomInset * 0.66).rounded(.down)
        shutterButton.bounds = CGRect(x: 0, y: 0, width: 96, height: 96)
        shutterButton.center = CGPoint(x: bounds.width / 2, y: shutterCenterY)
        recordingFlipButton.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        recordingFlipButton.center = CGPoint(x: bounds.width - 48 - 28 + 22, y: shutterCenterY)
        // The bottom row, 21 pt under the shutter's square, or 2 pt over it on a short screen.
        let sideInset: CGFloat = isShort ? 9 : 16
        let rowTop = shutterCenterY + 48 + (isShort ? -2 : 21)
        galleryButton.bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
        galleryButton.center = CGPoint(x: sideInset + 24, y: rowTop + 24)
        flipGlass.bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
        flipGlass.center = CGPoint(x: bounds.width - sideInset - 24, y: rowTop + 24)
        flipButton.frame = flipGlass.contentView.bounds
        let modeSize = modeControl.sizeThatFits(CGSize(width: bounds.width - 140, height: 48))
        modeControl.bounds = CGRect(origin: .zero, size: modeSize)
        modeControl.center = CGPoint(
            x: bounds.width / 2,
            y: bounds.height - bottomInset + 24 + controlsBottomInset + 16,
        )
        // The guides 9 pt off the shutter's square, the lock over the gallery button's place on the shutter's row,
        // the hint 136 pt over the bottom inset, or over the held shutter's 92 pt ring where the controls rise on a
        // short screen.
        let guideHeight = 1 + 1 / max(1, traitCollection.displayScale)
        let isHolding = recording == .holding
        let guideWidth: CGFloat = isHolding ? 60 : 0
        leftGuide.frame = CGRect(
            x: shutterButton.center.x - 48 - 9 - guideWidth,
            y: shutterCenterY - guideHeight / 2,
            width: guideWidth,
            height: guideHeight,
        )
        rightGuide.frame = CGRect(
            x: shutterButton.center.x + 48 + 9,
            y: shutterCenterY - guideHeight / 2,
            width: guideWidth,
            height: guideHeight,
        )
        for guide in [leftGuide, rightGuide] {
            guide.layer.cornerRadius = guideHeight / 2
        }
        lockView.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
        lockView.center = CGPoint(x: 28 + 24, y: shutterCenterY)
        hintLabel.bounds = CGRect(x: 0, y: 0, width: bounds.width - 32, height: 20)
        hintLabel.center = CGPoint(
            x: bounds.width / 2,
            y: min(bounds.height - bottomInset - 136, shutterCenterY - 46 - 20),
        )
        let timeSize = timeLabel.sizeThatFits(CGSize(width: 200, height: 28))
        let timeCenter = CGPoint(x: bounds.width / 2, y: topRowTop + 20)
        timeLabel.bounds = CGRect(origin: .zero, size: CGSize(width: timeSize.width, height: 28))
        timeLabel.center = timeCenter
        timeBackground.bounds = CGRect(origin: .zero, size: CGSize(width: timeSize.width + 8, height: 28))
        timeBackground.center = timeCenter
    }

    nonisolated func photoOutput(
        _: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error _: Error?,
    ) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let captureSession = captureSession
            sessionQueue.async { captureSession.session.stopRunning() }
            onPhoto?(image)
        }
    }

    /// stopVideoRecording's result: the file goes to the editor, also when the minute ran out.
    nonisolated func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo url: URL,
        from _: [AVCaptureConnection],
        error: Error?,
    ) {
        let finished = error == nil
            || (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        Task { @MainActor [weak self] in
            guard let self else { return }
            if recording != .none { endRecording() }
            guard finished else { return }
            let captureSession = captureSession
            sessionQueue.async { captureSession.session.stopRunning() }
            onVideo?(url)
        }
    }

    private func configure(_ button: UIButton, image: UIImage?, label: String) {
        button.setImage(image?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = label
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.25
        button.layer.shadowRadius = 3
        button.layer.shadowOffset = .zero
        view.addSubview(button)
    }

    /// GlassBarButtonComponent's tinted glass in 0x212121 around FlipButtonContentComponent.
    private func configureFlipGlass() {
        let effect = UIGlassEffect(style: .regular)
        effect.tintColor = UIColor(red: 0x21 / 255, green: 0x21 / 255, blue: 0x21 / 255, alpha: 1)
        effect.isInteractive = true
        flipGlass.effect = effect
        flipGlass.cornerConfiguration = .capsule()
        flipGlass.clipsToBounds = true
        flipButton.setImage(
            UIImage(named: "MediaEditor/CameraFlipIcon")?.withRenderingMode(.alwaysTemplate),
            for: .normal,
        )
        flipButton.tintColor = .white
        flipButton.accessibilityLabel = "Flip"
        flipButton.addAction(UIAction { [weak self] _ in self?.flip() }, for: .touchUpInside)
        flipGlass.contentView.addSubview(flipButton)
        view.addSubview(flipGlass)
    }

    // MARK: Controls

    /// What the camera's state shows: the shutter's look, and the rows recording hides.
    private func updateControls(animated: Bool) {
        let isRecording = recording != .none
        shutterButton.setLook(
            {
                switch recording {
                case .handsFree: .stopRecording
                case .holding: .holdRecording(progress: recordingProgress)
                case .none: mode == .video ? .video : .generic
                }
            }(),
            animated: animated,
        )
        let changes = {
            for view in [self.closeButton, self.flashButton] as [UIView] {
                view.alpha = isRecording ? 0 : 1
            }
            self.modeControl.alpha = isRecording ? 0 : 1
            self.galleryButton.alpha = isRecording ? 0 : 1
            self.galleryButton.transform = isRecording ? CGAffineTransform(scaleX: 0.1, y: 0.1) : .identity
            self.flipGlass.alpha = isRecording ? 0 : 1
            self.flipGlass.transform = isRecording ? CGAffineTransform(scaleX: 0.01, y: 0.01) : .identity
            self.recordingFlipButton.alpha = isRecording ? 1 : 0
            self.recordingFlipButton.transform = isRecording ? .identity : CGAffineTransform(scaleX: 0.01, y: 0.01)
            self.timeLabel.alpha = isRecording ? 1 : 0
            self.timeBackground.alpha = isRecording ? 1 : 0
            let isHolding = self.recording == .holding
            self.lockView.alpha = isHolding ? 1 : 0
            self.lockView.transform = isHolding ? .identity : CGAffineTransform(scaleX: 0.1, y: 0.1)
            self.hintLabel.alpha = isHolding ? 1 : 0
            for guide in [self.leftGuide, self.rightGuide] {
                guide.alpha = isHolding ? 1 : 0
            }
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
        for view in [closeButton, flashButton, modeControl, galleryButton, flipGlass] as [UIView] {
            view.isUserInteractionEnabled = !isRecording
        }
        recordingFlipButton.isUserInteractionEnabled = isRecording
        if animated {
            UIView.animate(springDuration: 0.4, bounce: 0, animations: changes)
        } else {
            changes()
        }
    }

    /// The length as minutes and seconds.
    private func updateTime() {
        let seconds = Int(recordingDuration)
        timeLabel.text = String(format: "%02d:%02d", (seconds / 60) % 60, seconds % 60)
        view.setNeedsLayout()
        if recording == .holding {
            shutterButton.setLook(.holdRecording(progress: recordingProgress), animated: true)
        }
    }

    /// updateCameraMode: video turns an automatic flash on, since video has only on and off.
    private func select(_ mode: StoryCameraModeControl.Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
        modeControl.setMode(mode, animated: true)
        if mode == .video, flashMode == .auto {
            flashMode = .on
            updateFlashIcon()
        }
        updateControls(animated: true)
    }

    // MARK: Camera

    /// requestDeviceAccess: the camera, then the microphone; the camera starts only with both, and either refused
    /// shows the access placeholder.
    private func startCamera() {
        let camera = AVCaptureDevice.authorizationStatus(for: .video)
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        if camera == .notDetermined || (camera == .authorized && microphone == .notDetermined) {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else {
                    Task { @MainActor [weak self] in self?.startCamera() }
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.startCamera() }
                }
            }
            return
        }
        guard camera == .authorized, microphone == .authorized else {
            showAccessPlaceholder()
            return
        }
        setUpSession()
    }

    private func setUpSession() {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) != nil else {
            // No camera here, as on a simulator: Telegram's placeholder picture stands in.
            hasCamera = false
            placeholderView.isHidden = false
            shutterButton.isEnabled = false
            flashButton.isEnabled = false
            return
        }
        let captureSession = captureSession
        let position = position
        sessionQueue.async { captureSession.configure(position: position) }
    }

    private func showAccessPlaceholder() {
        accessView.isHidden = false
        shutterButton.isEnabled = false
        modeControl.isHidden = true
    }

    /// PlaceholderComponent: the request in 17 pt semibold, the reason in 15 pt and Open Settings in the accent colour.
    private func configureAccessView() {
        accessView.axis = .vertical
        accessView.alignment = .center
        accessView.distribution = .equalCentering
        accessView.spacing = 12
        accessView.isHidden = true
        let title = UILabel()
        title.text = L10n.telegram("Story.Camera.AccessPlaceholderTitle")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .white
        title.numberOfLines = 0
        title.textAlignment = .center
        let text = UILabel()
        text.text = L10n.telegram("Story.Camera.AccessPlaceholderText")
        text.font = .systemFont(ofSize: 15)
        text.textColor = UIColor(white: 1, alpha: 0.6)
        text.numberOfLines = 0
        text.textAlignment = .center
        let settings = UIButton(type: .system)
        settings.setTitle(L10n.telegram("Story.Camera.AccessOpenSettings"), for: .normal)
        settings.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        settings.addAction(UIAction { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }, for: .touchUpInside)
        let inner = UIStackView(arrangedSubviews: [title, text, settings])
        inner.axis = .vertical
        inner.alignment = .center
        inner.spacing = 12
        accessView.addArrangedSubview(UIView())
        accessView.addArrangedSubview(inner)
        accessView.addArrangedSubview(UIView())
        view.addSubview(accessView)
    }

    /// togglePosition: the other camera, also while recording.
    private func flip() {
        guard hasCamera else { return }
        position = position == .back ? .front : .back
        setUpSession()
        if recording != .none { setTorch(flashMode == .on) }
    }

    /// toggleFlashMode: off, on and auto for photos; off and on for video.
    private func toggleFlash() {
        flashMode =
            switch flashMode {
            case .off: .on
            case .on: mode == .video ? .off : .auto
            default: .off
            }
        updateFlashIcon()
    }

    /// flash_off, flash_on and flash_auto's resting frames.
    private func updateFlashIcon() {
        let name =
            switch flashMode {
            case .on: "bolt.fill"
            case .auto: "bolt.badge.automatic.fill"
            default: "bolt.slash.fill"
            }
        flashButton.setImage(
            UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)),
            for: .normal,
        )
    }

    /// shutterTapped: a photo in photo mode; in video mode a recording starts, and a tap during one stops it.
    private func shutterTapped() {
        guard recording == .none else {
            stopRecording()
            return
        }
        switch mode {
        case .photo: capture()
        case .video: startRecording(holding: false)
        }
    }

    /// shutterPressed, handlePan and shutterReleased: held, the shutter records in either mode until it is let go.
    /// The red circle follows the finger along the row: let go past 60 pt to the left it locks the recording, which
    /// then goes on until a tap; dragged past 70 pt from the right edge it flips the camera once; raised above the
    /// controls it zooms in by one for each 60 pt.
    @objc private func shutterHeld(_ gesture: UILongPressGestureRecognizer) {
        guard shutterButton.isEnabled else { return }
        let width = view.bounds.width
        let location = gesture.location(in: view)
        switch gesture.state {
        case .began:
            guard recording == .none else { return }
            startRecording(holding: true)
            setSwipeHint(.zoom)
            shutterButton.setInnerOffset(0, animated: false)
        case .changed:
            guard recording == .holding else { return }
            followFinger(location)
        case .cancelled,
             .ended:
            isBanding = nil
            didFlip = false
            guard recording == .holding else { return }
            if gesture.state == .ended, location.x < width / 2 - 60 {
                lockRecording()
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                stopRecording()
                shutterButton.setInnerOffset(0, spring: 0.25)
            }
        default:
            break
        }
    }

    /// handlePan's horizontal half: the offset banded near the middle and free past 60 pt, the hint for the side,
    /// the flip at the right edge and the zoom above the row.
    private func followFinger(_ location: CGPoint) {
        let width = view.bounds.width
        let controlsY = location.y - (shutterButton.center.y - 48)
        let zoom = controlsY < -10 ? min(8, (abs(controlsY) - 10) / 60) : 0
        if zoom != zoomFraction {
            zoomFraction = zoom
            let captureSession = captureSession
            let position = position
            sessionQueue.async { captureSession.setZoom(zoom, position: position) }
        }
        func band(_ offset: CGFloat) -> CGFloat {
            (1 - 1 / (offset * 0.4 / 60 + 1)) * 60
        }
        var offset = max(lockView.center.x, min(recordingFlipButton.center.x, location.x)) - width / 2
        let banding: Bool
        if location.x < width / 2 - 30 {
            if location.x < width / 2 - 60 {
                setSwipeHint(.releaseLock)
                banding = false
            } else {
                setSwipeHint(.lock)
                offset = band(offset)
                banding = true
            }
        } else if location.x > width / 2 + 30 {
            setSwipeHint(.flip)
            if location.x > width / 2 + 60 {
                banding = false
                if didFlip, location.x < width - 100 { didFlip = false }
                if !didFlip, location.x > width - 70 {
                    didFlip = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    flip()
                }
            } else {
                didFlip = false
                offset = -band(-offset)
                banding = true
            }
        } else {
            offset = band(offset)
            setSwipeHint(.zoom)
            banding = true
        }
        if let isBanding, isBanding != banding {
            shutterButton.setInnerOffset(offset, spring: 0.35)
        } else {
            shutterButton.setInnerOffset(offset, animated: false)
        }
        isBanding = banding
    }

    /// lockVideoRecording: the circle springs onto the lock and the recording goes on hands-free.
    private func lockRecording() {
        recording = .handsFree
        updateControls(animated: true)
        shutterButton.setInnerOffset(lockView.center.x - view.bounds.width / 2, spring: 0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.shutterButton.setInnerOffset(0, animated: false)
        }
    }

    /// HintLabelComponent: uppercased in SF Camera 14 pt semibold.
    private func setSwipeHint(_ hint: SwipeHint) {
        guard hint != swipeHint || hintLabel.attributedText == nil else { return }
        swipeHint = hint
        let font = UIFont(name: "SFCamera-Semibold", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        let apply = {
            self.hintLabel.attributedText = NSAttributedString(
                string: hint.text.uppercased(),
                attributes: [.font: font, .foregroundColor: UIColor.white],
            )
        }
        if hintLabel.window != nil {
            UIView.transition(with: hintLabel, duration: 0.2, options: .transitionCrossDissolve, animations: apply)
        } else {
            apply()
        }
    }

    private func capture() {
        guard session.isRunning else { return }
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(flashMode) { settings.flashMode = flashMode }
        shutterButton.flash()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    /// startVideoRecording: the microphone joins the session, the torch lights for a flash that is on, and the file
    /// records until it is stopped or the minute runs out.
    private func startRecording(holding: Bool) {
        guard session.isRunning, recording == .none else { return }
        recording = holding ? .holding : .handsFree
        recordingStart = CACurrentMediaTime()
        updateTime()
        updateControls(animated: true)
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateTime() }
        }
        if flashMode == .on { setTorch(true) }
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("bettertg-story-camera-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let captureSession = captureSession
        sessionQueue.async { [weak self] in
            guard let self else { return }
            captureSession.startRecording(to: url, maxDuration: Self.maxDuration, delegate: self)
        }
    }

    private func stopRecording() {
        guard recording != .none else { return }
        endRecording()
        let captureSession = captureSession
        sessionQueue.async { captureSession.movieOutput.stopRecording() }
    }

    private func endRecording() {
        recording = .none
        recordingTimer?.invalidate()
        recordingTimer = nil
        setTorch(false)
        updateControls(animated: true)
    }

    /// The back camera's torch stands in for the flash while a video records.
    private func setTorch(_ isOn: Bool) {
        let position = position
        sessionQueue.async {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  device.hasTorch, (try? device.lockForConfiguration()) != nil
            else { return }
            device.torchMode = isOn ? .on : .off
            device.unlockForConfiguration()
        }
    }

    /// The gallery button's picture: the newest photo in the library, when the app may read it.
    private func loadNewestPhoto() {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
            || PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited
        else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: options).firstObject else { return }
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 144, height: 144),
            contentMode: .aspectFill,
            options: nil,
        ) { [weak self] image, _ in
            Task { @MainActor [weak self] in self?.galleryButton.setImage(image, for: .normal) }
        }
    }
}

// MARK: - StoryCameraPreviewView

private final class StoryCameraPreviewView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        unsafeDowncast(layer, to: AVCaptureVideoPreviewLayer.self)
    }
}

// MARK: - StoryShutterButton

/// ShutterButtonContentComponent in a 96 pt square: a 3 pt white ring 68 pt wide around a 60 pt circle, white for
/// photos and red for video. Recording hands-free the circle shrinks to a 26 pt stop; recording held the ring grows to
/// 92 pt and fills red with the minute's progress. The circle shrinks a little while pressed. Disabled, it dims.
private final class StoryShutterButton: UIControl {
    enum Look: Equatable {
        case generic
        case video
        case stopRecording
        case holdRecording(progress: CGFloat)
    }

    /// videoRedColor.
    static let videoRed = UIColor(red: 1, green: 0x3B / 255, blue: 0x30 / 255, alpha: 1)

    override var isHighlighted: Bool {
        didSet { inner.transform = isHighlighted ? CATransform3DMakeScale(0.9, 0.9, 1) : CATransform3DIdentity }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.4 }
    }

    private let underRing = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let progress = CAShapeLayer()
    private let inner = CALayer()
    private var look = Look.generic
    /// The circle's offset along the row, as ShutterBlobView follows the finger.
    private var innerOffset: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        for layer in [underRing, ring, progress] {
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = 3
            layer.lineCap = .round
            self.layer.addSublayer(layer)
        }
        underRing.strokeColor = UIColor(white: 1, alpha: 0.2).cgColor
        ring.strokeColor = UIColor.white.cgColor
        progress.strokeColor = Self.videoRed.cgColor
        progress.lineWidth = 3 + 1 / 3
        progress.strokeEnd = 0
        inner.backgroundColor = UIColor.white.cgColor
        layer.addSublayer(inner)
        accessibilityLabel = L10n.telegram("Story.Camera.Photo")
        accessibilityTraits = .button
        isAccessibilityElement = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply(animated: false)
    }

    func setLook(_ look: Look, animated: Bool) {
        guard look != self.look else { return }
        self.look = look
        accessibilityLabel = L10n.telegram(look == .generic ? "Story.Camera.Photo" : "Story.Camera.Video")
        apply(animated: animated)
    }

    func setInnerOffset(_ offset: CGFloat, animated: Bool) {
        innerOffset = offset
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        inner.position = CGPoint(x: bounds.midX + offset, y: bounds.midY)
        CATransaction.commit()
    }

    /// The offset on a spring of the given duration.
    func setInnerOffset(_ offset: CGFloat, spring duration: TimeInterval) {
        let from = inner.presentation()?.position ?? inner.position
        setInnerOffset(offset, animated: false)
        let animation = CASpringAnimation(perceptualDuration: duration, bounce: 0)
        animation.keyPath = "position"
        animation.fromValue = NSValue(cgPoint: from)
        animation.toValue = NSValue(cgPoint: inner.position)
        animation.duration = animation.settlingDuration
        inner.add(animation, forKey: "offset")
    }

    /// The capture's blink.
    func flash() {
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 0.3
        blink.toValue = 1
        blink.duration = 0.2
        inner.add(blink, forKey: "blink")
    }

    /// The circle's colour and size and the ring's size for the look; the progress follows in 0.33 s.
    private func apply(animated: Bool) {
        let innerColor: UIColor
        let innerSize: CGFloat
        var ringSize: CGFloat = 68
        var recordingProgress: CGFloat = 0
        switch look {
        case .generic:
            innerColor = .white
            innerSize = 60
        case .video:
            innerColor = Self.videoRed
            innerSize = 60
        case .stopRecording:
            innerColor = Self.videoRed
            innerSize = 26
        case .holdRecording(let value):
            innerColor = Self.videoRed
            innerSize = 60
            ringSize = 92
            recordingProgress = value
        }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let ringPath = UIBezierPath(
            ovalIn: CGRect(x: -ringSize / 2, y: -ringSize / 2, width: ringSize, height: ringSize),
        ).cgPath
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        for layer in [underRing, ring, progress] {
            layer.bounds = .zero
            layer.position = center
            layer.path = ringPath
        }
        // The progress starts at the top.
        progress.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        progress.strokeEnd = recordingProgress
        inner.backgroundColor = innerColor.cgColor
        inner.bounds = CGRect(x: 0, y: 0, width: innerSize, height: innerSize)
        inner.cornerRadius = innerSize / 2
        inner.position = CGPoint(x: center.x + innerOffset, y: center.y)
        CATransaction.commit()
    }
}

// MARK: - StoryCameraModeControl

/// ModeComponent: the modes from the last, VIDEO then PHOTO, uppercased in 14 pt medium with -0.5 kerning, white or
/// 0xffd300 when current, 40 pt apart and 23 pt in, on a 48 pt capsule of 11% white. The current one sits under
/// UIKit's liquid lens 3 pt in; a touch lifts the lens under the finger, which carries it, and the mode it is let
/// go over becomes current (TabSelectionRecognizer).
private final class StoryCameraModeControl: UIView {
    enum Mode: CaseIterable {
        case photo
        case video

        var title: String {
            L10n.telegram(self == .photo ? "Story.Camera.Photo" : "Story.Camera.Video").uppercased()
        }
    }

    private static let height: CGFloat = 48
    private static let accent = UIColor(red: 1, green: 0xD3 / 255, blue: 0, alpha: 1)

    var onSelect: ((Mode) -> Void)?

    /// availableModes reversed.
    private let modes: [Mode] = [.video, .photo]
    private let liftedContainer = UIView()
    private let capsule = UIView()
    /// The titles in the accent colour, shown inside the lens.
    private let selectedTitlesView = UIView()
    /// The titles as they rest, cut away under the lens.
    private let titlesView = UIView()
    /// LiquidLensView's resting background, 10% white under the resting lens.
    private let selectionView = UIView()
    private var lens: LiquidLens?
    private var current = Mode.photo
    private var itemFrames = [CGRect]()
    private var inset: CGFloat = 23
    private var drag: (startX: CGFloat, index: Int)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(liftedContainer)
        capsule.backgroundColor = UIColor(white: 1, alpha: 0.11)
        capsule.layer.cornerRadius = Self.height / 2
        capsule.clipsToBounds = true
        liftedContainer.addSubview(capsule)
        selectionView.backgroundColor = UIColor(white: 1, alpha: 0.1)
        selectionView.isUserInteractionEnabled = false
        capsule.addSubview(selectionView)
        for layer in [selectedTitlesView, titlesView] {
            layer.isUserInteractionEnabled = false
            capsule.addSubview(layer)
        }
        selectedTitlesView.accessibilityElementsHidden = true
        for mode in modes {
            selectedTitlesView.addSubview(Self.titleLabel(mode, color: Self.accent))
            titlesView.addSubview(Self.titleLabel(mode, color: .white))
        }
        self.lens = LiquidLens(
            liftedContainer: liftedContainer,
            liftedContent: selectedTitlesView,
            punchout: titlesView,
        )
        if lens == nil {
            // Without UIKit's lens the tinted capsule alone marks the current mode, whose title turns yellow.
            selectedTitlesView.removeFromSuperview()
        }
        let gesture = LiquidLensTabRecognizer(target: self, action: #selector(touched(_:)))
        addGestureRecognizer(gesture)
        isAccessibilityElement = false
        accessibilityElements = modes.map { mode in
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = mode.title
            return element
        }
        updateTitles()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let widths = titlesView.subviews.map { $0.sizeThatFits(.zero).width.rounded(.up) }
        let inset: CGFloat = size.width < 200 ? 20 : 23
        let spacing: CGFloat = size.width < 200 ? 24 : 40
        let total = widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1)) + inset * 2
        return CGSize(width: min(size.width, total), height: Self.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        liftedContainer.frame = bounds
        capsule.frame = bounds
        for layer in [selectedTitlesView, titlesView] {
            layer.frame = capsule.bounds
        }
        inset = bounds.width < 200 ? 20 : 23
        let spacing: CGFloat = bounds.width < 200 ? 24 : 40
        var x = inset
        itemFrames = titlesView.subviews.map { label in
            let width = label.sizeThatFits(.zero).width.rounded(.up)
            defer { x += width + spacing }
            return CGRect(x: x, y: 0, width: width, height: Self.height)
        }
        for views in [selectedTitlesView.subviews, titlesView.subviews] {
            for (view, frame) in zip(views, itemFrames) {
                view.frame = frame
            }
        }
        for (element, frame) in zip(accessibilityElements ?? [], itemFrames) {
            (element as? UIAccessibilityElement)?.accessibilityFrameInContainerSpace = frame
        }
        placeLens(at: modes.firstIndex(of: current) ?? 0, offset: nil, animated: false)
    }

    private static func titleLabel(_ mode: Mode, color: UIColor) -> UILabel {
        let label = UILabel()
        label.attributedText = NSAttributedString(string: mode.title, attributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: color,
            .kern: -0.5,
        ])
        label.textAlignment = .center
        return label
    }

    func setMode(_ mode: Mode, animated: Bool) {
        current = mode
        updateTitles()
        placeLens(at: modes.firstIndex(of: mode) ?? 0, offset: nil, animated: animated)
    }

    private func updateTitles() {
        guard lens == nil else { return }
        for (label, mode) in zip(titlesView.subviews.compactMap { $0 as? UILabel }, modes) {
            label.textColor = mode == current ? Self.accent : .white
        }
    }

    /// The lens over the mode's title 23 pt to each side, 3 pt inside the capsule; a finger's lens keeps its width
    /// where the finger takes it.
    private func lensFrame(at index: Int, offset: CGFloat?) -> CGRect {
        guard itemFrames.indices.contains(index) else { return .zero }
        var frame = itemFrames[index].insetBy(dx: -inset, dy: 0).insetBy(dx: 3, dy: 3)
        if let offset {
            frame.origin.x = min(max(3, offset), bounds.width - 3 - frame.width)
        }
        return frame
    }

    private func placeLens(at index: Int, offset: CGFloat?, animated: Bool) {
        let frame = lensFrame(at: index, offset: offset)
        guard frame.width > 0 else { return }
        let isLifted = offset != nil
        if let lens {
            if isLifted, !animated {
                lens.follow(frame)
            } else {
                lens.place(frame, isLifted: isLifted, springDuration: animated ? 0.4 : nil)
            }
        }
        let changes = {
            self.selectionView.frame = frame
            self.selectionView.layer.cornerRadius = frame.height / 2
            // The lifted lens shows no resting background.
            self.selectionView.alpha = isLifted && self.lens != nil ? 0 : 1
        }
        if animated {
            UIView.animate(springDuration: 0.4, bounce: 0.15, animations: changes)
        } else {
            changes()
        }
    }

    private func index(at x: CGFloat) -> Int {
        itemFrames.enumerated().min { abs($0.element.midX - x) < abs($1.element.midX - x) }?.offset ?? 0
    }

    @objc private func touched(_ gesture: LiquidLensTabRecognizer) {
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            let index = index(at: location.x)
            let startX = lensFrame(at: index, offset: nil).minX
            drag = (startX, index)
            placeLens(at: index, offset: startX, animated: true)
        case .changed:
            guard var drag else { return }
            let index = index(at: location.x)
            if index != drag.index {
                UISelectionFeedbackGenerator().selectionChanged()
                drag.index = index
                self.drag = drag
            }
            placeLens(at: drag.index, offset: drag.startX + gesture.translation.x, animated: false)
        case .ended:
            guard let drag else { return }
            self.drag = nil
            let mode = modes[drag.index]
            setMode(mode, animated: true)
            onSelect?(mode)
        default:
            drag = nil
            placeLens(at: modes.firstIndex(of: current) ?? 0, offset: nil, animated: true)
        }
    }
}

// MARK: - StoryCaptureSession

/// The camera's session, its photo and movie outputs and the microphone, touched only on the camera's queue once
/// set up.
private final class StoryCaptureSession: @unchecked Sendable {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let movieOutput = AVCaptureMovieFileOutput()

    /// The given camera in, the photo and movie outputs out, running. A front camera's video is mirrored, as its
    /// preview is.
    func configure(position: AVCaptureDevice.Position) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        for input in session.inputs.compactMap({ $0 as? AVCaptureDeviceInput })
            where input.device.hasMediaType(.video)
        {
            session.removeInput(input)
        }
        if session.canAddInput(input) { session.addInput(input) }
        for output in [photoOutput, movieOutput] as [AVCaptureOutput]
            where !session.outputs.contains(output) && session.canAddOutput(output)
        {
            session.addOutput(output)
        }
        if let connection = movieOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = position == .front
        }
        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
    }

    /// setZoomLevel: the neutral zoom plus the level, within what the camera allows.
    func setZoom(_ level: CGFloat, position: AVCaptureDevice.Position) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              (try? device.lockForConfiguration()) != nil
        else { return }
        device.videoZoomFactor = min(
            max(1 + level, device.minAvailableVideoZoomFactor),
            device.maxAvailableVideoZoomFactor,
        )
        device.unlockForConfiguration()
    }

    /// The microphone joins the session for the first video, then the file records.
    func startRecording(
        to url: URL,
        maxDuration: Double,
        delegate: AVCaptureFileOutputRecordingDelegate,
    ) {
        if !session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }),
           let microphone = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: microphone)
        {
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
        }
        movieOutput.maxRecordedDuration = CMTime(seconds: maxDuration, preferredTimescale: 600)
        movieOutput.startRecording(to: url, recordingDelegate: delegate)
    }
}

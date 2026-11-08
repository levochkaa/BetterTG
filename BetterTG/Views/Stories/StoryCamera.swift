// StoryCamera.swift

import AVFoundation
import Photos
import UIKit

// MARK: - StoryCameraViewController

/// CameraScreen for a story, photo mode: the 9:16 viewfinder with 30 pt corners under the status bar (or from the
/// top where the screen is too short for it and 30 pt more), Close at the top right and the flash 50 pt before it,
/// then CaptureControlsComponent at the bottom: the 68 pt ring around the 60 pt white shutter in the middle and the
/// flip button 28 pt from the right, with the 48 pt round gallery button showing the newest photo 16 pt in under
/// them. A camera the app may not use shows Telegram's access placeholder with Open Settings; a device without a
/// camera shows Telegram's camera placeholder picture.
final class StoryCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    override var prefersStatusBarHidden: Bool {
        true
    }

    var onPhoto: ((UIImage) -> Void)?
    var onGallery: (() -> Void)?

    /// The session and its photo output, set up and started on `sessionQueue`.
    private let captureSession = StoryCaptureSession()

    private let previewView = StoryCameraPreviewView()
    private let placeholderView = UIImageView(image: UIImage(named: "MediaEditor/CameraPlaceholder"))
    private let closeButton = UIButton(type: .custom)
    private let flashButton = UIButton(type: .custom)
    private let flipButton = UIButton(type: .custom)
    private let shutterButton = StoryShutterButton()
    private let galleryButton = UIButton(type: .custom)
    private let accessView = UIStackView()
    private var position = AVCaptureDevice.Position.back
    private var flashMode = AVCaptureDevice.FlashMode.off
    private let sessionQueue = DispatchQueue(label: "bettertg.story.camera")

    private var session: AVCaptureSession {
        captureSession.session
    }

    private var photoOutput: AVCapturePhotoOutput {
        captureSession.photoOutput
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
        configure(flipButton, image: UIImage(named: "MediaEditor/CameraFlipIcon"), label: "Flip")
        flipButton.addAction(UIAction { [weak self] _ in self?.flip() }, for: .touchUpInside)
        shutterButton.addAction(UIAction { [weak self] _ in self?.capture() }, for: .touchUpInside)
        view.addSubview(shutterButton)
        galleryButton.clipsToBounds = true
        galleryButton.layer.cornerRadius = 24
        galleryButton.backgroundColor = UIColor(white: 1, alpha: 0.2)
        galleryButton.imageView?.contentMode = .scaleAspectFill
        galleryButton.accessibilityLabel = L10n.telegram("Attachment.Gallery")
        galleryButton.addAction(UIAction { [weak self] _ in self?.onGallery?() }, for: .touchUpInside)
        view.addSubview(galleryButton)
        updateFlashIcon()
        loadNewestPhoto()
        configureAccessView()
        startCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let safe = view.safeAreaInsets
        let previewSize = CGSize(width: bounds.width, height: (bounds.width * 1.77778).rounded(.down))
        // The viewfinder starts under the status bar unless the screen has no 30 pt to spare for it.
        let topInset: CGFloat = bounds.height < previewSize.height + 30 ? 0 : safe.top + 5
        previewView.frame = CGRect(origin: CGPoint(x: 0, y: topInset), size: previewSize)
        placeholderView.frame = previewView.bounds
        accessView.frame = previewView.frame.insetBy(dx: 32, dy: 0)
        let controlsBottomInset: CGFloat = bounds.height < previewSize.height + 30 ? -70 : 0
        let topRowTop = max(safe.top + 12, 5)
        let rightInset = 9 + safe.right
        closeButton.frame = CGRect(x: bounds.width - rightInset - 40, y: topRowTop, width: 40, height: 40)
        flashButton.frame = CGRect(x: closeButton.frame.minX - 50, y: topRowTop, width: 40, height: 40)
        let shutterCenterY = bounds.height - 48 - safe.bottom - 5 + (controlsBottomInset * 0.66).rounded(.down)
        shutterButton.frame = CGRect(x: (bounds.width - 96) / 2, y: shutterCenterY - 48, width: 96, height: 96)
        flipButton.frame = CGRect(x: bounds.width - 48 - 28, y: shutterCenterY - 22, width: 44, height: 44)
        galleryButton.frame =
            if controlsBottomInset < 0 {
                CGRect(x: 9, y: shutterButton.frame.maxY - 2, width: 48, height: 48)
            } else {
                CGRect(x: 16, y: shutterButton.frame.maxY + 21, width: 48, height: 48)
            }
        // On a short screen the gallery button can't fall below the screen.
        if galleryButton.frame.maxY > bounds.height - safe.bottom {
            galleryButton.frame.origin.y = shutterCenterY - 24
            galleryButton.frame.origin.x = 28
        }
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

    // MARK: Camera

    private func startCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setUpSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    if granted {
                        self?.setUpSession()
                    } else {
                        self?.showAccessPlaceholder()
                    }
                }
            }
        default:
            showAccessPlaceholder()
        }
    }

    private func setUpSession() {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) != nil else {
            // No camera here, as on a simulator: Telegram's placeholder picture stands in.
            placeholderView.isHidden = false
            shutterButton.isEnabled = false
            flipButton.isEnabled = false
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

    /// togglePosition: the other camera.
    private func flip() {
        position = position == .back ? .front : .back
        setUpSession()
    }

    /// The flash cycles off, on and auto, as the camera's flash button does.
    private func toggleFlash() {
        flashMode =
            switch flashMode {
            case .off: .on
            case .on: .auto
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

    private func capture() {
        guard session.isRunning else { return }
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(flashMode) { settings.flashMode = flashMode }
        shutterButton.flash()
        photoOutput.capturePhoto(with: settings, delegate: self)
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

/// ShutterButtonContentComponent in its generic state: a 3 pt white ring 68 pt wide around a 60 pt white circle, in a
/// 96 pt square; the circle shrinks a little while pressed. Disabled, it dims.
private final class StoryShutterButton: UIControl {
    override var isHighlighted: Bool {
        didSet { inner.transform = isHighlighted ? CATransform3DMakeScale(0.9, 0.9, 1) : CATransform3DIdentity }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.4 }
    }

    private let ring = CAShapeLayer()
    private let inner = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = 3
        layer.addSublayer(ring)
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
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        ring.frame = bounds
        ring.path = UIBezierPath(
            ovalIn: CGRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68),
        ).cgPath
        inner.bounds = CGRect(x: 0, y: 0, width: 60, height: 60)
        inner.cornerRadius = 30
        inner.position = center
    }

    /// The capture's blink.
    func flash() {
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 0.3
        blink.toValue = 1
        blink.duration = 0.2
        inner.add(blink, forKey: "blink")
    }
}

// MARK: - StoryCaptureSession

/// The camera's session and photo output, touched only on the camera's queue once set up.
private final class StoryCaptureSession: @unchecked Sendable {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()

    /// The given camera in, the photo output out, running.
    func configure(position: AVCaptureDevice.Position) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }
        if session.canAddInput(input) { session.addInput(input) }
        if session.outputs.isEmpty, session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
    }
}

// WebAppQRScanner.swift

import AVFoundation
import UIKit

// MARK: - WebAppQRScanner

/// `web_app_open_scan_qr_popup` / `web_app_close_scan_qr_popup`: Telegram's QrCodeScanScreen with a custom subject.
/// Each code
/// the camera settles on goes to the page as `qr_text_received` while the scanner stays open for the page to close it;
/// the user's Close sends `scan_qr_popup_closed`.
@MainActor final class WebAppQRScanner {
    private let bridge: WebAppBridge
    private weak var screen: WebAppQRScannerViewController?

    init(bridge: WebAppBridge) {
        self.bridge = bridge
    }

    func open(_ json: [String: Any]?) {
        guard screen == nil, let presenter = bridge.topPresenter() else { return }
        let screen = WebAppQRScannerViewController(info: json?["text"] as? String ?? "")
        let send = bridge.send
        screen.completion = { result in
            if let result {
                send("qr_text_received", ["data": result])
            } else {
                send("scan_qr_popup_closed", nil)
            }
        }
        self.screen = screen
        presenter.present(screen, animated: true)
    }

    /// The page closes the scanner without `scan_qr_popup_closed`.
    func close() {
        guard let screen else { return }
        self.screen = nil
        screen.completion = nil
        screen.dismiss(animated: true)
    }
}

// MARK: - WebAppQRScannerViewController

/// QrCodeScanScreenNode for `.custom(info:)`: the camera under a dimmed frame with corner brackets, "Scan QR Code" and
/// the
/// page's text above it, the torch below it when the camera has one, and Close in the corner. A QR code centred in the
/// view draws the frame around itself and is reported half a second later.
private final class WebAppQRScannerViewController: UIViewController {
    private struct Code {
        let value: String
        let bounds: CGRect
    }

    /// The capture session and its camera, used on the session queue.
    private final class Capture: @unchecked Sendable {
        let session = AVCaptureSession()
        var device: AVCaptureDevice?
    }

    /// AVCaptureMetadataOutput's delegate on the main queue.
    private final class MetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
        var handler: (@MainActor ([Code]) -> Void)?

        func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection,
        ) {
            let codes = metadataObjects.compactMap { object -> Code? in
                guard let code = object as? AVMetadataMachineReadableCodeObject, let value = code.stringValue
                else { return nil }
                return Code(value: value, bounds: code.bounds)
            }
            MainActor.assumeIsolated { handler?(codes) }
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    var completion: ((String?) -> Void)?

    private let info: String
    private let capture = Capture()
    private let metadataDelegate = MetadataDelegate()
    private let sessionQueue = DispatchQueue(label: "bettertg.web-app.qr-scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let previewView = UIView()
    private let dimViews = (0..<4).map { _ in UIView() }
    private let frameView = WebAppQRFrameView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let torchButton = UIButton(type: .custom)
    private var focusedRect: CGRect?
    private var focusedCode: String?
    private var lostTask: Task<Void, Never>?
    private var isTorchOn = false
    private var needsAccessAlert = false
    private var didAnimateFrame = false

    init(info: String) {
        self.info = info
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    deinit {
        lostTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewView.backgroundColor = .black
        view.addSubview(previewView)
        for dim in dimViews {
            dim.backgroundColor = UIColor(white: 0, alpha: 0.8)
            dim.alpha = 0.625
            view.addSubview(dim)
        }
        view.addSubview(frameView)

        titleLabel.text = L10n.telegram("AuthSessions.AddDevice.ScanTitle")
        titleLabel.font = .boldSystemFont(ofSize: 32)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        textLabel.attributedText = WebAppBridge.attributed(info, font: .systemFont(ofSize: 17), color: .white)
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0

        var closeConfiguration = UIButton.Configuration.filled()
        closeConfiguration.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        )
        closeConfiguration.baseForegroundColor = .white
        closeConfiguration.baseBackgroundColor = UIColor(white: 1, alpha: 0.16)
        closeConfiguration.cornerStyle = .capsule
        closeButton.configuration = closeConfiguration
        closeButton.accessibilityLabel = L10n.telegram("Common.Close")
        closeButton.addAction(UIAction { [weak self] _ in self?.cancel() }, for: .touchUpInside)

        torchButton.isHidden = true
        torchButton.layer.cornerRadius = 36
        torchButton.clipsToBounds = true
        torchButton.addAction(UIAction { [weak self] _ in self?.toggleTorch() }, for: .touchUpInside)
        updateTorchButton()

        for subview in [titleLabel, textLabel, torchButton, closeButton] as [UIView] {
            view.addSubview(subview)
        }

        metadataDelegate.handler = { [weak self] codes in self?.received(codes) }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCamera()
        case .notDetermined:
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard let self else { return }
                if granted { startCamera() } else { presentAccessDenied() }
            }
        default:
            needsAccessAlert = true
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if needsAccessAlert {
            needsAccessAlert = false
            presentAccessDenied()
        }
        if !didAnimateFrame {
            didAnimateFrame = true
            frameView.animateIn()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        lostTask?.cancel()
        let capture = capture
        sessionQueue.async {
            if capture.session.isRunning { capture.session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layout()
    }

    // MARK: Private

    /// containerLayoutUpdated: a square of max(240, width - 132) in the middle, the text 48 pt above it with the title
    /// 18 pt over the text, and the 72 pt torch 98 pt under the frame.
    private func layout() {
        let bounds = view.bounds
        previewView.frame = bounds
        previewLayer?.frame = bounds
        updatePreviewRotation()

        let frameSide = min(max(240, bounds.width - 66 * 2), bounds.height * 0.6)
        let dimHeight = ceil((bounds.height - frameSide) / 2)
        let dimInset = (bounds.width - frameSide) / 2
        let frameRect = focusedRect ?? CGRect(x: dimInset, y: dimHeight, width: frameSide, height: frameSide)
        dimViews[0].frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, frameRect.minY))
        dimViews[1].frame = CGRect(
            x: 0,
            y: frameRect.maxY,
            width: bounds.width,
            height: max(0, bounds.height - frameRect.maxY),
        )
        dimViews[2].frame = CGRect(x: 0, y: frameRect.minY, width: max(0, frameRect.minX), height: frameRect.height)
        dimViews[3].frame = CGRect(
            x: frameRect.maxX,
            y: frameRect.minY,
            width: max(0, bounds.width - frameRect.maxX),
            height: frameRect.height,
        )
        frameView.frame = frameRect
        let isFocused = focusedRect != nil
        for dim in dimViews {
            dim.alpha = isFocused ? 1 : 0.625
        }
        let controlsAlpha: CGFloat = isFocused ? 0 : 1

        let top = max(view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0, view.safeAreaInsets.top)
        closeButton.frame = CGRect(x: 16 + view.safeAreaInsets.left, y: top + 5, width: 44, height: 44)
        let navigationHeight = top + 5 + 44

        let torchSize = CGSize(width: 72, height: 72)
        torchButton.frame = CGRect(
            x: floor((bounds.width - torchSize.width) / 2),
            y: min(dimHeight + frameSide + 98, bounds.height - torchSize.height - 10),
            width: torchSize.width,
            height: torchSize.height,
        )
        torchButton.alpha = controlsAlpha

        let fitting = CGSize(width: bounds.width - 16, height: bounds.height)
        let titleSize = titleLabel.sizeThatFits(fitting)
        let textSize = textLabel.sizeThatFits(fitting)
        var textY = max(
            dimHeight - textSize.height - 48,
            navigationHeight + floor((dimHeight - navigationHeight - textSize.height) / 2) + 5,
        )
        let titleY = textY - 18 - titleSize.height
        if titleY < navigationHeight {
            titleLabel.alpha = 0
            textY -= 5
        } else {
            titleLabel.alpha = controlsAlpha
        }
        titleLabel.frame = CGRect(
            x: floor((bounds.width - titleSize.width) / 2),
            y: titleY,
            width: titleSize.width,
            height: titleSize.height,
        )
        textLabel.frame = CGRect(
            x: floor((bounds.width - textSize.width) / 2),
            y: textY,
            width: textSize.width,
            height: textSize.height,
        )
        textLabel.alpha = controlsAlpha
    }

    private func updatePreviewRotation() {
        guard let connection = previewLayer?.connection else { return }
        let angle: CGFloat =
            switch view.window?.windowScene?.effectiveGeometry.interfaceOrientation {
            case .landscapeLeft: 180
            case .landscapeRight: 0
            case .portraitUpsideDown: 270
            default: 90
            }
        if connection.videoRotationAngle != angle, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    /// Camera(configuration: .hd1920x1080, back, metadata): QR codes only.
    private func startCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        else { return }
        let layer = AVCaptureVideoPreviewLayer(session: capture.session)
        layer.videoGravity = .resizeAspectFill
        previewView.layer.addSublayer(layer)
        previewLayer = layer
        view.setNeedsLayout()
        torchButton.isHidden = !device.hasTorch
        capture.device = device
        let capture = capture
        let delegate = metadataDelegate
        sessionQueue.async {
            guard let device = capture.device, let input = try? AVCaptureDeviceInput(device: device) else { return }
            let session = capture.session
            session.beginConfiguration()
            if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
            if session.canAddInput(input) { session.addInput(input) }
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(delegate, queue: .main)
                if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }
            }
            session.commitConfiguration()
            session.startRunning()
        }
    }

    /// The first code whose centre is in the middle 40 % of the view; a code that stays away for half a second
    /// releases the frame.
    private func received(_ codes: [Code]) {
        guard let previewLayer, presentedViewController == nil else { return }
        let bounds = view.bounds
        let middle = bounds.insetBy(dx: bounds.width * 0.3, dy: bounds.height * 0.3)
        let found = codes.lazy
            .map { ($0.value, previewLayer.layerRectConverted(fromMetadataOutputRect: $0.bounds)) }
            .first { middle.contains(CGPoint(x: $0.1.midX, y: $0.1.midY)) }
        lostTask?.cancel()
        guard let (value, rect) = found else { return codeLost() }
        lostTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.codeLost()
        }
        let side = max(rect.width, rect.height)
        setFocusedRect(CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
        guard value != focusedCode else { return }
        focusedCode = value
        // focusedCode → distinctUntilChanged → delay(0.5): the page gets the code half a second later.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.completion?(value)
        }
    }

    private func codeLost() {
        lostTask = nil
        focusedCode = nil
        setFocusedRect(nil)
    }

    private func setFocusedRect(_ rect: CGRect?) {
        guard rect != focusedRect else { return }
        focusedRect = rect
        UIView.animate(springDuration: 0.4, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.layout()
        }
    }

    private func toggleTorch() {
        isTorchOn.toggle()
        updateTorchButton()
        let isOn = isTorchOn
        let capture = capture
        sessionQueue.async {
            guard let device = capture.device, device.hasTorch,
                  (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = isOn ? .on : .off
            device.unlockForConfiguration()
        }
    }

    private func updateTorchButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(
            systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .regular),
        )
        configuration.baseForegroundColor = isTorchOn ? .black : .white
        configuration.baseBackgroundColor = isTorchOn ? .white : UIColor(white: 1, alpha: 0.16)
        configuration.cornerStyle = .capsule
        torchButton.configuration = configuration
        torchButton.isSelected = isTorchOn
    }

    private func cancel() {
        let completion = completion
        self.completion = nil
        completion?(nil)
        dismiss(animated: true)
    }

    private func presentAccessDenied() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: L10n.betterTG("Permissions.CameraTitle"),
            message: L10n.betterTG("Permissions.CameraMessage"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Notifications.PermissionsOpenSettings"), style: .default) {
            _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }
}

// MARK: - WebAppQRFrameView

/// QrCodeScanScreen's FrameNode: four 4 pt white corner strokes with a 6 pt arc, about 24 pt along each side.
private final class WebAppQRFrameView: UIView {
    private let lines = (0..<4).map { _ in CAShapeLayer() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for line in lines {
            line.strokeColor = UIColor.white.cgColor
            line.fillColor = UIColor.clear.cgColor
            line.lineWidth = 4
            line.lineCap = .round
            layer.addSublayer(line)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0 else { return }
        let radius: CGFloat = 6
        let lineLength = size.width / 2 - radius
        let fraction = min(1, 24 / max(lineLength, 1))
        let strokeStart = (1 - fraction) / 2
        let halfWidth = size.width / 2, halfHeight = size.height / 2
        let corners: [(start: CGPoint, center: CGPoint, from: CGFloat, to: CGFloat, end: CGPoint)] = [
            (CGPoint(x: 0, y: halfHeight), CGPoint(x: radius, y: radius), -.pi, -.pi / 2, CGPoint(x: halfWidth, y: 0)),
            (
                CGPoint(x: halfWidth, y: 0),
                CGPoint(x: size.width - radius, y: radius),
                -.pi / 2,
                0,
                CGPoint(x: size.width, y: halfHeight),
            ),
            (
                CGPoint(x: size.width, y: halfHeight),
                CGPoint(x: size.width - radius, y: size.height - radius),
                0,
                .pi / 2,
                CGPoint(x: halfWidth, y: size.height),
            ),
            (
                CGPoint(x: halfWidth, y: size.height),
                CGPoint(x: radius, y: size.height - radius),
                .pi / 2,
                .pi,
                CGPoint(x: 0, y: halfHeight),
            ),
        ]
        CATransaction.begin()
        CATransaction.setDisableActions(UIView.inheritedAnimationDuration == 0)
        for (line, corner) in zip(lines, corners) {
            let path = CGMutablePath()
            path.move(to: corner.start)
            path.addArc(
                center: corner.center,
                radius: radius,
                startAngle: corner.from,
                endAngle: corner.to,
                clockwise: false,
            )
            path.addLine(to: corner.end)
            line.frame = bounds
            line.path = path
            line.strokeStart = strokeStart
            line.strokeEnd = 1 - strokeStart
        }
        CATransaction.commit()
    }

    /// FrameNode.animateIn: the strokes grow from the corners after 0.15 s.
    func animateIn() {
        for line in lines {
            for (keyPath, from, to) in [
                ("strokeStart", 0.0, Double(line.strokeStart)),
                ("strokeEnd", 1.0, Double(line.strokeEnd)),
            ] {
                let animation = CASpringAnimation(keyPath: keyPath)
                animation.fromValue = from
                animation.toValue = to
                animation.damping = 88
                animation.stiffness = 900
                animation.mass = 1
                animation.duration = 0.85
                animation.beginTime = CACurrentMediaTime() + 0.15
                animation.fillMode = .backwards
                line.add(animation, forKey: keyPath)
            }
        }
    }
}

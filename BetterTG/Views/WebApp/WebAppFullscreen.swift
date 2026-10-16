// WebAppFullscreen.swift

import UIKit

// MARK: - WebAppFullscreen

/// WebAppController's fullscreen mode (`web_app_request_fullscreen` / `web_app_exit_fullscreen`): the page leaves the
/// sheet and covers the screen up to the status bar, the bot's header gives way to FullscreenControlsComponent's
/// floating Close/Back and More pills, and the page learns their height from `content_safe_area_changed`. A system
/// sheet can't grow past its large detent, so the content moves into a host over the sheet in its container view and
/// returns to the sheet when the mode ends. Also owns `web_app_toggle_orientation_lock`.
@MainActor final class WebAppFullscreen {
    struct Configuration {
        let title: String
        /// Everything the sheet shows: the header, the page and the bottom panel.
        let contentView: UIView
        let headerView: UIView
        let webView: UIView
        /// The page under the header; fullscreen pins it to the top of the content instead.
        let webViewTopToHeader: NSLayoutConstraint
        let menu: () -> [UIMenuElement]
        let back: () -> Void
        let send: (String, [String: Any]?) -> Void
        /// Viewport and safe areas changed; `true` sends them even when the height stayed the same.
        let layoutChanged: (_ force: Bool) -> Void
    }

    /// FullscreenControlsComponent: 30 pt pills 8 pt under the status bar.
    private static let controlsHeight: CGFloat = 30
    private static let controlsMargin: CGFloat = 8

    private(set) var isActive = false

    /// The header's text is dark: Telegram's `.Black` fullscreen status bar and grey pills.
    var usesDarkContent = false {
        didSet {
            guard usesDarkContent != oldValue else { return }
            hostView?.controls.usesDarkContent = usesDarkContent
            if isActive { controller?.setNeedsStatusBarAppearanceUpdate() }
        }
    }

    var hasBack = false {
        didSet { hostView?.controls.hasBack = hasBack }
    }

    private weak var controller: UIViewController?
    private var configuration: Configuration?
    private var webViewTopToContent: NSLayoutConstraint?
    private var hostView: WebAppFullscreenHostView?
    private var locksOrientation = false

    /// fullScreenStatusBarStyle while the page covers the screen.
    var statusBarStyle: UIStatusBarStyle {
        guard isActive else { return .default }
        return usesDarkContent ? .darkContent : .lightContent
    }

    /// `safe_area_changed`'s top: the status bar over the page in fullscreen.
    var safeAreaTop: CGFloat {
        isActive ? hostView?.statusBarHeight ?? 0 : 0
    }

    /// `content_safe_area_changed`'s top: the pills with their margins in fullscreen.
    var contentSafeAreaTop: CGFloat {
        isActive ? Self.controlsHeight + Self.controlsMargin * 2 : 0
    }

    func attach(to controller: UIViewController, configuration: Configuration) {
        self.controller = controller
        self.configuration = configuration
        webViewTopToContent = configuration.webView.topAnchor.constraint(equalTo: configuration.contentView.topAnchor)
    }

    /// setIsFullscreen: the same state again fails with ALREADY_FULLSCREEN; otherwise the page hears
    /// `fullscreen_changed` first, the sheet expands and the layout springs over 0.4 s.
    func setActive(_ active: Bool) {
        guard let configuration else { return }
        guard active != isActive else {
            configuration.send("fullscreen_failed", ["error": "ALREADY_FULLSCREEN"])
            return
        }
        guard let controller, let container = controller.presentationController?.containerView ?? controller.view
            .window
        else {
            configuration.send("fullscreen_failed", ["error": "UNSUPPORTED"])
            return
        }
        configuration.send("fullscreen_changed", ["is_fullscreen": active])
        isActive = active
        if active {
            if let sheet = controller.sheetPresentationController, sheet.selectedDetentIdentifier != .large {
                sheet.animateChanges { sheet.selectedDetentIdentifier = .large }
            }
            enter(in: container, configuration: configuration)
        } else {
            exit(configuration: configuration)
        }
        controller.modalPresentationCapturesStatusBarAppearance = active
        controller.setNeedsStatusBarAppearanceUpdate()
    }

    /// `web_app_toggle_orientation_lock`: the container's `lockOrientation`.
    func setOrientationLocked(_ locked: Bool) {
        guard locked != locksOrientation else { return }
        locksOrientation = locked
        WebAppOrientationLock.setLocked(locked, in: controller?.view.window?.windowScene)
    }

    /// The sheet is going away: the page fades with it instead of staying over the screen until the end.
    func disappear(alongside coordinator: UIViewControllerTransitionCoordinator?) {
        guard let host = hostView else { return }
        if let coordinator {
            coordinator.animate(alongsideTransition: { _ in host.alpha = 0 })
        } else {
            host.alpha = 0
        }
    }

    /// The Web App closed: its orientation lock ends with it.
    func tearDown() {
        setOrientationLocked(false)
    }

    // MARK: Private

    private func enter(in container: UIView, configuration: Configuration) {
        let host = WebAppFullscreenHostView(frame: container.bounds)
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.controls.title = configuration.title
        host.controls.usesDarkContent = usesDarkContent
        host.controls.hasBack = hasBack
        host.controls.onBack = configuration.back
        host.controls.menu = configuration.menu
        host.layoutChanged = { configuration.layoutChanged(false) }
        container.addSubview(host)
        hostView = host

        let content = configuration.contentView
        let start = content.convert(content.bounds, to: host)
        host.insertSubview(content, at: 0)
        content.autoresizingMask = []
        content.frame = start
        configuration.webViewTopToHeader.isActive = false
        webViewTopToContent?.isActive = true
        host.layoutControls()
        host.controls.alpha = 0
        UIView.animate(springDuration: 0.4, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            content.frame = host.bounds
            configuration.headerView.alpha = 0
            content.layoutIfNeeded()
        } completion: { _ in
            content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            configuration.layoutChanged(true)
        }
        UIView.animate(withDuration: 0.25) { host.controls.alpha = 1 }
        configuration.layoutChanged(true)
    }

    private func exit(configuration: Configuration) {
        guard let host = hostView, let sheetView = controller?.view else { return }
        hostView = nil
        let content = configuration.contentView
        let target = sheetView.convert(sheetView.bounds, to: host)
        content.autoresizingMask = []
        webViewTopToContent?.isActive = false
        configuration.webViewTopToHeader.isActive = true
        UIView.animate(withDuration: 0.25) { host.controls.alpha = 0 }
        UIView.animate(springDuration: 0.4, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            content.frame = target
            configuration.headerView.alpha = 1
            content.layoutIfNeeded()
        } completion: { [weak self] _ in
            // Entering again during the animation already took the content into the new host.
            if self?.isActive != true {
                sheetView.insertSubview(content, at: 0)
                content.frame = sheetView.bounds
                content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }
            host.removeFromSuperview()
            configuration.layoutChanged(true)
        }
    }
}

// MARK: - WebAppViewController + Status Bar

extension WebAppViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle {
        fullscreen.statusBarStyle
    }
}

// MARK: - WebAppFullscreenHostView

/// The page's place over the sheet while it is fullscreen, with the pills on top. Touches outside the page pass
/// through to the sheet.
private final class WebAppFullscreenHostView: UIView {
    let controls = WebAppFullscreenControlsView()
    var layoutChanged: (() -> Void)?

    /// ContainerViewLayout's statusBarHeight.
    var statusBarHeight: CGFloat {
        window?.windowScene?.statusBarManager?.statusBarFrame.height ?? safeAreaInsets.top
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(controls)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutControls()
        layoutChanged?()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self ? nil : result
    }

    func layoutControls() {
        controls.insets = UIEdgeInsets(top: 0, left: safeAreaInsets.left, bottom: 0, right: safeAreaInsets.right)
        controls.frame = CGRect(x: 0, y: statusBarHeight + 8, width: bounds.width, height: 30)
    }
}

// MARK: - WebAppFullscreenControlsView

/// FullscreenControlsComponent: a blurred pill on the left with Close or Back and the bot's name, which slides out for
/// the button's own title after 2.5 s, and the More pill on the right. BetterTG has no minimized Web Apps, so the
/// right pill holds More only.
private final class WebAppFullscreenControlsView: UIView {
    private static let sideInset: CGFloat = 16
    private static let pillHeight: CGFloat = 30
    private static let rightPillWidth: CGFloat = 40

    var title = "" {
        didSet {
            titleLabel.text = title
            setNeedsLayout()
        }
    }

    var hasBack = false {
        didSet { if hasBack != oldValue { backChanged() } }
    }

    var usesDarkContent = false {
        didSet { applyColors() }
    }

    var insets = UIEdgeInsets.zero {
        didSet { if insets != oldValue { setNeedsLayout() } }
    }

    var onBack: (() -> Void)?
    var menu: (() -> [UIMenuElement])?

    private let leftBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let rightBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let leftButton = UIButton(type: .custom)
    private let iconView = UIImageView()
    private let titleClippingView = UIView()
    private let titleLabel = UILabel()
    private let buttonTitleLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private var displaysTitle = true
    private var timer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let font = Self.roundedFont()
        titleLabel.font = font
        buttonTitleLabel.font = font
        buttonTitleLabel.text = L10n.telegram("Common.Close")
        titleClippingView.clipsToBounds = true
        titleClippingView.isUserInteractionEnabled = false
        for background in [leftBackground, rightBackground] {
            background.clipsToBounds = true
            background.layer.cornerRadius = Self.pillHeight / 2
            background.layer.cornerCurve = .continuous
            background.isUserInteractionEnabled = false
        }
        iconView.contentMode = .center
        iconView.isUserInteractionEnabled = false
        iconView.image = icon()
        leftButton.accessibilityLabel = L10n.telegram("Common.Close")
        leftButton.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
        leftButton.addAction(
            UIAction { [weak self] _ in self?.setHighlighted(true) },
            for: [.touchDown, .touchDragEnter],
        )
        leftButton.addAction(
            UIAction { [weak self] _ in self?.setHighlighted(false) },
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit],
        )
        moreButton.setImage(
            UIImage(
                systemName: "ellipsis",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold),
            ),
            for: .normal,
        )
        moreButton.accessibilityLabel = L10n.telegram("Common.More")
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.menu?() ?? [])
        }])
        titleClippingView.addSubview(titleLabel)
        titleClippingView.addSubview(buttonTitleLabel)
        for subview in [
            leftBackground,
            leftButton,
            titleClippingView,
            iconView,
            rightBackground,
            moreButton,
        ] as [UIView] {
            addSubview(subview)
        }
        applyColors()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    deinit {
        timer?.invalidate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, timer == nil, displaysTitle else { return }
        // The bot's name gives way to the button's title after 2.5 s.
        let timer = Timer(timeInterval: 2.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideTitle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pill = Self.pillHeight
        let rightFrame = CGRect(
            x: bounds.width - insets.right - Self.sideInset - Self.rightPillWidth,
            y: 0,
            width: Self.rightPillWidth,
            height: pill,
        )
        rightBackground.frame = rightFrame
        moreButton.frame = CGRect(x: rightFrame.midX - 18, y: rightFrame.midY - 18, width: 36, height: 36)

        let titleSize = titleLabel.sizeThatFits(CGSize(width: bounds.width / 2, height: pill))
        let buttonTitleSize = buttonTitleLabel.sizeThatFits(CGSize(width: bounds.width / 2, height: pill))
        let additionalWidth = (displaysTitle ? titleSize.width : buttonTitleSize.width) + 10
        let leftFrame = CGRect(x: Self.sideInset + insets.left, y: 0, width: pill + additionalWidth, height: pill)
        leftBackground.frame = leftFrame
        leftButton.frame = leftFrame
        iconView.frame = CGRect(x: leftFrame.minX, y: 0, width: pill, height: pill)
        titleClippingView.frame = CGRect(
            x: leftFrame.minX + pill - 3,
            y: 0,
            width: leftFrame.width - pill,
            height: pill,
        )
        titleLabel.bounds = CGRect(origin: .zero, size: titleSize)
        titleLabel.center = CGPoint(
            x: (displaysTitle ? 3 : -titleSize.width - 15) + titleSize.width / 2,
            y: pill / 2,
        )
        titleLabel.alpha = displaysTitle ? 1 : 0
        buttonTitleLabel.bounds = CGRect(origin: .zero, size: buttonTitleSize)
        buttonTitleLabel.center = CGPoint(
            x: (displaysTitle ? pill + additionalWidth + 3 : 3) + buttonTitleSize.width / 2,
            y: pill / 2,
        )
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self ? nil : result
    }

    // MARK: Private

    private static func roundedFont() -> UIFont {
        let base = UIFont.systemFont(ofSize: 13, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: 13)
    }

    private func icon() -> UIImage? {
        UIImage(
            systemName: hasBack ? "chevron.backward" : "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold),
        )?.withRenderingMode(.alwaysTemplate)
    }

    private func applyColors() {
        let background = usesDarkContent ? UIColor(white: 0.7, alpha: 0.35) : UIColor(white: 0.45, alpha: 0.25)
        let text = usesDarkContent ? UIColor(white: 128 / 255, alpha: 1) : .white
        leftBackground.contentView.backgroundColor = background
        rightBackground.contentView.backgroundColor = background
        titleLabel.textColor = text
        buttonTitleLabel.textColor = text
        iconView.tintColor = text
        moreButton.tintColor = text
    }

    private func setHighlighted(_ highlighted: Bool) {
        let alpha: CGFloat = highlighted ? 0.6 : 1
        UIView.animate(withDuration: highlighted ? 0 : 0.2) {
            self.iconView.alpha = alpha
            self.buttonTitleLabel.alpha = alpha
        }
    }

    private func hideTitle() {
        timer = nil
        displaysTitle = false
        setNeedsLayout()
        UIView.animate(springDuration: 0.3, bounce: 0) { self.layoutIfNeeded() }
    }

    /// The Close/Back morph: the old title slides out, the new one slides in and the pill resizes.
    private func backChanged() {
        let multiplier: CGFloat = hasBack ? 1 : -1
        if !displaysTitle, window != nil, let snapshot = buttonTitleLabel.snapshotView(afterScreenUpdates: false) {
            snapshot.frame = buttonTitleLabel.frame
            titleClippingView.addSubview(snapshot)
            UIView.animate(springDuration: 0.3, bounce: 0) {
                snapshot.transform = CGAffineTransform(translationX: -snapshot.bounds.width * 1.5 * multiplier, y: 0)
            } completion: { _ in
                snapshot.removeFromSuperview()
            }
        }
        let title = hasBack ? L10n.telegram("Common.Back") : L10n.telegram("Common.Close")
        buttonTitleLabel.text = title
        leftButton.accessibilityLabel = title
        UIView.transition(with: iconView, duration: 0.2, options: .transitionCrossDissolve) {
            self.iconView.image = self.icon()
        }
        setNeedsLayout()
        guard !displaysTitle, window != nil else { return }
        let offset = buttonTitleLabel.sizeThatFits(bounds.size).width * 1.5 * multiplier
        buttonTitleLabel.transform = CGAffineTransform(translationX: offset, y: 0)
        UIView.animate(springDuration: 0.3, bounce: 0) {
            self.buttonTitleLabel.transform = .identity
            self.layoutIfNeeded()
        }
    }
}

// MARK: - WebAppOrientationLock

/// Telegram's `lockOrientation`: while a Web App holds the lock, the app supports only the orientation the interface
/// had
/// when it was taken. The app delegate reports these orientations; with no lock they are Info.plist's.
@MainActor enum WebAppOrientationLock {
    private static var lockedMask: UIInterfaceOrientationMask?

    /// UISupportedInterfaceOrientations for the device.
    private static let declaredMask: UIInterfaceOrientationMask = {
        let bundle = Bundle.main
        let padNames = UIDevice.current.userInterfaceIdiom == .pad
            ? bundle.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations~ipad") as? [String]
            : nil
        let names = padNames ?? bundle.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations") as? [String]
        var mask: UIInterfaceOrientationMask = []
        for name in names ?? [] {
            switch name {
            case "UIInterfaceOrientationPortrait": mask.insert(.portrait)
            case "UIInterfaceOrientationPortraitUpsideDown": mask.insert(.portraitUpsideDown)
            case "UIInterfaceOrientationLandscapeLeft": mask.insert(.landscapeLeft)
            case "UIInterfaceOrientationLandscapeRight": mask.insert(.landscapeRight)
            default: break
            }
        }
        return mask.isEmpty ? .portrait : mask
    }()

    static var supportedOrientations: UIInterfaceOrientationMask {
        lockedMask ?? declaredMask
    }

    static func setLocked(_ locked: Bool, in scene: UIWindowScene?) {
        if locked {
            let current: UIInterfaceOrientationMask? =
                switch scene?.effectiveGeometry.interfaceOrientation {
                case .portrait: .portrait
                case .portraitUpsideDown: .portraitUpsideDown
                case .landscapeLeft: .landscapeLeft
                case .landscapeRight: .landscapeRight
                default: nil
                }
            guard let current, declaredMask.contains(current) else { return }
            lockedMask = current
        } else {
            guard lockedMask != nil else { return }
            lockedMask = nil
        }
        for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in windowScene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
        }
    }
}

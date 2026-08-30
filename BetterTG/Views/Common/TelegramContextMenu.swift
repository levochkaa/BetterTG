// TelegramContextMenu.swift

import ObjectiveC.runtime
import UIKit

// MARK: - TelegramContextMenuLayout

private enum TelegramContextMenuLayout {
    static let actionHeight = CGFloat(44)
    static let menuWidth = CGFloat(250)
    static let sectionSeparatorHeight = CGFloat(8)
}

// MARK: - TelegramContextMenuAction

struct TelegramContextMenuAction {
    // MARK: Internal

    let title: String
    let image: UIImage?
    let isDestructive: Bool
    let startsNewSection: Bool
    let handler: () -> Void

    init(
        title: String,
        image: UIImage? = nil,
        isDestructive: Bool = false,
        startsNewSection: Bool = false,
        handler: @escaping () -> Void,
    ) {
        self.title = title
        self.image = image
        self.isDestructive = isDestructive
        self.startsNewSection = startsNewSection
        self.handler = handler
    }
}

// MARK: - TelegramContextMenuPresentationStyle

enum TelegramContextMenuPresentationStyle: Equatable {
    case message
    case avatar
    case chatPreview
    case menuOnly
}

// MARK: - TelegramContextMenuKeyboardHost

private enum TelegramContextMenuKeyboardHost {
    // MARK: Internal

    static func visibleKeyboardWindow(for sourceWindow: UIWindow) -> UIWindow? {
        if #available(iOS 16.0, *),
           let screen = sourceWindow.windowScene?.screen,
           let keyboardWindow = remoteKeyboardWindow(on: screen),
           !keyboardWindow.isHidden
        {
            return keyboardWindow
        }

        return UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { window in
                let name = NSStringFromClass(type(of: window))
                return !window.isHidden
                    && (name.hasSuffix("RemoteKeyboardWindow") || name.hasSuffix("TextEffectsWindow"))
            }
    }

    // MARK: Private

    @available(iOS 16.0, *) private static func remoteKeyboardWindow(on screen: UIScreen) -> UIWindow? {
        guard let keyboardClass = NSClassFromString("UIRemoteKeyboardWindow"),
              let method = class_getClassMethod(
                  keyboardClass,
                  NSSelectorFromString("remoteKeyboardWindowForScreen:create:"),
              )
        else { return nil }

        typealias GetKeyboardWindow = @convention(c) (
            AnyClass,
            Selector,
            UIScreen,
            Bool,
        ) -> UIWindow?
        let implementation = method_getImplementation(method)
        let getKeyboardWindow = unsafeBitCast(implementation, to: GetKeyboardWindow.self)
        return getKeyboardWindow(
            keyboardClass,
            NSSelectorFromString("remoteKeyboardWindowForScreen:create:"),
            screen,
            false,
        )
    }
}

// MARK: - TelegramContextMenuExtractableView

// swiftformat:disable preferFinalClasses
/// Keeps an extracted view's layout slot occupied while the real content is
/// temporarily hosted by the context-menu overlay, mirroring Telegram's
/// takeView/putBack contract.
class TelegramContextMenuExtractableView: UIView {
    // MARK: Internal

    let extractedContentView = UIView()

    // MARK: Private

    private var contentConstraints = [NSLayoutConstraint]()
    private var placeholderConstraints = [NSLayoutConstraint]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        extractedContentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(extractedContentView)
        installContentConstraints()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Fileprivate

    fileprivate func takeContextMenuContent() -> UIView? {
        guard extractedContentView.superview === self else { return nil }
        layoutIfNeeded()
        placeholderConstraints = [
            widthAnchor.constraint(equalToConstant: bounds.width),
            heightAnchor.constraint(equalToConstant: bounds.height),
        ]
        NSLayoutConstraint.activate(placeholderConstraints)
        NSLayoutConstraint.deactivate(contentConstraints)
        extractedContentView.removeFromSuperview()
        extractedContentView.translatesAutoresizingMaskIntoConstraints = true
        return extractedContentView
    }

    fileprivate func putBackContextMenuContent(_ content: UIView) {
        guard content === extractedContentView else { return }
        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        installContentConstraints()
        setNeedsLayout()
        layoutIfNeeded()
        NSLayoutConstraint.deactivate(placeholderConstraints)
        placeholderConstraints.removeAll()
    }

    private func installContentConstraints() {
        contentConstraints = [
            extractedContentView.topAnchor.constraint(equalTo: topAnchor),
            extractedContentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            extractedContentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            extractedContentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        NSLayoutConstraint.activate(contentConstraints)
    }
}

// swiftformat:enable preferFinalClasses

extension UIViewController {
    @discardableResult func presentTelegramContextMenu(
        sourceView: UIView,
        actions: [TelegramContextMenuAction],
        tracking gesture: UIGestureRecognizer? = nil,
        sourceBaseTransform: CGAffineTransform? = nil,
        performsInitialFeedback: Bool = true,
        presentationStyle: TelegramContextMenuPresentationStyle = .message,
        previewController: UIViewController? = nil,
    ) -> Bool {
        guard !actions.isEmpty,
              TelegramContextMenuController.activeController == nil,
              let sourceWindow = sourceView.window
        else { return false }
        let controller = TelegramContextMenuController(
            sourceView: sourceView,
            actions: actions,
            trackingGesture: gesture,
            sourceTransform: sourceBaseTransform ?? sourceView.transform,
            presentationStyle: presentationStyle,
            previewController: previewController,
        )
        if performsInitialFeedback {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
            if presentationStyle != .menuOnly {
                UIView.animate(
                    withDuration: 0.12,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                ) {
                    sourceView.transform = sourceView.transform.scaledBy(x: 0.98, y: 0.98)
                }
            }
        }
        controller.show(in: sourceWindow)
        return true
    }
}

// MARK: - TelegramContextMenuController

private final class TelegramContextMenuController: UIViewController {
    // MARK: Fileprivate

    fileprivate static var activeController: TelegramContextMenuController?

    // MARK: Private

    private weak var sourceView: UIView?
    private let sourceTransform: CGAffineTransform
    private let presentationStyle: TelegramContextMenuPresentationStyle
    private let previewController: UIViewController?
    private weak var trackingGesture: UIGestureRecognizer?
    private let actions: [TelegramContextMenuAction]
    private let backgroundEffectView = UIVisualEffectView(effect: nil)
    private let dimView = UIView()
    private let previewContainer = UIView()
    private let menuEffectView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        return UIVisualEffectView(effect: effect)
    }()

    private let menuStack = UIStackView()
    private let selectionHighlightView = UIView()
    private var previewView: UIView?
    private weak var extractedSource: TelegramContextMenuExtractableView?
    private var sourceFrame = CGRect.zero
    private var targetPreviewFrame = CGRect.zero
    private var targetMenuFrame = CGRect.zero
    private var messageContentSize = CGSize.zero
    private var targetMessageScale = CGFloat(1)
    private var originalContentCornerRadius = CGFloat.zero
    private weak var presentationHostView: UIView?
    private var actionButtons = [TelegramContextMenuActionButton]()
    private weak var trackedButton: TelegramContextMenuActionButton?
    private var hasAnimatedIn = false
    private var isDismissing = false
    private var isPerformingAction = false

    private lazy var menuSelectionGesture = UILongPressGestureRecognizer(
        target: self,
        action: #selector(menuSelectionGestureChanged(_:)),
    )

    init(
        sourceView: UIView,
        actions: [TelegramContextMenuAction],
        trackingGesture: UIGestureRecognizer?,
        sourceTransform: CGAffineTransform,
        presentationStyle: TelegramContextMenuPresentationStyle,
        previewController: UIViewController?,
    ) {
        self.sourceView = sourceView
        self.sourceTransform = sourceTransform
        self.actions = actions
        self.trackingGesture = trackingGesture
        self.presentationStyle = presentationStyle
        self.previewController = previewController
        super.init(nibName: nil, bundle: nil)
        trackingGesture?.addTarget(self, action: #selector(trackingGestureChanged(_:)))
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        trackingGesture?.removeTarget(self, action: #selector(trackingGestureChanged(_:)))
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isDismissing else { return }
        layoutPreviewAndMenu()
    }

    fileprivate func show(in sourceWindow: UIWindow) {
        let hostView = TelegramContextMenuKeyboardHost.visibleKeyboardWindow(for: sourceWindow) ?? sourceWindow
        presentationHostView = hostView
        Self.activeController = self
        loadViewIfNeeded()
        view.frame = hostView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.layer.zPosition = 1000
        hostView.addSubview(view)
        beginAppearanceTransition(true, animated: false)
        endAppearanceTransition()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        animateIn()
    }

    private func configureViews() {
        view.backgroundColor = .clear

        backgroundEffectView.frame = view.bounds
        backgroundEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundEffectView)

        dimView.frame = view.bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimView.backgroundColor = presentationStyle == .menuOnly
            ? .clear
            : UIColor.black.withAlphaComponent(0.18)
        dimView.alpha = 0
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissMenu)))
        view.addSubview(dimView)

        previewContainer.layer.shadowColor = UIColor.black.cgColor
        previewContainer.layer.shadowOpacity = 0.24
        previewContainer.layer.shadowRadius = 24
        previewContainer.layer.shadowOffset = CGSize(width: 0, height: 10)
        previewContainer.clipsToBounds = presentationStyle == .chatPreview
        previewContainer.layer.cornerCurve = .continuous
        previewContainer.layer.cornerRadius = presentationStyle == .chatPreview ? 24 : 0
        view.addSubview(previewContainer)

        if let previewController {
            addChild(previewController)
            previewController.view.frame = previewContainer.bounds
            previewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            previewContainer.addSubview(previewController.view)
            previewController.didMove(toParent: self)
            previewView = previewController.view
            sourceView?.alpha = 0
        } else if presentationStyle != .menuOnly, let sourceView {
            let extractedView: UIView?
            if let source = sourceView as? TelegramContextMenuExtractableView {
                extractedSource = source
                extractedView = source.takeContextMenuContent()
            } else {
                extractedView = sourceView.snapshotView(afterScreenUpdates: false)
                sourceView.alpha = 0
            }
            if let extractedView {
                originalContentCornerRadius = extractedView.layer.cornerRadius
                extractedView.frame = previewContainer.bounds
                extractedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                previewContainer.addSubview(extractedView)
                previewView = extractedView
            }
        }

        menuEffectView.layer.cornerRadius = 26
        menuEffectView.layer.cornerCurve = .continuous
        menuEffectView.cornerConfiguration = .corners(radius: 26)
        menuEffectView.clipsToBounds = true
        menuEffectView.alpha = 0
        view.addSubview(menuEffectView)

        selectionHighlightView.backgroundColor = .contextMenuSelectionHighlight
        selectionHighlightView.layer.cornerRadius = 20
        selectionHighlightView.layer.cornerCurve = .continuous
        selectionHighlightView.alpha = 0
        selectionHighlightView.isUserInteractionEnabled = false
        menuEffectView.contentView.addSubview(selectionHighlightView)

        menuStack.axis = .vertical
        menuStack.alignment = .fill
        menuStack.translatesAutoresizingMaskIntoConstraints = false
        menuEffectView.contentView.addSubview(menuStack)
        NSLayoutConstraint.activate([
            menuStack.topAnchor.constraint(equalTo: menuEffectView.contentView.topAnchor),
            menuStack.leadingAnchor.constraint(equalTo: menuEffectView.contentView.leadingAnchor),
            menuStack.trailingAnchor.constraint(equalTo: menuEffectView.contentView.trailingAnchor),
            menuStack.bottomAnchor.constraint(equalTo: menuEffectView.contentView.bottomAnchor),
        ])

        menuSelectionGesture.minimumPressDuration = 0
        menuSelectionGesture.cancelsTouchesInView = true
        menuEffectView.addGestureRecognizer(menuSelectionGesture)

        for (index, action) in actions.enumerated() {
            if index > 0, action.startsNewSection {
                menuStack.addArrangedSubview(TelegramContextMenuSectionDivider())
            }
            let button = TelegramContextMenuActionButton(action: action)
            button.addTarget(self, action: #selector(actionPressed(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: TelegramContextMenuLayout.actionHeight).isActive = true
            menuStack.addArrangedSubview(button)
            actionButtons.append(button)
        }
    }

    private func layoutPreviewAndMenu() {
        guard let sourceView else { return }
        sourceFrame = view.convert(sourceView.convert(sourceView.bounds, to: nil), from: nil)
        let horizontalInset: CGFloat = 12
        let verticalInset = max(view.safeAreaInsets.top, CGFloat(12))
        let availableWidth = view.bounds.width - horizontalInset * 2
        let separatorHeight = actions.dropFirst().reduce(CGFloat.zero) {
            $0 + ($1.startsNewSection ? TelegramContextMenuLayout.sectionSeparatorHeight : 0)
        }
        let menuHeight = CGFloat(actions.count) * TelegramContextMenuLayout.actionHeight + separatorHeight
        let menuWidth = min(TelegramContextMenuLayout.menuWidth, availableWidth)
        let bottomInset = max(view.safeAreaInsets.bottom, CGFloat(12))
        let maximumBottom = view.bounds.height - bottomInset

        switch presentationStyle {
        case .message:
            let spacing: CGFloat = 10
            let baseSourceFrame = sourceFrameAtBaseTransform()
            let maximumPreviewHeight = max(44, maximumBottom - verticalInset - menuHeight - spacing)
            messageContentSize = sourceView.bounds.size
            targetMessageScale = min(
                1,
                availableWidth / max(1, messageContentSize.width),
                maximumPreviewHeight / max(1, messageContentSize.height),
            )
            let previewHeight = messageContentSize.height * targetMessageScale
            let previewWidth = messageContentSize.width * targetMessageScale
            let alignedPreviewX = baseSourceFrame.midX > view.bounds.midX
                ? baseSourceFrame.maxX - previewWidth
                : baseSourceFrame.minX
            let previewX = min(max(0, alignedPreviewX), view.bounds.width - previewWidth)
            let maximumPreviewY = maximumBottom - menuHeight - spacing - previewHeight
            let previewY = min(max(verticalInset, baseSourceFrame.minY), maximumPreviewY)
            targetPreviewFrame = CGRect(x: previewX, y: previewY, width: previewWidth, height: previewHeight)
            let menuX = baseSourceFrame.midX > view.bounds.midX
                ? view.bounds.width - horizontalInset - menuWidth
                : horizontalInset
            targetMenuFrame = CGRect(
                x: menuX,
                y: targetPreviewFrame.maxY + spacing,
                width: menuWidth,
                height: menuHeight,
            )
        case .avatar:
            let spacing: CGFloat = 10
            let squareSize = min(
                view.bounds.width - 32,
                maximumBottom - verticalInset - menuHeight - spacing,
            )
            let centeredY = view.bounds.midY - squareSize / 2
            let previewY = min(
                max(verticalInset, centeredY),
                maximumBottom - menuHeight - spacing - squareSize,
            )
            targetPreviewFrame = CGRect(
                x: (view.bounds.width - squareSize) / 2,
                y: previewY,
                width: squareSize,
                height: squareSize,
            )
            targetMenuFrame = CGRect(
                x: view.bounds.width - horizontalInset - menuWidth,
                y: targetPreviewFrame.maxY + spacing,
                width: menuWidth,
                height: menuHeight,
            )
        case .chatPreview:
            let spacing: CGFloat = 10
            let preferredHeight = view.bounds.height * 0.48
            let previewHeight = min(
                preferredHeight,
                maximumBottom - verticalInset - menuHeight - spacing,
            )
            targetPreviewFrame = CGRect(
                x: horizontalInset,
                y: verticalInset,
                width: availableWidth,
                height: max(220, previewHeight),
            )
            targetMenuFrame = CGRect(
                x: view.bounds.width - horizontalInset - menuWidth,
                y: targetPreviewFrame.maxY + spacing,
                width: menuWidth,
                height: menuHeight,
            )
        case .menuOnly:
            targetPreviewFrame = .zero
            let menuX = min(
                max(horizontalInset, sourceFrame.midX - menuWidth / 2),
                view.bounds.width - horizontalInset - menuWidth,
            )
            targetMenuFrame = CGRect(
                x: menuX,
                y: max(verticalInset, sourceFrame.minY - 4 - menuHeight),
                width: menuWidth,
                height: menuHeight,
            )
        }

        if presentationStyle == .message {
            previewContainer.bounds = CGRect(origin: .zero, size: messageContentSize)
            if hasAnimatedIn {
                previewContainer.center = CGPoint(x: targetPreviewFrame.midX, y: targetPreviewFrame.midY)
                previewContainer.transform = CGAffineTransform(
                    scaleX: targetMessageScale,
                    y: targetMessageScale,
                )
            } else {
                previewContainer.center = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
                previewContainer.transform = CGAffineTransform(
                    scaleX: sourceFrame.width / max(1, messageContentSize.width),
                    y: sourceFrame.height / max(1, messageContentSize.height),
                )
            }
        } else if presentationStyle == .avatar {
            previewContainer.bounds = CGRect(origin: .zero, size: targetPreviewFrame.size)
            if hasAnimatedIn {
                previewContainer.center = CGPoint(x: targetPreviewFrame.midX, y: targetPreviewFrame.midY)
                previewContainer.transform = .identity
            } else {
                previewContainer.center = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
                previewContainer.transform = CGAffineTransform(
                    scaleX: sourceFrame.width / max(1, targetPreviewFrame.width),
                    y: sourceFrame.height / max(1, targetPreviewFrame.height),
                )
                previewView?.layer.cornerRadius = targetPreviewFrame.width / 2
            }
        } else if presentationStyle == .chatPreview {
            previewContainer.bounds = CGRect(origin: .zero, size: targetPreviewFrame.size)
            if hasAnimatedIn {
                previewContainer.center = CGPoint(x: targetPreviewFrame.midX, y: targetPreviewFrame.midY)
                previewContainer.transform = .identity
            } else {
                previewContainer.center = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
                previewContainer.transform = CGAffineTransform(
                    scaleX: sourceFrame.width / max(1, targetPreviewFrame.width),
                    y: sourceFrame.height / max(1, targetPreviewFrame.height),
                )
            }
        } else {
            previewContainer.frame =
                if hasAnimatedIn {
                    targetPreviewFrame
                } else {
                    presentationStyle == .menuOnly ? .zero : sourceFrame
                }
        }
        menuEffectView.frame = targetMenuFrame
        previewView?.frame = previewContainer.bounds
        if presentationStyle == .avatar {
            previewView?.layoutIfNeeded()
        }
    }

    private func animateIn() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
        menuEffectView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            if self.presentationStyle != .menuOnly {
                self.backgroundEffectView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            }
            self.dimView.alpha = 1
            if self.presentationStyle != .menuOnly {
                if self.presentationStyle == .message {
                    self.previewContainer.center = CGPoint(
                        x: self.targetPreviewFrame.midX,
                        y: self.targetPreviewFrame.midY,
                    )
                    self.previewContainer.transform = CGAffineTransform(
                        scaleX: self.targetMessageScale,
                        y: self.targetMessageScale,
                    )
                } else if self.presentationStyle == .avatar {
                    self.previewContainer.center = CGPoint(
                        x: self.targetPreviewFrame.midX,
                        y: self.targetPreviewFrame.midY,
                    )
                    self.previewContainer.transform = .identity
                } else if self.presentationStyle == .chatPreview {
                    self.previewContainer.center = CGPoint(
                        x: self.targetPreviewFrame.midX,
                        y: self.targetPreviewFrame.midY,
                    )
                    self.previewContainer.transform = .identity
                } else {
                    self.previewContainer.frame = self.targetPreviewFrame
                }
                if self.presentationStyle == .avatar {
                    self.previewView?.layer.cornerRadius = 28
                    self.previewView?.layer.cornerCurve = .continuous
                }
            }
            self.menuEffectView.alpha = 1
            self.menuEffectView.transform = .identity
        }
    }

    private func dismissMenu(completion: (() -> Void)? = nil) {
        guard !isDismissing else { return }
        isDismissing = true
        let returnFrame = sourceFrameAtBaseTransform()
        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState],
        ) {
            self.backgroundEffectView.effect = nil
            self.dimView.alpha = 0
            if self.presentationStyle != .menuOnly {
                if self.presentationStyle == .message {
                    self.previewContainer.center = CGPoint(x: returnFrame.midX, y: returnFrame.midY)
                    self.previewContainer.transform = CGAffineTransform(
                        scaleX: returnFrame.width / max(1, self.messageContentSize.width),
                        y: returnFrame.height / max(1, self.messageContentSize.height),
                    )
                } else if self.presentationStyle == .avatar {
                    self.previewContainer.center = CGPoint(x: returnFrame.midX, y: returnFrame.midY)
                    self.previewContainer.transform = CGAffineTransform(
                        scaleX: returnFrame.width / max(1, self.targetPreviewFrame.width),
                        y: returnFrame.height / max(1, self.targetPreviewFrame.height),
                    )
                } else if self.presentationStyle == .chatPreview {
                    self.previewContainer.center = CGPoint(x: returnFrame.midX, y: returnFrame.midY)
                    self.previewContainer.transform = CGAffineTransform(
                        scaleX: returnFrame.width / max(1, self.targetPreviewFrame.width),
                        y: returnFrame.height / max(1, self.targetPreviewFrame.height),
                    )
                } else {
                    self.previewContainer.frame = returnFrame
                }
                self.previewView?.layer.cornerRadius = self.presentationStyle == .avatar
                    ? self.targetPreviewFrame.width / 2
                    : self.originalContentCornerRadius
            }
            self.menuEffectView.alpha = 0
            self.menuEffectView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        } completion: { _ in
            self.sourceView?.transform = self.sourceTransform
            if let previewView = self.previewView, let extractedSource = self.extractedSource {
                extractedSource.putBackContextMenuContent(previewView)
            }
            self.previewController?.willMove(toParent: nil)
            self.previewController?.view.removeFromSuperview()
            self.previewController?.removeFromParent()
            self.sourceView?.alpha = 1
            self.beginAppearanceTransition(false, animated: false)
            self.view.removeFromSuperview()
            self.endAppearanceTransition()
            self.presentationHostView = nil
            Self.activeController = nil
            completion?()
        }
    }

    private func sourceFrameAtBaseTransform() -> CGRect {
        guard let sourceView else { return sourceFrame }
        let currentTransform = sourceView.transform
        var result = sourceFrame
        UIView.performWithoutAnimation {
            sourceView.transform = sourceTransform
            result = view.convert(sourceView.convert(sourceView.bounds, to: nil), from: nil)
            sourceView.transform = currentTransform
        }
        return result
    }

    @objc private func dismissMenu() {
        dismissMenu(completion: nil)
    }

    @objc private func actionPressed(_ sender: TelegramContextMenuActionButton) {
        perform(sender)
    }

    private func perform(_ button: TelegramContextMenuActionButton) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        trackingGesture?.removeTarget(self, action: #selector(trackingGestureChanged(_:)))
        let handler = button.menuAction.handler
        dismissMenu(completion: handler)
    }

    @objc private func trackingGestureChanged(_ gesture: UIGestureRecognizer) {
        switch gesture.state {
        case .changed:
            updateTrackedButton(at: gesture.location(in: view))
        case .ended:
            if let trackedButton {
                perform(trackedButton)
            }
        case .cancelled, .failed:
            updateTrackedButton(at: nil)
        default:
            break
        }
    }

    @objc private func menuSelectionGestureChanged(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            updateTrackedButton(at: gesture.location(in: view))
        case .ended:
            if let trackedButton {
                perform(trackedButton)
            } else {
                updateTrackedButton(at: nil)
            }
        case .cancelled, .failed:
            updateTrackedButton(at: nil)
        default:
            break
        }
    }

    private func updateTrackedButton(at location: CGPoint?) {
        let button = location.flatMap { point in
            actionButtons.first { $0.convert($0.bounds, to: view).contains(point) }
        }
        guard trackedButton !== button else { return }
        let previousButton = trackedButton
        trackedButton = button
        updateSelectionHighlight(from: previousButton, to: button)
        if button != nil, previousButton != nil {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func updateSelectionHighlight(
        from previousButton: TelegramContextMenuActionButton?,
        to button: TelegramContextMenuActionButton?,
    ) {
        menuEffectView.layoutIfNeeded()
        guard let button else {
            UIView.animate(
                withDuration: 0.08,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            ) {
                self.selectionHighlightView.alpha = 0
            }
            return
        }

        let targetFrame = button.convert(button.bounds.insetBy(dx: 6, dy: 4), to: menuEffectView.contentView)
        let crossesSectionDivider: Bool = {
            guard let previousButton,
                  let previousIndex = actionButtons.firstIndex(where: { $0 === previousButton }),
                  let nextIndex = actionButtons.firstIndex(where: { $0 === button })
            else { return false }
            let lower = min(previousIndex, nextIndex)
            let upper = max(previousIndex, nextIndex)
            guard lower != upper else { return false }
            return actions[(lower + 1)...upper].contains(where: \.startsNewSection)
        }()

        if previousButton == nil || selectionHighlightView.alpha < 0.01 || crossesSectionDivider {
            let placeAndReveal = {
                self.selectionHighlightView.frame = targetFrame
                UIView.animate(
                    withDuration: 0.08,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                ) {
                    self.selectionHighlightView.alpha = 1
                }
            }
            if crossesSectionDivider, selectionHighlightView.alpha > 0.01 {
                UIView.animate(
                    withDuration: 0.06,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                ) {
                    self.selectionHighlightView.alpha = 0
                } completion: { _ in
                    placeAndReveal()
                }
            } else {
                placeAndReveal()
            }
        } else {
            UIView.animate(
                withDuration: 0.1,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
            ) {
                self.selectionHighlightView.frame = targetFrame
                self.selectionHighlightView.alpha = 1
            }
        }
    }
}

// MARK: - TelegramContextMenuSectionDivider

private final class TelegramContextMenuSectionDivider: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: TelegramContextMenuLayout.sectionSeparatorHeight).isActive = true

        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.backgroundColor = UIColor.separator.withAlphaComponent(0.62)
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - TelegramContextMenuActionButton

private final class TelegramContextMenuActionButton: UIControl {
    // MARK: Internal

    let menuAction: TelegramContextMenuAction

    // MARK: Private

    private let titleLabel = UILabel()
    private let iconView = UIImageView()

    init(action: TelegramContextMenuAction) {
        self.menuAction = action
        super.init(frame: .zero)

        let color: UIColor = action.isDestructive ? .systemRed : .label
        titleLabel.text = action.title
        titleLabel.textColor = color
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        iconView.image = action.image
        iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
        accessibilityLabel = action.title
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - TelegramContextGestureRecognizer

/// Telegram's context gesture starts showing press progress before activation and
/// yields immediately to a real drag. This keeps scrolling responsive while making
/// a stationary hold feel immediate.
final class TelegramContextGestureRecognizer: UIGestureRecognizer {
    // MARK: Internal

    var onPressingChanged: ((Bool) -> Void)?
    var feedbackDelay: TimeInterval = 0.1
    var activationDelay: TimeInterval = 0.26
    var allowableMovement: CGFloat = 12

    // MARK: Private

    private var feedbackWorkItem: DispatchWorkItem?
    private var activationWorkItem: DispatchWorkItem?
    private var initialLocation: CGPoint?
    private var feedbackStarted = false
    private var activated = false

    override func reset() {
        super.reset()
        feedbackWorkItem?.cancel()
        activationWorkItem?.cancel()
        feedbackWorkItem = nil
        activationWorkItem = nil
        initialLocation = nil
        feedbackStarted = false
        activated = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard touches.count == 1, let touch = touches.first, let view else {
            state = .failed
            return
        }
        initialLocation = touch.location(in: view)

        let feedback = DispatchWorkItem { [weak self] in
            guard let self, state == .possible else { return }
            feedbackStarted = true
            onPressingChanged?(true)
        }
        feedbackWorkItem = feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + feedbackDelay, execute: feedback)

        let activation = DispatchWorkItem { [weak self] in
            guard let self, state == .possible else { return }
            if !feedbackStarted {
                feedbackStarted = true
                onPressingChanged?(true)
            }
            activated = true
            cancelCompetingParentGestures()
            state = .began
        }
        activationWorkItem = activation
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay, execute: activation)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first, let view, let initialLocation else { return }
        let location = touch.location(in: view)
        if state == .possible,
           hypot(location.x - initialLocation.x, location.y - initialLocation.y) > allowableMovement
        {
            cancelBeforeActivation()
        } else if state == .began || state == .changed {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        feedbackWorkItem?.cancel()
        activationWorkItem?.cancel()
        if state == .began || state == .changed {
            state = .ended
        } else {
            cancelBeforeActivation()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        feedbackWorkItem?.cancel()
        activationWorkItem?.cancel()
        if state == .began || state == .changed {
            state = .cancelled
        } else {
            cancelBeforeActivation()
        }
    }

    private func cancelCompetingParentGestures() {
        var ancestor = view
        while let currentView = ancestor {
            for gesture in currentView.gestureRecognizers ?? [] where gesture !== self {
                switch gesture.state {
                case .began, .changed, .possible:
                    gesture.isEnabled = false
                    gesture.isEnabled = true
                default:
                    break
                }
            }
            ancestor = currentView.superview
        }
    }

    private func cancelBeforeActivation() {
        feedbackWorkItem?.cancel()
        activationWorkItem?.cancel()
        if feedbackStarted, !activated {
            feedbackStarted = false
            onPressingChanged?(false)
        }
        state = .failed
    }
}

extension UIView {
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return nil
    }
}

// TelegramContextMenu.swift

import UIKit

// MARK: - TelegramContextMenuLayout

private enum TelegramContextMenuLayout {
    static let actionFontSize = CGFloat(17)
    static let actionVerticalInset = CGFloat(11)
    static let actionHeight = ceil(UIFont.systemFont(ofSize: actionFontSize).lineHeight)
        + actionVerticalInset * 2
    static let contentSideInset = CGFloat(18)
    static let contentVerticalInset = CGFloat(10)
    static let iconSize = CGFloat(24)
    static let iconSlotWidth = CGFloat(32)
    static let iconSideInset = CGFloat(20)
    static let iconSpacing = CGFloat(8)
    static let minimumMenuWidth = CGFloat(220)
    static let maximumMenuWidth = CGFloat(240)
    static let sectionSeparatorHeight = CGFloat(20)
    static let menuCornerRadius = CGFloat(30)
    /// The shared highlight is inset like the system's largeItemContentShape: 10 pt on each side, with the
    /// menu radius less that inset, capped at half the row height.
    static let highlightInset = CGFloat(10)
}

// MARK: - TelegramContextMenuAction

struct TelegramContextMenuAction {
    // MARK: Internal

    let title: String
    let image: UIImage?
    let isDestructive: Bool
    var startsNewSection: Bool
    let children: [TelegramContextMenuAction]
    let handler: () -> Void

    init(
        title: String,
        image: UIImage? = nil,
        isDestructive: Bool = false,
        startsNewSection: Bool = false,
        children: [TelegramContextMenuAction] = [],
        handler: @escaping () -> Void = {},
    ) {
        self.title = title
        self.image = image
        self.isDestructive = isDestructive
        self.startsNewSection = startsNewSection
        self.children = children
        self.handler = handler
    }
}

// MARK: - TelegramContextQuoteSelection

struct TelegramContextQuoteSelection {
    let textView: MessageTextContentView
    let handler: (NSRange) -> Void
}

// MARK: - TelegramContextMenuPresentationStyle

enum TelegramContextMenuPresentationStyle: Equatable {
    case message
    case avatar
    case chatPreview
    case menuOnly
    /// A button's menu without a preview. It opens in the button's place and morphs out of it with UIKit's liquid
    /// morph (Telegram 58ce7d6688, f44a25a649); without the runtime, with Reduce Motion or when the button has left
    /// the window, it opens next to the button with the Telegram spring.
    case sourceMorph

    var showsPreview: Bool {
        switch self {
        case .avatar, .chatPreview, .message: true
        case .menuOnly, .sourceMorph: false
        }
    }
}

// MARK: - TelegramContextMenuKeyboardHost

private enum TelegramContextMenuKeyboardHost {
    // MARK: Internal

    static func visibleKeyboardWindow(for sourceWindow: UIWindow, sourceView: UIView?) -> UIWindow? {
        guard let owner = sourceView?.nearestViewController?.viewIfLoaded,
              owner.keyboardLayoutGuide.layoutFrame.height > owner.safeAreaInsets.bottom + 1
        else { return nil }
        if let scene = sourceWindow.windowScene,
           let keyboardWindow = remoteKeyboardWindow(in: scene),
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

    /// The keyboard lives in a `UIRemoteKeyboardWindow` of an internal keyboard scene, so it is absent from
    /// `UIWindowScene.windows`; Telegram reaches it through the window scene's keyboard scene delegate.
    /// `+[UIRemoteKeyboardWindow remoteKeyboardWindowForScreen:create:]` traps on iOS 27 in a binary linked
    /// against the iOS 27 SDK.
    private static func remoteKeyboardWindow(in scene: UIWindowScene) -> UIWindow? {
        let delegateSelector = NSSelectorFromString("keyboardSceneDelegate")
        let windowSelector = NSSelectorFromString("keyboardWindow")
        guard scene.responds(to: delegateSelector),
              let keyboardSceneDelegate = scene.perform(delegateSelector)?.takeUnretainedValue() as? NSObject,
              keyboardSceneDelegate.responds(to: windowSelector)
        else { return nil }
        // `nil` until the scene has a keyboard, and whenever the keyboard UI is hosted out of process.
        return keyboardSceneDelegate.perform(windowSelector)?.takeUnretainedValue() as? UIWindow
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

    #if DEBUG
        func probeTakeContextMenuContent() -> UIView? { takeContextMenuContent() }
        func probePutBackContextMenuContent(_ content: UIView) { putBackContextMenuContent(content) }
    #endif

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
    var isPresentingTelegramContextMenu: Bool {
        TelegramContextMenuController.activeController?.owner === self
    }

    /// A `.menuOnly` menu sits `menuSpacing` above `menuAnchorView`, or above the source when there is none.
    /// A `ContextMenuPressGestureRecognizer` passed as `gesture` hands its grown source over to the menu and
    /// keeps driving it: the same finger scrubs the actions and pans the preview.
    @discardableResult func presentTelegramContextMenu(
        sourceView: UIView,
        actions: [TelegramContextMenuAction],
        tracking gesture: UIGestureRecognizer? = nil,
        presentationStyle: TelegramContextMenuPresentationStyle = .message,
        previewController: UIViewController? = nil,
        menuAnchorView: UIView? = nil,
        menuSpacing: CGFloat = 4,
        reactionsProvider: TelegramContextReactionsProvider? = nil,
        quoteSelection: TelegramContextQuoteSelection? = nil,
        onDismiss: (() -> Void)? = nil,
    ) -> Bool {
        // A menu that is still closing (a liquid morph settles for up to 1.6 s) does not block the next one.
        guard !actions.isEmpty,
              TelegramContextMenuController.activeController?.isOpen != true,
              let sourceWindow = sourceView.window
        else { return false }
        let pressGesture = gesture as? ContextMenuPressGestureRecognizer
        let sourceTransform: CGAffineTransform?
        if !presentationStyle.showsPreview {
            // Without a preview the source stays in place, so it settles back instead of being taken over.
            sourceTransform = pressGesture?.pressBaseTransform(of: sourceView)
            pressGesture?.releasePress()
        } else {
            sourceTransform = pressGesture?.handOffPress(of: sourceView)
        }
        let controller = TelegramContextMenuController(
            sourceView: sourceView,
            actions: actions,
            trackingGesture: gesture,
            sourceTransform: sourceTransform ?? sourceView.transform,
            presentationStyle: presentationStyle,
            previewController: previewController,
            menuAnchorView: menuAnchorView,
            menuSpacing: menuSpacing,
            reactionsProvider: reactionsProvider,
            quoteSelection: quoteSelection,
            owner: self, onDismiss: onDismiss,
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        controller.show(in: sourceWindow)
        return true
    }
}

// MARK: - TelegramContextMenuRootView

private final class TelegramContextMenuRootView: UIView {
    override var canBecomeFirstResponder: Bool { true }

    /// Also reached while the quote text inside the menu holds focus.
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapePressed))]
    }

    var onDetached: (() -> Void)?
    var onEscape: (() -> Void)?

    private var wasAttached = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { wasAttached = true }
        else if wasAttached { onDetached?() }
    }

    override func accessibilityPerformEscape() -> Bool {
        onEscape?()
        return onEscape != nil
    }

    @objc private func escapePressed() {
        onEscape?()
    }
}

// MARK: - TelegramContextMenuDismissView

/// The dimmed background. Touches go to the menu's touch session; VoiceOver can still dismiss through it.
private final class TelegramContextMenuDismissView: UIView {
    var onActivate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return onActivate != nil
    }
}

// MARK: - TelegramContextMenuPassthroughView

/// Carries the preview pan offset, so the native tracking spring moves it independently of the preview's own
/// transition. Touches outside the preview fall through.
private final class TelegramContextMenuPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}

// MARK: - TelegramContextMenuFirstResponder

@MainActor private enum TelegramContextMenuFirstResponder {
    fileprivate weak static var found: UIResponder?

    static func current() -> UIResponder? {
        found = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.reportTelegramContextMenuFirstResponder),
            to: nil,
            from: nil,
            for: nil,
        )
        let responder = found
        found = nil
        // Without a focused responder the action reaches the window or the application instead.
        return responder?.isFirstResponder == true ? responder : nil
    }
}

private extension UIResponder {
    @objc func reportTelegramContextMenuFirstResponder() {
        TelegramContextMenuFirstResponder.found = self
    }
}

private extension UIViewController {
    /// Escape while a context menu is open and focus stays outside it, such as in the composer.
    @objc func dismissTelegramContextMenuWithEscape() {
        TelegramContextMenuController.activeController?.dismissWithEscape()
    }
}

// MARK: - TelegramContextMenuController

private final class TelegramContextMenuController: UIViewController {
    // MARK: Fileprivate

    fileprivate static var activeController: TelegramContextMenuController?

    /// Menus replaced by a newer one while they still close; each stays alive until its close completes.
    private static var closingControllers = [TelegramContextMenuController]()

    /// End of the visible close motion of a liquid morph, recorded at about 0.7 s (Telegram 7c2cfd6a1f).
    private static let liquidMorphCloseMotionDuration: TimeInterval = 0.7

    fileprivate weak var owner: UIViewController?

    private var onDismiss: (() -> Void)?
    private var dismissCompletion: (() -> Void)?
    private var didFinishDismissal = false

    // MARK: Private

    private weak var sourceView: UIView?
    private weak var menuAnchorView: UIView?
    private let menuSpacing: CGFloat
    private let sourceTransform: CGAffineTransform
    private let presentationStyle: TelegramContextMenuPresentationStyle
    private let previewController: UIViewController?
    private let quoteSelection: TelegramContextQuoteSelection?
    private var selectableTextViews = [MessageTextContentView]()
    private let reactionsProvider: TelegramContextReactionsProvider?
    private let reactionStrip = TelegramReactionStripView()
    private var reactionTask: Task<Void, Never>?
    private weak var trackingGesture: UIGestureRecognizer?
    private var actions: [TelegramContextMenuAction]
    private var parentActions = [[TelegramContextMenuAction]]()
    private let backgroundEffectView = UIVisualEffectView(effect: nil)
    private let dimView = TelegramContextMenuDismissView()
    private let previewPanView = TelegramContextMenuPassthroughView()
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
    private var hasAnimatedIn = false
    private var isDismissing = false
    private var isPerformingAction = false
    /// One touch at a time, as in the system menu: the finger that opened the menu or a later touch on it.
    private var touchSession: ContextMenuTouchSession?
    private var touchSessionIsInitiating = false
    private var touchPoint = CGPoint.zero
    private var panOffset = CGPoint.zero
    private var selectionDelayWork: DispatchWorkItem?
    private var highlightedIndex: Int?
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let panBehavior = ContextMenuNativeAnimation.makePanBehavior()
    private let highlightFrameBehavior = ContextMenuNativeAnimation.makeBehavior(dampingRatio: 1, response: 0.12)
    private let highlightAlphaBehavior = ContextMenuNativeAnimation.makeBehavior(dampingRatio: 1, response: 0.3)
    private weak var escapeCommandOwner: UIViewController?
    private lazy var touchRecognizer = ContextMenuTouchRecognizer(
        target: self,
        action: #selector(menuTouchChanged(_:)),
    )
    private lazy var escapeCommand: UIKeyCommand = {
        let command = UIKeyCommand(
            input: UIKeyCommand.inputEscape,
            modifierFlags: [],
            action: #selector(UIViewController.dismissTelegramContextMenuWithEscape),
        )
        command.wantsPriorityOverSystemBehavior = true
        return command
    }()

    /// Decided when the menu opens and kept for its lifetime, like Telegram's `hasActiveLiquidMorph`.
    private lazy var usesLiquidMorph = presentationStyle == .sourceMorph
        && ContextMenuLiquidMorph.isSupported
        && !UIAccessibility.isReduceMotionEnabled
    private var liquidMorph: ContextMenuLiquidMorph?
    private var morphSourcePreview: UITargetedPreview?
    private var isMorphPresenting = false
    /// Hides the button for the menu's lifetime; UIKit's own suppression ends when the opening morph completes.
    private var sourceVisibilityAssertion: AnyObject?
    /// Keeps the closed menu hidden after UIKit's morph cleanup puts it back on screen fully open.
    private var menuVisibilityAssertion: AnyObject?

    fileprivate var isOpen: Bool { !isDismissing }

    /// Model frame of the preview including the pan, like the system's platterView.frame checks.
    private var previewFrame: CGRect {
        presentationStyle.showsPreview ? previewContainer.convert(previewContainer.bounds, to: view) : .zero
    }

    init(
        sourceView: UIView,
        actions: [TelegramContextMenuAction],
        trackingGesture: UIGestureRecognizer?,
        sourceTransform: CGAffineTransform,
        presentationStyle: TelegramContextMenuPresentationStyle,
        previewController: UIViewController?,
        menuAnchorView: UIView?,
        menuSpacing: CGFloat,
        reactionsProvider: TelegramContextReactionsProvider?,
        quoteSelection: TelegramContextQuoteSelection?,
        owner: UIViewController,
        onDismiss: (() -> Void)?,
    ) {
        self.sourceView = sourceView
        self.menuAnchorView = menuAnchorView
        self.menuSpacing = menuSpacing
        self.sourceTransform = sourceTransform
        self.actions = actions
        self.trackingGesture = trackingGesture
        self.presentationStyle = presentationStyle
        self.previewController = previewController
        self.reactionsProvider = reactionsProvider
        self.quoteSelection = quoteSelection
        self.owner = owner
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        trackingGesture?.addTarget(self, action: #selector(trackingGestureChanged(_:)))
        NotificationCenter.default.addObserver(
            self, selector: #selector(dismissMenu), name: UIApplication.didEnterBackgroundNotification, object: nil,
        )
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        reactionTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        trackingGesture?.removeTarget(self, action: #selector(trackingGestureChanged(_:)))
    }

    // MARK: Internal

    override func loadView() {
        let root = TelegramContextMenuRootView()
        root.onDetached = { [weak self] in self?.finishDismissal() }
        root.onEscape = { [weak self] in self?.dismissWithEscape() }
        root.accessibilityViewIsModal = true
        view = root
    }

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
        let hostView = TelegramContextMenuKeyboardHost
            .visibleKeyboardWindow(for: sourceWindow, sourceView: sourceView) ?? sourceWindow
        #if DEBUG
        TelegramQuoteSelectionDiagnostics
            .record(
                "host=\(NSStringFromClass(type(of: hostView))) key=\(hostView.isKeyWindow)",
            )
        #endif
        presentationHostView = hostView
        if let previous = Self.activeController, previous !== self {
            Self.closingControllers.append(previous)
        }
        Self.activeController = self
        loadViewIfNeeded()
        // A dark gallery keeps a dark menu even when the window is light.
        view.overrideUserInterfaceStyle = sourceView?.traitCollection.userInterfaceStyle ?? .unspecified
        view.frame = hostView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Added last above the app/keyboard content. Leave the normal layer
        // order so UIKit can present the selected text's edit menu above us.
        hostView.addSubview(view)
        beginAppearanceTransition(true, animated: false)
        endAppearanceTransition()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        beginInitiatingTouchSession()
        installEscape()
        animateIn()
        UIAccessibility.post(notification: .screenChanged, argument: actionButtons.first)
    }

    fileprivate func dismissWithEscape() {
        dismissMenu(completion: nil)
    }

    private func configureViews() {
        view.backgroundColor = .clear

        backgroundEffectView.frame = view.bounds
        backgroundEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundEffectView)

        dimView.frame = view.bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimView.backgroundColor = presentationStyle.showsPreview
            ? UIColor.black.withAlphaComponent(0.18)
            : .clear
        dimView.alpha = 0
        dimView.isAccessibilityElement = true
        dimView.accessibilityTraits = .button
        dimView.accessibilityLabel = L10n.telegram("Common.Close")
        dimView.onActivate = { [weak self] in self?.dismissMenu(completion: nil) }
        view.addSubview(dimView)

        previewPanView.frame = view.bounds
        previewPanView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(previewPanView)

        previewContainer.layer.shadowColor = UIColor.black.cgColor
        previewContainer.layer.shadowOpacity = 0.24
        previewContainer.layer.shadowRadius = 24
        previewContainer.layer.shadowOffset = CGSize(width: 0, height: 10)
        previewContainer.clipsToBounds = presentationStyle == .chatPreview
        previewContainer.layer.cornerCurve = .continuous
        previewContainer.layer.cornerRadius = presentationStyle == .chatPreview ? 24 : 0
        previewPanView.addSubview(previewContainer)

        if let previewController {
            addChild(previewController)
            previewController.view.frame = previewContainer.bounds
            previewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            previewContainer.addSubview(previewController.view)
            previewController.didMove(toParent: self)
            previewView = previewController.view
            sourceView?.alpha = 0
        } else if presentationStyle.showsPreview, let sourceView {
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

        if let quoteSelection, presentationStyle == .message {
            let textView = quoteSelection.textView
            let handler = quoteSelection.handler
            textView.setContextQuoteAction { [weak self] range in
                self?.dismissMenu { handler(range) }
            }
            selectableTextViews = [textView]
        }

        menuEffectView.layer.cornerRadius = TelegramContextMenuLayout.menuCornerRadius
        menuEffectView.layer.cornerCurve = .continuous
        menuEffectView
            .cornerConfiguration = .corners(radius: .fixed(Double(TelegramContextMenuLayout.menuCornerRadius)))
        menuEffectView.clipsToBounds = true
        menuEffectView.alpha = 0
        view.addSubview(menuEffectView)

        selectionHighlightView.backgroundColor = .contextMenuSelectionHighlight
        selectionHighlightView.layer.cornerCurve = .continuous
        selectionHighlightView.alpha = 0
        selectionHighlightView.isUserInteractionEnabled = false
        menuEffectView.contentView.addSubview(selectionHighlightView)

        menuStack.axis = .vertical
        menuStack.alignment = .fill
        menuStack.isLayoutMarginsRelativeArrangement = true
        menuStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: TelegramContextMenuLayout.contentVerticalInset,
            leading: 0,
            bottom: TelegramContextMenuLayout.contentVerticalInset,
            trailing: 0,
        )
        menuStack.translatesAutoresizingMaskIntoConstraints = false
        menuEffectView.contentView.addSubview(menuStack)
        NSLayoutConstraint.activate([
            menuStack.topAnchor.constraint(equalTo: menuEffectView.contentView.topAnchor),
            menuStack.leadingAnchor.constraint(equalTo: menuEffectView.contentView.leadingAnchor),
            menuStack.trailingAnchor.constraint(equalTo: menuEffectView.contentView.trailingAnchor),
            menuStack.bottomAnchor.constraint(equalTo: menuEffectView.contentView.bottomAnchor),
        ])

        view.addGestureRecognizer(touchRecognizer)

        rebuildActions()
        reactionStrip.isHidden = reactionsProvider == nil
        reactionStrip.alpha = 0
        view.addSubview(reactionStrip)
        reactionStrip.onSelect = { [weak self] reaction in
            guard let self, !isPerformingAction else { return }
            isPerformingAction = true
            dismissMenu(completion: reaction.handler)
        }
        if let reactionsProvider {
            reactionTask = Task { [weak self] in
                let reactions = await reactionsProvider()
                guard let self, !Task.isCancelled, !isDismissing else { return }
                reactionStrip.configure(reactions)
                reactionStrip.isHidden = reactions.isEmpty
                UIView.performWithoutAnimation { self.layoutPreviewAndMenu() }
            }
        }
    }

    private func rebuildActions() {
        touchSession?.highlighted = nil
        setHighlight(nil)
        actionButtons.removeAll()
        for child in menuStack.arrangedSubviews {
            menuStack.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        for (index, action) in actions.enumerated() {
            if index > 0, action.startsNewSection {
                menuStack.addArrangedSubview(TelegramContextMenuSectionDivider())
            }
            let button = TelegramContextMenuActionButton(action: action)
            button.onActivate = { [weak self, weak button] in
                guard let self, let button else { return }
                perform(button)
            }
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
        let menuHeight = TelegramContextMenuLayout.contentVerticalInset * 2
            + CGFloat(actions.count) * TelegramContextMenuLayout.actionHeight
            + separatorHeight
        let menuWidth = menuWidth(availableWidth: availableWidth)
        let bottomInset = max(view.safeAreaInsets.bottom, CGFloat(12))
        let maximumBottom = view.bounds.height - bottomInset

        switch presentationStyle {
        case .message:
            let spacing: CGFloat = 10
            let reactionHeight: CGFloat = reactionStrip.isHidden ? 0 : 56
            let baseSourceFrame = sourceFrameAtBaseTransform()
            let maximumPreviewHeight = max(44, maximumBottom - verticalInset - reactionHeight - menuHeight - spacing)
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
            let previewY = min(max(verticalInset + reactionHeight, baseSourceFrame.minY), maximumPreviewY)
            targetPreviewFrame = CGRect(x: previewX, y: previewY, width: previewWidth, height: previewHeight)
            let alignedMenuX = baseSourceFrame.midX > view.bounds.midX
                ? targetPreviewFrame.maxX - menuWidth
                : targetPreviewFrame.minX
            let menuX = min(max(horizontalInset, alignedMenuX), view.bounds.width - horizontalInset - menuWidth)
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
            let anchorFrame = menuAnchorView.map { anchor in
                view.convert(anchor.convert(anchor.bounds, to: nil), from: nil)
            } ?? sourceFrame
            targetMenuFrame = CGRect(
                x: menuX,
                y: max(verticalInset, anchorFrame.minY - menuSpacing - menuHeight),
                width: menuWidth,
                height: menuHeight,
            )
        case .sourceMorph:
            // Telegram f44a25a649: a morphing menu takes the button's place, its top edge on the button's top edge
            // (bottom on bottom for a button in the lower half) and its left or right edge on the button's edge in
            // that half of the screen. Without the morph it opens next to the button.
            targetPreviewFrame = .zero
            let growsDown = sourceFrame.midY < view.bounds.midY
            let alignedX = sourceFrame.midX < view.bounds.midX ? sourceFrame.minX : sourceFrame.maxX - menuWidth
            let proposedY =
                switch (usesLiquidMorph, growsDown) {
                case (true, true): sourceFrame.minY
                case (true, false): sourceFrame.maxY - menuHeight
                case (false, true): sourceFrame.maxY + menuSpacing
                case (false, false): sourceFrame.minY - menuSpacing - menuHeight
                }
            targetMenuFrame = CGRect(
                x: min(max(horizontalInset, alignedX), view.bounds.width - horizontalInset - menuWidth),
                y: min(max(verticalInset, proposedY), max(verticalInset, maximumBottom - menuHeight)),
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
                    presentationStyle.showsPreview ? sourceFrame : .zero
                }
        }
        menuEffectView.frame = targetMenuFrame
        if presentationStyle == .message, !reactionStrip.isHidden {
            let width = min(availableWidth, reactionStrip.preferredWidth)
            let proposedX = targetPreviewFrame.midX > view.bounds.midX
                ? targetPreviewFrame.maxX - width
                : targetPreviewFrame.minX
            reactionStrip.frame = CGRect(
                x: min(max(horizontalInset, proposedX), view.bounds.width - horizontalInset - width),
                y: targetPreviewFrame.minY - 56, width: width, height: 46,
            )
        }
        previewView?.frame = previewContainer.bounds
        if presentationStyle == .avatar {
            previewView?.layoutIfNeeded()
        }
    }

    private func menuWidth(availableWidth: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: TelegramContextMenuLayout.actionFontSize)
        let naturalWidth = actions.reduce(CGFloat.zero) { width, action in
            let titleWidth = ceil((action.title as NSString).size(withAttributes: [.font: font]).width)
            let contentWidth = titleWidth + TelegramContextMenuLayout.contentSideInset * 2
            guard action.image != nil else { return max(width, contentWidth) }
            return max(
                width,
                titleWidth
                    + TelegramContextMenuLayout.contentSideInset
                    + TelegramContextMenuLayout.iconSlotWidth
                    + TelegramContextMenuLayout.iconSideInset
                    + TelegramContextMenuLayout.iconSpacing,
            )
        }
        return min(
            max(naturalWidth, TelegramContextMenuLayout.minimumMenuWidth),
            min(TelegramContextMenuLayout.maximumMenuWidth, availableWidth),
        )
    }

    private func animateIn() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
        if !startLiquidMorphIn() { animateMenuIn() }
        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            if self.presentationStyle.showsPreview {
                self.backgroundEffectView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            }
            self.dimView.alpha = 1
            if self.presentationStyle.showsPreview {
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
            self.reactionStrip.alpha = 1
        }
    }

    /// Telegram's actions animation: the menu springs out of its source, starting at its edge next to the
    /// content and travelling with it, and a menu-only source also centres it on the source.
    private func animateMenuIn() {
        let contentTravelY = presentationStyle.showsPreview ? targetPreviewFrame.midY - sourceFrame.midY : 0
        let offset = menuTransitionOffset(contentTravelY: contentTravelY)
        let layer = menuEffectView.layer
        menuEffectView.alpha = 1
        layer.addTelegramAnimation(keyPath: "opacity", from: 0, to: 1, duration: 0.05, isRemovedOnCompletion: true)
        layer.addTelegramSpring(keyPath: "transform.scale", from: 0.01, to: 1)
        layer.addTelegramSpring(
            keyPath: "position",
            from: NSValue(cgPoint: offset),
            to: NSValue(cgPoint: .zero),
            isAdditive: true,
        )
    }

    private func animateMenuOut(returnFrame: CGRect) {
        let contentTravelY = presentationStyle.showsPreview ? targetPreviewFrame.midY - returnFrame.midY : 0
        let offset = menuTransitionOffset(contentTravelY: contentTravelY)
        let layer = menuEffectView.layer
        let presentation = layer.presentation()
        let scale = (presentation?.value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue ?? 1
        layer.addTelegramAnimation(keyPath: "opacity", from: presentation?.opacity ?? layer.opacity, to: 0)
        layer.addTelegramAnimation(keyPath: "transform.scale", from: scale, to: 0.01)
        layer.addTelegramAnimation(
            keyPath: "position",
            from: NSValue(cgPoint: .zero),
            to: NSValue(cgPoint: offset),
            isAdditive: true,
        )
    }

    private func menuTransitionOffset(contentTravelY: CGFloat) -> CGPoint {
        let contentFrame = presentationStyle.showsPreview ? targetPreviewFrame : sourceFrame
        let direction: CGFloat = contentFrame.minY < targetMenuFrame.minY ? -1 : 1
        let spacing: CGFloat = presentationStyle.showsPreview ? 10 : menuSpacing
        return CGPoint(
            x: presentationStyle.showsPreview ? 0 : sourceFrame.midX - targetMenuFrame.midX,
            y: -contentTravelY + direction * targetMenuFrame.height / 2 - spacing,
        )
    }

    // MARK: Liquid morph

    private func makeMenuPreview() -> UITargetedPreview {
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(
            roundedRect: menuEffectView.bounds,
            cornerRadius: TelegramContextMenuLayout.menuCornerRadius,
        )
        return UITargetedPreview(view: menuEffectView, parameters: parameters)
    }

    /// Telegram 58ce7d6688 `LensTransitionContainer.animateIn`: the button morphs into the menu, and an assertion
    /// keeps the button hidden until the menu closes.
    private func startLiquidMorphIn() -> Bool {
        guard usesLiquidMorph, let sourceView, sourceView.window != nil, view.window != nil,
              !sourceView.bounds.isEmpty
        else { return false }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        // A plain icon button has no shape of its own; its capsule hit area is the shape that morphs.
        let path = UIBezierPath(
            roundedRect: sourceView.bounds,
            cornerRadius: min(sourceView.bounds.width, sourceView.bounds.height) / 2,
        )
        parameters.visiblePath = path
        parameters.shadowPath = path
        guard let source = ContextMenuLiquidMorph.sourcePreview(for: sourceView, parameters: parameters) else {
            return false
        }
        menuEffectView.alpha = 1
        let morph = ContextMenuLiquidMorph()
        let attachment = source.target.container.convert(source.target.center, to: view)
        isMorphPresenting = true
        let started = morph.animate(
            from: source,
            to: makeMenuPreview(),
            attachment: attachment,
            in: view,
            sourceIdentity: sourceView,
            alongsideAnimations: { [weak self] in
                self?.sourceVisibilityAssertion = ContextMenuLiquidMorph.sourceVisibilityAssertion(for: source.view)
            },
            completion: { [weak self] in
                // A close that took over this opening owns the menu from then on.
                self?.isMorphPresenting = false
            },
        )
        guard started else {
            isMorphPresenting = false
            menuEffectView.alpha = 0
            return false
        }
        liquidMorph = morph
        morphSourcePreview = source
        return true
    }

    /// Telegram 11a469d1f8 and 7c2cfd6a1f `LensTransitionContainer.animateOut`: the menu morphs back into the
    /// button's current position, taking over an opening that is still running; an assertion keeps the closed
    /// menu hidden through UIKit's cleanup. Returns false when the button has left the window.
    private func startLiquidMorphOut() -> Bool {
        let interruptsPresentation = isMorphPresenting
        isMorphPresenting = false
        guard let morph = liquidMorph, let sourceView, sourceView.window != nil, menuEffectView.window != nil,
              let source = morphSourcePreview,
              let destination = ContextMenuLiquidMorph.sourcePreview(
                  for: source.view,
                  parameters: source.parameters,
                  usePresentationTransform: true,
              )
        else { return false }
        let menu = makeMenuPreview()
        let attachment = destination.target.container.convert(destination.target.center, to: view)
        return morph.animate(
            from: menu,
            to: destination,
            attachment: attachment,
            in: view,
            sourceIdentity: sourceView,
            interruptingCurrent: interruptsPresentation,
            alongsideAnimations: { [weak self] in
                self?.menuVisibilityAssertion = ContextMenuLiquidMorph.sourceVisibilityAssertion(for: menu.view)
            },
            completion: { [weak self] in self?.finishDismissal() },
        )
    }

    private func dismissMenu(completion: (() -> Void)? = nil) {
        guard !isDismissing else { return }
        finishTracking()
        isDismissing = true
        removeEscape()
        selectableTextViews.forEach { $0.setContextQuoteAction(nil) }
        selectableTextViews.removeAll()
        reactionTask?.cancel()
        dismissCompletion = completion
        if liquidMorph != nil {
            if startLiquidMorphOut() {
                // UIKit reports the close only once every spring settles, about 1.6 s after it starts; the motion
                // ends at about 0.7 s (Telegram 7c2cfd6a1f). Touches pass through and the action runs then.
                view.isUserInteractionEnabled = false
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.liquidMorphCloseMotionDuration) { [weak self] in
                    self?.performDismissCompletion()
                }
                return
            }
            // The button left the window: fade the menu out at once.
            UIView.animate(withDuration: 0.15) {
                self.menuEffectView.alpha = 0
            } completion: { _ in self.finishDismissal() }
            return
        }
        let returnFrame = sourceFrameAtBaseTransform()
        animateMenuOut(returnFrame: returnFrame)
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
            self.reactionStrip.alpha = 0
        } completion: { _ in self.finishDismissal() }
    }

    private func finishDismissal() {
        guard !didFinishDismissal else { return }
        didFinishDismissal = true
        isDismissing = true
        removeEscape()
        // The menu goes transparent before its visibility assertion ends, so UIKit's cleanup never shows it open.
        menuEffectView.alpha = 0
        menuVisibilityAssertion = nil
        sourceVisibilityAssertion = nil
        liquidMorph = nil
        morphSourcePreview = nil
        sourceView?.transform = sourceTransform
        reactionStrip.prepareForReuse()
        if let previewView, let extractedSource { extractedSource.putBackContextMenuContent(previewView) }
        previewController?.willMove(toParent: nil)
        previewController?.view.removeFromSuperview()
        previewController?.removeFromParent()
        if presentationStyle.showsPreview { sourceView?.alpha = 1 }
        beginAppearanceTransition(false, animated: false)
        view.removeFromSuperview()
        endAppearanceTransition()
        presentationHostView = nil
        if Self.activeController === self { Self.activeController = nil }
        Self.closingControllers.removeAll { $0 === self }
        UIAccessibility.post(notification: .screenChanged, argument: sourceView)
        let callback = onDismiss
        onDismiss = nil
        performDismissCompletion()
        callback?()
    }

    /// Runs the chosen action once: when the menu is gone, or when a liquid morph close has visibly finished.
    private func performDismissCompletion() {
        let action = dismissCompletion
        dismissCompletion = nil
        action?()
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

    private func perform(_ button: TelegramContextMenuActionButton) {
        guard !isPerformingAction else { return }
        if !button.menuAction.children.isEmpty {
            parentActions.append(actions)
            let back = TelegramContextMenuAction(
                title: L10n.telegram("Common.Back"),
                image: UIImage(systemName: "chevron.left"),
            ) { [weak self] in self?.showParentActions() }
            var children = button.menuAction.children
            children[0].startsNewSection = true
            actions = [back] + children
            showActions()
            return
        }
        if !parentActions.isEmpty, button === actionButtons.first {
            showParentActions()
            return
        }
        isPerformingAction = true
        trackingGesture?.removeTarget(self, action: #selector(trackingGestureChanged(_:)))
        let handler = button.menuAction.handler
        dismissMenu(completion: handler)
    }

    private func showParentActions() {
        guard let parent = parentActions.popLast() else { return }
        actions = parent
        showActions()
    }

    private func showActions() {
        rebuildActions()
        UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.layoutPreviewAndMenu()
            self.menuEffectView.layoutIfNeeded()
        }
        UIAccessibility.post(notification: .layoutChanged, argument: actionButtons.first)
    }

    // MARK: Touch tracking

    /// The finger that opened the menu keeps scrubbing; pan hysteresis and the release rules restart here, as
    /// in the system menu when the press turns into an open menu.
    private func beginInitiatingTouchSession() {
        guard let trackingGesture, trackingGesture.state == .began || trackingGesture.state == .changed else { return }
        let point = trackingGesture.location(in: view)
        touchPoint = point
        touchSession = ContextMenuTouchSession(origin: .initiatingPreview, start: point, time: CACurrentMediaTime())
        touchSessionIsInitiating = true
        selectionFeedback.prepare()
    }

    @objc private func trackingGestureChanged(_ gesture: UIGestureRecognizer) {
        guard touchSessionIsInitiating, touchSession != nil else { return }
        let time = (gesture as? ContextMenuPressGestureRecognizer)?.timestamp ?? CACurrentMediaTime()
        trackTouch(at: gesture.location(in: view), time: time, state: gesture.state)
    }

    @objc private func menuTouchChanged(_ recognizer: ContextMenuTouchRecognizer) {
        guard !isDismissing else { return }
        let point = view.convert(recognizer.point, from: nil)
        if recognizer.state == .began {
            guard touchSession == nil, let origin = touchOrigin(at: point) else { return }
            touchSession = ContextMenuTouchSession(origin: origin, start: point, time: recognizer.timestamp)
            touchSessionIsInitiating = false
            selectionFeedback.prepare()
        }
        guard touchSession != nil, !touchSessionIsInitiating else { return }
        trackTouch(at: point, time: recognizer.timestamp, state: recognizer.state)
    }

    /// `nil` leaves the touch to the view under it: reactions, quote selection in the message text and the
    /// scrollable chat preview keep their own gestures.
    private func touchOrigin(at point: CGPoint) -> ContextMenuTouchSession.Origin? {
        if !reactionStrip.isHidden, reactionStrip.frame.contains(point) { return nil }
        if menuEffectView.frame.contains(point) { return .menu }
        guard previewFrame.contains(point) else { return .outside }
        if presentationStyle == .chatPreview { return nil }
        if selectableTextViews.contains(where: { $0.convert($0.bounds, to: view).contains(point) }) { return nil }
        return .preview
    }

    private func trackTouch(at point: CGPoint, time: TimeInterval, state: UIGestureRecognizer.State) {
        guard touchSession != nil, !isDismissing else { return }
        touchPoint = point
        touchSession?.move(to: point, insidePreview: previewFrame.contains(point))
        // The preview keeps its last position while the finger is over the menu.
        if let anchor = touchSession?.panAnchor, !menuEffectView.frame.contains(point) {
            let offset = ContextMenuMotion.platterOffset(
                location: point,
                anchor: anchor,
                menuIsBelow: targetMenuFrame.midY >= targetPreviewFrame.midY,
            )
            setPan(offset, tracking: true)
        }
        if touchSessionIsInitiating, !reactionStrip.isHidden {
            // Reactions follow the same handoff: a resting finger picks none.
            let tracksReactions = touchSession?.selectsOnRelease == true
            reactionStrip.updateTracking(at: tracksReactions ? reactionStrip.convert(point, from: view) : nil)
        }
        switch state {
        case .ended:
            if touchSessionIsInitiating, reactionStrip.selectTrackedReaction() { return }
            // The selection delay fails on touch end, so the action under the finger counts once the touch may select.
            let index = touchSession?.selectsOnRelease == true ? actionIndex(at: point) : nil
            touchSession?.highlighted = index
            setHighlight(index)
            let release = touchSession?.release(at: time) ?? .keepOpen
            finishTracking()
            switch release {
            case .select(let index) where actionButtons.indices.contains(index):
                perform(actionButtons[index])
            case .dismiss:
                dismissMenu(completion: nil)
            case .keepOpen, .select:
                break
            }
        case .cancelled, .failed:
            finishTracking()
        default:
            updateSelection(at: point, time: time)
        }
    }

    private func finishTracking() {
        touchSession = nil
        touchSessionIsInitiating = false
        selectionDelayWork?.cancel()
        selectionDelayWork = nil
        // Released, the tracked velocity carries into the 0.85 / 0.5 s spring back.
        if panOffset != .zero { setPan(.zero, tracking: false) }
        setHighlight(nil)
        reactionStrip.updateTracking(at: nil)
    }

    private func actionIndex(at point: CGPoint) -> Int? {
        guard menuEffectView.frame.contains(point) else { return nil }
        return actionButtons.firstIndex { $0.convert($0.bounds, to: view).contains(point) }
    }

    private func setPan(_ offset: CGPoint, tracking: Bool) {
        panOffset = offset
        let center = CGPoint(x: view.bounds.midX + offset.x, y: view.bounds.midY + offset.y)
        ContextMenuNativeAnimation.animate(
            behavior: panBehavior,
            tracking: tracking,
            fallbackDampingRatio: tracking ? 0.8 : 0.85,
            fallbackResponse: tracking ? 0.4 : 0.5,
        ) { [previewPanView] in previewPanView.center = center }
    }

    /// Touches that begin on the menu wait for the 0.15 s selection delay before highlighting.
    private func updateSelection(at point: CGPoint, time: TimeInterval) {
        guard let session = touchSession else { return }
        guard session.allowsHighlight(at: time) else {
            if session.origin == .menu {
                scheduleSelectionDelay(after: ContextMenuMotion.selectionDelay - (time - session.startTime))
            }
            return
        }
        let index = actionIndex(at: point)
        touchSession?.highlighted = index
        setHighlight(index)
    }

    private func scheduleSelectionDelay(after delay: TimeInterval) {
        guard selectionDelayWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            selectionDelayWork = nil
            updateSelection(at: touchPoint, time: CACurrentMediaTime())
        }
        selectionDelayWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    /// The system's shared highlight (`highlightItemAtIndexPath:` 0x1c482dba0, `unHighlightItemAtIndexPath:`
    /// 0x1c482d9d8): it slides between actions on a 1 / 0.12 s frame spring and fades on a 1 / 0.3 s spring, and
    /// one that is effectively invisible appears in place.
    private func setHighlight(_ index: Int?) {
        guard index != highlightedIndex else { return }
        highlightedIndex = index
        let highlight = selectionHighlightView
        guard let index, actionButtons.indices.contains(index) else {
            ContextMenuNativeAnimation.animate(
                behavior: highlightAlphaBehavior,
                tracking: false,
                fallbackDampingRatio: 1,
                fallbackResponse: 0.3,
            ) { highlight.alpha = 0 }
            return
        }
        menuEffectView.layoutIfNeeded()
        let button = actionButtons[index]
        let rect = button.convert(button.bounds, to: menuEffectView.contentView)
            .insetBy(dx: TelegramContextMenuLayout.highlightInset, dy: 0)
        let radius = min(
            TelegramContextMenuLayout.menuCornerRadius - TelegramContextMenuLayout.highlightInset,
            rect.height / 2,
        )
        let place = {
            highlight.frame = rect
            highlight.layer.cornerRadius = radius
        }
        if (highlight.layer.presentation() ?? highlight.layer).opacity < 0.05 {
            UIView.performWithoutAnimation(place)
        } else {
            ContextMenuNativeAnimation.animate(
                behavior: highlightFrameBehavior,
                tracking: false,
                fallbackDampingRatio: 1,
                fallbackResponse: 0.12,
                place,
            )
        }
        ContextMenuNativeAnimation.animate(
            behavior: highlightAlphaBehavior,
            tracking: false,
            fallbackDampingRatio: 1,
            fallbackResponse: 0.3,
        ) { highlight.alpha = 1 }
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    // MARK: Escape

    /// Escape reaches the menu's root view when nothing else holds focus. Otherwise the focused view keeps it,
    /// so the keyboard stays up, and its view controller carries the command while the menu is open.
    private func installEscape() {
        if let responder = TelegramContextMenuFirstResponder.current() {
            var next: UIResponder? = responder
            while let current = next, !(current is UIViewController) {
                next = current.next
            }
            guard let controller = next as? UIViewController else { return }
            controller.addKeyCommand(escapeCommand)
            escapeCommandOwner = controller
        } else {
            view.becomeFirstResponder()
        }
    }

    private func removeEscape() {
        escapeCommandOwner?.removeKeyCommand(escapeCommand)
        escapeCommandOwner = nil
        if view.isFirstResponder { view.resignFirstResponder() }
    }
}

// MARK: - Telegram layer animations

private extension CALayer {
    /// Telegram's `animateSpring`: a mass-5, stiffness-900 spring sped up to settle within `duration`.
    func addTelegramSpring(
        keyPath: String,
        from: Any,
        to: Any,
        duration: CFTimeInterval = 0.42,
        damping: CGFloat = 104,
        isAdditive: Bool = false,
    ) {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 5
        animation.stiffness = 900
        animation.damping = damping
        animation.duration = animation.settlingDuration
        animation.speed = Float(animation.duration / duration)
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fromValue = from
        animation.toValue = to
        animation.isAdditive = isAdditive
        animation.fillMode = .forwards
        add(animation, forKey: isAdditive ? nil : keyPath)
    }

    /// Telegram's dismissal curve. The final value stays until the menu is removed.
    func addTelegramAnimation(
        keyPath: String,
        from: Any,
        to: Any,
        duration: CFTimeInterval = 0.2,
        isAdditive: Bool = false,
        isRemovedOnCompletion: Bool = false,
    ) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fromValue = from
        animation.toValue = to
        animation.isAdditive = isAdditive
        animation.isRemovedOnCompletion = isRemovedOnCompletion
        animation.fillMode = .forwards
        add(animation, forKey: isAdditive ? nil : keyPath)
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
            line.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: TelegramContextMenuLayout.contentSideInset,
            ),
            line.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -TelegramContextMenuLayout.contentSideInset,
            ),
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
    var onActivate: (() -> Void)?

    // MARK: Private

    private let titleLabel = UILabel()
    private let iconView = UIImageView()

    init(action: TelegramContextMenuAction) {
        self.menuAction = action
        super.init(frame: .zero)

        let color: UIColor = action.isDestructive ? .systemRed : .label
        titleLabel.text = action.title
        titleLabel.textColor = color
        titleLabel.font = .systemFont(ofSize: TelegramContextMenuLayout.actionFontSize)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        iconView.image = action.image
        iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        var constraints = [
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -TelegramContextMenuLayout.contentSideInset,
            ),
        ]
        if action.image != nil {
            addSubview(iconView)
            constraints.append(contentsOf: [
                iconView.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: TelegramContextMenuLayout.iconSideInset
                        + (TelegramContextMenuLayout.iconSlotWidth - TelegramContextMenuLayout.iconSize) / 2,
                ),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: TelegramContextMenuLayout.iconSize),
                iconView.heightAnchor.constraint(equalToConstant: TelegramContextMenuLayout.iconSize),
                titleLabel.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: TelegramContextMenuLayout.iconSideInset
                        + TelegramContextMenuLayout.iconSlotWidth
                        + TelegramContextMenuLayout.iconSpacing,
                ),
            ])
        } else {
            constraints.append(titleLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: TelegramContextMenuLayout.contentSideInset,
            ))
        }
        NSLayoutConstraint.activate(constraints)
        isAccessibilityElement = true
        accessibilityLabel = action.title
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return onActivate != nil
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

#if DEBUG
@MainActor enum TelegramQuoteSelectionDiagnostics {
    private static var events = [String]()

    static func record(_ event: String) {
        guard ProcessInfo.processInfo.arguments.contains("-custom-emoji-text-probe") else { return }
        events.append(event)
        if events.count > 40 { events.removeFirst(events.count - 40) }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("quote-selection-ui-probe.txt")
        try? events.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif

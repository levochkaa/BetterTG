// TelegramContextMenu.swift

import Combine
import UIKit

// MARK: - TelegramContextMenuLayout

enum TelegramContextMenuLayout {
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
    /// ChatReadReportContextItem in a private chat: 0.8 of the 17-point list font, 7 pt above and below.
    static let headerFontSize = CGFloat(13)
    static let headerVerticalInset = CGFloat(7)
    static let headerHeight = ceil(UIFont.systemFont(ofSize: headerFontSize).lineHeight) + headerVerticalInset * 2
    static let headerIconSize = CGFloat(20)
    /// The chevron of a row with a submenu is centred this far from the trailing edge, as in the system menu.
    static let submenuIndicatorCenterInset = CGFloat(31)
    /// `navigateDownFromNode:` scales the parent menu to 0.97 behind an open submenu.
    static let submenuParentScale = CGFloat(0.97)
    /// The room a row's chevron takes beyond the usual trailing inset.
    static let submenuIndicatorReserve = CGFloat(26)

    static func height(of action: TelegramContextMenuAction) -> CGFloat {
        action.isHeader ? headerHeight : actionHeight
    }

    /// Telegram's `.twoLinesMax` action text: a title too long for the menu wraps onto a second line and the row
    /// grows to hold it. Headers and titles that arrive later keep one line.
    static func height(of action: TelegramContextMenuAction, menuWidth: CGFloat) -> CGFloat {
        guard wrapsTitle(of: action), menuWidth > 0 else { return height(of: action) }
        let font = UIFont.systemFont(ofSize: titleFontSize(of: action))
        let textWidth = max(1, menuWidth - titleLeadingInset(of: action) - titleTrailingInset(of: action))
        let titleHeight = (action.title as NSString)
            .boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin,
                attributes: [.font: font],
                context: nil,
            )
            .height
        guard titleHeight > font.lineHeight * 1.5 else { return actionHeight }
        return max(actionHeight, ceil(font.lineHeight * 2) + actionVerticalInset * 2)
    }

    static func wrapsTitle(of action: TelegramContextMenuAction) -> Bool {
        !action.isHeader && action.titleUpdates == nil
    }

    static func titleFontSize(of action: TelegramContextMenuAction) -> CGFloat {
        if action.isHeader { return headerFontSize }
        return action.isInformational || action.usesSmallText ? 14 : actionFontSize
    }

    static func titleLeadingInset(of action: TelegramContextMenuAction) -> CGFloat {
        action.image == nil ? contentSideInset : iconSideInset + iconSlotWidth + iconSpacing
    }

    static func titleTrailingInset(of action: TelegramContextMenuAction) -> CGFloat {
        contentSideInset + (action.children.isEmpty ? 0 : submenuIndicatorReserve)
    }
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
    /// A title that arrives after the menu opens, such as Telegram's read time; it shrinks to the menu's width.
    var titleUpdates: AnyPublisher<String, Never>?
    /// A row that only shows its text in the smaller 14-point font, such as when a checklist task was completed
    /// (ContextMenuActionItem with `.small` text and no action): it is never highlighted or selected.
    var isInformational = false
    /// A selectable row in the smaller 14-point font, such as who added a poll answer (ContextMenuActionItem with
    /// `.small` text and an action).
    var usesSmallText = false
    /// ChatReadReportContextItem in a private chat: a compact line of text at the top of the menu, such as when the
    /// message was read. It is never highlighted or selected unless `headerSelectableUpdates` says so.
    var isHeader = false
    /// Makes a header tappable while it shows something to act on, such as Telegram's "show when".
    var headerSelectableUpdates: AnyPublisher<Bool, Never>?

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

// MARK: - TelegramContextMenuSource

/// One of Telegram's context sources (ContextController.Source). A menu with more than one source shows tabs at the
/// bottom of the screen that switch between their actions, with the active source's footer above them.
struct TelegramContextMenuSource {
    let title: String
    var footer: String?
    let actions: [TelegramContextMenuAction]
    /// Whether the reaction strip shows while the source is active; only the message's own actions carry reactions.
    var showsReactions = true
}

// MARK: - TelegramContextQuoteSelection

struct TelegramContextQuoteSelection {
    let textView: MessageTextContentView
    /// The message's `canBeCopied`; protected messages offer only Quote for the selection.
    let allowsCopy: Bool
    /// Whether the selection offers Quote; text that can't be replied to is still selected to copy it.
    var allowsQuote = true
    let handler: (NSRange) -> Void
    /// Telegram's Translate for the selected text; nil where the chat doesn't offer it.
    var translate: ((String) -> Void)?
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
        case .avatar,
             .chatPreview,
             .message: true
        case .menuOnly,
             .sourceMorph: false
        }
    }
}

// MARK: - TelegramContextMenuKeyboardHost

enum TelegramContextMenuKeyboardHost {
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
    /// With more than one of `sources` the menu opens on the first source's actions in place of `actions`.
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
        sources: [TelegramContextMenuSource] = [],
        onDismiss: (() -> Void)? = nil,
    ) -> Bool {
        let sources = sources.count > 1 ? sources : []
        let actions = sources.first?.actions ?? actions
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
            sources: sources,
            owner: self, onDismiss: onDismiss,
        )
        cancelCompetingPans(from: sourceView, except: gesture)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        controller.show(in: sourceWindow)
        return true
    }

    /// The system menu takes the finger over from the views under it: a swipe to reply, a list's scroll or a row's
    /// swipe actions that started with the same finger stop, instead of moving the source behind the open menu and
    /// acting when the finger lifts. The window's own recognizers are left alone.
    private func cancelCompetingPans(from sourceView: UIView, except tracking: UIGestureRecognizer?) {
        var view: UIView? = sourceView
        while let current = view, !(current is UIWindow) {
            for recognizer in current.gestureRecognizers ?? [] where recognizer !== tracking {
                guard recognizer is UIPanGestureRecognizer, recognizer.isEnabled,
                      [.possible, .began, .changed].contains(recognizer.state)
                else { continue }
                recognizer.isEnabled = false
                recognizer.isEnabled = true
            }
            view = current.superview
        }
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

private final class TelegramContextMenuController: UIViewController, UIScrollViewDelegate {
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
    /// Open submenus, innermost last; each card lies over the one before it, or over the menu.
    private var submenus = [TelegramContextSubmenuView]()
    /// The screen's top and bottom limits for the menu, which an open submenu keeps within too.
    private var menuTopLimit = CGFloat.zero
    private var menuBottomLimit = CGFloat.zero
    /// Telegram's context sources; with more than one, tabs under the menu switch between their actions.
    private let sources: [TelegramContextMenuSource]
    private var activeSourceIndex = 0
    private let sourceTabsView = TelegramContextMenuSourceTabsView()
    private let sourceFooterLabel = UILabel()
    /// Whether the reactions provider returned any; the active source decides whether they show.
    private var hasReactions = false
    private let backgroundEffectView = UIVisualEffectView(effect: nil)
    private let dimView = TelegramContextMenuDismissView()
    private let previewPanView = TelegramContextMenuPassthroughView()
    /// The preview and the menu; its bounds scroll them together when a message is taller than the room above the
    /// menu (ContextControllerExtractedPresentationNode's scrollNode).
    private let contentContainer = TelegramContextMenuPassthroughView()
    /// Telegram's hidden scroller: its pan, on the root view, drives `contentContainer`'s bounds.
    private let scroller = UIScrollView()
    /// How far the content reaches past the bottom of the screen; zero when it fits and nothing scrolls.
    private var contentOverflow = CGFloat.zero
    private let previewContainer = UIView()
    /// Carries the system menu's flexible glass, which stretches toward a finger dragged across the menu. The glass
    /// draws past the bounds while it stretches, so this view does not clip; `menuContentView` clips the actions.
    private let menuView = UIView()
    private let menuContentView = UIView()
    /// Interactive public glass where the private material is unavailable.
    private let fallbackGlassView = UIVisualEffectView(effect: nil)
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
    /// Each action's row height, which grows once the menu's width wraps its title.
    private var actionHeightConstraints = [NSLayoutConstraint]()
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
    /// `navigateDownFromNode:` opens on 0.85 / 0.4 s; `navigateUpFromNode:` closes on 1 / 0.4 s and fades the
    /// submenu's actions on 1 / 0.5 s.
    private let submenuOpenBehavior = ContextMenuNativeAnimation.makeBehavior(dampingRatio: 0.85, response: 0.4)
    private let submenuCloseBehavior = ContextMenuNativeAnimation.makeBehavior(dampingRatio: 1, response: 0.4)
    private let submenuFadeBehavior = ContextMenuNativeAnimation.makeBehavior(dampingRatio: 1, response: 0.5)
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

    private var showsSourceTabs: Bool { sources.count > 1 }

    private var activeSourceShowsReactions: Bool {
        sources.indices.contains(activeSourceIndex) ? sources[activeSourceIndex].showsReactions : true
    }

    /// Model frame of the preview including the pan, like the system's platterView.frame checks.
    private var previewFrame: CGRect {
        presentationStyle.showsPreview ? previewContainer.convert(previewContainer.bounds, to: view) : .zero
    }

    /// Where the content is scrolled to: content coordinates are the screen's moved by this much.
    private var contentScrollOffset: CGFloat {
        contentContainer.bounds.origin.y
    }

    /// The menu's frame on screen, wherever the content is scrolled.
    private var menuFrameInView: CGRect {
        menuView.convert(menuView.bounds, to: view)
    }

    /// The menu and the submenus open over it, on screen.
    private var menuHitFrame: CGRect {
        submenus.reduce(menuFrameInView) { $0.union($1.convert($1.bounds, to: view)) }
    }

    /// The rows a touch can choose: the innermost submenu's, or the menu's.
    private var activeButtons: [TelegramContextMenuActionButton] {
        submenus.last?.buttons ?? actionButtons
    }

    /// Every submenu card, including one still closing.
    private var submenuViews: [TelegramContextSubmenuView] {
        contentContainer.subviews.compactMap { $0 as? TelegramContextSubmenuView }
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
        sources: [TelegramContextMenuSource],
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
        self.sources = sources
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

    private static func submenuParentTransform(height: CGFloat, anchorsBottom: Bool) -> CGAffineTransform {
        let scale = TelegramContextMenuLayout.submenuParentScale
        let shift = height * (1 - scale) / 2 * (anchorsBottom ? 1 : -1)
        return CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: 0, y: shift))
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === scroller else { return }
        contentContainer.bounds.origin.y = scrollView.contentOffset.y
        layoutReactionStrip()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Scrolling takes the touch: no row stays highlighted and the preview stops following it.
        guard scrollView === scroller else { return }
        finishTracking()
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

        contentContainer.frame = view.bounds
        contentContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(contentContainer)
        previewPanView.frame = contentContainer.bounds
        previewPanView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentContainer.addSubview(previewPanView)

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
            let translate: ((String) -> Void)? = quoteSelection.translate.map { translate in
                { [weak self] text in self?.dismissMenu { translate(text) } }
            }
            textView.setContextQuoteAction(
                { [weak self] range in self?.dismissMenu { handler(range) } },
                allowsCopy: quoteSelection.allowsCopy,
                allowsQuote: quoteSelection.allowsQuote,
                translate: translate,
            )
            selectableTextViews = [textView]
        }

        let menuCornerRadius = TelegramContextMenuLayout.menuCornerRadius
        menuView.layer.cornerRadius = menuCornerRadius
        menuView.layer.cornerCurve = .continuous
        menuView.clipsToBounds = false
        menuView.alpha = 0
        if !ContextMenuNativeGlass.applyMenuGlass(to: menuView) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = true
            fallbackGlassView.effect = glass
            fallbackGlassView.cornerConfiguration = .corners(radius: .fixed(Double(menuCornerRadius)))
            fallbackGlassView.frame = menuView.bounds
            fallbackGlassView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            menuView.addSubview(fallbackGlassView)
        }
        menuContentView.frame = menuView.bounds
        menuContentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        menuContentView.layer.cornerRadius = menuCornerRadius
        menuContentView.layer.cornerCurve = .continuous
        menuContentView.clipsToBounds = true
        menuView.addSubview(menuContentView)
        contentContainer.addSubview(menuView)

        selectionHighlightView.backgroundColor = .contextMenuSelectionHighlight
        selectionHighlightView.layer.cornerCurve = .continuous
        selectionHighlightView.alpha = 0
        selectionHighlightView.isUserInteractionEnabled = false
        menuContentView.addSubview(selectionHighlightView)

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
        menuContentView.addSubview(menuStack)
        NSLayoutConstraint.activate([
            menuStack.topAnchor.constraint(equalTo: menuContentView.topAnchor),
            menuStack.leadingAnchor.constraint(equalTo: menuContentView.leadingAnchor),
            menuStack.trailingAnchor.constraint(equalTo: menuContentView.trailingAnchor),
            menuStack.bottomAnchor.constraint(equalTo: menuContentView.bottomAnchor),
        ])

        view.addGestureRecognizer(touchRecognizer)

        rebuildActions()
        configureSourceTabs()
        reactionStrip.isHidden = reactionsProvider == nil || !activeSourceShowsReactions
        reactionStrip.alpha = 0
        // The strip belongs to the message: it pans and scrolls with it.
        previewPanView.addSubview(reactionStrip)
        scroller.isHidden = true
        scroller.delegate = self
        scroller.showsVerticalScrollIndicator = false
        scroller.contentInsetAdjustmentBehavior = .never
        scroller.alwaysBounceVertical = true
        scroller.panGestureRecognizer.isEnabled = false
        view.addSubview(scroller)
        view.addGestureRecognizer(scroller.panGestureRecognizer)
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
                hasReactions = !reactions.isEmpty
                reactionStrip.isHidden = !hasReactions || !activeSourceShowsReactions
                UIView.performWithoutAnimation { self.layoutPreviewAndMenu() }
            }
        }
    }

    /// ContextSourceContainer's tab selector and footer, for a menu with more than one source.
    private func configureSourceTabs() {
        guard showsSourceTabs else { return }
        sourceFooterLabel.font = .systemFont(ofSize: 13)
        sourceFooterLabel.textColor = UIColor.label.withAlphaComponent(0.4)
        sourceFooterLabel.textAlignment = .center
        sourceFooterLabel.numberOfLines = 0
        sourceFooterLabel.text = sources[activeSourceIndex].footer
        sourceFooterLabel.alpha = 0
        view.addSubview(sourceFooterLabel)
        sourceTabsView.configure(titles: sources.map(\.title), selectedIndex: activeSourceIndex)
        sourceTabsView.onSelect = { [weak self] index in self?.selectSource(at: index) }
        sourceTabsView.alpha = 0
        view.addSubview(sourceTabsView)
    }

    /// ContextSourceContainer: a tab, or a horizontal swipe, shows another source's actions and footer. Only a
    /// source that carries reactions keeps the strip.
    private func selectSource(at index: Int) {
        guard sources.indices.contains(index), index != activeSourceIndex, !isDismissing, !isPerformingAction
        else { return }
        activeSourceIndex = index
        let source = sources[index]
        removeSubmenus()
        actions = source.actions
        sourceTabsView.setSelectedIndex(index, animated: true)
        let showsReactions = reactionsProvider != nil && hasReactions && source.showsReactions
        reactionStrip.isHidden = !showsReactions
        if showsReactions { reactionStrip.alpha = 0 }
        if let footer = source.footer { sourceFooterLabel.text = footer }
        selectionFeedback.selectionChanged()
        rebuildActions()
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
        ) {
            self.layoutPreviewAndMenu()
            self.menuView.layoutIfNeeded()
            self.sourceFooterLabel.alpha = source.footer == nil ? 0 : 1
            self.reactionStrip.alpha = showsReactions ? 1 : 0
        }
        UIAccessibility.post(notification: .layoutChanged, argument: actionButtons.first)
    }

    /// ContextSourceContainer's tabs sit 30 points above the bottom inset, its footer 20 points above them, and the
    /// preview and menu stay above both. Returns the lowest point the menu may reach.
    private func layoutSourceTabs(bottom: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard showsSourceTabs else { return bottom }
        let fitting = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        let tabsSize = sourceTabsView.sizeThatFits(fitting)
        let tabsFrame = CGRect(
            x: ((view.bounds.width - tabsSize.width) / 2).rounded(.down),
            y: bottom - 30 - tabsSize.height,
            width: tabsSize.width,
            height: tabsSize.height,
        )
        sourceTabsView.frame = tabsFrame
        guard sources[activeSourceIndex].footer != nil else { return tabsFrame.minY - 10 }
        let footerSize = sourceFooterLabel.sizeThatFits(fitting)
        sourceFooterLabel.frame = CGRect(
            x: ((view.bounds.width - footerSize.width) / 2).rounded(.down),
            y: tabsFrame.minY - 20 - footerSize.height,
            width: footerSize.width,
            height: footerSize.height,
        )
        return sourceFooterLabel.frame.minY - 10
    }

    private func rebuildActions() {
        touchSession?.highlighted = nil
        setHighlight(nil)
        actionButtons.removeAll()
        actionHeightConstraints.removeAll()
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
            let heightConstraint = button.heightAnchor
                .constraint(equalToConstant: TelegramContextMenuLayout.height(of: action))
            heightConstraint.isActive = true
            menuStack.addArrangedSubview(button)
            actionButtons.append(button)
            actionHeightConstraints.append(heightConstraint)
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
        let menuWidth = menuWidth(availableWidth: availableWidth)
        for (button, constraint) in zip(actionButtons, actionHeightConstraints) {
            constraint.constant = TelegramContextMenuLayout.height(of: button.menuAction, menuWidth: menuWidth)
        }
        let menuHeight = TelegramContextMenuLayout.contentVerticalInset * 2
            + actions.reduce(CGFloat.zero) { $0 + TelegramContextMenuLayout.height(of: $1, menuWidth: menuWidth) }
            + separatorHeight
        let bottomInset = max(view.safeAreaInsets.bottom, CGFloat(12))
        let maximumBottom = layoutSourceTabs(bottom: view.bounds.height - bottomInset, availableWidth: availableWidth)
        menuTopLimit = verticalInset
        menuBottomLimit = maximumBottom

        switch presentationStyle {
        case .message:
            let spacing: CGFloat = 10
            let reactionHeight: CGFloat = reactionStrip.isHidden ? 0 : 56
            let baseSourceFrame = sourceFrameAtBaseTransform()
            messageContentSize = sourceView.bounds.size
            // ContextControllerExtractedPresentationNode never shrinks a tall message: it keeps its size and the
            // content scrolls, the menu at the bottom first.
            targetMessageScale = min(1, availableWidth / max(1, messageContentSize.width))
            let previewHeight = messageContentSize.height * targetMessageScale
            let previewWidth = messageContentSize.width * targetMessageScale
            let alignedPreviewX = baseSourceFrame.midX > view.bounds.midX
                ? baseSourceFrame.maxX - previewWidth
                : baseSourceFrame.minX
            let previewX = min(max(0, alignedPreviewX), view.bounds.width - previewWidth)
            let contentTop = verticalInset + reactionHeight
            let maximumPreviewY = maximumBottom - menuHeight - spacing - previewHeight
            let previewY = max(contentTop, min(baseSourceFrame.minY, maximumPreviewY))
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
            updateContentOverflow(max(0, targetMenuFrame.maxY - maximumBottom))
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
            let maximumHeight = maximumBottom - verticalInset - menuHeight - spacing
            if let contentSize = previewController?.preferredContentSize, contentSize.width > 0,
               contentSize.height > 0
            {
                // GalleryController's preferredContentSizeForLayout: media keeps its aspect in the space above the
                // menu.
                let scale = min(availableWidth / contentSize.width, max(44, maximumHeight) / contentSize.height)
                let fitted = CGSize(width: floor(contentSize.width * scale), height: floor(contentSize.height * scale))
                targetPreviewFrame = CGRect(
                    x: (view.bounds.width - fitted.width) / 2,
                    y: verticalInset,
                    width: fitted.width,
                    height: fitted.height,
                )
            } else {
                let preferredHeight = view.bounds.height * 0.48
                targetPreviewFrame = CGRect(
                    x: horizontalInset,
                    y: verticalInset,
                    width: availableWidth,
                    height: max(220, min(preferredHeight, maximumHeight)),
                )
            }
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
                // The source sits on screen; the scrolled content is offset from it.
                previewContainer.center = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY + contentScrollOffset)
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
        // Bounds and centre, not frame: an open submenu keeps the menu shrunk.
        menuView.bounds = CGRect(origin: .zero, size: targetMenuFrame.size)
        menuView.center = CGPoint(x: targetMenuFrame.midX, y: targetMenuFrame.midY)
        layoutSubmenus()
        layoutReactionStrip()
        previewView?.frame = previewContainer.bounds
        if presentationStyle == .avatar {
            previewView?.layoutIfNeeded()
        }
    }

    /// ReactionContextNode's anchor: the strip sits above the message, and while the message reaches above the room
    /// for it, at the top over the message, until scrolling leaves room above it again.
    private func layoutReactionStrip() {
        guard presentationStyle == .message, !reactionStrip.isHidden else { return }
        let horizontalInset: CGFloat = 12
        let availableWidth = view.bounds.width - horizontalInset * 2
        let width = min(availableWidth, reactionStrip.preferredWidth)
        let proposedX = targetPreviewFrame.midX > view.bounds.midX
            ? targetPreviewFrame.maxX - width
            : targetPreviewFrame.minX
        let pinnedTop = max(view.safeAreaInsets.top, CGFloat(12)) + contentScrollOffset
        reactionStrip.frame = CGRect(
            x: min(max(horizontalInset, proposedX), view.bounds.width - horizontalInset - width),
            y: max(pinnedTop, targetPreviewFrame.minY - 56),
            width: width,
            height: 46,
        )
    }

    /// Telegram's scroller covers the overflow; the menu opens scrolled to the bottom, so it shows in full.
    private func updateContentOverflow(_ overflow: CGFloat) {
        let previous = contentOverflow
        contentOverflow = overflow
        scroller.frame = view.bounds
        scroller.contentSize = CGSize(width: view.bounds.width, height: view.bounds.height + overflow)
        scroller.panGestureRecognizer.isEnabled = overflow > 0 && !isDismissing
        if previous == 0 || scroller.contentOffset.y > overflow {
            scroller.contentOffset = CGPoint(x: 0, y: overflow)
        }
        contentContainer.bounds.origin.y = scroller.contentOffset.y
    }

    private func menuWidth(availableWidth: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: TelegramContextMenuLayout.actionFontSize)
        // A submenu opens as wide as the menu, so its actions count too.
        func withSubmenus(_ actions: [TelegramContextMenuAction]) -> [TelegramContextMenuAction] {
            actions.flatMap { [$0] + withSubmenus($0.children) }
        }
        let naturalWidth = withSubmenus(actions).reduce(CGFloat.zero) { width, action in
            let titleWidth = ceil((action.title as NSString).size(withAttributes: [.font: font]).width)
                + (action.children.isEmpty ? 0 : TelegramContextMenuLayout.submenuIndicatorReserve)
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
            if self.showsSourceTabs {
                self.sourceTabsView.alpha = 1
                self.sourceFooterLabel.alpha = self.sources[self.activeSourceIndex].footer == nil ? 0 : 1
            }
        }
    }

    /// Telegram's actions animation: the menu springs out of its source, starting at its edge next to the
    /// content and travelling with it, and a menu-only source also centres it on the source.
    private func animateMenuIn() {
        let contentTravelY = presentationStyle.showsPreview
            ? targetPreviewFrame.midY - (sourceFrame.midY + contentScrollOffset)
            : 0
        let offset = menuTransitionOffset(contentTravelY: contentTravelY)
        let layer = menuView.layer
        menuView.alpha = 1
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
        let layer = menuView.layer
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
        // Open submenus shrink with the menu into the same point.
        let menuCenter = menuView.center
        for submenu in submenuViews {
            let cardLayer = submenu.layer
            let cardPresentation = cardLayer.presentation()
            let cardScale = (cardPresentation?.value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue ?? 1
            cardLayer.addTelegramAnimation(
                keyPath: "opacity",
                from: cardPresentation?.opacity ?? cardLayer.opacity,
                to: 0,
            )
            cardLayer.addTelegramAnimation(keyPath: "transform.scale", from: cardScale, to: 0.01)
            let travel = CGPoint(
                x: offset.x + (menuCenter.x - submenu.center.x) * 0.99,
                y: offset.y + (menuCenter.y - submenu.center.y) * 0.99,
            )
            cardLayer.addTelegramAnimation(
                keyPath: "position",
                from: NSValue(cgPoint: .zero),
                to: NSValue(cgPoint: travel),
                isAdditive: true,
            )
        }
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
            roundedRect: menuView.bounds,
            cornerRadius: TelegramContextMenuLayout.menuCornerRadius,
        )
        return UITargetedPreview(view: menuView, parameters: parameters)
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
        menuView.alpha = 1
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
            menuView.alpha = 0
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
        guard let morph = liquidMorph, let sourceView, sourceView.window != nil, menuView.window != nil,
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
        scroller.panGestureRecognizer.isEnabled = false
        if liquidMorph != nil {
            // The morph carries the menu alone; open submenus fade.
            let cards = submenuViews
            UIView.animate(withDuration: 0.15) { cards.forEach { $0.alpha = 0 } }
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
                self.menuView.alpha = 0
            } completion: { _ in self.finishDismissal() }
            return
        }
        // The preview flies back to where the source sits on screen, in the scrolled content's coordinates.
        let returnFrame = sourceFrameAtBaseTransform().offsetBy(dx: 0, dy: contentScrollOffset)
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
            self.sourceTabsView.alpha = 0
            self.sourceFooterLabel.alpha = 0
        } completion: { _ in self.finishDismissal() }
    }

    private func finishDismissal() {
        guard !didFinishDismissal else { return }
        didFinishDismissal = true
        isDismissing = true
        removeEscape()
        // The menu goes transparent before its visibility assertion ends, so UIKit's cleanup never shows it open.
        menuView.alpha = 0
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
        guard !isPerformingAction, button.acceptsSelection else { return }
        if let submenu = submenus.last, button === submenu.headerButton {
            closeSubmenu()
            return
        }
        if !button.menuAction.children.isEmpty {
            openSubmenu(from: button)
            return
        }
        isPerformingAction = true
        trackingGesture?.removeTarget(self, action: #selector(trackingGestureChanged(_:)))
        let handler = button.menuAction.handler
        dismissMenu(completion: handler)
    }

    // MARK: Submenus

    /// `navigateDownFromNode:`: the chosen row's highlight grows into the submenu's card, as wide as the parent,
    /// while the parent shrinks and dims behind it.
    private func openSubmenu(from button: TelegramContextMenuActionButton) {
        guard !isDismissing else { return }
        touchSession?.highlighted = nil
        setHighlight(nil)
        // A card still closing would leave its header over the new one.
        for closing in submenuViews where !submenus.contains(closing) {
            closing.removeFromSuperview()
        }
        let parentView: UIView = submenus.last ?? menuView
        let submenu = TelegramContextSubmenuView(action: button.menuAction)
        submenu.sourceButton = button
        submenu.setExpandedWidth(parentView.bounds.width)
        for child in submenu.buttons {
            child.onActivate = { [weak self, weak child] in
                guard let self, let child else { return }
                perform(child)
            }
        }
        let geometry = submenuGeometry(submenu, parentView: parentView)
        UIView.performWithoutAnimation {
            submenu.bounds = CGRect(origin: .zero, size: geometry.collapsed.size)
            submenu.center = CGPoint(x: geometry.collapsed.midX, y: geometry.collapsed.midY)
            contentContainer.insertSubview(submenu, aboveSubview: parentView)
            submenu.layoutIfNeeded()
        }
        submenus.append(submenu)
        submenu.isExpanded = true
        ContextMenuNativeAnimation.animate(
            behavior: submenuOpenBehavior,
            tracking: false,
            fallbackDampingRatio: 0.85,
            fallbackResponse: 0.4,
        ) {
            self.layoutSubmenus()
            submenu.headerButton.setSubmenuExpanded(true)
        }
        updateSubmenuAccessibility(focus: submenu.headerButton)
    }

    /// `navigateUpFromNode:`: the card shrinks back into its row, its actions fading, and the parent returns.
    private func closeSubmenu() {
        guard let submenu = submenus.last else { return }
        touchSession?.highlighted = nil
        setHighlight(nil)
        let collapsed = submenuGeometry(submenu, parentView: submenus.dropLast().last ?? menuView).collapsed
        submenus.removeLast()
        submenu.isExpanded = false
        submenu.isUserInteractionEnabled = false
        submenu.accessibilityElementsHidden = true
        ContextMenuNativeAnimation.animate(
            behavior: submenuFadeBehavior,
            tracking: false,
            fallbackDampingRatio: 1,
            fallbackResponse: 0.5,
        ) { submenu.setClosingAlpha(0) }
        ContextMenuNativeAnimation.animate(
            behavior: submenuCloseBehavior,
            tracking: false,
            fallbackDampingRatio: 1,
            fallbackResponse: 0.4,
        ) {
            self.layoutSubmenus()
            submenu.bounds = CGRect(origin: .zero, size: collapsed.size)
            submenu.center = CGPoint(x: collapsed.midX, y: collapsed.midY)
            submenu.layoutIfNeeded()
            submenu.headerButton.setSubmenuExpanded(false)
        } completion: {
            _ in submenu.removeFromSuperview()
        }
        updateSubmenuAccessibility(focus: submenu.sourceButton)
    }

    /// Another source's actions replace the menu, and its submenus go at once.
    private func removeSubmenus() {
        guard !submenus.isEmpty else { return }
        submenus.removeAll()
        submenuViews.forEach { $0.removeFromSuperview() }
        layoutSubmenus()
        updateSubmenuAccessibility(focus: nil)
    }

    /// Places each open submenu over its parent, which shrinks to 0.97 toward the edge the card grows from while
    /// its rows dim to half, as `navigateDownFromNode:` leaves them.
    private func layoutSubmenus() {
        var parentView: UIView = menuView
        var parentContent: UIView = menuContentView
        for submenu in submenus {
            let geometry = submenuGeometry(submenu, parentView: parentView)
            submenu.anchorsParentBottom = geometry.anchorsParentBottom
            parentView.transform = Self.submenuParentTransform(
                height: parentView.bounds.height,
                anchorsBottom: geometry.anchorsParentBottom,
            )
            parentContent.alpha = 0.5
            let frame = submenu.isExpanded ? geometry.expanded : geometry.collapsed
            submenu.bounds = CGRect(origin: .zero, size: frame.size)
            submenu.center = CGPoint(x: frame.midX, y: frame.midY)
            submenu.layoutIfNeeded()
            parentView = submenu
            parentContent = submenu.contentView
        }
        parentView.transform = .identity
        parentContent.alpha = 1
    }

    /// The card closed on its source row, inset like the row's highlight, and open as wide as the parent. Open, its
    /// header sits 2 points above the shrunk row; with no room below, the card ends 12 points above the parent's
    /// bottom and grows upward over it (iOS 26.5 and 27.2).
    private func submenuGeometry(
        _ submenu: TelegramContextSubmenuView,
        parentView: UIView,
    ) -> (collapsed: CGRect, expanded: CGRect, anchorsParentBottom: Bool) {
        // Bounds and centre give the parent's frame before its shrink.
        let parentFrame = CGRect(
            x: parentView.center.x - parentView.bounds.width / 2,
            y: parentView.center.y - parentView.bounds.height / 2,
            width: parentView.bounds.width,
            height: parentView.bounds.height,
        )
        let row = submenu.sourceButton.map { $0.convert($0.bounds, to: parentView) }
            ?? CGRect(x: 0, y: 0, width: parentFrame.width, height: TelegramContextMenuLayout.actionHeight)
        let inset = TelegramContextMenuLayout.highlightInset
        let collapsed = CGRect(
            x: parentFrame.minX + row.minX + inset,
            y: parentFrame.minY + row.minY,
            width: max(0, row.width - inset * 2),
            height: row.height,
        )
        let lift = TelegramContextMenuLayout.contentVerticalInset + 2
        let height = submenu.expandedHeight
        let bottomLimit = menuBottomLimit + contentScrollOffset
        var originY = parentFrame.minY + row.minY * TelegramContextMenuLayout.submenuParentScale - lift
        let anchorsParentBottom = originY + height > bottomLimit
        if anchorsParentBottom {
            originY = min(bottomLimit, parentFrame.maxY - lift) - height
        }
        let expanded = CGRect(
            x: parentFrame.minX,
            y: max(menuTopLimit + contentScrollOffset, originY),
            width: parentFrame.width,
            height: height,
        )
        return (collapsed, expanded, anchorsParentBottom)
    }

    /// Only the innermost level reads out; the dimmed ones behind it hide from VoiceOver.
    private func updateSubmenuAccessibility(focus: UIView?) {
        menuView.accessibilityElementsHidden = !submenus.isEmpty
        for (index, submenu) in submenus.enumerated() {
            submenu.accessibilityElementsHidden = index < submenus.count - 1
        }
        UIAccessibility.post(notification: .layoutChanged, argument: focus)
    }

    /// A tap on the dimmed menu behind a submenu closes the submenu.
    private func tapClosesSubmenu(_ session: ContextMenuTouchSession?, at point: CGPoint) -> Bool {
        guard let submenu = submenus.last, let session, session.origin == .menu else { return false }
        let cardFrame = submenu.convert(submenu.bounds, to: view)
        return !cardFrame.contains(session.start) && !cardFrame.contains(point)
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
        if showsSourceTabs, sourceTabsView.frame.contains(point) { return nil }
        if !reactionStrip.isHidden, reactionStrip.convert(reactionStrip.bounds, to: view).contains(point) { return nil }
        if menuHitFrame.contains(point) { return .menu }
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
        if let anchor = touchSession?.panAnchor, !menuHitFrame.contains(point) {
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
            if let session = touchSession, !touchSessionIsInitiating, session.origin != .menu,
               let step = sourceSwipeStep(from: session.start, to: point)
            {
                finishTracking()
                selectSource(at: activeSourceIndex + step)
                return
            }
            // The selection delay fails on touch end, so the action under the finger counts once the touch may select.
            let index = touchSession?.selectsOnRelease == true ? actionIndex(at: point) : nil
            touchSession?.highlighted = index
            setHighlight(index)
            let session = touchSession
            let release = session?.release(at: time) ?? .keepOpen
            finishTracking()
            switch release {
            case .select(let index) where activeButtons.indices.contains(index):
                perform(activeButtons[index])
            case .dismiss:
                dismissMenu(completion: nil)
            case .keepOpen,
                 .select:
                if tapClosesSubmenu(session, at: point) { closeSubmenu() }
            }
        case .cancelled,
             .failed:
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
        guard menuHitFrame.contains(point) else { return nil }
        return activeButtons.firstIndex { button in
            button.acceptsSelection && button.convert(button.bounds, to: view).contains(point)
        }
    }

    /// ContextSourceContainer's horizontal pan: a mostly horizontal swipe of 80 points shows the next source to the
    /// left, or the previous one to the right.
    private func sourceSwipeStep(from start: CGPoint, to end: CGPoint) -> Int? {
        guard showsSourceTabs else { return nil }
        let deltaX = end.x - start.x
        guard abs(deltaX) >= 80, abs(deltaX) > abs(end.y - start.y) * 2 else { return nil }
        let step = deltaX < 0 ? 1 : -1
        return sources.indices.contains(activeSourceIndex + step) ? step : nil
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
        let highlight = submenus.last?.highlightView ?? selectionHighlightView
        let host = submenus.last?.contentView ?? menuContentView
        let buttons = activeButtons
        guard let index, buttons.indices.contains(index) else {
            ContextMenuNativeAnimation.animate(
                behavior: highlightAlphaBehavior,
                tracking: false,
                fallbackDampingRatio: 1,
                fallbackResponse: 0.3,
            ) { highlight.alpha = 0 }
            return
        }
        (submenus.last ?? menuView).layoutIfNeeded()
        let button = buttons[index]
        let rect = button.convert(button.bounds, to: host)
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

// MARK: - TelegramContextSubmenuView

/// The system submenu (`_UIContextMenuStackedHierarchyLayout navigateDownFromNode:`, iOS 26.5 and 27.2): a glass
/// card of its own that grows out of the chosen row over the dimmed parent. Its header repeats that row and closes
/// the card; a divider separates it from the submenu's actions.
///
/// Like `_UIContextMenuListView`, the card's glass is a separate background that is never smaller than the header
/// with the menu's insets around it. Closed, the card is the row inset like its highlight and clips that background,
/// so only the flat middle of the glass shows, with no rim or shadow, and the glass blends into the menu under it.
private final class TelegramContextSubmenuView: UIView {
    // MARK: Internal

    let headerButton: TelegramContextMenuActionButton
    let childButtons: [TelegramContextMenuActionButton]
    /// Clips the rows to the glass while it grows and dims them behind a deeper submenu.
    let contentView = UIView()
    let highlightView = UIView()
    weak var sourceButton: TelegramContextMenuActionButton?
    /// Whether the parent shrinks toward its bottom edge, when the card has no room below and grows upward over it.
    var anchorsParentBottom = false
    var isExpanded = false {
        didSet { setNeedsLayout() }
    }

    /// The open card: the header, a divider and the actions, within the menu's vertical insets.
    private(set) var expandedHeight = CGFloat.zero

    // MARK: Private

    /// The rows where they sit in the open card; while closed they move up and left by the card's insets, so the
    /// header lies exactly on the source row.
    private let rowsView = UIView()
    private let divider = UIView()
    /// Carries the menu glass, which draws past its bounds while it stretches under a finger.
    private let backgroundView = UIView()
    private let fallbackGlassView = UIVisualEffectView(effect: nil)
    private var expandedWidth = CGFloat.zero

    var buttons: [TelegramContextMenuActionButton] {
        [headerButton] + childButtons
    }

    /// Open, the menu's radius; closed, the radius of the row highlight the card clips the glass to.
    private var cornerRadius: CGFloat {
        if isExpanded {
            TelegramContextMenuLayout.menuCornerRadius
        } else {
            min(
                TelegramContextMenuLayout.menuCornerRadius - TelegramContextMenuLayout.highlightInset,
                bounds.height / 2,
            )
        }
    }

    /// The glass and the rows: the card's bounds when open; closed, the header with the menu's insets around it.
    private var glassFrame: CGRect {
        if isExpanded {
            bounds
        } else {
            bounds.insetBy(
                dx: -TelegramContextMenuLayout.highlightInset,
                dy: -TelegramContextMenuLayout.contentVerticalInset,
            )
        }
    }

    init(action: TelegramContextMenuAction) {
        self.headerButton = TelegramContextMenuActionButton(action: action, role: .submenuHeader)
        self.childButtons = action.children.map { TelegramContextMenuActionButton(action: $0) }
        super.init(frame: .zero)
        layer.cornerCurve = .continuous
        let menuCornerRadius = TelegramContextMenuLayout.menuCornerRadius
        backgroundView.layer.cornerRadius = menuCornerRadius
        backgroundView.layer.cornerCurve = .continuous
        if !ContextMenuNativeGlass.applyMenuGlass(to: backgroundView) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = true
            fallbackGlassView.effect = glass
            fallbackGlassView.cornerConfiguration = .corners(radius: .fixed(Double(menuCornerRadius)))
            fallbackGlassView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            backgroundView.addSubview(fallbackGlassView)
        }
        addSubview(backgroundView)
        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = menuCornerRadius
        contentView.layer.cornerCurve = .continuous
        addSubview(contentView)
        highlightView.backgroundColor = .contextMenuSelectionHighlight
        highlightView.layer.cornerCurve = .continuous
        highlightView.alpha = 0
        highlightView.isUserInteractionEnabled = false
        contentView.addSubview(highlightView)
        contentView.addSubview(rowsView)
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.62)
        rowsView.addSubview(divider)
        buttons.forEach(rowsView.addSubview)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // As in the system, the card clips only while it closes: opening, the glass grows freely out of the row.
        clipsToBounds = !isExpanded
        layer.cornerRadius = cornerRadius
        backgroundView.frame = glassFrame
        fallbackGlassView.frame = backgroundView.bounds
        contentView.frame = glassFrame
        rowsView.frame = CGRect(x: 0, y: 0, width: expandedWidth, height: expandedHeight)
    }

    /// Lays the rows out for an open card as wide as the parent menu.
    func setExpandedWidth(_ width: CGFloat) {
        guard width != expandedWidth else { return }
        expandedWidth = width
        var originY = TelegramContextMenuLayout.contentVerticalInset
        let headerHeight = TelegramContextMenuLayout.height(of: headerButton.menuAction, menuWidth: width)
        headerButton.frame = CGRect(x: 0, y: originY, width: width, height: headerHeight)
        originY += headerHeight
        let lineHeight = 1 / max(1, traitCollection.displayScale)
        divider.frame = CGRect(
            x: TelegramContextMenuLayout.contentSideInset,
            y: originY + (TelegramContextMenuLayout.sectionSeparatorHeight - lineHeight) / 2,
            width: width - TelegramContextMenuLayout.contentSideInset * 2,
            height: lineHeight,
        )
        originY += TelegramContextMenuLayout.sectionSeparatorHeight
        for button in childButtons {
            let height = TelegramContextMenuLayout.height(of: button.menuAction, menuWidth: width)
            button.frame = CGRect(x: 0, y: originY, width: width, height: height)
            originY += height
        }
        expandedHeight = originY + TelegramContextMenuLayout.contentVerticalInset
        setNeedsLayout()
    }

    /// `navigateUpFromNode:` fades the submenu's actions out while the card shrinks back into its row. The glass fades
    /// with them, so it has blended into the menu by the time the card stops, as the system's does (iOS 27.2, dark
    /// appearance), rather than staying until the card is removed.
    func setClosingAlpha(_ alpha: CGFloat) {
        divider.alpha = alpha
        childButtons.forEach { $0.alpha = alpha }
        backgroundView.alpha = alpha
    }
}

// MARK: - TelegramContextMenuSourceTabsView

/// Telegram's TabSelectorComponent as ContextSourceContainer sets it up: medium 14-point titles in 32-point capsules
/// with 12 points of inner inset, 9 points apart, and a faint capsule behind the selected one.
private final class TelegramContextMenuSourceTabsView: UIView {
    // MARK: Private

    private static let height = CGFloat(32)
    private static let innerInset = CGFloat(12)
    private static let spacing = CGFloat(9)
    private static let font = UIFont.systemFont(ofSize: 14, weight: .medium)

    // MARK: Internal

    var onSelect: ((Int) -> Void)?

    private let selectionView = UIView()
    private var buttons = [UIButton]()
    private var selectedIndex = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        selectionView.backgroundColor = UIColor.label.withAlphaComponent(0.1)
        selectionView.layer.cornerRadius = Self.height / 2
        selectionView.layer.cornerCurve = .continuous
        selectionView.isUserInteractionEnabled = false
        addSubview(selectionView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = buttons.reduce(Self.spacing) { $0 + itemWidth($1) + Self.spacing }
        return CGSize(width: min(width, size.width), height: Self.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var originX = Self.spacing
        for button in buttons {
            let width = itemWidth(button)
            button.frame = CGRect(x: originX, y: 0, width: width, height: Self.height)
            originX += width + Self.spacing
        }
        placeSelection()
    }

    func configure(titles: [String], selectedIndex: Int) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = titles.enumerated().map { index, title in
            let button = UIButton(type: .custom)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = Self.font
            button.setTitleColor(UIColor.label.withAlphaComponent(0.8), for: .normal)
            button.setTitleColor(UIColor.label.withAlphaComponent(0.4), for: .highlighted)
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
            addSubview(button)
            return button
        }
        self.selectedIndex = selectedIndex
        updateAccessibility()
        setNeedsLayout()
    }

    func setSelectedIndex(_ index: Int, animated: Bool) {
        selectedIndex = index
        updateAccessibility()
        guard animated else {
            placeSelection()
            return
        }
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
        ) { self.placeSelection() }
    }

    private func placeSelection() {
        guard buttons.indices.contains(selectedIndex) else { return }
        selectionView.frame = buttons[selectedIndex].frame
    }

    private func itemWidth(_ button: UIButton) -> CGFloat {
        let title = (button.title(for: .normal) ?? "") as NSString
        return ceil(title.size(withAttributes: [.font: Self.font]).width) + Self.innerInset * 2
    }

    private func updateAccessibility() {
        for (index, button) in buttons.enumerated() {
            button.accessibilityTraits = index == selectedIndex ? [.button, .selected] : .button
        }
    }
}

// MARK: - TelegramContextMenuActionButton

final class TelegramContextMenuActionButton: UIControl {
    // MARK: Internal

    enum Role {
        case action
        /// The top row of an open submenu (`_UIContextMenuSubmenuTitleView`): the chosen row again, its title
        /// semibold and its chevron turned down; choosing it closes the submenu.
        case submenuHeader
    }

    let menuAction: TelegramContextMenuAction
    var onActivate: (() -> Void)?
    /// Whether a touch may highlight and choose the row: never for informational rows, and for a header only while
    /// it offers something.
    private(set) var acceptsSelection: Bool

    // MARK: Private

    private let titleLabel = UILabel()
    /// The submenu header's semibold title, which the system cross-fades with the regular one.
    private let expandedTitleLabel = UILabel()
    private let iconView = UIImageView()
    /// The system's chevron after a row that opens a submenu.
    private let submenuIndicator = UIImageView()
    private var titleCancellable: AnyCancellable?
    private var selectableCancellable: AnyCancellable?

    init(action: TelegramContextMenuAction, role: Role = .action) {
        self.menuAction = action
        self.acceptsSelection = !action.isInformational && !action.isHeader
        super.init(frame: .zero)

        let color: UIColor = action.isDestructive ? .systemRed : .label
        titleLabel.text = action.title
        titleLabel.textColor = color
        titleLabel.font = .systemFont(ofSize: TelegramContextMenuLayout.titleFontSize(of: action))
        titleLabel.numberOfLines = TelegramContextMenuLayout.wrapsTitle(of: action) ? 2 : 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        iconView.image = action.image
        iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        var constraints = [titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)]
        if action.children.isEmpty {
            constraints.append(titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -TelegramContextMenuLayout.contentSideInset,
            ))
        } else {
            submenuIndicator.image = UIImage(
                systemName: "chevron.forward",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold),
            )
            submenuIndicator.tintColor = color
            submenuIndicator.translatesAutoresizingMaskIntoConstraints = false
            addSubview(submenuIndicator)
            constraints.append(contentsOf: [
                submenuIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
                submenuIndicator.centerXAnchor.constraint(
                    equalTo: trailingAnchor,
                    constant: -TelegramContextMenuLayout.submenuIndicatorCenterInset,
                ),
                titleLabel.trailingAnchor.constraint(
                    lessThanOrEqualTo: submenuIndicator.leadingAnchor,
                    constant: -TelegramContextMenuLayout.iconSpacing,
                ),
            ])
        }
        if role == .submenuHeader {
            expandedTitleLabel.text = action.title
            expandedTitleLabel.textColor = color
            expandedTitleLabel.font = .systemFont(ofSize: TelegramContextMenuLayout.actionFontSize, weight: .semibold)
            expandedTitleLabel.numberOfLines = titleLabel.numberOfLines
            expandedTitleLabel.alpha = 0
            expandedTitleLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(expandedTitleLabel)
            constraints.append(contentsOf: [
                expandedTitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                expandedTitleLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
                expandedTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: submenuIndicator.leadingAnchor),
            ])
        }
        if action.image != nil {
            addSubview(iconView)
            let iconSize = action.isHeader
                ? TelegramContextMenuLayout.headerIconSize
                : TelegramContextMenuLayout.iconSize
            constraints.append(contentsOf: [
                iconView.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: TelegramContextMenuLayout.iconSideInset
                        + (TelegramContextMenuLayout.iconSlotWidth - iconSize) / 2,
                ),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: iconSize),
                iconView.heightAnchor.constraint(equalToConstant: iconSize),
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
        accessibilityTraits = acceptsSelection ? .button : .staticText
        if action.isHeader, let updates = action.headerSelectableUpdates {
            self.selectableCancellable = updates
                .receive(on: DispatchQueue.main)
                .sink { [weak self] selectable in
                    self?.acceptsSelection = selectable
                    self?.accessibilityTraits = selectable ? .button : .staticText
                }
        }
        if let updates = action.titleUpdates {
            titleLabel.adjustsFontSizeToFitWidth = true
            titleLabel.minimumScaleFactor = 0.7
            self.titleCancellable = updates
                .receive(on: DispatchQueue.main)
                .sink { [weak self] title in
                    self?.titleLabel.text = title
                    self?.accessibilityLabel = title
                }
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return onActivate != nil
    }

    /// The header of a submenu as it opens or closes: the title turns semibold and the chevron turns to point down.
    func setSubmenuExpanded(_ expanded: Bool) {
        titleLabel.alpha = expanded ? 0 : 1
        expandedTitleLabel.alpha = expanded ? 1 : 0
        let angle = CGFloat.pi / 2 * (effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1)
        submenuIndicator.transform = expanded ? CGAffineTransform(rotationAngle: angle) : .identity
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

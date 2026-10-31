// TelegramSplitViewController.swift

import UIKit

// MARK: - TelegramMasterPaneScreen

/// A list that opens in the chat list's pane while the window is split, as Telegram's
/// `navigationPresentation = .master`.
@MainActor protocol TelegramMasterPaneScreen: AnyObject {}

// MARK: - ArchiveViewController + TelegramMasterPaneScreen

extension ArchiveViewController: TelegramMasterPaneScreen {}

// MARK: - ForumTopicsViewController + TelegramMasterPaneScreen

extension ForumTopicsViewController: TelegramMasterPaneScreen {}

// MARK: - TelegramSplitPaneView

/// One of the split's two columns. `UIView.iPhoneDuoLayout` measures a screen against it.
final class TelegramSplitPaneView: UIView {}

// MARK: - TelegramSplitPlaceholderViewController

/// The detail pane with no chat open, and the root its stack pops back to.
final class TelegramSplitPlaceholderViewController: UIViewController, TelegramEmbeddedNavigationChrome {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
    }
}

// MARK: - TelegramSplitViewController

/// Telegram's NavigationSplitContainer: on a regular-width window the chat list stays in one column and what it opens
/// goes in the other. Every other window shows the master navigation controller alone, and the one stack it holds
/// splits and joins again as the window resizes, such as when iPhone Duo folds or rotates.
@MainActor final class TelegramSplitViewController: UIViewController {
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
        isSplit ? detail : master
    }

    // MARK: Internal

    let master: TelegramNavigationController
    let detail = TelegramNavigationController()

    /// Whether the chat a list row opens stays highlighted, reported to the lists.
    var onDetailChange: (() -> Void)?

    private(set) var isSplit = false

    // MARK: Private

    private let masterPane = TelegramSplitPaneView()
    private let detailPane = TelegramSplitPaneView()
    private let separator = UIView()
    private let placeholder = TelegramSplitPlaceholderViewController()
    private var lastLayoutSize = CGSize.zero

    /// Every screen, master's first: what one navigation controller would hold.
    var logicalStack: [UIViewController] {
        isSplit ? master.viewControllers + detail.viewControllers.dropFirst() : master.viewControllers
    }

    /// The navigation controller a new screen goes on.
    var activeNavigation: TelegramNavigationController {
        isSplit ? detail : master
    }

    private var activeDivision: CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        return view.reservedRegions(kind: .division).first(where: \.isActive)?.frame
    }

    init(master: TelegramNavigationController) {
        self.master = master
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        master.splitController = self
        detail.splitController = self
        detail.setStackDirectly([placeholder], animated: false)
        detail.onDidShow = { [weak self] _ in self?.onDetailChange?() }

        for pane in [masterPane, detailPane] {
            pane.clipsToBounds = true
            view.addSubview(pane)
        }
        detailPane.isHidden = true
        separator.backgroundColor = .separator
        separator.isHidden = true
        view.addSubview(separator)
        for (controller, pane) in [(master, masterPane), (detail, detailPane)] {
            addChild(controller)
            controller.view.frame = pane.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            pane.addSubview(controller.view)
            controller.didMove(toParent: self)
        }
        if #available(iOS 27.1, *) {
            // The fold's region changes as the hinge does.
            view.addInteraction(UIHingeInteraction { [weak self] _, _ in self?.view.setNeedsLayout() })
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updatePanes()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        Utils.splitDetailWidth = isSplit
            ? detail.view.bounds.width - detail.view.safeAreaInsets.left - detail.view.safeAreaInsets.right
            : nil
    }

    // MARK: Internal

    /// Telegram's `layoutMetricsForWindowSize`. UIKit calls the unfolded portrait screen regular too, but a chat list
    /// beside a chat is narrower than a phone there.
    static func splits(_ size: CGSize) -> Bool {
        size.width > 690 && size.height > 650
    }

    /// Telegram's `splitMasterWidth`: while the fold is active and runs through the whole window, the split sits on its
    /// midline, so the chat list and the chat each get one side of it. Otherwise a third, at least 320 pt, at most
    /// half.
    static func masterWidth(containerSize: CGSize, division: CGRect?) -> CGFloat {
        if let division, division.width < containerSize.width, division.minY <= 0.5,
           division.maxY >= containerSize.height - 0.5
        {
            return floor(division.midX)
        }
        return min(max(320, floor(containerSize.width / 3)), floor(containerSize.width / 2))
    }

    // MARK: Private

    private static func partition(_ stack: [UIViewController]) -> (
        master: [UIViewController],
        detail: [UIViewController],
    ) {
        let lists = stack.dropFirst().prefix { $0 is TelegramMasterPaneScreen }
        return (Array(stack.prefix(1) + lists), Array(stack.dropFirst(1 + lists.count)))
    }

    /// Whether `controller` goes in the other pane when pushed on `navigation`.
    func redirectsPush(of controller: UIViewController, on navigation: TelegramNavigationController) -> Bool {
        isSplit && navigation === master && !(controller is TelegramMasterPaneScreen)
    }

    /// What the chat list's pane opens takes the detail pane's whole stack, as a tablet's list replaces what its
    /// details show.
    func replaceDetail(with controller: UIViewController) {
        detail.replaceStackAboveRoot(with: controller)
    }

    /// Sets every screen, `logicalStack`'s order: lists stay with the chat list and the rest go in the detail pane.
    func setLogicalStack(_ stack: [UIViewController], animated: Bool) {
        guard isSplit else { return master.setStackDirectly(stack, animated: animated) }
        let parts = Self.partition(stack)
        master.setStackDirectly(parts.master, animated: false)
        detail.setStackDirectly([placeholder] + parts.detail, animated: animated)
    }

    /// Goes back to the chat list alone.
    func popToRoots(animated: Bool) {
        master.popToRootViewController(animated: animated)
        if isSplit { detail.popToRootViewController(animated: false) }
    }

    private func updatePanes() {
        let bounds = view.bounds
        let shouldSplit = Self.splits(bounds.size)
        var split = isSplit
        var relocates = false
        if shouldSplit != isSplit {
            if let coordinator = master.transitionCoordinator ?? detail.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.view.setNeedsLayout() }
            } else {
                split = shouldSplit
                relocates = true
            }
        }
        // The panes take their places first: the screens move as their stacks lay out.
        defer { if relocates { relocateScreens(split: split) } }
        let masterWidth = split
            ? Self.masterWidth(containerSize: bounds.size, division: activeDivision)
            : bounds.width
        // The panes follow the hinge; a resize already animates as the system's.
        let followsHinge = isSplit && lastLayoutSize == bounds.size && masterPane.frame.width != masterWidth
            && !UIAccessibility.isReduceMotionEnabled && view.window != nil
        lastLayoutSize = bounds.size
        let apply = { [self] in
            masterPane.frame = CGRect(x: 0, y: 0, width: masterWidth, height: bounds.height)
            detailPane.frame = CGRect(x: masterWidth, y: 0, width: bounds.width - masterWidth, height: bounds.height)
            let pixel = 1 / max(traitCollection.displayScale, 1)
            separator.frame = CGRect(x: masterWidth, y: 0, width: pixel, height: bounds.height)
        }
        detailPane.isHidden = !split
        separator.isHidden = !split
        guard followsHinge else { return apply() }
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            apply()
            self.master.view.layoutIfNeeded()
            self.detail.view.layoutIfNeeded()
        }
    }

    /// Hands the screens over as the window splits or joins. Each one is off its old stack before the other adopts it:
    /// UIKit moves a stack's screens as it lays out, and a screen that left its old stack after joining the new one
    /// would
    /// be on screen as disappeared, which no longer follows the safe area.
    private func relocateScreens(split: Bool) {
        TelegramNavigationController.isRelocatingScreens = true
        let stack = logicalStack
        isSplit = split
        if split {
            let parts = Self.partition(stack)
            for controller in parts.detail {
                master.releaseChrome(of: controller)
            }
            master.setStackDirectly(parts.master, animated: false)
            master.view.layoutIfNeeded()
            detail.setStackDirectly([placeholder] + parts.detail, animated: false)
        } else {
            for controller in detail.viewControllers.dropFirst() {
                detail.releaseChrome(of: controller)
            }
            detail.setStackDirectly([placeholder], animated: false)
            detail.view.layoutIfNeeded()
            master.setStackDirectly(stack, animated: false)
        }
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        onDetailChange?()
        // UIKit runs the screens' appearance callbacks with the next layout pass.
        DispatchQueue.main.async { TelegramNavigationController.isRelocatingScreens = false }
    }
}

// MARK: - UIViewController + isLeavingNavigation

extension UIViewController {
    /// Whether the screen is leaving navigation for good, not moving between the split's panes.
    var isLeavingNavigation: Bool {
        isMovingFromParent && !TelegramNavigationController.isRelocatingScreens
    }
}

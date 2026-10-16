// TelegramClassicNavigationChrome.swift

import Combine
import UIKit

// MARK: - TelegramEmbeddedNavigationChrome

/// Screens which already lay out their own Telegram navigation chrome.
protocol TelegramEmbeddedNavigationChrome: AnyObject {}

// MARK: - TelegramNavigationSearchProvider

/// Keep search state out of UINavigationItem: iOS 26 otherwise creates an
/// additional bottom toolbar search even while the native bar is hidden.
@MainActor protocol TelegramNavigationSearchProvider: AnyObject {
    var telegramNavigationSearch: UISearchController { get }
}

extension UISearchController {
    /// Ends the classic chrome's search for this controller as its close button does: the field clears and gives up
    /// the keyboard, and the results updater hears the empty query. Telegram closes a picker's search once a result
    /// is chosen.
    func endTelegramNavigationSearch() {
        searchBar.text = nil
        NotificationCenter.default.post(name: .telegramNavigationSearchEnd, object: self)
    }
}

private extension Notification.Name {
    static let telegramNavigationSearchEnd = Self("telegramNavigationSearchEnd")
}

// MARK: - TelegramNavigationAttemptHandling

/// Telegram's ViewController.attemptNavigation: a screen with unsaved changes can hold Back and the swipe back.
@MainActor protocol TelegramNavigationAttemptHandling: AnyObject {
    /// True when the screen may leave now; false once it has taken over, for example to ask about unsaved changes.
    func attemptNavigation() -> Bool
}

// MARK: - MainViewController + TelegramEmbeddedNavigationChrome

extension MainViewController: TelegramEmbeddedNavigationChrome {}

// MARK: - ChatViewController + TelegramEmbeddedNavigationChrome

extension ChatViewController: TelegramEmbeddedNavigationChrome {}

// MARK: - ArchiveViewController + TelegramEmbeddedNavigationChrome

extension ArchiveViewController: TelegramEmbeddedNavigationChrome {}

// MARK: - ForumTopicsViewController + TelegramEmbeddedNavigationChrome

extension ForumTopicsViewController: TelegramEmbeddedNavigationChrome {}

// MARK: - ForwardForumTopicsViewController + TelegramEmbeddedNavigationChrome

extension ForwardForumTopicsViewController: TelegramEmbeddedNavigationChrome {}

// MARK: - LoginViewController + TelegramEmbeddedNavigationChrome

extension LoginViewController: TelegramEmbeddedNavigationChrome {}

// MARK: - TelegramNavigationChromeState

@MainActor final class TelegramNavigationChromeState {
    let bar = TelegramClassicNavigationChrome()

    private weak var controller: UIViewController?
    private weak var navigation: UINavigationController?
    private var observations = [NSKeyValueObservation]()
    private var buttonObservations = [NSKeyValueObservation]()
    private var observedButtons = [UIBarButtonItem]()
    private var reservedHeight: CGFloat = 0

    init(controller: UIViewController, navigation: UINavigationController) {
        self.controller = controller
        self.navigation = navigation
        let item = controller.navigationItem
        let changed: () -> Void = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        self.observations = [
            item.observe(\.title) { _, _ in changed() },
            item.observe(\.titleView) { _, _ in changed() },
            item.observe(\.leftBarButtonItem) { _, _ in changed() },
            item.observe(\.rightBarButtonItem) { _, _ in changed() },
            item.observe(\.leftBarButtonItems) { _, _ in changed() },
            item.observe(\.rightBarButtonItems) { _, _ in changed() },
            item.observe(\.hidesBackButton) { _, _ in changed() },
            item.observe(\.prompt) { _, _ in changed() },
            item.observe(\.subtitle) { _, _ in changed() },
            controller.observe(\.title) { _, _ in changed() },
        ]
        if let scrollView = controller.view as? UIScrollView {
            observations.append(scrollView.observe(\.contentOffset) { [weak self] _, _ in
                // UIKit scroll mutations are on main. Keep the fixed header at
                // the viewport origin in this same frame, including deceleration.
                MainActor.assumeIsolated { self?.layout() }
            })
        }
        bar.layer.zPosition = 1000
        controller.view.addSubview(bar)
        bar.onBack = { [weak navigation, weak controller] in
            if let handler = controller as? TelegramNavigationAttemptHandling, !handler.attemptNavigation() { return }
            navigation?.popViewController(animated: true)
        }
        bar.onHeightChange = { [weak self] in self?.refresh() }
    }

    func refresh() {
        guard let controller, let navigation else { return }
        let item = controller.navigationItem
        let buttons = (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? [])
        if buttons != observedButtons {
            observedButtons = buttons
            buttonObservations = buttons.flatMap { button in
                let changed: () -> Void = { [weak self] in
                    Task { @MainActor in self?.refresh() }
                }
                return [
                    button.observe(\.title) { _, _ in changed() },
                    button.observe(\.image) { _, _ in changed() },
                    button.observe(\.isEnabled) { _, _ in changed() },
                    button.observe(\.customView) { _, _ in changed() },
                    button.observe(\.menu) { _, _ in changed() },
                ]
            }
        }
        bar.configure(
            item: item,
            fallbackTitle: controller.title,
            showsBack: navigation.viewControllers.first !== controller,
            searchController: (controller as? TelegramNavigationSearchProvider)?.telegramNavigationSearch,
        )
        let height = bar.contentHeight
        if reservedHeight != height {
            controller.additionalSafeAreaInsets.top += height - reservedHeight
            reservedHeight = height
        }
        if navigation.isViewLoaded { layout() }
    }

    func detach() {
        controller?.additionalSafeAreaInsets.top -= reservedHeight
        reservedHeight = 0
        bar.removeFromSuperview()
    }

    func layout() {
        guard let controller, let navigation, controller.isViewLoaded, navigation.isViewLoaded else { return }
        let host = controller.view!
        bar.topInset = navigation.view.safeAreaInsets.top
        bar.frame = CGRect(
            origin: host.bounds.origin,
            size: CGSize(width: host.bounds.width, height: bar.topInset + bar.contentHeight),
        )
        bar.setNeedsLayout()
    }
}

// MARK: - TelegramClassicNavigationChrome

@MainActor final class TelegramClassicNavigationChrome: UIView {
    var onBack: (() -> Void)?
    var onHeightChange: (() -> Void)?
    var topInset: CGFloat = 0

    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let separator = UIView()
    /// `UINavigationItem.prompt` (Reconnecting…, Saving…): a line above the title row, 30 pt like the system bar's.
    private let promptLabel = UILabel()
    private let titleLabel = UILabel()
    /// `UINavigationItem.subtitle` under the title, as Telegram's CounterControllerTitle shows a picker's count.
    private let subtitleLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private var leftViews = [UIView]()
    private var rightViews = [UIView]()
    private var items = [UIBarButtonItem]()
    private weak var customTitle: UIView?
    private weak var searchController: UISearchController?
    private var searchView: ChatListNavigationSearchView?
    private var searchEndSubscription: AnyCancellable?
    private var searchActive = false

    var contentHeight: CGFloat { promptHeight + 44 + (searchView != nil && !searchActive ? 44 : 0) }

    private var promptHeight: CGFloat { promptLabel.text?.isEmpty == false ? 30 : 0 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(background)
        separator.backgroundColor = .separator
        addSubview(separator)
        promptLabel.font = .preferredFont(forTextStyle: .footnote)
        promptLabel.adjustsFontForContentSizeCategory = true
        promptLabel.textColor = .secondaryLabel
        promptLabel.textAlignment = .center
        promptLabel.lineBreakMode = .byTruncatingTail
        addSubview(promptLabel)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        addSubview(titleLabel)
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.isHidden = true
        addSubview(subtitleLabel)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.addTarget(self, action: #selector(backPressed), for: .touchUpInside)
        addSubview(backButton)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        separator.frame = CGRect(
            x: 0,
            y: bounds.maxY - 1 / traitCollection.displayScale,
            width: bounds.width,
            height: 1 / traitCollection.displayScale,
        )
        promptLabel.frame = CGRect(x: 16, y: topInset, width: max(0, bounds.width - 32), height: promptHeight)
        let rowY = topInset + promptHeight
        backButton.frame = CGRect(x: 2, y: rowY, width: 44, height: 44)
        var left: CGFloat = backButton.isHidden ? 6 : 46
        for control in leftViews {
            let width = max(44, control.sizeThatFits(CGSize(width: bounds.width / 3, height: 44)).width + 12)
            control.frame = CGRect(x: left, y: rowY, width: width, height: 44)
            left += width
        }
        var right = bounds.width - 6
        for control in rightViews {
            let width = max(44, control.sizeThatFits(CGSize(width: bounds.width / 3, height: 44)).width + 12)
            right -= width
            control.frame = CGRect(x: right, y: rowY, width: width, height: 44)
        }
        let inset = max(left, bounds.width - right) + 8
        let titleFrame = CGRect(x: inset, y: rowY, width: max(0, bounds.width - 2 * inset), height: 44)
        if subtitleLabel.isHidden {
            titleLabel.frame = titleFrame
        } else {
            titleLabel.frame = CGRect(x: titleFrame.minX, y: rowY + 3, width: titleFrame.width, height: 22)
            subtitleLabel.frame = CGRect(x: titleFrame.minX, y: rowY + 24, width: titleFrame.width, height: 16)
        }
        customTitle?.frame = titleFrame
        for item in [titleLabel, subtitleLabel, backButton] + leftViews + rightViews + [customTitle]
            .compactMap(\.self)
        {
            item.alpha = searchActive
                ? 0
                : 1
        }
        searchView?.frame = CGRect(x: 0, y: rowY + (searchActive ? 0 : 44), width: bounds.width, height: 44)
    }

    func configure(
        item: UINavigationItem, fallbackTitle: String?, showsBack: Bool,
        searchController newSearch: UISearchController?,
    ) {
        titleLabel.text = item.title ?? fallbackTitle
        subtitleLabel.text = item.subtitle
        subtitleLabel.isHidden = item.subtitle?.isEmpty != false || item.titleView != nil
        setNeedsLayout()
        if promptLabel.text != item.prompt {
            promptLabel.text = item.prompt
            if let prompt = item.prompt, !prompt.isEmpty {
                UIAccessibility.post(notification: .announcement, argument: prompt)
            }
        }
        backButton.accessibilityLabel = L10n.telegram("Common.Back")
        let left = item.leftBarButtonItems ?? []
        let right = item.rightBarButtonItems ?? []
        backButton.isHidden = !showsBack || item.hidesBackButton || !left.isEmpty || searchActive
        (leftViews + rightViews).forEach { $0.removeFromSuperview() }
        items = left + right
        leftViews = left.map(makeButton)
        rightViews = right.map(makeButton)
        (leftViews + rightViews).forEach { addSubview($0) }
        if customTitle !== item.titleView {
            customTitle?.removeFromSuperview()
            customTitle = item.titleView
            if let customTitle { addSubview(customTitle) }
        }
        titleLabel.isHidden = customTitle != nil
        if searchController !== newSearch {
            searchView?.removeFromSuperview()
            searchEndSubscription = nil
            searchController = newSearch
            searchActive = false
            if let search = newSearch {
                let field = ChatListNavigationSearchView(placeholder: search.searchBar.placeholder ?? L10n
                    .telegram("Common.Search"))
                field.onQueryChange = { [weak search] query in
                    guard let search else { return }
                    search.searchBar.text = query
                    search.searchResultsUpdater?.updateSearchResults(for: search)
                }
                field.onActiveChange = { [weak self] active in
                    guard let self else { return }
                    searchActive = active
                    onHeightChange?()
                }
                searchEndSubscription = NotificationCenter.default
                    .publisher(for: .telegramNavigationSearchEnd, object: search)
                    .sink { [weak field] _ in field?.endSearch() }
                addSubview(field)
                searchView = field
            } else { searchView = nil }
        }
        if let search = newSearch {
            searchView?.setPlaceholder(search.searchBar.placeholder ?? L10n.telegram("Common.Search"))
        }
        setNeedsLayout()
    }

    private func makeButton(_ item: UIBarButtonItem) -> UIView {
        if let custom = item.customView {
            if let control = custom as? UIControl { control.isEnabled = item.isEnabled }
            return custom
        }
        let button = UIButton(type: .system)
        // An item made from a UIAction keeps its title and image there and runs it instead of a target-action.
        let primaryAction = item.primaryAction
        let title = [item.title, primaryAction?.title].compactMap(\.self).first { !$0.isEmpty }
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: item.style == .prominent ? .semibold : .regular)
        button.setImage(item.image ?? primaryAction?.image, for: .normal)
        button.setPreferredSymbolConfiguration(.init(pointSize: 18, weight: .medium), forImageIn: .normal)
        button.accessibilityLabel = item.accessibilityLabel ?? title
        button.accessibilityIdentifier = item.accessibilityIdentifier
        button.accessibilityHint = item.accessibilityHint
        button.isEnabled = item.isEnabled
        button.tintColor = item.tintColor ?? .systemBlue
        button.menu = item.menu
        button.showsMenuAsPrimaryAction = item.menu != nil
        button.addAction(UIAction { [weak item] _ in
            guard let item, item.isEnabled else { return }
            if let primaryAction = item.primaryAction {
                primaryAction.performWithSender(item, target: nil)
                return
            }
            guard let action = item.action else { return }
            UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil)
        }, for: .touchUpInside)
        return button
    }

    @objc private func backPressed() { onBack?() }
}

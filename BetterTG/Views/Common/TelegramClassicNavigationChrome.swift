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

// MARK: - TelegramConditionalNavigationSearchProvider

/// A screen whose search field shows only at times, as Telegram shows AttachmentFileController's search button once
/// there are more than ten recent files. The screen asks TelegramNavigationController.refreshChrome(of:) when it
/// changes.
@MainActor protocol TelegramConditionalNavigationSearchProvider: AnyObject {
    var shownTelegramNavigationSearch: UISearchController? { get }
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

    /// A sheet has no status bar above its bar; its row keeps the 10 pt UIKit leaves under it above it too.
    private var sheetTopInset: CGFloat {
        guard let navigation, navigation.sheetPresentationController != nil,
              navigation.presentingViewController != nil, navigation.view.safeAreaInsets.top < 1
        else { return 0 }
        return TelegramGlassPlatter.barBottomInset
    }

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
            searchController: (controller as? TelegramNavigationSearchProvider)?.telegramNavigationSearch
                ?? (controller as? TelegramConditionalNavigationSearchProvider)?.shownTelegramNavigationSearch,
        )
        if navigation.isViewLoaded { layout() }
    }

    func detach() {
        controller?.additionalSafeAreaInsets.top -= reservedHeight
        reservedHeight = 0
        bar.removeFromSuperview()
        bar.columnView.removeFromSuperview()
    }

    func layout() {
        guard let controller, let navigation, controller.isViewLoaded, navigation.isViewLoaded else { return }
        // A retained screen can acquire its chrome before its new sheet is presented. Reserve the current
        // sheet padding during layout too, when presentation and safe-area changes first become visible.
        let height = bar.contentHeight + sheetTopInset
        if reservedHeight != height {
            let difference = height - reservedHeight
            reservedHeight = height
            controller.additionalSafeAreaInsets.top += difference
        }
        let host = controller.view!
        // UITableView inserts section headers after this overlay while scrolling. zPosition keeps the bar
        // visible, but hit testing follows the UIView order and would otherwise reach a header behind it.
        host.bringSubviewToFront(bar)
        let duoLayout = navigation.view.iPhoneDuoLayout
        bar.sideColumn = duoLayout?.sideColumn
        if duoLayout?.sideColumn != nil {
            if bar.columnView.superview !== host { host.addSubview(bar.columnView) }
            bar.columnView.frame = CGRect(origin: host.bounds.origin, size: host.bounds.size)
            host.bringSubviewToFront(bar.columnView)
        } else {
            bar.columnView.removeFromSuperview()
        }
        bar.trailingButtonsInset = duoLayout?.trailingButtonsInset ?? 0
        bar.topInset = navigation.view.safeAreaInsets.top + sheetTopInset
        bar.frame = CGRect(
            origin: host.bounds.origin,
            size: CGSize(width: host.bounds.width, height: bar.topInset + bar.contentHeight),
        )
        bar.setNeedsLayout()
    }
}

// MARK: - TelegramSideColumnView

/// Takes touches only on the shapes of iPhone Duo's side column.
final class TelegramSideColumnView: UIView {
    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        subviews.contains { !$0.isHidden && $0.frame.contains(point) }
    }
}

// MARK: - TelegramClassicNavigationChrome

@MainActor final class TelegramClassicNavigationChrome: UIView {
    var onBack: (() -> Void)?
    var onHeightChange: (() -> Void)?
    var topInset: CGFloat = 0
    /// iPhone Duo's strip, where back and the icon buttons go instead of the row.
    var sideColumn: IPhoneDuoLayout.SideColumn?
    /// Holds the column's shapes over the screen, as the bar is only as tall as its row.
    let columnView = TelegramSideColumnView()
    /// iPhone Duo's status island beside the row.
    var trailingButtonsInset: CGFloat = 0

    private let background = TelegramBarBackgroundView(edge: .top)
    /// `UINavigationItem.prompt` (Reconnecting…, Saving…): a line above the title row, 30 pt like the system bar's.
    private let promptLabel = UILabel()
    private let titleLabel = UILabel()
    /// `UINavigationItem.subtitle` under the title, as Telegram's CounterControllerTitle shows a picker's count.
    private let subtitleLabel = UILabel()
    private let backButton = UIButton.telegramGlassIcon(UIImage(systemName: "chevron.left"))
    /// The back button and the left items' first section share the leading platter; the other left sections and the
    /// right items form UIKit's sections.
    private let leadingPlatter = TelegramGlassPlatter(role: .leading)
    private var leadingSectionPlatters = [TelegramGlassPlatter]()
    private var trailingPlatters = [TelegramGlassPlatter]()
    private var leftViews = [UIView]()
    private var rightViews = [UIView]()
    private var items = [UIBarButtonItem]()
    private weak var customTitle: UIView?
    private weak var searchController: UISearchController?
    private var searchView: ChatListNavigationSearchView?
    private var searchEndSubscription: AnyCancellable?
    private var searchActive = false

    var contentHeight: CGFloat {
        if searchView != nil, searchActive { return promptHeight + ChatListNavigationSearchView.contentHeight }
        return promptHeight + 44
            + (searchView != nil ? ChatListNavigationSearchView.contentHeight : TelegramGlassPlatter.barBottomInset)
    }

    /// The bar's glass platters for the push and pop morph, leading first.
    var glassPlatters: [TelegramGlassPlatter] { [leadingPlatter] + leadingSectionPlatters + trailingPlatters }

    private var promptHeight: CGFloat { promptLabel.text?.isEmpty == false ? 30 : 0 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(background)
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
        backButton.addTarget(self, action: #selector(backPressed), for: .touchUpInside)
        let backHold = UILongPressGestureRecognizer(target: self, action: #selector(backLongPressed(_:)))
        backHold.minimumPressDuration = 0.4
        backButton.addGestureRecognizer(backHold)
        leadingPlatter.translatesAutoresizingMaskIntoConstraints = true
        addSubview(leadingPlatter)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        promptLabel.frame = CGRect(x: 16, y: topInset, width: max(0, bounds.width - 32), height: promptHeight)
        let rowY = topInset + promptHeight
        let edge = TelegramGlassPlatter.edgeInset
        // The system's bar keeps a text button against the band beside its vertical bar.
        let rightEdge = sideColumn == nil ? edge + trailingButtonsInset : 0
        var columnY = sideColumn?.minY ?? 0
        // Puts the platter in the side column if it goes there.
        func placeInColumn(_ platter: TelegramGlassPlatter) -> Bool {
            guard let sideColumn, platter.fitsSideColumn else {
                platter.isInSideColumn = false
                if platter.superview !== self { addSubview(platter) }
                return false
            }
            platter.isInSideColumn = true
            if platter.superview !== columnView { columnView.addSubview(platter) }
            platter.frame = CGRect(
                x: sideColumn.x,
                y: columnY,
                width: IPhoneDuoLayout.Metrics.columnWidth,
                height: platter.columnLength,
            )
            columnY += platter.columnLength + IPhoneDuoLayout.Metrics.columnSpacing
            return true
        }
        var left = safeAreaInsets.left + edge
        for platter in [leadingPlatter] + leadingSectionPlatters where platter.hasVisibleItems {
            if placeInColumn(platter) { continue }
            if left > safeAreaInsets.left + edge { left += TelegramGlassPlatter.interSectionSpacing }
            let width = platter.preferredWidth
            platter.frame = CGRect(x: left, y: rowY, width: width, height: TelegramGlassPlatter.height)
            left += width
        }
        var right = bounds.width - safeAreaInsets.right - rightEdge
        for platter in trailingPlatters where platter.hasVisibleItems {
            if placeInColumn(platter) { continue }
            let width = platter.preferredWidth
            right -= width
            platter.frame = CGRect(x: right, y: rowY, width: width, height: TelegramGlassPlatter.height)
            right -= TelegramGlassPlatter.interSectionSpacing
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
        for item in [titleLabel, subtitleLabel] + glassPlatters + [customTitle].compactMap(\.self) {
            item.alpha = searchActive
                ? 0
                : 1
        }
        // The search keeps to the band, and clear of the status island beside it.
        let searchInsets = (left: safeAreaInsets.left, right: safeAreaInsets.right + trailingButtonsInset)
        searchView?.frame = CGRect(
            x: searchInsets.left,
            y: rowY + (searchActive ? 0 : 44),
            width: bounds.width - searchInsets.left - searchInsets.right,
            height: ChatListNavigationSearchView.contentHeight,
        )
    }

    /// `-[UIBarButtonItem _requiresOwnSection]` (read on iOS 27): every text item and every prominent one, and any
    /// item that does not share its background.
    private static func requiresOwnSection(_ item: UIBarButtonItem) -> Bool {
        if item.style == .prominent || !item.sharesBackground { return true }
        guard item.customView == nil else { return false }
        let title = [item.title, item.primaryAction?.title].compactMap(\.self).first { !$0.isEmpty }
        return title != nil
    }

    /// UIKit's sections (`_addImplicitTopBarSectionsFromItems`): a text or prominent item takes a pill of its own,
    /// any other joins the current pill.
    private static func sections(of items: [(UIBarButtonItem, UIView)]) -> [[(UIBarButtonItem, UIView)]] {
        var sections = [[(UIBarButtonItem, UIView)]]()
        var current = [(UIBarButtonItem, UIView)]()
        for entry in items {
            if requiresOwnSection(entry.0) {
                if !current.isEmpty { sections.append(current) }
                current = []
                sections.append([entry])
            } else {
                current.append(entry)
            }
        }
        if !current.isEmpty { sections.append(current) }
        return sections
    }

    /// A prominent item's pill is glass in its tint, with the item drawn in white.
    /// A lone prominent item tints its pill, UIKit's accent capsule; any other pill is plain glass.
    private static func applyProminence(of section: [(UIBarButtonItem, UIView)], to platter: TelegramGlassPlatter) {
        let isProminent = section.count == 1 && section[0].0.style == .prominent
        if isProminent { (section[0].1 as? UIButton)?.tintColor = .white }
        let tint = isProminent ? section[0].0.tintColor ?? .systemBlue : nil
        guard (platter.glassView.effect as? UIGlassEffect)?.tintColor != tint else { return }
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        effect.tintColor = tint
        platter.glassView.effect = effect
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
        items = left + right
        leftViews = left.map(makeButton)
        rightViews = right.map(makeButton)
        // The left sections run from the edge inward; the first shares the back button's pill.
        let leftSections = Self.sections(of: Array(zip(left, leftViews)))
        leadingPlatter.setItems([backButton] + (leftSections.first?.map(\.1) ?? []))
        let leadingSections = Array(leftSections.dropFirst())
        leadingSectionPlatters = reusing(leadingSectionPlatters, count: leadingSections.count) { .leadingSection($0) }
        for (platter, section) in zip(leadingSectionPlatters, leadingSections) {
            platter.setItems(section.map(\.1))
            Self.applyProminence(of: section, to: platter)
        }
        // `rightBarButtonItems` lists the right items outermost first.
        let trailingSections = Self.sections(of: Array(zip(right, rightViews)))
        trailingPlatters = reusing(trailingPlatters, count: trailingSections.count) { .trailing($0) }
        for (platter, section) in zip(trailingPlatters, trailingSections) {
            // UIKit lays a section's items out leading to trailing.
            platter.setItems(section.reversed().map(\.1))
            Self.applyProminence(of: section, to: platter)
        }
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

    /// The platters for `count` sections: the ones there stay, so that one the push morph holds hidden remains the one
    /// on screen; missing ones are added and spare ones leave.
    private func reusing(
        _ platters: [TelegramGlassPlatter],
        count: Int,
        role: (Int) -> TelegramGlassPlatter.Role,
    ) -> [TelegramGlassPlatter] {
        for platter in platters.dropFirst(count) {
            platter.removeFromSuperview()
        }
        var result = Array(platters.prefix(count))
        while result.count < count {
            let platter = TelegramGlassPlatter(role: role(result.count))
            platter.translatesAutoresizingMaskIntoConstraints = true
            addSubview(platter)
            result.append(platter)
        }
        return result
    }

    private func makeButton(_ item: UIBarButtonItem) -> UIView {
        if let custom = item.customView {
            if let control = custom as? UIControl { control.isEnabled = item.isEnabled }
            item.telegramChromeView = custom
            return custom
        }
        // An item made from a UIAction keeps its title and image there and runs it instead of a target-action.
        let primaryAction = item.primaryAction
        let title = [item.title, primaryAction?.title].compactMap(\.self).first { !$0.isEmpty }
        let image = item.image ?? primaryAction?.image
        let button = UIButton.telegramGlassIcon(title == nil ? image : nil)
        if let title {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17, weight: item.style == .prominent ? .semibold : .medium)
        }
        button.accessibilityLabel = item.accessibilityLabel ?? title
        button.accessibilityIdentifier = item.accessibilityIdentifier
        button.accessibilityHint = item.accessibilityHint
        button.isEnabled = item.isEnabled
        button.tintColor = item.tintColor ?? .label
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
        item.telegramChromeView = button
        return button
    }

    @objc private func backPressed() { onBack?() }

    /// UIKit's back button menu: holding Back lists the screens under this one.
    @objc private func backLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !backButton.isHidden else { return }
        backButton.cancelTracking(with: nil)
        presentTelegramBackMenu(from: leadingPlatter, tracking: gesture)
    }
}

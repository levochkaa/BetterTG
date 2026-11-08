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

    /// Focuses the classic chrome's field for this controller, for a screen whose search opens from a button: the
    /// field shows once the screen's conditional search returns it, so this asks on the next turn of the main queue.
    /// The field's close button then tells the delegate `didDismissSearchController`.
    func beginTelegramNavigationSearch() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .telegramNavigationSearchBegin, object: self)
        }
    }
}

private extension Notification.Name {
    static let telegramNavigationSearchEnd = Self("telegramNavigationSearchEnd")
    static let telegramNavigationSearchBegin = Self("telegramNavigationSearchBegin")
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
            showsBack: navigation.viewControllers.first !== controller
                && !(controller.parent is MainTabsViewController)
                && (navigation as? TelegramNavigationController)?.isDetailPaneRoot(controller) != true,
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
        bar.topInset = navigation.view.safeAreaInsets.top + sheetTopInset
        bar.applyIPhoneDuoLayout(navigation.view.iPhoneDuoLayout, host: host)
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
    private typealias MorphShape = (frame: CGRect, items: TelegramGlassLoan)

    private struct RowCapture {
        let frame: CGRect
        let views: [(UIView, CGRect)]

        /// The items, out of their old glass now, in a stand-in for it for the morph to lend. The loan holds its home
        /// weakly: `homes` keeps it until the morph is done.
        @MainActor func shape(keeping homes: inout [UIView]) -> MorphShape {
            let home = UIView(frame: CGRect(origin: .zero, size: frame.size))
            homes.append(home)
            for (view, itemFrame) in views {
                view.removeFromSuperview()
                view.translatesAutoresizingMaskIntoConstraints = true
                view.isHidden = false
                view.alpha = 1
                home.addSubview(view)
                view.frame = itemFrame
            }
            return (frame, TelegramGlassLoan(views: views.map(\.0), home: home))
        }
    }

    var onBack: (() -> Void)?
    var onHeightChange: (() -> Void)?
    var topInset: CGFloat = 0
    /// iPhone Duo's strip, where back and the icon buttons go instead of the row.
    var sideColumn: IPhoneDuoLayout.SideColumn?
    /// Holds the column's shapes over the screen, as the bar is only as tall as its row.
    let columnView = TelegramSideColumnView()
    /// iPhone Duo's status island beside the row.
    var trailingButtonsInset: CGFloat = 0

    /// White bar buttons over a profile's colour cover (PeerInfoHeaderNode's navigation contents primary colour); nil
    /// gives the buttons back their own tints.
    var buttonTintOverride: UIColor? {
        didSet {
            guard buttonTintOverride != oldValue else { return }
            applyButtonTintOverride()
        }
    }

    /// White title and subtitle over a profile's colour cover (PeerInfoHeaderNode's navigation contents colours); nil
    /// keeps the label colours.
    var titleColorOverride: UIColor? {
        didSet {
            titleLabel.textColor = titleColorOverride ?? .label
            subtitleLabel.textColor = titleColorOverride?.withAlphaComponent(0.75) ?? .secondaryLabel
        }
    }

    /// How far the row stands from the top safe area beside the island, where the search under it starts below it.
    private var rowTopOffset: CGFloat = 0

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
    private var searchBeginSubscription: AnyCancellable?
    private var searchActive = false

    /// How much of the bar's background shows: a profile's colour cover fills the bar itself while it reaches the top,
    /// as PeerInfoHeaderNode's navigation background does.
    var backgroundAlpha: CGFloat {
        get { background.alpha }
        set { background.alpha = newValue }
    }

    var contentHeight: CGFloat {
        // An open search takes the row in its place, so the bar keeps the row's height.
        if searchView != nil, searchActive { return promptHeight + 44 + TelegramGlassPlatter.barBottomInset }
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
        let contentY = topInset + promptHeight
        let rowY = contentY + rowTopOffset
        let edge = TelegramGlassPlatter.edgeInset
        // The system's bar keeps a text button against the band beside its vertical bar, and its buttons against the
        // status island.
        let rightEdge = sideColumn != nil ? 0 : trailingButtonsInset > 0 ? trailingButtonsInset : edge
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
        // The title centres on the band, over the list: beside iPhone Duo's strip that isn't the screen's middle.
        // Beside
        // the island the buttons are so far from even that it centres between them.
        let titleCenter = trailingButtonsInset > 0
            ? (left + right) / 2
            : (safeAreaInsets.left + bounds.width - safeAreaInsets.right) / 2
        let titleHalfWidth = max(0, min(titleCenter - left, right - titleCenter) - 8)
        let titleFrame = CGRect(x: titleCenter - titleHalfWidth, y: rowY, width: titleHalfWidth * 2, height: 44)
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
        // The search keeps to the band. Under the row it starts below the status island and takes the band's whole
        // width; open, it takes the row, clear of the island.
        let searchInsets = (
            left: safeAreaInsets.left,
            right: safeAreaInsets.right + (searchActive ? trailingButtonsInset : 0),
        )
        searchView?.frame = CGRect(
            x: searchInsets.left,
            // Open, the field centres on the row, where the buttons it grew out of stood.
            y: searchActive ? rowY + 22 - ChatListNavigationSearchView.contentHeight / 2 : contentY + 44,
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

    private static func opensFromButton(_ search: UISearchController?) -> Bool {
        search?.delegate?.responds(to: #selector(UISearchControllerDelegate.didDismissSearchController(_:))) == true
    }

    /// Moves back and the icon buttons into iPhone Duo's strip over `host`, and the row clear of the status island.
    func applyIPhoneDuoLayout(_ layout: IPhoneDuoLayout?, host: UIView) {
        sideColumn = layout?.sideColumn
        trailingButtonsInset = layout?.trailingButtonsInset(rowTop: topInset) ?? 0
        rowTopOffset = layout?.rowTopOffset(safeTop: topInset) ?? 0
        if sideColumn != nil {
            if columnView.superview !== host { host.addSubview(columnView) }
            columnView.frame = host.bounds
            host.bringSubviewToFront(columnView)
        } else {
            columnView.removeFromSuperview()
        }
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
        // A search from a button morphs out of the row's glass and back into it, as the chat list's does.
        let opensButtonSearch = searchController !== newSearch && Self.opensFromButton(newSearch)
            && window != nil && !bounds.isEmpty
        let closingField = searchController !== newSearch && newSearch == nil && window != nil
            ? searchView.flatMap { $0.onClose == nil ? nil : $0 }
            : nil
        let rowBefore = opensButtonSearch ? rowShapes() : (leading: [RowCapture](), trailing: [RowCapture]())
        // A search that closed gives Back its place again in this pass.
        if searchController !== newSearch {
            if searchView !== closingField { searchView?.removeFromSuperview() }
            searchEndSubscription = nil
            searchBeginSubscription = nil
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
                searchBeginSubscription = NotificationCenter.default
                    .publisher(for: .telegramNavigationSearchBegin, object: search)
                    .sink { [weak field] _ in field?.focus() }
                addSubview(field)
                searchView = field
                // A search that opens from a button takes the row at once and stays open with the keyboard down,
                // as a chat's does, until its close button: the field clears as it would, then the screen hears
                // it's done.
                if Self.opensFromButton(search) {
                    field.followsFocus = false
                    field.onClose = { [weak field, weak search] in
                        guard let field, let search else { return }
                        field.restoreQuery("")
                        field.onQueryChange?("")
                        field.unfocus()
                        search.delegate?.didDismissSearchController?(search)
                    }
                    field.setPresented(true)
                }
            } else { searchView = nil }
        }
        backButton.accessibilityLabel = L10n.telegram("Common.Back")
        let left = item.leftBarButtonItems ?? []
        let right = item.rightBarButtonItems ?? []
        backButton.isHidden = !showsBack || item.hidesBackButton || !left.isEmpty || searchActive
        items = left + right
        leftViews = left.map(makeButton)
        rightViews = right.map(makeButton)
        applyButtonTintOverride()
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
        if let search = newSearch {
            searchView?.setPlaceholder(search.searchBar.placeholder ?? L10n.telegram("Common.Search"))
        }
        setNeedsLayout()
        if opensButtonSearch, let field = searchView {
            runOpenSearchMorph(from: rowBefore, field: field)
        } else if let closingField {
            runCloseSearchMorph(field: closingField)
        }
    }

    /// The override on Back and every item's button; without it, Back in the label colour and each item in its own
    /// tint, as `makeButton` gives them.
    private func applyButtonTintOverride() {
        backButton.tintColor = buttonTintOverride ?? .label
        for (item, view) in zip(items, leftViews + rightViews) {
            guard let button = view as? UIButton, item.style != .prominent else { continue }
            button.tintColor = buttonTintOverride ?? item.tintColor ?? .label
        }
    }

    /// The row's glass as it shows, in the bar's coordinates, leading first and the right sections outermost first,
    /// with the items it shows and where. The row is about to be rebuilt: its old items leave their glass and the morph
    /// carries them, live. Back stays in its glass, hidden, so a new one stands in for it.
    private func rowShapes() -> (leading: [RowCapture], trailing: [RowCapture]) {
        layoutIfNeeded()
        func capture(_ platter: TelegramGlassPlatter) -> RowCapture? {
            guard !platter.isHidden, !platter.isInSideColumn, platter.hasVisibleItems, platter.alpha > 0 else {
                return nil
            }
            let views = platter.visibleItems.map { view -> (UIView, CGRect) in
                guard view === backButton else { return (view, view.frame) }
                return (UIButton.telegramGlassIcon(UIImage(systemName: "chevron.left")), view.frame)
            }
            return RowCapture(frame: platter.convert(platter.bounds, to: self), views: views)
        }
        return (
            ([leadingPlatter] + leadingSectionPlatters).compactMap(capture),
            trailingPlatters.compactMap(capture),
        )
    }

    /// The live row's glass, for the closing morph to lend.
    private func liveRowShapes() -> (leading: [MorphShape], trailing: [MorphShape]) {
        func shape(of platter: TelegramGlassPlatter) -> MorphShape? {
            guard !platter.isHidden, !platter.isInSideColumn, platter.hasVisibleItems else { return nil }
            return (platter.convert(platter.bounds, to: self), TelegramGlassLoan(platter: platter))
        }
        return (
            ([leadingPlatter] + leadingSectionPlatters).compactMap(shape(of:)),
            trailingPlatters.compactMap(shape(of:)),
        )
    }

    /// TelegramNavigationBar's openButtonSearch: the innermost right section becomes the field, the others draw
    /// together into the close button, and the left glass goes.
    private func runOpenSearchMorph(
        from captured: (leading: [RowCapture], trailing: [RowCapture]),
        field: ChatListNavigationSearchView,
    ) {
        layoutIfNeeded()
        var homes = [UIView]()
        let row = (
            leading: captured.leading.map { $0.shape(keeping: &homes) },
            trailing: captured.trailing.map { $0.shape(keeping: &homes) },
        )
        let search = field.glassShapes(in: self)
        var shapes = [TelegramGlassInPlaceMorph.Shape]()
        let button = row.trailing.last
        shapes.append(.init(
            from: button?.frame,
            fromItems: button?.items,
            to: search[0].frame,
            toItems: search[0].items,
        ))
        let others = row.trailing.dropLast()
        for (index, shape) in others.enumerated() {
            shapes.append(.init(
                from: shape.frame,
                fromItems: shape.items,
                to: search[1].frame,
                toItems: index == 0 ? search[1].items : nil,
            ))
        }
        if others.isEmpty { shapes.append(.init(to: search[1].frame, toItems: search[1].items)) }
        for shape in row.leading {
            shapes.append(.init(from: shape.frame, fromItems: shape.items))
        }
        fadeTitle(from: 1, to: 0)
        TelegramGlassInPlaceMorph.run(
            in: self,
            shapes: shapes,
            spacing: TelegramGlassPlatter.interSectionSpacing,
            handOver: { field.setGlassHidden(true) },
            completion: {
                field.setGlassHidden(false)
                // The old items went back to their stand-ins, which go with them.
                withExtendedLifetime(homes) {}
            },
        )
    }

    /// The reverse: the field goes back into the innermost right section, the close button parts into the others,
    /// and the left glass comes back. The closed field stays until the morph has taken its content back.
    private func runCloseSearchMorph(field: ChatListNavigationSearchView) {
        layoutIfNeeded()
        let search = field.glassShapes(in: self)
        let row = liveRowShapes()
        var shapes = [TelegramGlassInPlaceMorph.Shape]()
        let button = row.trailing.last
        shapes.append(.init(
            from: search[0].frame,
            fromItems: search[0].items,
            to: button?.frame,
            toItems: button?.items,
        ))
        let others = row.trailing.dropLast()
        for (index, shape) in others.enumerated() {
            shapes.append(.init(
                from: search[1].frame,
                fromItems: index == 0 ? search[1].items : nil,
                to: shape.frame,
                toItems: shape.items,
            ))
        }
        if others.isEmpty { shapes.append(.init(from: search[1].frame, fromItems: search[1].items)) }
        for shape in row.leading {
            shapes.append(.init(to: shape.frame, toItems: shape.items))
        }
        let platters = glassPlatters
        fadeTitle(from: 0, to: 1)
        TelegramGlassInPlaceMorph.run(
            in: self,
            shapes: shapes,
            spacing: TelegramGlassPlatter.interSectionSpacing,
            handOver: {
                field.setGlassHidden(true)
                for platter in platters {
                    platter.glassView.isHidden = true
                }
            },
            completion: {
                for platter in platters {
                    platter.glassView.isHidden = false
                }
                field.removeFromSuperview()
            },
        )
    }

    private func fadeTitle(from start: CGFloat, to end: CGFloat) {
        let labels = [titleLabel, subtitleLabel] + [customTitle].compactMap(\.self)
        for label in labels {
            label.alpha = start
        }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            for label in labels {
                label.alpha = end
            }
        }
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

// MainTabsView.swift

import Combine
import UIKit

// MARK: - MainTab

enum MainTab: Int, CaseIterable {
    // Chats in the middle: the archive above it, or left of it along the bottom, and Settings below or right.
    case archive
    case chats
    case settings

    var title: String {
        switch self {
        case .chats: L10n.telegram("DialogList.Title")
        case .archive: L10n.telegram("ChatList.ArchiveAction")
        case .settings: L10n.telegram("Settings.Title")
        }
    }

    var image: UIImage? {
        switch self {
        case .chats: UIImage(systemName: "bubble.left.and.bubble.right.fill")
        case .archive: UIImage(systemName: "archivebox.fill")
        case .settings: UIImage(systemName: "gearshape.fill")
        }
    }
}

// MARK: - MainTabsViewController

/// Telegram's TabBarController at the root of the navigation stack: Chats, the archive and Settings each fill it in
/// turn, and every screen they open is pushed over it, tab bar and all. Along the bottom the bar floats over the tab's
/// content, which keeps its safe area clear of it; beside iPhone Duo's strip it stands at the strip's bottom, under
/// the screen's buttons.
final class MainTabsViewController: UIViewController, ClientRestorableNavigationEntry,
TelegramEmbeddedNavigationChrome {
    // MARK: Internal

    struct ClientRestorationState {
        let selectedTab: MainTab
    }

    // MARK: Internal

    override var childForStatusBarStyle: UIViewController? { selectedController }

    private(set) var chats: MainViewController

    private(set) var selectedTab = MainTab.chats

    // MARK: Private

    private let rootVM: RootVM
    private var archive: ArchiveViewController?
    private let settings = SettingsViewController()
    private var settingsChrome: TelegramNavigationChromeState?
    private let tabBar = MainTabBarView()
    /// Telegram hides the bar while a list edits, for its toolbar.
    private var isTabBarHidden = false
    /// Chats' and the archive's bars are built for BetterTG's Search Bar at Top as it was then.
    private let builtWithSearchField = BetterTGSettings.shared.searchBarAtTop
    private var cancellables = Set<AnyCancellable>()

    var navigationClientSource: TdUpdateSource? {
        chats.navigationClientSource
    }

    /// The tabs BetterTG's settings keep: Swiftgram's Hide Tab Bar leaves Chats alone, and each of the others can go.
    /// A hidden one opens from Chats' bar.
    private var tabs: [MainTab] {
        let settings = BetterTGSettings.shared
        return MainTab.allCases.filter { tab in
            switch tab {
            case .chats: true
            case .archive:
                !settings.hidesTabBar && settings.showsArchiveTab && (rootVM.archive != nil || archive != nil)
            case .settings: !settings.hidesTabBar && settings.showsSettingsTab
            }
        }
    }

    /// Chats alone needs no bar.
    private var isTabBarDisabled: Bool { tabs.count < 2 }

    private var selectedController: UIViewController {
        controller(for: selectedTab) ?? chats
    }

    init(
        rootVM: RootVM,
        chats: MainViewController? = nil,
        archive: ArchiveViewController? = nil,
        restoration: ClientRestorationState? = nil,
    ) {
        self.rootVM = rootVM
        self.chats = chats ?? MainViewController(rootVM: rootVM)
        self.archive = archive
        super.init(nibName: nil, bundle: nil)
        self.selectedTab = restoration?.selectedTab ?? .chats
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        tabBar.onSelect = { [weak self] index in
            guard let self, tabs.indices.contains(index) else { return }
            show(tabs[index])
        }
        tabBar.onReselect = { [weak self] index in
            guard let self, tabs.indices.contains(index) else { return }
            reselect(tabs[index])
        }
        tabBar.onHold = { [weak self] index, source, gesture in
            guard let self, tabs.indices.contains(index) else { return }
            switch tabs[index] {
            case .chats: chats.showFolderMenu(from: source, tracking: gesture, anchor: tabBar)
            case .settings: chats.showAccountSwitcher(from: source, tracking: gesture, anchor: tabBar)
            case .archive: break
            }
        }
        chats.onTabBarHiddenChange = { [weak self] hidden in self?.setTabBarHidden(hidden) }
        view.addSubview(tabBar)
        rootVM.$archive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.reloadTabs() }
            }
            .store(in: &cancellables)
        nc.publisher(&cancellables, for: .appLanguageChanged) { [weak self] _ in
            self?.reloadTabs()
        }
        BetterTGSettings.shared
            .changes
            .sink { [weak self] in
                guard let self else { return }
                if BetterTGSettings.shared.searchBarAtTop != builtWithSearchField {
                    rebuildForSearchMode()
                } else {
                    reloadTabs()
                }
            }
            .store(in: &cancellables)
        show(selectedTab, force: true)
        reloadTabs()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutTabBar()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        settingsChrome?.layout()
    }

    /// Shows Chats with its search open, as Telegram's quick action does.
    func activateChatsSearch() {
        show(.chats)
        chats.activateSearch()
    }

    func prepareReplacementForReadyClient(_ source: TdUpdateSource) -> PreparedClientNavigationReplacement? {
        guard let chatsPlan = chats.prepareReplacementForReadyClient(source) else { return nil }
        let archivePlan = archive?.prepareReplacementForReadyClient(source)
        let state = ClientRestorationState(selectedTab: selectedTab)
        let rootVM = rootVM
        return PreparedClientNavigationReplacement(
            preflight: { chatsPlan.canCommitReplacement() && archivePlan?.canCommitReplacement() != false },
            commit: {
                guard let chats = chatsPlan.commitReplacement() as? MainViewController else { return nil }
                let archive = archivePlan?.commitReplacement() as? ArchiveViewController
                return MainTabsViewController(rootVM: rootVM, chats: chats, archive: archive, restoration: state)
            },
        )
    }

    private func controller(for tab: MainTab) -> UIViewController? {
        switch tab {
        case .chats: return chats
        case .settings: return settings
        case .archive:
            if archive == nil, let folder = rootVM.archive {
                archive = ArchiveViewController(folder: folder, rootVM: rootVM, isTabRoot: true)
            }
            archive?.onTabBarHiddenChange = { [weak self] hidden in self?.setTabBarHidden(hidden) }
            return archive
        }
    }

    private func reloadTabs() {
        let tabs = tabs
        if !tabs.contains(selectedTab) { show(.chats) }
        tabBar.configure(
            items: tabs.map { MainTabBarView.Item(title: $0.title, image: $0.image) },
            selectedIndex: tabs.firstIndex(of: selectedTab) ?? 0,
        )
        tabBar.holdableIndices = Set([MainTab.chats, .settings].compactMap { tabs.firstIndex(of: $0) })
        tabBar.showsTitles = BetterTGSettings.shared.showsTabNames
        chats.setTabShortcuts(
            archive: !tabs.contains(.archive) && rootVM.archive != nil,
            settings: !tabs.contains(.settings),
        )
        view.setNeedsLayout()
    }

    /// Search Bar at Top changed: new tabs take this one's place under whatever is pushed over it, on the same tab,
    /// with Chats' and the archive's bars built for the new search.
    private func rebuildForSearchMode() {
        guard let navigation = navigationController,
              let index = navigation.viewControllers.firstIndex(where: { $0 === self })
        else { return }
        let replacement = MainTabsViewController(
            rootVM: rootVM,
            restoration: ClientRestorationState(selectedTab: selectedTab),
        )
        var controllers = navigation.viewControllers
        controllers[index] = replacement
        navigation.setViewControllers(controllers, animated: false)
    }

    private func reselect(_ tab: MainTab) {
        switch tab {
        case .chats: chats.scrollCurrentFolderToTop()
        case .archive: archive?.scrollToTop()
        case .settings: settings.tableView.setContentOffset(
                CGPoint(x: 0, y: -settings.tableView.adjustedContentInset.top),
                animated: true,
            )
        }
    }

    private func show(_ tab: MainTab, force: Bool = false) {
        guard force || tab != selectedTab, let next = controller(for: tab) else { return }
        let previous = force ? nil : selectedController
        // The outgoing tab's glass, measured while its bar is still on screen.
        let outgoingPlatters = previous == nil ? [] : telegramGlassPlatters
        selectedTab = tab
        if next.parent !== self {
            addChild(next)
            next.view.frame = view.bounds
            next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.insertSubview(next.view, belowSubview: tabBar)
            next.didMove(toParent: self)
        }
        if next === settings, settingsChrome == nil, let navigation = navigationController {
            settingsChrome = TelegramNavigationChromeState(controller: settings, navigation: navigation)
        }
        settingsChrome?.refresh()
        tabBar.select(tabs.firstIndex(of: tab) ?? 0, animated: true)
        layoutTabBar()
        setNeedsStatusBarAppearanceUpdate()
        guard let previous, previous !== next else { return }
        // The bars' glass morphs from the outgoing tab's to the incoming one's while both are still in place, as
        // UIKit's
        // tab bar controller morphs its children's bars.
        next.view.layoutIfNeeded()
        TelegramGlassNavigationMorph.runInPlace(
            in: view,
            from: outgoingPlatters,
            to: telegramGlassPlatters,
            destinationView: next.view,
        )
        previous.willMove(toParent: nil)
        previous.view.removeFromSuperview()
        previous.removeFromParent()
    }

    private func setTabBarHidden(_ hidden: Bool) {
        guard hidden != isTabBarHidden else { return }
        isTabBarHidden = hidden
        tabBar.isUserInteractionEnabled = !hidden
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState]) {
            self.tabBar.alpha = hidden ? 0 : 1
        }
        layoutTabBar()
    }

    /// Telegram's TabBarControllerNode: along the bottom 20 pt from the sides and over the home indicator (8 pt
    /// without one), with names, or only icons in a split's list pane; standing in iPhone Duo's strip without them.
    private func layoutTabBar() {
        let count = tabs.count
        let bounds = view.bounds
        let duoLayout = view.iPhoneDuoLayout
        let verticalSize = MainTabBarView.size(axis: .vertical, isCompact: true, count: count, availableLength: 0)
        var reserved: CGFloat = 0
        tabBar.isHidden = isTabBarDisabled
        if isTabBarDisabled {
            // Swiftgram's Hide Tab Bar: the content takes the bottom, less the editing list's toolbar.
            chats.setStandingTabBar(false)
            let reserved = isTabBarHidden ? ChatListSelectionToolbar.contentHeight : 0
            for controller in [chats, archive, settings].compactMap(\.self)
                where controller.additionalSafeAreaInsets.bottom != reserved
            {
                controller.additionalSafeAreaInsets.bottom = reserved
            }
            return
        }
        if let frame = duoLayout?.tabBarFrame(size: verticalSize) {
            tabBar.setAxis(.vertical, isCompact: true)
            tabBar.frame = frame
        } else {
            let isCompact = NavigationStorage.shared.splitController.isSplit
            tabBar.setAxis(.horizontal, isCompact: isCompact)
            let safe = view.safeAreaInsets
            let margin = MainTabBarView.Metrics.sideMargin
            let available = bounds.width - safe.left - safe.right - margin * 2
            let size = MainTabBarView.size(
                axis: .horizontal,
                isCompact: isCompact,
                count: count,
                availableLength: available,
                showsTitles: BetterTGSettings.shared.showsTabNames,
                isWide: BetterTGSettings.shared.wideTabBar,
            )
            let bottom = MainTabBarView.Metrics
                .bottomMargin(safeBottom: view.window?.safeAreaInsets.bottom ?? safe.bottom)
            tabBar.frame = CGRect(
                x: safe.left + margin + (available - size.width) / 2,
                y: bounds.height - bottom - size.height,
                width: size.width,
                height: size.height,
            )
            // The tab's content keeps 4 pt clear of the bar's top; while the list edits, its toolbar takes the bar's
            // place.
            reserved = max(0, bounds.height - tabBar.frame.minY + 4 - safe.bottom)
        }
        if isTabBarHidden, tabBar.axis == .vertical { reserved = ChatListSelectionToolbar.contentHeight }
        for controller in [chats, archive, settings].compactMap(\.self)
            where controller.additionalSafeAreaInsets.bottom != reserved
        {
            controller.additionalSafeAreaInsets.bottom = reserved
        }
        chats.setStandingTabBar(tabBar.axis == .vertical && !isTabBarHidden)
    }
}

// MARK: TelegramGlassPlatterHost

extension MainTabsViewController: TelegramGlassPlatterHost {
    var telegramGlassPlatters: [TelegramGlassPlatter] {
        switch selectedTab {
        case .chats: chats.telegramGlassPlatters
        case .archive: archive?.telegramGlassPlatters ?? []
        case .settings: settingsChrome?.bar.glassPlatters ?? []
        }
    }
}

// MARK: TelegramBackMenuTitled

extension MainTabsViewController: TelegramBackMenuTitled {
    var telegramBackMenuTitle: String? { selectedTab.title }
}

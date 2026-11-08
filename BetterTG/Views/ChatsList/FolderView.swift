// FolderView.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ArchiveViewController

final class ArchiveViewController: UIViewController, ClientRestorableNavigationEntry {
    struct ClientRestorationState {
        let query: String
        let searchWasFocused: Bool
        let viewport: ChatListViewportSnapshot
    }

    /// Telegram hides the tab bar while the list edits, for its toolbar.
    var onTabBarHiddenChange: ((Bool) -> Void)?

    // MARK: Private

    private let rootVM: RootVM
    private let actionAuthority = ChatListActionAuthority()
    private var folderController: FolderViewController
    private let navigationBarView: TelegramListNavigationBar
    private lazy var searchResultsController = ChatListSearchResultsViewController(
        rootVM: rootVM,
        chatList: .chatListArchive,
        actionAuthority: actionAuthority,
    )
    /// A non-empty query shows TDLib results over the archive, as Telegram's search container does.
    private var isShowingSearchResults = false
    private var navigationBarHeightConstraint: NSLayoutConstraint!
    private var cancellables = Set<AnyCancellable>()
    private var query: String
    private var restoresSearchFocus: Bool
    private var isRestoringSearchFocus = false
    /// BetterTG's Search Bar at Top, read once: the bar is built for one or the other.
    private let usesSearchField = BetterTGSettings.shared.searchBarAtTop
    private lazy var navigationContentHeight = usesSearchField
        ? TelegramListNavigationBar.expandedContentHeight
        : TelegramListNavigationBar.rowContentHeight

    /// Whether the archive is a tab of the root, with no back button.
    private let isTabRoot: Bool

    /// ChatListController's archive stories: the hidden posters (storyListArchive), collapsed beside the title and
    /// pulled down into the row as in Chats, with no My Story.
    private let storySubscriptions = StorySubscriptions(isArchive: true)
    private var storyPeers = [Int64: SettingsPeer]()
    private var storyTitles = [Int64: String]()
    private let storyRowView = StoryPeerListExpandedView()
    /// Ends the list's selection while it lasts.
    private var editingDone: (() -> Void)?
    private var storyPeerTask: Task<Void, Never>?

    var navigationClientSource: TdUpdateSource? { actionAuthority.scope(owner: self).source }

    /// The archive's posters, none under BetterTG's Hide Stories.
    private var shownStoryEntries: [StorySubscriptions.Entry] {
        BetterTGSettings.shared.hidesStories ? [] : storySubscriptions.entries
    }

    init(folder: CustomFolder, rootVM: RootVM, isTabRoot: Bool = false, restoration: ClientRestorationState? = nil) {
        self.rootVM = rootVM
        self.isTabRoot = isTabRoot
        self.query = restoration?.query ?? ""
        self.restoresSearchFocus = restoration?.searchWasFocused ?? false
        self.folderController = FolderViewController(
            folder: folder, rootVM: rootVM, showsStandaloneSearch: true,
            usesSearchField: BetterTGSettings.shared.searchBarAtTop,
            actionAuthority: actionAuthority, restorationViewport: restoration?.viewport,
        )
        folderController.setSearchActive(
            restoration?.searchWasFocused ?? false,
            animated: false,
            preservingViewport: true,
        )
        var openMoreMenu: (() -> Void)?
        var editPressed: (() -> Void)?
        // As a tab the archive leads with Chats' Edit; pushed, with Back.
        self.navigationBarView = TelegramListNavigationBar(
            title: folder.name,
            placeholder: L10n.betterTG("Folders.SearchIn", folder.name.lowercased()),
            leftImage: isTabRoot ? UIBarButtonItem.editImage : UIImage(systemName: "chevron.left"),
            rightImage: UIImage(systemName: "ellipsis"),
            leftAction: isTabRoot ? { editPressed?() } : { NavigationStorage.shared.pop() },
            rightAction: { openMoreMenu?() },
            showsBackButton: !isTabRoot,
            leftAccessibilityLabel: isTabRoot ? L10n.telegram("Common.Edit") : nil,
            rightAccessibilityLabel: L10n.telegram("Common.More"),
            opensSearchFromButton: !BetterTGSettings.shared.searchBarAtTop,
        )
        super.init(nibName: nil, bundle: nil)
        // The name the back button's history menu shows for this folder.
        title = folder.name
        openMoreMenu = { [weak self] in self?.openArchiveMoreMenu() }
        editPressed = { [weak self] in self?.editPressed() }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        installFolderController()

        navigationBarView.translatesAutoresizingMaskIntoConstraints = false
        navigationBarView.restoreSearchQuery(query)
        navigationBarView.onQueryChange = { [weak self] query in
            guard let self else { return }
            self.query = query
            updateSearchResults(animated: true)
            scheduleRestorationRetry()
        }
        navigationBarView.onSearchActiveChange = { [weak self] active in
            guard let self else { return }
            folderController.setSearchActive(
                active, animated: !isRestoringSearchFocus, preservingViewport: isRestoringSearchFocus,
            )
            if usesSearchField, !active, isShowingSearchResults {
                // The query stays on screen above its results; the archive list restored its own offset.
                navigationBarView.applyScroll(offset: 0, animated: true)
            }
            scheduleRestorationRetry()
        }
        navigationBarView.onVisibleHeightChange = { [weak self] contentHeight in
            guard let self, usesSearchField else { return }
            navigationContentHeight = contentHeight
            navigationBarHeightConstraint?.constant = view.safeAreaInsets.top + contentHeight
            searchResultsController.topBarHeight = view.safeAreaInsets.top + contentHeight
        }
        TDLib.shared
            .chatListNetworkStatus
            .sink { [weak self] status in self?.navigationBarView.setNetworkStatus(status) }
            .store(in: &cancellables)
        view.addSubview(navigationBarView)
        navigationBarHeightConstraint = navigationBarView.heightAnchor.constraint(
            equalToConstant: view.safeAreaInsets.top + navigationContentHeight,
        )

        NSLayoutConstraint.activate([
            navigationBarView.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBarHeightConstraint,
        ])
        configureSearchResults()
        configureStories()
        rootVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.scheduleRestorationRetry() }
            .store(in: &cancellables)
        reloadFolderIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        navigationBarHeightConstraint?.constant = view.safeAreaInsets.top + navigationContentHeight
        searchResultsController.topBarHeight = view.safeAreaInsets.top + navigationContentHeight
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if actionAuthority.isCurrent, restoresSearchFocus {
            restoresSearchFocus = false
            isRestoringSearchFocus = true
            navigationBarView.focusSearch(animated: false)
            isRestoringSearchFocus = false
        }
        scheduleRestorationRetry()
    }

    /// A second tap on the Archive tab scrolls the list to its top.
    func scrollToTop() {
        folderController.scrollToTop()
    }

    func prepareReplacementForReadyClient(_ source: TdUpdateSource) -> PreparedClientNavigationReplacement? {
        guard canRestoreClient(source), let folder = rootVM.archive else { return nil }
        let isTabRoot = isTabRoot
        let state = ClientRestorationState(
            query: query,
            searchWasFocused: isViewLoaded ? navigationBarView.isSearchFocused : restoresSearchFocus,
            viewport: folderController.clientRestorationViewport(),
        )
        let rootVM = rootVM
        return PreparedClientNavigationReplacement(
            preflight: { [weak self] in
                self?.canRestoreClient(source) == true && rootVM.archive === folder
            },
            commit: {
                let replacement = ArchiveViewController(
                    folder: folder,
                    rootVM: rootVM,
                    isTabRoot: isTabRoot,
                    restoration: state,
                )
                #if DEBUG
                    log("Archive client restoration: replacement accepted; search-focus=\(state.searchWasFocused)")
                #endif
                return replacement
            },
        )
    }

    /// The archive's own items, Archive Settings and How Does It Work?, for its bar's menu and its tab's. `run` takes
    /// each choice, so the tab's menu can bring the archive up first.
    func archiveMenuActions(run: @escaping (@escaping () -> Void) -> Void) -> [TelegramContextMenuAction] {
        var actions = [TelegramContextMenuAction(
            title: L10n.telegram("ChatList.Archive.ContextSettings"),
            image: UIImage(systemName: "slider.horizontal.3"),
        ) { [weak self] in run { self?.openArchiveSettings() } }]
        if !folderController.isEmpty {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.Archive.ContextInfo"),
                image: UIImage(systemName: "questionmark.circle"),
            ) { [weak self] in run { self?.openArchiveInfo() } })
        }
        return actions
    }

    /// ChatListControllerImpl.openArchiveMoreMenu: Archive Settings, then How Does It Work? for an archive with chats,
    /// and Select Chats while the archive is pushed; as a tab it has Chats' Edit instead.
    private func openArchiveMoreMenu() {
        var actions = archiveMenuActions(run: { $0() })
        if !folderController.isEmpty, !isTabRoot {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.ContextSelectChats"),
                image: UIImage(systemName: "checkmark.circle"),
            ) { [weak self] in self?.folderController.beginEditing() })
        }
        presentTelegramContextMenu(
            sourceView: navigationBarView.rightButtonView,
            actions: actions,
            presentationStyle: .sourceMorph,
        )
    }

    private func openArchiveInfo() {
        let client = TDLib.shared.activeClient
        Task { [weak self] in
            let settings = try? await client.send(TDNativeRequests.getArchiveChatListSettings())
            guard let self, TDLib.shared.activeClient.id == client.id else { return }
            let info = ArchiveInfoViewController(
                keepsUnmutedArchived: settings?.keepUnmutedChatsArchived ?? false,
            ) { [weak self] in self?.openArchiveSettings() }
            present(info, animated: true)
        }
    }

    private func openArchiveSettings() {
        navigationController?.pushViewController(ArchiveSettingsViewController(), animated: true)
    }

    /// Chats' Edit: the list's selection, and Done ends it.
    private func editPressed() {
        if let editingDone {
            editingDone()
        } else {
            folderController.beginEditing()
        }
    }

    private func canRestoreClient(_ source: TdUpdateSource) -> Bool {
        source == TDLib.shared.activeUpdateSource
            && source.accountID == navigationClientSource?.accountID
            && source.accountID == rootVM.activeAccountID
            && !folderController.isInteractingWithList && !navigationBarView.hasMarkedText
            && !isBeingDismissed && !isMovingFromParent
    }

    private func scheduleRestorationRetry() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            reloadFolderIfNeeded()
            NavigationStorage.shared.retryClientRestoration()
        }
    }

    private func reloadFolderIfNeeded() {
        guard isViewLoaded, actionAuthority.isCurrent,
              !folderController.isInteractingWithList, !navigationBarView.hasMarkedText,
              let folder = rootVM.archive, folder !== folderController.folder
        else { return }
        let viewport = folderController.clientRestorationViewport()
        folderController.willMove(toParent: nil)
        folderController.view.removeFromSuperview()
        folderController.removeFromParent()
        folderController = FolderViewController(
            folder: folder, rootVM: rootVM, showsStandaloneSearch: true, usesSearchField: usesSearchField,
            actionAuthority: actionAuthority, restorationViewport: viewport,
        )
        folderController.setSearchActive(navigationBarView.isSearchActive, animated: false, preservingViewport: true)
        installFolderController()
        view.bringSubviewToFront(navigationBarView)
    }

    private func installFolderController() {
        folderController.isSearchActive = { [weak self] in self?.navigationBarView.isSearchActive == true }
        folderController.onSelectionEditingChange = { [weak self] title, done in
            guard let self else { return }
            editingDone = done
            let isTabRoot = isTabRoot
            let bar = navigationBarView
            bar.animateGlassChange {
                // As a tab the Edit turns into Done, as Chats' does; pushed, the bar shows its own Done.
                bar.setEditing(title: title, done: done, showsDone: !isTabRoot)
                if isTabRoot {
                    bar.setLeftIcon(
                        done == nil ? UIBarButtonItem.editImage : UIBarButtonItem.doneImage,
                        accessibilityLabel: L10n.telegram(done == nil ? "Common.Edit" : "Common.Done"),
                        isProminent: done != nil,
                    )
                }
            }
            onTabBarHiddenChange?(done != nil)
        }
        folderController.selectionToolbarTakesTabBarPlace = isTabRoot
        folderController.onSearchScrollOffsetChange = { [weak self] offset in
            guard let self, !isShowingSearchResults else { return }
            navigationBarView.applyScroll(offset: offset)
        }
        folderController.onListInteractionEnded = { [weak self] in self?.scheduleRestorationRetry() }
        folderController.storiesEnabled = { [weak self] in self?.storyRowView.items.isEmpty == false }
        folderController.onStoriesPull = { [weak self] pull in self?.applyStoriesPull(pull) }
        addChild(folderController)
        folderController.view.translatesAutoresizingMaskIntoConstraints = false
        // The list stays beneath search results and the navigation bar when it is replaced.
        view.insertSubview(folderController.view, at: 0)
        NSLayoutConstraint.activate([
            folderController.view.topAnchor.constraint(equalTo: view.topAnchor),
            folderController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            folderController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            folderController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        folderController.didMove(toParent: self)
    }

    private func configureStories() {
        let client = actionAuthority.client
        let source = TDLib.shared.activeUpdateSource
        storySubscriptions.onChange = { [weak self] in self?.updateStoryPeers() }
        nc.scopedPublisher(&cancellables, for: .updateChatActiveStories) { [weak self] event in
            guard let self, event.source == source, actionAuthority.isCurrent else { return }
            storySubscriptions.apply(event.value.activeStories)
        }
        BetterTGSettings.shared
            .changes
            .sink { [weak self] in self?.applyStoryPeers() }
            .store(in: &cancellables)
        navigationBarView.onStoriesTap = { [weak self] in self?.folderController.expandStories() }
        storyRowView.clipsToBounds = true
        storyRowView.isHidden = true
        storyRowView.onSelect = { [weak self] chatID, source in self?.openStories(from: chatID, sourceView: source) }
        storyRowView.onContextMenu = { [weak self] chatID, source, gesture in
            guard let self else { return }
            let authority = actionAuthority
            StoryRowMenu.present(
                chatID: chatID,
                source: source,
                gesture: gesture,
                from: self,
                client: authority.client,
                isCurrent: { authority.isCurrent },
            ) { [weak self] chatID in self?.openStories(from: chatID, sourceView: source) }
        }
        view.insertSubview(storyRowView, belowSubview: navigationBarView)
        storySubscriptions.load(client: client)
    }

    /// ChatListNavigationBar.applyScroll: the pull reveals the row under the bar and fades the title's posters.
    private func applyStoriesPull(_ pull: CGFloat) {
        guard folderController.isViewLoaded else { return }
        let bottom = folderController.hasSearchField
            ? view.safeAreaInsets.top + TelegramListNavigationBar.titleHeight + pull
            : folderController.view.convert(CGPoint(x: 0, y: folderController.storiesRegionBottom), to: view).y
        storyRowView.isHidden = pull <= 0
        storyRowView.frame = CGRect(x: 0, y: bottom - pull, width: view.bounds.width, height: pull)
        // Between the title and the search field the row stands over the bar, whose background grows behind it.
        if folderController.hasSearchField, pull > 0,
           let barIndex = view.subviews.firstIndex(of: navigationBarView),
           let rowIndex = view.subviews.firstIndex(of: storyRowView), rowIndex < barIndex
        {
            view.insertSubview(storyRowView, aboveSubview: navigationBarView)
        }
        let fraction = min(1, pull / StoryPeerListExpandedView.height)
        storyRowView.alpha = fraction
        navigationBarView.storiesView.alpha = 1 - fraction
    }

    private func updateStoryPeers() {
        let missing = storySubscriptions.entries.map(\.chatID).filter { storyPeers[$0] == nil }
        applyStoryPeers()
        guard !missing.isEmpty else { return }
        let client = actionAuthority.client
        storyPeerTask?.cancel()
        storyPeerTask = Task { [weak self] in
            var found = [Int64: SettingsPeer]()
            var titles = [Int64: String]()
            for chatID in missing {
                guard let chat = try? await client.getChat(chatId: chatID) else { continue }
                if case .chatTypePrivate(let user) = chat.type {
                    found[chatID] = await SettingsPeer.user(user.userId, client: client)
                    let person = try? await client.getUser(userId: user.userId)
                    titles[chatID] = person.map { $0.firstName.isEmpty ? $0.lastName : $0.firstName }
                } else {
                    found[chatID] = SettingsPeer(chat: chat)
                    titles[chatID] = chat.title
                }
            }
            guard let self, !Task.isCancelled, actionAuthority.isCurrent else { return }
            storyPeers.merge(found) { $1 }
            storyTitles.merge(titles) { $1 }
            applyStoryPeers()
        }
    }

    private func applyStoryPeers() {
        let entries = shownStoryEntries
        navigationBarView.storiesView.update(
            items: entries.prefix(3).compactMap { entry in
                storyPeers[entry.chatID].map { StoryPeerListCollapsedView.Item(peer: $0, ringStyle: entry.ringStyle) }
            },
            client: actionAuthority.client,
            accountID: TDLib.shared.activeAccountID,
        )
        navigationBarView.updateStories()
        storyRowView.update(
            items: entries.compactMap { entry in
                storyPeers[entry.chatID].map {
                    StoryPeerListExpandedView.Item(
                        chatID: entry.chatID,
                        peer: $0,
                        title: storyTitles[entry.chatID] ?? $0.title,
                        ringStyle: entry.ringStyle,
                    )
                }
            },
            client: actionAuthority.client,
            accountID: TDLib.shared.activeAccountID,
        )
    }

    /// ChatListController.openStories in the archive: a poster's stories, then the row's others.
    private func openStories(from chatID: Int64, sourceView: UIView) {
        StoryViewerController.present(
            .activeStories(chatIDs: shownStoryEntries.map(\.chatID), initialChatID: chatID),
            client: actionAuthority.client,
            from: self,
            sourceView: sourceView,
            sourceIsAvatar: true,
        )
    }

    private func configureSearchResults() {
        searchResultsController.chatMenu = { [weak self] chat in
            self?.folderController.searchResultMenu(for: chat) ?? []
        }
        addChild(searchResultsController)
        let resultsView = searchResultsController.view!
        resultsView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(resultsView, belowSubview: navigationBarView)
        searchResultsController.didMove(toParent: self)
        // The results fill the screen, under the bar and the keyboard, and inset their lists for both.
        NSLayoutConstraint.activate([
            resultsView.topAnchor.constraint(equalTo: view.topAnchor),
            resultsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        resultsView.alpha = 0
        resultsView.isHidden = true
        updateSearchResults(animated: false)
    }

    private func updateSearchResults(animated: Bool) {
        searchResultsController.updateQuery(query)
        let showsResults = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard showsResults != isShowingSearchResults else { return }
        isShowingSearchResults = showsResults
        let resultsView = searchResultsController.view!
        if showsResults {
            resultsView.isHidden = false
            if usesSearchField { navigationBarView.applyScroll(offset: 0, animated: animated) }
        } else if usesSearchField {
            navigationBarView.applyScroll(offset: folderController.searchScrollOffset, animated: animated)
        }
        guard animated else {
            resultsView.alpha = showsResults ? 1 : 0
            resultsView.isHidden = !showsResults
            return
        }
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: { resultsView.alpha = showsResults ? 1 : 0 },
        ) { _ in
            // A later query may have shown the results again.
            resultsView.isHidden = !self.isShowingSearchResults
        }
    }
}

// MARK: - ChatListViewportSnapshot

/// Stable row identity plus its viewport displacement. The fallback preserves
/// the list position if the row disappeared while TDLib was suspended.
struct ChatListViewportSnapshot {
    let chatID: Int64?
    let rowMinYRelativeToViewport: CGFloat
    let offsetFromTop: CGFloat

    @MainActor static func capture(
        tableView: UITableView,
        chatID: (IndexPath) -> Int64?,
    ) -> ChatListViewportSnapshot {
        let first = tableView.indexPathsForVisibleRows?.min()
        return ChatListViewportSnapshot(
            chatID: first.flatMap(chatID),
            rowMinYRelativeToViewport: first.map {
                tableView.rectForRow(at: $0).minY - tableView.contentOffset.y
            } ?? 0,
            offsetFromTop: tableView.contentOffset.y + tableView.adjustedContentInset.top,
        )
    }

    @MainActor func restore(
        tableView: UITableView,
        indexPath: (Int64) -> IndexPath?,
    ) {
        tableView.layoutIfNeeded()
        let insets = tableView.adjustedContentInset
        let minimum = -insets.top
        let maximum = max(minimum, tableView.contentSize.height - tableView.bounds.height + insets.bottom)
        let requested = chatID.flatMap(indexPath).map {
            tableView.rectForRow(at: $0).minY - rowMinYRelativeToViewport
        } ?? (minimum + offsetFromTop)
        tableView.setContentOffset(
            CGPoint(x: tableView.contentOffset.x, y: min(max(requested, minimum), maximum)),
            animated: false,
        )
    }
}

// MARK: - ChatListViewportRestoration

/// A diffable apply may finish after a newer query, another apply, or first layout.
/// Only the latest completed snapshot may consume a saved viewport, exactly once.
struct ChatListViewportRestoration {
    private(set) var pending: ChatListViewportSnapshot?

    private var latestApply: UUID?
    private var completedApply: UUID?

    var snapshotIsApplied: Bool { latestApply != nil && latestApply == completedApply }

    init(_ snapshot: ChatListViewportSnapshot?) {
        self.pending = snapshot
    }

    mutating func beginApply() -> UUID {
        let token = UUID()
        latestApply = token
        completedApply = nil
        return token
    }

    mutating func completeApply(_ token: UUID) {
        guard latestApply == token else { return }
        completedApply = token
    }

    mutating func takeForLayout(usable: Bool) -> ChatListViewportSnapshot? {
        guard snapshotIsApplied, usable else { return nil }
        defer { pending = nil }
        return pending
    }

    mutating func cancel() {
        pending = nil
    }
}

// MARK: - FolderViewController

final class FolderViewController: UITableViewController, UITableViewDataSourcePrefetching {
    // MARK: Private

    private enum Section {
        case main
    }

    /// What an empty page shows: Telegram's empty-folder text, or a loading list while it is not known yet.
    private enum EmptyState {
        case empty
        case loading
    }

    private struct VisibleRowAnchor {
        let id: Int64
        let minYRelativeToOffset: CGFloat
        let previousIndex: Int
        let nextIndex: Int
    }

    /// Moves rows only while the page reorders its pinned chats; the diffable source keeps its snapshot in step.
    private final class ChatRowsDataSource: UITableViewDiffableDataSource<Section, Int64> {
        var canMoveRow: ((IndexPath) -> Bool)?
        /// Rows that offer swipe actions; UIKit asks for them only on editable rows.
        var canSwipeRow: ((IndexPath) -> Bool)?
        /// The moved chat, the chat it was dropped onto, and whether it moved down.
        var didMoveRow: ((Int64, Int64, Bool) -> Void)?

        override func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
            canMoveRow?(indexPath) == true || canSwipeRow?(indexPath) == true
        }

        override func tableView(_: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
            canMoveRow?(indexPath) ?? false
        }

        override func tableView(
            _ tableView: UITableView,
            moveRowAt sourceIndexPath: IndexPath,
            to destinationIndexPath: IndexPath,
        ) {
            let movedID = itemIdentifier(for: sourceIndexPath)
            let referenceID = itemIdentifier(for: destinationIndexPath)
            super.tableView(tableView, moveRowAt: sourceIndexPath, to: destinationIndexPath)
            guard sourceIndexPath != destinationIndexPath, let movedID, let referenceID else { return }
            didMoveRow?(movedID, referenceID, sourceIndexPath.row < destinationIndexPath.row)
        }
    }

    /// Telegram's service notifications account, which Telegram never archives.
    private static let serviceNotificationsUserID: Int64 = 777_000

    // MARK: Internal

    let folder: CustomFolder
    var isSearchActive: (() -> Bool)?
    /// The main screen leaves a pan that starts near a side edge to folder paging, as Telegram's chat list does.
    var allowsRowSwipe: (() -> Bool)?
    var onListInteractionEnded: (() -> Void)?
    /// ChatListEmptyNode's Edit Folder in an empty folder of the user's.
    var onEditFolder: (() -> Void)?
    /// ChatListEmptyNode's New Message in an empty main list.
    var onNewMessage: (() -> Void)?
    /// The selection's title for the screen's bar and its Done, or nil and nil once selection ends.
    var onSelectionEditingChange: ((String?, (() -> Void)?) -> Void)?

    /// Where the selection toolbar goes: under the safe area, in the place of the hidden tab bar, rather than over it.
    var selectionToolbarTakesTabBarPlace = false

    /// BetterTG's Search Bar at Top: Telegram's search field under the bar, which the list scrolls away and back.
    var onSearchScrollOffsetChange: ((CGFloat) -> Void)?

    // MARK: Stories

    /// ChatListControllerNode's stories: a pull past the list's top that starts there shows them under the bar
    /// (`onStoriesPull`, the pull in points); past 65 pt they unlock (back under 61 pt they lock again, with
    /// Telegram's haptics) and a release while unlocked keeps them open on a 96 pt top inset (tempTopInset), which
    /// goes once the list scrolls 4 pt into its rows.
    var storiesEnabled: (() -> Bool)?
    var onStoriesPull: ((CGFloat) -> Void)?
    private(set) var storiesInset: CGFloat = 0
    private(set) var storiesUnlocked = false

    private let showsStandaloneSearch: Bool
    private let usesSearchField: Bool
    /// How far the field is scrolled away before the list is first laid out: all of it, as Telegram's list opens.
    private var initialSearchScrollOffset: CGFloat
    private var initialSearchScrollOffsetBeforeSearch: CGFloat?
    private let rootVM: RootVM
    private let actionAuthority: ChatListActionAuthority
    private var searchActive = false
    /// The height of the header panels under the navigation bar (the playback header), which the rows sit below.
    private var accessoryTopInset = CGFloat.zero
    /// The folder tabs' room at the bottom of a page of the chat list; none with the tabs at the top.
    private var accessoryBottomInset = FolderPickerView.barHeight
    private var didPlaceInitialViewport = false
    /// Where the page was before the shared search began. Search covers every page, as Telegram's search overlay
    /// does, and ending it returns each page there instead of scrolling it to the top with search revealed.
    private var viewportBeforeSearch: ChatListViewportSnapshot?
    private var clientViewportRestoration: ChatListViewportRestoration
    private var cancellables = Set<AnyCancellable>()
    private var prefetchTasks = [Int64: Task<Void, Never>]()
    private var chatsByID = [Int64: CustomChat]()
    private var pendingChangedChatIDs = Set<Int64>()
    private var chatUpdateScheduled = false
    private var indexedChatsGeneration: Int?
    private var didApplyFirstSnapshot = false
    private var isApplyingSnapshot = false
    private var snapshotNeedsApply = false
    private var pendingSnapshotAnimated = false
    private var pendingSnapshotChangedIDs = Set<Int64>()
    /// The last applied snapshot had no rows.
    private var showsNoRows = false
    private var emptyState: EmptyState?
    private var dataSource: ChatRowsDataSource!

    private var pressGesture: ContextMenuPressGestureRecognizer?
    private let pressGestureDelegate = ChatRowPressGestureDelegate()
    /// Telegram's reorder mode for pinned chats; list updates wait until it ends so a drag is never interrupted.
    private var isReorderingPinnedChats = false
    /// Telegram's chat selection (selectPeerThread); nil outside it.
    private var selectedChatIDs: Set<Int64>?
    private var selectionToolbar: ChatListSelectionToolbar?

    private var storiesDragStartedAtTop = false

    /// Whether the list shows no chats, as Telegram's `archiveChatList.items.isEmpty`.
    var isEmpty: Bool {
        dataSource?.snapshot().numberOfItems ?? 0 == 0
    }

    var isInteractingWithList: Bool {
        guard isViewLoaded else { return false }
        // A tracking-only touch has no terminal scroll callback to retry from.
        return tableView.isDragging || tableView.isDecelerating
    }

    // MARK: Chat selection

    /// Whether the list edits: Telegram's Edit, which selects chats and reorders the pinned ones.
    var isEditingList: Bool { selectedChatIDs != nil }

    /// The list's distance from its top up to the search field's height; negative while the list is pulled past its
    /// top, which the navigation bar follows. Zero without the field.
    var searchScrollOffset: CGFloat {
        guard usesSearchField else { return 0 }
        guard isViewLoaded, didPlaceInitialViewport else { return initialSearchScrollOffset }
        // Open stories stand between the title and the field: the field keeps their room under it.
        return min(
            ChatListNavigationSearchView.scrollHeight,
            tableView.contentOffset.y + tableView.adjustedContentInset.top - storiesInset,
        )
    }

    /// How far the list stands below its top without the stories.
    var storiesPull: CGFloat {
        guard isViewLoaded else { return 0 }
        return -(tableView.contentOffset.y + tableView.adjustedContentInset.top - storiesInset)
    }

    /// Whether the search field stands under the bar's title, the stories opening between them.
    var hasSearchField: Bool {
        usesSearchField
    }

    /// Where the rows start, in the view's coordinates; the stories show in the pull above it.
    var storiesRegionBottom: CGFloat {
        tableView.convert(CGPoint.zero, to: view).y
    }

    private var orderedChats: [CustomChat] {
        folder.chats.sortedByListOrder()
    }

    private var isArchivePage: Bool {
        if case .archive = folder.type { return true }
        return false
    }

    /// The screen that owns this page: overlays sit there, above the folder picker on the main list.
    /// The screen that holds this list: a tab keeps its overlays clear of the tab bar, as its safe area does.
    private var overlayHost: UIViewController {
        var host: UIViewController = self
        while let parent = host.parent, !(parent is UINavigationController), !(parent is MainTabsViewController) {
            host = parent
        }
        return host
    }

    private var overlayBottomInset: CGFloat {
        showsStandaloneSearch ? 12 : 64
    }

    /// TDLib's limit for pinned chats in this page's list.
    private var pinLimitType: TDNativePremiumLimitType {
        switch folder.type {
        case .main: .premiumLimitTypePinnedChatCount
        case .archive: .premiumLimitTypePinnedArchivedChatCount
        case .folder: .premiumLimitTypeChatFolderChosenChatCount
        }
    }

    /// `-ui-probe-empty-folder`: every chat list shows as empty.
    private var probesEmptyFolder: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-ui-probe-empty-folder")
        #else
            false
        #endif
    }

    /// The bar's content the rows start under: its row, and the search field while there is one.
    private var barContentHeight: CGFloat {
        guard usesSearchField else { return TelegramListNavigationBar.rowContentHeight }
        return searchActive
            ? ChatListNavigationSearchView.contentHeight
            : TelegramListNavigationBar.expandedContentHeight
    }

    private var allowsStories: Bool {
        searchActive != true && storiesEnabled?() == true
    }

    init(
        folder: CustomFolder,
        rootVM: RootVM,
        showsStandaloneSearch: Bool,
        usesSearchField: Bool = false,
        actionAuthority: ChatListActionAuthority? = nil,
        restorationViewport: ChatListViewportSnapshot? = nil,
    ) {
        self.folder = folder
        self.rootVM = rootVM
        self.actionAuthority = actionAuthority ?? ChatListActionAuthority()
        self.showsStandaloneSearch = showsStandaloneSearch
        self.usesSearchField = usesSearchField
        self.initialSearchScrollOffset = !usesSearchField
            ? 0
            : min(
                ChatListNavigationSearchView.scrollHeight,
                max(0, restorationViewport?.offsetFromTop ?? ChatListNavigationSearchView.scrollHeight),
            )
        self.clientViewportRestoration = ChatListViewportRestoration(restorationViewport)
        super.init(style: .plain)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        prefetchTasks.values.forEach { $0.cancel() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NavigationStorage.shared
            .splitSelectedChatID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateSplitSelection() }
            .store(in: &cancellables)
        view.backgroundColor = .systemGroupedBackground
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .none
        tableView.rowHeight = ChatListCell.cardRowHeight
        tableView.keyboardDismissMode = .interactive
        tableView.alwaysBounceVertical = true
        tableView.contentInset.top = barContentHeight + accessoryTopInset
        tableView.contentInset.bottom = showsStandaloneSearch ? 0 : accessoryBottomInset
        tableView.automaticallyAdjustsScrollIndicatorInsets = false
        tableView.prefetchDataSource = self
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseIdentifier)
        let pressGesture = ContextMenuPressGestureRecognizer(target: self, action: #selector(chatLongPressed(_:)))
        pressGesture.pressedViewProvider = { [weak self] gesture in
            guard let self,
                  let indexPath = tableView.indexPathForRow(at: gesture.location(in: tableView)),
                  let cell = tableView.cellForRow(at: indexPath) as? ChatListCell
            else { return nil }
            return cell.contextPreviewView
        }
        // An avatar with its own menu takes its long press; the row's press must not start under it too.
        pressGesture.delegate = pressGestureDelegate
        tableView.addGestureRecognizer(pressGesture)
        self.pressGesture = pressGesture
        configureDataSource()
        rebuildChatIndex()
        updateSnapshot(animated: false)
        startStateUpdates()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadMoreChatsIfNeeded()
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-ui-smoke-scroll-chats") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let top = -tableView.adjustedContentInset.top
            tableView.setContentOffset(CGPoint(x: 0, y: top + 30), animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                tableView.setContentOffset(CGPoint(x: 0, y: top + 300), animated: false)
            }
        }
        #endif
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        // What changed while the page was off screen is simply there when it shows.
        pendingSnapshotAnimated = false
        applyPendingSnapshot()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        endPinnedReorder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        (tableView.backgroundView as? ChatListEmptyView)?.insets = tableView.adjustedContentInset
        (tableView.backgroundView as? ChatListArchiveEmptyView)?.insets = tableView.adjustedContentInset
        updateIndicatorInsets()
        if snapshotNeedsApply, !isApplyingSnapshot, !isReorderingPinnedChats, view.window != nil {
            DispatchQueue.main.async { [weak self] in self?.applyPendingSnapshot() }
        }
        guard !didPlaceInitialViewport,
              clientViewportRestoration.snapshotIsApplied,
              tableView.bounds.width > 0, tableView.bounds.height > 0,
              dataSource.snapshot().numberOfItems == 0 || tableView.contentSize.height > 0
        else { return }
        didPlaceInitialViewport = true
        if let viewport = clientViewportRestoration.takeForLayout(usable: true) {
            viewport.restore(tableView: tableView) { dataSource.indexPath(for: $0) }
        } else {
            tableView.setContentOffset(
                CGPoint(x: 0, y: -tableView.adjustedContentInset.top + initialSearchScrollOffset),
                animated: false,
            )
        }
        if usesSearchField { onSearchScrollOffsetChange?(searchScrollOffset) }
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        if usesSearchField { onSearchScrollOffsetChange?(searchScrollOffset) }
        updateIndicatorInsets()
        updateStoriesPull()
    }

    /// A drag that ends with the field half shown settles it shown or hidden, as Telegram's list does.
    override func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity _: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>,
    ) {
        if scrollView === tableView, allowsStories, storiesDragStartedAtTop || storiesInset > 0 {
            settleStories(targetContentOffset)
            return
        }
        guard usesSearchField, scrollView === tableView, isSearchActive?() != true else { return }
        let top = -scrollView.adjustedContentInset.top
        let distance = targetContentOffset.pointee.y - top
        guard distance > 0, distance < ChatListNavigationSearchView.scrollHeight else { return }
        let targetDistance = distance < ChatListNavigationSearchView.scrollHeight * 0.5
            ? CGFloat.zero
            : ChatListNavigationSearchView.scrollHeight
        targetContentOffset.pointee.y = top + targetDistance
    }

    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        // startedScrollingAtUpperBound: only a drag from the top can open the stories.
        storiesDragStartedAtTop = storiesPull >= -1
        clientViewportRestoration.cancel()
        didPlaceInitialViewport = true
    }

    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView === tableView, !decelerate { onListInteractionEnded?() }
    }

    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView === tableView { onListInteractionEnded?() }
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        if selectedChatIDs != nil {
            guard let chatID = dataSource.itemIdentifier(for: indexPath) else { return }
            selectedChatIDs?.insert(chatID)
            updateChatSelection()
            return
        }
        // The split's list keeps the row of the chat it shows selected.
        if !NavigationStorage.shared.splitController.isSplit { tableView.deselectRow(at: indexPath, animated: true) }
        guard let chatID = dataSource.itemIdentifier(for: indexPath), let chat = chat(for: chatID) else { return }
        NavigationStorage.shared.push(.customChat(chat), fromList: true)
    }

    override func tableView(_: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard selectedChatIDs != nil, let chatID = dataSource.itemIdentifier(for: indexPath) else { return }
        selectedChatIDs?.remove(chatID)
        updateChatSelection()
    }

    override func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath,
    ) {
        // A row that scrolls in doesn't show the selection the split gave it while it was off screen.
        if selectedChatIDs == nil, let chatID = NavigationStorage.shared.splitSelectedChatID.value,
           dataSource.itemIdentifier(for: indexPath) == chatID
        {
            cell.setSelected(true, animated: false)
        }
        if indexPath.row >= tableView.numberOfRows(inSection: indexPath.section) - 12 {
            loadMoreChatsIfNeeded()
        }
    }

    override func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt _: IndexPath,
    ) -> UITableViewCell.EditingStyle {
        // Reordering shows only the grip; outside it the style lets UIKit offer the row's swipe actions, and
        // selection its checks.
        tableView.isEditing && selectedChatIDs == nil ? .none : .delete
    }

    /// Telegram's reveal options (ChatListItem `revealOptions`): Mute or Unmute, Delete, then Archive or Unarchive
    /// with the last one on a full swipe; the archive offers Pin or Unpin, Delete and Unarchive.
    override func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        swipeConfiguration(at: indexPath, leading: false)
    }

    /// Telegram's left reveal options (`leftRevealOptions`): Read or Unread, then Pin or Unpin, outside the archive.
    override func tableView(
        _: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        swipeConfiguration(at: indexPath, leading: true)
    }

    override func tableView(_: UITableView, shouldIndentWhileEditingRowAt _: IndexPath) -> Bool {
        false
    }

    /// Telegram (ChatListNode.reorderItem) moves a pinned chat only among the pinned chats.
    override func tableView(
        _: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath,
    ) -> IndexPath {
        let pinnedCount = dataSource.snapshot()
            .itemIdentifiers
            .prefix { chat(for: $0)?.position.isPinned == true }
            .count
        guard pinnedCount > 0 else { return sourceIndexPath }
        return IndexPath(row: min(proposedDestinationIndexPath.row, pinnedCount - 1), section: sourceIndexPath.section)
    }

    /// scrollToStories: the collapsed posters' tap opens the stories.
    func expandStories() {
        guard isViewLoaded, allowsStories else { return }
        setStoriesInset(StoryPeerListExpandedView.height)
        storiesUnlocked = true
        storiesDragStartedAtTop = true
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: true)
    }

    func clientRestorationViewport() -> ChatListViewportSnapshot {
        guard isViewLoaded, didPlaceInitialViewport else {
            return clientViewportRestoration.pending ?? ChatListViewportSnapshot(
                chatID: nil,
                rowMinYRelativeToViewport: 0,
                offsetFromTop: initialSearchScrollOffset,
            )
        }
        return .capture(tableView: tableView) { dataSource.itemIdentifier(for: $0) }
    }

    func tableView(_: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let client = actionAuthority.client
        let authority = actionAuthority
        guard authority.isCurrent else { return }
        for indexPath in indexPaths {
            guard let id = dataSource.itemIdentifier(for: indexPath),
                  let chat = chat(for: id),
                  prefetchTasks[id] == nil
            else { continue }
            prefetchTasks[id] = Task { [weak self] in
                guard authority.isCurrent, !Task.isCancelled else { return }
                if let avatar = chat.chat.photo?.small {
                    await TDImagePrefetcher.prefetch(file: avatar, maximumPixelSize: 160, client: client)
                }
                guard authority.isCurrent, !Task.isCancelled else { return }
                if chat.chat.viewAsTopics {
                    let _: ForumTopics? = try? await client.getForumTopics(
                        chatId: id,
                        limit: 30,
                        offsetDate: 0,
                        offsetForumTopicId: 0,
                        offsetMessageId: 0,
                        query: "",
                    )
                } else {
                    let _: Messages? = try? await client.getChatHistory(
                        chatId: id,
                        fromMessageId: 0,
                        limit: 30,
                        offset: 0,
                        onlyLocal: false,
                    )
                }
                await MainActor.run { self?.prefetchTasks[id] = nil }
            }
        }
    }

    func tableView(_: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let id = dataSource.itemIdentifier(for: indexPath) else { continue }
            prefetchTasks[id]?.cancel()
            prefetchTasks[id] = nil
        }
    }

    func scrollToTop() {
        guard !orderedChats.isEmpty else { return }
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: true)
    }

    func revealSearch(animated: Bool) {
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: animated)
    }

    /// A header panel appearing under the navigation bar pushes the rows down by its height and keeps the search
    /// field's reveal, as Telegram's navigation header panels do.
    func setAccessoryTopInset(_ inset: CGFloat) {
        let delta = inset - accessoryTopInset
        guard abs(delta) > 0.5 else { return }
        accessoryTopInset = inset
        guard isViewLoaded else { return }
        let offset = tableView.contentOffset.y
        tableView.contentInset.top += delta
        tableView.contentOffset.y = offset - delta
        updateIndicatorInsets()
    }

    func setAccessoryBottomInset(_ inset: CGFloat) {
        guard abs(inset - accessoryBottomInset) > 0.5 else { return }
        accessoryBottomInset = inset
        guard isViewLoaded, !showsStandaloneSearch else { return }
        tableView.contentInset.bottom = inset
        updateIndicatorInsets()
    }

    func setSearchActive(_ active: Bool, animated: Bool, preservingViewport: Bool = false) {
        if active { endPinnedReorder() }
        let wasActive = searchActive
        if active, !wasActive {
            viewportBeforeSearch = isViewLoaded && didPlaceInitialViewport ? clientRestorationViewport() : nil
            initialSearchScrollOffsetBeforeSearch = initialSearchScrollOffset
        }
        let viewport = preservingViewport
            ? clientRestorationViewport()
            : (!active && wasActive ? viewportBeforeSearch : nil)
        searchActive = active
        if active {
            if usesSearchField { initialSearchScrollOffset = 0 }
        } else if wasActive {
            initialSearchScrollOffset = initialSearchScrollOffsetBeforeSearch ?? initialSearchScrollOffset
            viewportBeforeSearch = nil
            initialSearchScrollOffsetBeforeSearch = nil
        }
        guard isViewLoaded else { return }
        let targetTopInset = barContentHeight
        let changes = {
            if self.usesSearchField { self.tableView.contentInset.top = targetTopInset + self.accessoryTopInset }
            self.updateIndicatorInsets()
            self.tableView.layoutIfNeeded()
            if let viewport {
                viewport.restore(tableView: self.tableView) { self.dataSource.indexPath(for: $0) }
            } else {
                self.tableView.contentOffset = CGPoint(x: 0, y: -self.tableView.adjustedContentInset.top)
            }
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
            animations: changes,
        )
    }

    /// ChatContextMenus' chatContextMenuItems for a chat the account has, found by search (`.search` source): no
    /// Remove from Folder, and Pin in the chat's own list.
    func searchResultMenu(for chat: CustomChat) -> [TelegramContextMenuAction] {
        menu(for: chat, inSearch: true)
    }

    /// Telegram's Edit (ChatListControllerImpl.editPressed): every row gets a check, the pinned ones their grips too,
    /// and
    /// the toolbar offers Read All until a chat is selected.
    func beginEditing() {
        guard actionAuthority.scope(owner: self).isCurrent, selectedChatIDs == nil, !isReorderingPinnedChats,
              isSearchActive?() != true else { return }
        isReorderingPinnedChats = true
        beginChatSelection(with: [])
    }

    /// Telegram's donePressed.
    func endEditing() {
        endChatSelection()
    }

    private func updateStoriesPull() {
        guard allowsStories else {
            if storiesInset > 0 { setStoriesInset(0) }
            onStoriesPull?(0)
            return
        }
        let pull = storiesPull
        if storiesInset > 0, pull < -4 {
            setStoriesInset(0)
            setStoriesUnlocked(false)
        }
        guard storiesDragStartedAtTop || storiesInset > 0 else {
            onStoriesPull?(0)
            return
        }
        if tableView.isTracking {
            if pull >= 65 {
                setStoriesUnlocked(true)
            } else if pull <= 61 {
                setStoriesUnlocked(false)
            }
        }
        onStoriesPull?(max(0, pull))
    }

    private func setStoriesUnlocked(_ unlocked: Bool) {
        guard unlocked != storiesUnlocked else { return }
        storiesUnlocked = unlocked
        if unlocked {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
        }
    }

    private func setStoriesInset(_ inset: CGFloat) {
        let delta = inset - storiesInset
        guard abs(delta) > 0.5 else { return }
        storiesInset = inset
        let offset = tableView.contentOffset
        tableView.contentInset.top += delta
        tableView.contentOffset = offset
        updateIndicatorInsets()
    }

    /// contentScrollingEnded: a release between the stories' closed and open positions settles open while they're
    /// unlocked and closed otherwise.
    private func settleStories(_ target: UnsafeMutablePointer<CGPoint>) {
        if storiesUnlocked {
            setStoriesInset(StoryPeerListExpandedView.height)
            let open = -tableView.adjustedContentInset.top
            if target.pointee.y < open + StoryPeerListExpandedView.height { target.pointee.y = open }
        } else if storiesInset > 0 {
            let closed = -tableView.adjustedContentInset.top + storiesInset
            if target.pointee.y < closed { target.pointee.y = closed }
        }
    }

    /// The scroll indicator runs beside the rows, under the navigation bar, which grows with a pull past the top of
    /// the list, and above the folder tabs. UIKit's own adjustment would leave it across iPhone Duo's strip, away from
    /// the rows, so all of it is set here.
    private func updateIndicatorInsets() {
        let safeArea = tableView.safeAreaInsets
        let pull = usesSearchField && !searchActive
            ? max(0, -(tableView.contentOffset.y + tableView.adjustedContentInset.top - storiesInset))
            : 0
        let insets = UIEdgeInsets(
            top: safeArea.top + barContentHeight + accessoryTopInset + pull,
            left: 0,
            bottom: safeArea.bottom + (showsStandaloneSearch ? 0 : accessoryBottomInset),
            right: safeArea.right,
        )
        let current = tableView.verticalScrollIndicatorInsets
        if abs(current.top - insets.top) > 0.5 || current.bottom != insets.bottom || current.right != insets.right {
            tableView.verticalScrollIndicatorInsets = insets
        }
    }

    /// Telegram opens a chat's stories from its avatar (ChatListItem.avatarStoryTapGesture) and then pages through
    /// the other posters, unseen ones first as its story subscriptions are ordered; here those are the page's chats
    /// with stories, in list order within each group.
    private func openStories(from chatID: Int64, sourceView: UIView) {
        guard actionAuthority.scope(owner: self).isCurrent, !isReorderingPinnedChats, !tableView.isEditing,
              overlayHost.presentedViewController == nil else { return }
        let posters = orderedChats.compactMap { chat in chat.activeStoryState.map { (chat.id, $0) } }
        let unseen = posters.filter { $0.1.ringStyle != .seen }.map(\.0)
        let seen = posters.filter { $0.1.ringStyle == .seen }.map(\.0)
        StoryViewerController.present(
            .activeStories(chatIDs: unseen + seen, initialChatID: chatID),
            client: actionAuthority.client,
            from: overlayHost,
            sourceView: sourceView,
            sourceIsAvatar: true,
        )
    }

    private func configureDataSource() {
        dataSource = ChatRowsDataSource(tableView: tableView) { [weak self] tableView, indexPath, id in
            guard let self, let chat = chat(for: id),
                  let cell = tableView.dequeueReusableCell(
                      withIdentifier: ChatListCell.reuseIdentifier,
                      for: indexPath,
                  ) as? ChatListCell
            else { return UITableViewCell() }
            cell.onOpenStories = { [weak self] sourceView in
                self?.openStories(from: id, sourceView: sourceView)
            }
            cell.onOpenTopic = { [weak self] topicID in
                self?.openTopic(topicID, of: id)
            }
            cell.showsFolderTags = true
            // The page's own folder leaves its tag out.
            cell.currentFolderID = folder.id
            cell.configure(
                chat: chat,
                isMuted: rootVM.isMuted(chat),
                isArchived: isArchivePage,
                client: actionAuthority.client,
            )
            return cell
        }
        dataSource.canMoveRow = { [weak self] indexPath in
            guard let self, isReorderingPinnedChats, let id = dataSource.itemIdentifier(for: indexPath) else {
                return false
            }
            return chat(for: id)?.position.isPinned == true
        }
        // Every row edits while the list selects, so that each gets its check.
        dataSource.canSwipeRow = { [weak self] indexPath in
            guard let self, selectedChatIDs != nil || !isReorderingPinnedChats,
                  let id = dataSource.itemIdentifier(for: indexPath)
            else { return false }
            return chat(for: id) != nil
        }
        dataSource.didMoveRow = { [weak self] movedID, referenceID, movedDown in
            self?.commitPinnedMove(movedID, relativeTo: referenceID, movedDown: movedDown)
        }
    }

    private func startStateUpdates() {
        folder.$isLoading
            .combineLatest(folder.$loadError)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateLoadingFooter()
            }
            .store(in: &cancellables)

        folder.$chats
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.rebuildChatIndex()
                    self?.updateSnapshot(animated: true)
                }
            }
            .store(in: &cancellables)
        PendingChatRemovals.shared
            .$hiddenKeys
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateSnapshot(animated: true) }
            }
            .store(in: &cancellables)
        rootVM.$scopeNotificationSettings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                updateSnapshot(animated: false, changedIDs: Set(folder.chats.map(\.id)))
            }
            .store(in: &cancellables)
        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            guard let self else { return }
            updateSnapshot(animated: false, changedIDs: Set(folder.chats.map(\.id)))
        }
        folder.chatsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] chatIDs in
                self?.scheduleChatUpdate(ids: chatIDs)
            }
            .store(in: &cancellables)
    }

    private func rebuildChatIndex() {
        guard indexedChatsGeneration != folder.chatsGeneration else { return }
        indexedChatsGeneration = folder.chatsGeneration
        // Retain rows from the previous snapshot until its animations finish.
        chatsByID.merge(folder.chatsByID, uniquingKeysWith: { _, latest in latest })
        for id in Array(prefetchTasks.keys) where folder.chatsByID[id] == nil {
            prefetchTasks[id]?.cancel()
            prefetchTasks[id] = nil
        }
    }

    private func scheduleChatUpdate(ids: Set<Int64>) {
        pendingChangedChatIDs.formUnion(ids)
        guard !chatUpdateScheduled else { return }
        chatUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            chatUpdateScheduled = false
            let changedIDs = pendingChangedChatIDs
            pendingChangedChatIDs.removeAll()
            updateSnapshot(animated: true, changedIDs: changedIDs)
        }
    }

    private func updateSnapshot(animated: Bool, changedIDs: Set<Int64> = []) {
        guard isViewLoaded else { return }
        snapshotNeedsApply = true
        pendingSnapshotAnimated = pendingSnapshotAnimated || animated
        pendingSnapshotChangedIDs.formUnion(changedIDs)
        applyPendingSnapshot()
    }

    private func applyPendingSnapshot() {
        guard snapshotNeedsApply, !isApplyingSnapshot, !isReorderingPinnedChats else { return }
        // A page off screen, behind a chat or another folder, catches up as it appears. Telegram keeps only the
        // pages around the current one live.
        guard viewIfLoaded?.window != nil || !didApplyFirstSnapshot else { return }
        didApplyFirstSnapshot = true
        snapshotNeedsApply = false
        let animated = pendingSnapshotAnimated
        let changedIDs = pendingSnapshotChangedIDs
        pendingSnapshotAnimated = false
        pendingSnapshotChangedIDs.removeAll()
        // Membership can change before a queued UI publisher runs. Populate the
        // provider cache before publishing new identifiers, including on scope updates.
        rebuildChatIndex()
        // A chat whose removal waits behind the Undo toast is hidden, as Telegram's pendingRemovalItemIds.
        let clientID = actionAuthority.client.id
        let probesEmpty = probesEmptyFolder
        let displayedChats = orderedChats.filter {
            !probesEmpty && !PendingChatRemovals.shared.isHidden(clientID: clientID, chatID: $0.id)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.main])
        snapshot.appendItems(displayedChats.map(\.id))
        if !changedIDs.isEmpty {
            let current = Set(dataSource.snapshot().itemIdentifiers)
            let reconfigured = snapshot.itemIdentifiers.filter { changedIDs.contains($0) && current.contains($0) }
            if !reconfigured.isEmpty {
                snapshot.reconfigureItems(reconfigured)
            }
        }
        isApplyingSnapshot = true
        // A list resting at its top keeps showing the top, as Telegram's chat list does: a chat that moves or arrives
        // above the first row appears there instead of sliding under the navigation bar while UIKit anchors the
        // previous first row.
        let restingTopOffset: CGFloat? = {
            guard didPlaceInitialViewport, clientViewportRestoration.pending == nil,
                  !isInteractingWithList, !tableView.isTracking
            else { return nil }
            let offset = tableView.contentOffset.y + tableView.adjustedContentInset.top
            let restingRange = usesSearchField ? ChatListNavigationSearchView.scrollHeight : 0
            return offset <= restingRange + 0.5 ? offset : nil
        }()
        // A list scrolled away from its top keeps its visible rows still, as Telegram's chat list does: a chat that
        // moves or arrives above the viewport shifts only the rows above it. UIKit otherwise re-anchors the batch
        // update on its own focus and can leave the list a fraction of a row off.
        let previousIDs = dataSource.snapshot().itemIdentifiers
        let visibleAnchor = restingTopOffset == nil && previousIDs != snapshot.itemIdentifiers
            ? stableVisibleRow(from: previousIDs, to: snapshot.itemIdentifiers)
            : nil
        let applyToken = clientViewportRestoration.beginApply()
        defer {
            if let restingTopOffset {
                let target = restingTopOffset - tableView.adjustedContentInset.top
                if abs(tableView.contentOffset.y - target) > 0.5 {
                    tableView.contentOffset = CGPoint(x: tableView.contentOffset.x, y: target)
                }
            }
            if let visibleAnchor {
                tableView.layoutIfNeeded()
                restoreVisibleRow(visibleAnchor)
            }
        }
        // Rows that would slide under a compensating offset change in place instead.
        let shiftsVisibleRows = visibleAnchor.map { $0.previousIndex != $0.nextIndex } ?? false
        dataSource.apply(snapshot, animatingDifferences: animated && !shiftsVisibleRows) { [weak self] in
            guard let self else { return }
            isApplyingSnapshot = false
            // Reloaded rows lose their checks; the selection puts them back and drops chats that left the list.
            updateChatSelection()
            updateSplitSelection()
            // UIKit can re-anchor the previous first row during the update animation; bring the top back.
            if let restingTopOffset, !isInteractingWithList, !tableView.isTracking {
                let target = restingTopOffset - tableView.adjustedContentInset.top
                if abs(tableView.contentOffset.y - target) > 0.5 {
                    tableView.setContentOffset(CGPoint(x: tableView.contentOffset.x, y: target), animated: true)
                }
            }
            if let visibleAnchor, !isInteractingWithList, !tableView.isTracking {
                restoreVisibleRow(visibleAnchor)
            }
            clientViewportRestoration.completeApply(applyToken)
            if !didPlaceInitialViewport { view.setNeedsLayout() }
            if chatsByID.count > folder.chatsByID.count {
                let retainedIDs = Set(dataSource.snapshot().itemIdentifiers).union(folder.chatsByID.keys)
                chatsByID = chatsByID.filter { retainedIDs.contains($0.key) }
            }
            loadMoreChatsIfNeeded()
            DispatchQueue.main.async { [weak self] in self?.applyPendingSnapshot() }
        }
        showsNoRows = displayedChats.isEmpty
        updateEmptyState()
    }

    /// The topmost visible row that stays among its neighbours: a chat that itself moves keeps no place to hold.
    private func stableVisibleRow(from previousIDs: [Int64], to nextIDs: [Int64]) -> VisibleRowAnchor? {
        guard didPlaceInitialViewport, clientViewportRestoration.pending == nil, !isInteractingWithList,
              !tableView.isTracking
        else { return nil }
        let nextIndexes = Dictionary(nextIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let viewportTop = tableView.contentOffset.y + tableView.adjustedContentInset.top
        let anchors = (tableView.indexPathsForVisibleRows ?? []).sorted().compactMap { indexPath -> VisibleRowAnchor? in
            let previousIndex = indexPath.row
            guard previousIDs.indices.contains(previousIndex) else { return nil }
            let id = previousIDs[previousIndex]
            guard let nextIndex = nextIndexes[id] else { return nil }
            let keepsPrevious = previousIndex > 0 && nextIndex > 0
                && previousIDs[previousIndex - 1] == nextIDs[nextIndex - 1]
            let keepsNext = previousIndex + 1 < previousIDs.count && nextIndex + 1 < nextIDs.count
                && previousIDs[previousIndex + 1] == nextIDs[nextIndex + 1]
            guard keepsPrevious || keepsNext else { return nil }
            return VisibleRowAnchor(
                id: id,
                minYRelativeToOffset: tableView.rectForRow(at: indexPath).minY - tableView.contentOffset.y,
                previousIndex: previousIndex,
                nextIndex: nextIndex,
            )
        }
        return anchors.first { $0.minYRelativeToOffset + tableView.contentOffset.y >= viewportTop - 0.5 }
            ?? anchors.first
    }

    private func restoreVisibleRow(_ anchor: VisibleRowAnchor) {
        guard let indexPath = dataSource.indexPath(for: anchor.id) else { return }
        let insets = tableView.adjustedContentInset
        let minimum = -insets.top
        let maximum = max(minimum, tableView.contentSize.height - tableView.bounds.height + insets.bottom)
        let target = min(max(tableView.rectForRow(at: indexPath).minY - anchor.minYRelativeToOffset, minimum), maximum)
        guard abs(tableView.contentOffset.y - target) > 0.5 else { return }
        tableView.contentOffset = CGPoint(x: tableView.contentOffset.x, y: target)
    }

    private func loadMoreChatsIfNeeded() {
        guard isViewLoaded, view.window != nil, folder.loadError == nil,
              tableView.contentOffset.y + tableView.bounds.height >= tableView.contentSize.height - 12 * 76
        else { return }
        rootVM.loadMoreChats(in: folder)
    }

    private func updateLoadingFooter() {
        updateEmptyState()
        if let error = folder.loadError {
            let button = UIButton(type: .system)
            button.frame.size = CGSize(width: tableView.bounds.width, height: 52)
            button.setTitle(L10n.telegram("ChatImportActivity.Retry"), for: .normal)
            button.accessibilityLabel = "\(error). \(L10n.telegram("ChatImportActivity.Retry"))"
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                rootVM.loadMoreChats(in: folder)
            }, for: .touchUpInside)
            tableView.tableFooterView = button
        } else if folder.isLoading {
            // An empty list shows its loading indicator in the middle instead.
            guard !showsNoRows else {
                tableView.tableFooterView = nil
                return
            }
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.frame.size = CGSize(width: tableView.bounds.width, height: 44)
            spinner.startAnimating()
            tableView.tableFooterView = spinner
        } else {
            tableView.tableFooterView = nil
            loadMoreChatsIfNeeded()
        }
    }

    /// Telegram shows a loading list until it knows a list is empty: the list of an account whose client is still
    /// starting, or one whose first chats are loading, is not empty yet (L-9).
    private func updateEmptyState() {
        let state: EmptyState? =
            if !showsNoRows {
                nil
            } else if probesEmptyFolder || folder.loadError != nil || !folder.hasMoreChats {
                .empty
            } else {
                .loading
            }
        guard state != emptyState else { return }
        emptyState = state
        tableView.backgroundView =
            switch state {
            case .empty: emptyView()
            case .loading: loadingPlaceholder()
            case nil: nil
            }
    }

    private func loadingPlaceholder() -> UIView {
        let container = UIView()
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        container.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    /// ChatListContainerItemNode's subject: a folder of the user's gets `.filter` (no Edit for one that only drops
    /// read chats and names none), All Chats `.chats`, and the archive ArchiveInfoContentComponent.
    private func emptyView() -> UIView {
        let view: ChatListEmptyView
        switch folder.type {
        case .folder(_, let filter):
            let onlyDropsRead = filter.excludeRead && filter.includedChatIds.isEmpty && filter.pinnedChatIds.isEmpty
            view = ChatListEmptyView(subject: .filter(showsEdit: !onlyDropsRead))
            view.onAction = { [weak self] in self?.onEditFolder?() }
        case .main:
            view = ChatListEmptyView(subject: .chats(hasArchive: !(rootVM.archive?.chats.isEmpty ?? true)))
            view.onAction = { [weak self] in self?.onNewMessage?() }
        case .archive:
            let view = ChatListArchiveEmptyView(keepsUnmutedArchived: false) { [weak self] in
                self?.navigationController?.pushViewController(ArchiveSettingsViewController(), animated: true)
            }
            view.insets = tableView.adjustedContentInset
            let client = actionAuthority.client
            Task { [weak view] in
                let settings = try? await client.send(TDNativeRequests.getArchiveChatListSettings())
                view?.content.keepsUnmutedArchived = settings?.keepUnmutedChatsArchived ?? false
            }
            return view
        }
        view.insets = tableView.adjustedContentInset
        return view
    }

    private func chat(for id: Int64) -> CustomChat? {
        chatsByID[id]
    }

    private func menu(for chat: CustomChat, inSearch: Bool = false) -> [TelegramContextMenuAction] {
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        guard scope.isCurrent else { return [] }
        let archived = chat.chat.positions.contains { $0.list == .chatListArchive && $0.order != 0 }
        let searchPinList: ChatList? = inSearch ? (archived ? .chatListArchive : .chatListMain) : nil
        let pinned = searchPinList.map { list in chat.chat.positions.contains { $0.list == list && $0.isPinned } }
            ?? chat.position.isPinned
        let unread = chat.unreadCount > 0 || chat.chat.isMarkedAsUnread
        let muted = rootVM.isMuted(chat)
        // Telegram (ChatContextMenus, chatContextMenuItems) keeps Saved Messages out of Archive and Mute, service
        // notifications out of Archive, and offers Mark as Unread only outside forums.
        let isSavedMessages = chat.isSavedMessages
        let isServiceNotifications = chat.user?.id == Self.serviceNotificationsUserID
        let isForum = chat.supergroup.map { $0.isForum || $0.isDirectMessagesGroup } ?? false
        let isCustomFolder =
            if !inSearch, case .folder = folder.type {
                true
            } else {
                false
            }

        var actions = [TelegramContextMenuAction]()
        if isCustomFolder {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.Context.RemoveFromFolder"),
                image: UIImage(systemName: "folder.badge.minus"),
            ) { [weak self] in
                self?.removeFromCurrentFolder(chat)
            })
        } else {
            // Telegram (ChatContextMenus, Add to Folder) lists only folders that do not already hold the chat, as a
            // submenu of the same menu, and hides the item when there is none. TDLib reports folder membership in
            // chat_lists, including folders whose chats were never loaded.
            let targets = rootVM.folders.compactMap { folder -> (id: Int, name: String, folder: ChatFolder)? in
                guard case .folder(let info, let definition) = folder.type, !chat.isListed(in: folder.chatList)
                else { return nil }
                return (info.id, folder.name, definition)
            }
            if !targets.isEmpty {
                actions.append(TelegramContextMenuAction(
                    title: L10n.telegram("ChatList.Context.AddToFolder"),
                    image: UIImage(systemName: "folder.badge.plus"),
                    children: targets.map { target in
                        TelegramContextMenuAction(
                            title: target.name,
                            image: UIImage(systemName: "folder"),
                        ) { [weak self] in
                            self?.runAction(scope, onFailure: { [weak self] error in
                                // Telegram shows the chats-per-folder limit when the folder is full.
                                self?.presentFailure(
                                    limit: error.isTDLibLimit("maximum number of")
                                        ? .premiumLimitTypeChatFolderChosenChatCount
                                        : nil,
                                    scope: scope,
                                    client: client,
                                )
                            }) {
                                _ = try await client.editChatFolder(
                                    chatFolderId: target.id,
                                    folder: target.folder.adding(chatID: chat.id),
                                )
                            }
                        }
                    },
                ))
            }
        }
        if unread {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.Context.MarkAsRead"),
                image: UIImage(systemName: "envelope.open"),
            ) { [weak self] in
                self?.markRead(chat, scope: scope, client: client)
            })
        } else if !isForum {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.Context.MarkAsUnread"),
                image: UIImage(systemName: "envelope.badge"),
            ) { [weak self] in
                self?.markUnread(chat, scope: scope, client: client)
            })
        }
        if !isSavedMessages, !isServiceNotifications {
            actions.append(TelegramContextMenuAction(
                title: archived
                    ? L10n.telegram("ChatList.Context.Unarchive")
                    : L10n.telegram("ChatList.Context.Archive"),
                image: UIImage(systemName: archived ? "tray.and.arrow.up" : "archivebox"),
            ) { [weak self] in
                self?.setArchived(chat, !archived, scope: scope, client: client)
            })
        }
        actions.append(TelegramContextMenuAction(
            title: pinned
                ? L10n.telegram("ChatList.Context.Unpin")
                : L10n.telegram("ChatList.Context.Pin"),
            image: UIImage(systemName: pinned ? "pin.slash.fill" : "pin.fill"),
        ) { [weak self] in
            self?.setPinned(chat, !pinned, in: searchPinList, scope: scope, client: client)
        })
        if !isSavedMessages {
            actions.append(TelegramContextMenuAction(
                title: muted
                    ? L10n.telegram("ChatList.Context.Unmute")
                    : L10n.telegram("ChatList.Context.Mute"),
                image: UIImage(systemName: muted ? "speaker.wave.2.fill" : "speaker.slash.fill"),
            ) { [weak self] in
                self?.setMuted(chat, !muted, scope: scope, client: client)
            })
        }
        // Telegram offers Delete for every chat in the list; the sheet decides between deleting, leaving and
        // clearing history.
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram("ChatList.Context.Delete"),
            image: UIImage(systemName: "trash"),
            isDestructive: true,
            startsNewSection: true,
        ) { [weak self] in
            self?.deleteChat(chat, scope: scope, client: client)
        })
        // Selecting and reordering pinned chats belong to Edit, as in Telegram's root list.
        return actions
    }

    // MARK: Row actions

    private func swipeChat(at indexPath: IndexPath) -> CustomChat? {
        guard actionAuthority.scope(owner: self).isCurrent, !isReorderingPinnedChats, selectedChatIDs == nil,
              allowsRowSwipe?() != false,
              let id = dataSource.itemIdentifier(for: indexPath)
        else { return nil }
        return chat(for: id)
    }

    private func swipeConfiguration(at indexPath: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
        guard let chat = swipeChat(at: indexPath) else { return nil }
        let actions = leading ? leadingSwipeActions(for: chat) : Array(trailingSwipeActions(for: chat).reversed())
        let configuration = UISwipeActionsConfiguration(actions: actions)
        configuration.performsFirstActionWithFullSwipe = !actions.isEmpty
        return configuration
    }

    private func swipeAction(
        _ key: String,
        _ symbol: String,
        _ color: UIColor,
        perform: @escaping () -> Void,
    ) -> UIContextualAction {
        let action = UIContextualAction(style: .normal, title: L10n.telegram(key)) { _, _, completion in
            perform()
            completion(true)
        }
        action.image = UIImage(systemName: symbol)
        action.backgroundColor = color
        return action
    }

    /// In Telegram's order, left to right.
    private func trailingSwipeActions(for chat: CustomChat) -> [UIContextualAction] {
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        let isArchiveList = folder.chatList == .chatListArchive
        var actions = [UIContextualAction]()
        if isArchiveList {
            let pinned = chat.position.isPinned
            actions.append(swipeAction(
                pinned ? "DialogList.Unpin" : "DialogList.Pin",
                pinned ? "pin.slash.fill" : "pin.fill",
                .systemGreen,
            ) { [weak self] in self?.setPinned(chat, !pinned, scope: scope, client: client) })
        } else if !chat.isSavedMessages {
            let muted = rootVM.isMuted(chat)
            actions.append(swipeAction(
                muted ? "ChatList.Unmute" : "ChatList.Mute",
                muted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                .systemOrange,
            ) { [weak self] in self?.setMuted(chat, !muted, scope: scope, client: client) })
        }
        actions.append(swipeAction("Common.Delete", "trash.fill", .systemRed) { [weak self] in
            self?.deleteChat(chat, scope: scope, client: client)
        })
        if isArchiveList {
            actions.append(swipeAction("ChatList.UnarchiveAction", "tray.and.arrow.up.fill", .systemGray) {
                [weak self] in self?.setArchived(chat, false, scope: scope, client: client)
            })
        } else if !chat.isSavedMessages, chat.user?.id != Self.serviceNotificationsUserID {
            // A custom folder offers Archive only when it hides archived chats (ChatListItemFilterData).
            let canArchive =
                switch folder.type {
                case .main: true
                case .archive: false
                case .folder(_, let definition): definition.excludeArchived
                }
            if canArchive {
                actions.append(swipeAction("ChatList.ArchiveAction", "archivebox.fill", .systemGray) {
                    [weak self] in self?.setArchived(chat, true, scope: scope, client: client)
                })
            }
        }
        return actions
    }

    private func leadingSwipeActions(for chat: CustomChat) -> [UIContextualAction] {
        guard folder.chatList != .chatListArchive else { return [] }
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        var actions = [UIContextualAction]()
        let unread = chat.unreadCount > 0 || chat.chat.isMarkedAsUnread
        let isForum = chat.supergroup.map { $0.isForum || $0.isDirectMessagesGroup } ?? false
        if unread {
            actions.append(swipeAction("DialogList.Read", "envelope.open.fill", .systemGray) { [weak self] in
                self?.markRead(chat, scope: scope, client: client)
            })
        } else if !isForum {
            actions.append(swipeAction("DialogList.Unread", "envelope.badge.fill", .systemBlue) { [weak self] in
                self?.markUnread(chat, scope: scope, client: client)
            })
        }
        let pinned = chat.position.isPinned
        let isCustomFolder =
            if case .folder = folder.type {
                true
            } else {
                false
            }
        if pinned || !(isCustomFolder && chat.secretChatID != nil) {
            actions.append(swipeAction(
                pinned ? "DialogList.Unpin" : "DialogList.Pin",
                pinned ? "pin.slash.fill" : "pin.fill",
                .systemGreen,
            ) { [weak self] in self?.setPinned(chat, !pinned, scope: scope, client: client) })
        }
        return actions
    }

    /// Shared by the context menu and the swipe actions.
    private func markRead(_ chat: CustomChat, scope: ChatListActionScope, client: TDLibClient) {
        runAction(scope) {
            if let messageID = chat.lastMessage?.id {
                // Best effort: the unread mark cleared below is what the row shows.
                _ = try? await client.viewMessages(
                    chatId: chat.id,
                    forceRead: true,
                    messageIds: [messageID],
                    source: nil,
                )
                try scope.check()
            }
            _ = try await client.toggleChatIsMarkedAsUnread(chatId: chat.id, isMarkedAsUnread: false)
            // Telegram's Mark as Read also marks mentions seen (updateMarkAllMentionsSeen); it leaves unseen
            // reactions, which the chat reads when they are shown.
            if chat.chat.unreadMentionCount > 0 {
                try scope.check()
                _ = try await client.send(TDNativeRequests.readAllChatMentions(chatId: chat.id))
            }
        }
    }

    private func markUnread(_ chat: CustomChat, scope: ChatListActionScope, client: TDLibClient) {
        runAction(scope) {
            _ = try await client.toggleChatIsMarkedAsUnread(chatId: chat.id, isMarkedAsUnread: true)
        }
    }

    private func setArchived(
        _ chat: CustomChat,
        _ archive: Bool,
        scope: ChatListActionScope,
        client: TDLibClient,
    ) {
        runAction(scope) { [weak self] in
            _ = try await client.addChatToList(
                chatId: chat.id,
                chatList: archive ? .chatListArchive : .chatListMain,
            )
            // Telegram (ChatListController, archiveChats) offers Undo after archiving.
            guard archive, let self, scope.isCurrent else { return }
            showUndoToast(L10n.telegram("ChatList.UndoArchiveTitle")) { [weak self] in
                self?.runAction(scope) {
                    _ = try await client.addChatToList(chatId: chat.id, chatList: .chatListMain)
                }
            }
        }
    }

    /// Pins in this page's list, or in `list` for a chat found by search.
    private func setPinned(
        _ chat: CustomChat,
        _ pin: Bool,
        in list: ChatList? = nil,
        scope: ChatListActionScope,
        client: TDLibClient,
    ) {
        let chatList = list ?? folder.chatList
        let pinLimit: TDNativePremiumLimitType =
            switch list {
            case .chatListArchive?: .premiumLimitTypePinnedArchivedChatCount
            case .some: .premiumLimitTypePinnedChatCount
            case nil: pinLimitType
            }
        runAction(scope, onFailure: { [weak self] error in
            // Telegram (toggleItemPinned, limitExceeded) shows the pin limit.
            self?.presentFailure(
                limit: pin && error.isTDLibLimit("maximum number of pinned chats") ? pinLimit : nil,
                scope: scope,
                client: client,
            )
        }) {
            _ = try await client.toggleChatIsPinned(chatId: chat.id, chatList: chatList, isPinned: pin)
        }
    }

    private func setMuted(_ chat: CustomChat, _ mute: Bool, scope: ChatListActionScope, client: TDLibClient) {
        runAction(scope) {
            _ = try await client.setChatNotificationSettings(
                chatId: chat.id,
                notificationSettings: chat.chat.notificationSettings.withMuteFor(mute ? Int(Int32.max) : 0),
            )
        }
    }

    private func deleteChat(_ chat: CustomChat, scope: ChatListActionScope, client: TDLibClient) {
        ChatListChatRemoval(
            chat: chat,
            client: client,
            scope: scope,
            host: self,
            showUndo: { [weak self] status, undo in self?.showUndoToast(status, undo: undo) },
        ) { [weak self] status in
            self?.showUndoToast(status)
        }.start()
    }

    /// ChatListNode's openForumThread: the unread topic a forum's row names opens straight in its chat.
    private func openTopic(_ topicID: Int, of chatID: Int64) {
        guard selectedChatIDs == nil, let chat = chat(for: chatID) else { return }
        let client = actionAuthority.client
        guard let topic = ChatListForumTopics.shared.recentTopic(chatID: chatID, topicID: topicID, client: client)
        else { return }
        NavigationStorage.shared.push(
            .customChat(
                chat,
                location: ChatLocation.current(chatID: chatID, client: client).withForumTopic(id: topicID),
                forumTopic: topic,
            ),
            fromList: true,
        )
    }

    @objc private func chatLongPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              let chatID = dataSource.itemIdentifier(for: indexPath),
              let chat = chat(for: chatID),
              let cell = tableView.cellForRow(at: indexPath) as? ChatListCell
        else { return }
        // Telegram previews a forum with its topic list (ChatListController, previewing: true), and the unread
        // topic its highlighted line names as that topic (activateChatPreview with the thread).
        let client = TDLib.shared.activeClient
        let previewedTopic = cell.selectableTopicID(at: gesture.location(in: cell)).flatMap { topicID in
            ChatListForumTopics.shared.recentTopic(chatID: chat.id, topicID: topicID, client: client)
        }
        let previewController: UIViewController =
            if let previewedTopic {
                ChatViewController(
                    customChat: chat,
                    location: ChatLocation.current(chatID: chat.id, client: client)
                        .withForumTopic(id: previewedTopic.info.forumTopicId),
                    forumTopic: previewedTopic,
                    presentationMode: .contextPreview,
                )
            } else if chat.chat.viewAsTopics {
                ForumTopicsViewController(
                    customChat: chat,
                    location: ChatLocation.current(chatID: chat.id, client: TDLib.shared.activeClient),
                    client: TDLib.shared.activeClient,
                    presentationMode: .contextPreview,
                )
            } else {
                ChatViewController(customChat: chat, presentationMode: .contextPreview)
            }
        presentTelegramContextMenu(
            sourceView: cell.contextPreviewView,
            actions: previewedTopic.map { topicMenu(for: $0, in: chat, client: client) } ?? menu(for: chat),
            tracking: gesture,
            presentationStyle: .chatPreview,
            previewController: previewController,
        )
    }

    /// ChatContextMenus' chatForumTopicMenuItems as the chat list asks for them (no pin state, no Select): Mark as
    /// Read while the topic is unread, Mute or Unmute, Close or Reopen Topic and Delete for whoever may.
    private func topicMenu(
        for topic: ForumTopic,
        in chat: CustomChat,
        client: TDLibClient,
    ) -> [TelegramContextMenuAction] {
        let chatID = chat.id
        let topicID = topic.info.forumTopicId
        let isGeneral = topic.info.isGeneral
        let canOpenClose = chat.canManageForumTopics || topic.info.isOutgoing
        var actions = [TelegramContextMenuAction]()
        if topic.unreadCount > 0, let lastMessageID = topic.lastMessage?.id {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.Context.MarkAsRead"),
                image: UIImage(systemName: "envelope.open"),
            ) { [weak self] in
                self?.performTopicRequest(chatID: chatID, client: client) { client in
                    _ = try await client.viewMessages(
                        chatId: chatID,
                        forceRead: true,
                        messageIds: [lastMessageID],
                        source: .messageSourceForumTopicHistory,
                    )
                }
            })
        }
        // A topic's own mute, else the forum's (ChatContextMenus' `.default` case).
        let settings = topic.notificationSettings
        let isMuted = settings.useDefaultMuteFor ? rootVM.isMuted(chat) : settings.muteFor > 0
        actions.append(ForumTopicMuteMenu.action(
            settings: settings,
            isMuted: isMuted,
            update: { [weak self] settings, toast in
                self?.updateTopicNotifications(topicID, in: chatID, to: settings, toast: toast, client: client)
            },
            openCustomMute: { [weak self] in
                guard let self else { return }
                PeerProfileTimerPickerViewController(mode: .muteUntil(onApply: { [weak self] seconds in
                    let until = Foundation.Date(timeIntervalSinceNow: TimeInterval(seconds))
                    self?.updateTopicNotifications(
                        topicID,
                        in: chatID,
                        to: settings.replacingMuteFor(seconds),
                        toast: L10n.telegram(
                            "PeerInfo.TooltipMutedUntil",
                            PeerProfileTimerPickerViewController.preciseText(for: until),
                        ),
                        client: client,
                    )
                })).present(from: overlayHost)
            },
            customize: { [weak self] in
                guard let self else { return }
                NotificationExceptionViewController(
                    title: topic.info.name,
                    scope: chat.notificationSettingsScope,
                    settings: settings,
                    offersStories: false,
                ) { [weak self] settings in
                    self?.updateTopicNotifications(
                        topicID,
                        in: chatID,
                        to: settings,
                        toast: settings.muteFor > 0 ? L10n.telegram("PeerInfo.TooltipMutedForever") : nil,
                        client: client,
                    )
                }.present(from: overlayHost)
            },
        ))
        if !isGeneral, canOpenClose {
            let isClosed = topic.info.isClosed
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(isClosed ? "ChatList.Context.ReopenTopic" : "ChatList.Context.CloseTopic"),
                image: UIImage(systemName: isClosed ? "play" : "pause"),
            ) { [weak self] in
                self?.performTopicRequest(chatID: chatID, client: client) { client in
                    _ = try await client.send(TDNativeRequests.toggleForumTopicIsClosed(
                        chatId: chatID, forumTopicId: topicID, isClosed: !isClosed,
                    ))
                }
            })
        }
        if !isGeneral, chat.canDeleteAllMessages {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.Context.Delete"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
            ) { [weak self] in self?.confirmDeleteTopic(topicID, in: chatID, client: client) })
        }
        return actions
    }

    private func updateTopicNotifications(
        _ topicID: Int,
        in chatID: Int64,
        to settings: ChatNotificationSettings,
        toast: String?,
        client: TDLibClient,
    ) {
        performTopicRequest(chatID: chatID, client: client) { client in
            _ = try await client.send(TDNativeRequests.setForumTopicNotificationSettings(
                chatId: chatID, forumTopicId: topicID, notificationSettings: settings,
            ))
        } onSuccess: { [weak self] in
            guard let toast else { return }
            self?.showUndoToast(toast)
        }
    }

    /// Telegram asks in an action sheet before deleting a topic with all its messages.
    private func confirmDeleteTopic(_ topicID: Int, in chatID: Int64, client: TDLibClient) {
        guard overlayHost.presentedViewController == nil else { return }
        let sheet = UIAlertController(
            title: nil,
            message: L10n.telegram("ChatList.DeleteTopicConfirmationText"),
            preferredStyle: .actionSheet,
        )
        sheet.addAction(UIAlertAction(
            title: L10n.telegram("ChatList.DeleteTopicConfirmationAction"),
            style: .destructive,
        ) { [weak self] _ in
            self?.performTopicRequest(chatID: chatID, client: client) { client in
                _ = try await client.send(TDNativeRequests.deleteForumTopic(chatId: chatID, forumTopicId: topicID))
            }
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = overlayHost.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: overlayHost.view.bounds.midX,
            y: overlayHost.view.bounds.midY,
            width: 0,
            height: 0,
        )
        overlayHost.present(sheet, animated: true)
    }

    /// Runs a topic request on the row's client; the row reads its recent topics again once it succeeds, as a
    /// closed, read or deleted topic changes the line without a new last message.
    private func performTopicRequest(
        chatID: Int64,
        client: TDLibClient,
        _ request: @escaping (TDLibClient) async throws -> Void,
        onSuccess: (() -> Void)? = nil,
    ) {
        Task { [weak self] in
            guard await (try? request(client)) != nil else { return }
            ChatListForumTopics.shared.invalidateRecentTopics(chatID: chatID, client: client)
            guard self != nil, TDLib.shared.activeClient.id == client.id else { return }
            onSuccess?()
        }
    }

    /// Shown on the screen that owns this page, above the folder picker on the main list.
    private func showUndoToast(_ text: String, undo: (() -> Void)? = nil) {
        TelegramUndoToast.show(
            text: text,
            in: overlayHost.view,
            bottomInset: overlayBottomInset,
            undo: undo,
        )
    }

    /// Telegram's selectPeerThread: the list edits with the chats selected, Done ends it, the count titles the list
    /// and the toolbar offers Read (Read All with nothing selected), Archive or Unarchive, and Delete.
    private func beginChatSelection(with chatIDs: Set<Int64>) {
        guard actionAuthority.scope(owner: self).isCurrent, selectedChatIDs == nil, isSearchActive?() != true
        else { return }
        selectedChatIDs = chatIDs
        pressGesture?.isEnabled = false
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.setEditing(true, animated: true)
        let toolbar = ChatListSelectionToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.onLeft = { [weak self] in self?.readSelectedChats() }
        toolbar.onMiddle = { [weak self] in self?.archiveSelectedChats() }
        toolbar.onRight = { [weak self] in self?.deleteSelectedChats() }
        let host: UIView = overlayHost.view
        host.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            toolbar.topAnchor.constraint(
                equalTo: host.safeAreaLayoutGuide.bottomAnchor,
                constant: selectionToolbarTakesTabBarPlace ? 0 : -ChatListSelectionToolbar.contentHeight,
            ),
        ])
        selectionToolbar = toolbar
        updateChatSelection()
    }

    /// Telegram's donePressed: editing ends and the selection is cleared.
    private func endChatSelection() {
        guard selectedChatIDs != nil else { return }
        selectedChatIDs = nil
        let wasReordering = isReorderingPinnedChats
        isReorderingPinnedChats = false
        pressGesture?.isEnabled = true
        selectionToolbar?.removeFromSuperview()
        selectionToolbar = nil
        onSelectionEditingChange?(nil, nil)
        guard isViewLoaded else { return }
        for indexPath in tableView.indexPathsForSelectedRows ?? [] {
            tableView.deselectRow(at: indexPath, animated: false)
        }
        tableView.setEditing(false, animated: true)
        tableView.allowsMultipleSelectionDuringEditing = false
        // The list shows TDLib's order again, with what changed meanwhile.
        if wasReordering { updateSnapshot(animated: true) }
    }

    /// Keeps the checks, the title and the toolbar in step with the selection (chatListSelectionOptions): Read needs
    /// an unread chat, or Read All an unread chat in the list; Archive leaves out Saved Messages and service
    /// notifications.
    /// The row of the chat the split's detail pane shows stays highlighted, as ChatListController's
    /// `updateNavigationCustomData` does.
    private func updateSplitSelection() {
        guard selectedChatIDs == nil, isViewLoaded else { return }
        let chatID = NavigationStorage.shared.splitSelectedChatID.value
        for indexPath in tableView.indexPathsForSelectedRows ?? []
            where dataSource.itemIdentifier(for: indexPath) != chatID
        {
            tableView.deselectRow(at: indexPath, animated: false)
        }
        guard let chatID, let indexPath = dataSource.indexPath(for: chatID) else { return }
        tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
    }

    private func updateChatSelection() {
        guard var selected = selectedChatIDs, isViewLoaded else { return }
        let displayed = Set(dataSource.snapshot().itemIdentifiers)
        selected.formIntersection(displayed)
        selectedChatIDs = selected
        for indexPath in tableView.indexPathsForSelectedRows ?? []
            where dataSource.itemIdentifier(for: indexPath).map(selected.contains) != true
        {
            tableView.deselectRow(at: indexPath, animated: false)
        }
        let selectedRows = Set(tableView.indexPathsForSelectedRows ?? [])
        for id in selected {
            guard let indexPath = dataSource.indexPath(for: id), !selectedRows.contains(indexPath) else { continue }
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        }
        let chats = selected.compactMap { chat(for: $0) }
        func isUnread(_ chat: CustomChat) -> Bool { chat.unreadCount > 0 || chat.chat.isMarkedAsUnread }
        onSelectionEditingChange?(
            selected.isEmpty
                ? nil
                : L10n.telegramPlural(
                    "ChatList.SelectedChats",
                    count: selected.count,
                    formattedCount: selected.count.formatted(.number),
                ),
            { [weak self] in self?.endChatSelection() },
        )
        let archivable = !chats.isEmpty && !chats.contains {
            $0.isSavedMessages || $0.user?.id == Self.serviceNotificationsUserID
        }
        selectionToolbar?.update(
            left: L10n.telegram(selected.isEmpty ? "ChatList.ReadAll" : "ChatList.Read"),
            leftEnabled: selected.isEmpty ? folder.chats.contains(where: isUnread) : chats.contains(where: isUnread),
            middle: L10n.telegram(isArchivePage ? "ChatList.UnarchiveAction" : "ChatList.ArchiveAction"),
            middleEnabled: archivable,
            right: L10n.telegram("Common.Delete"),
            rightEnabled: !chats.isEmpty,
        )
    }

    /// Telegram's left action: the selected chats read, or with none selected the whole list (readChatList).
    private func readSelectedChats() {
        guard let selected = selectedChatIDs else { return }
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        if selected.isEmpty {
            let chatList = folder.chatList
            runAction(scope) {
                _ = try await client.send(TDNativeRequests.readChatList(chatList: chatList))
            }
        } else {
            for chat in selected.compactMap({ chat(for: $0) })
                where chat.unreadCount > 0 || chat.chat.isMarkedAsUnread
            {
                markRead(chat, scope: scope, client: client)
            }
        }
        endChatSelection()
    }

    /// Telegram's middle action: archiveChats with its Undo, or out of the archive.
    private func archiveSelectedChats() {
        guard let selected = selectedChatIDs, !selected.isEmpty else { return }
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        let ids = Array(selected)
        let archive = !isArchivePage
        endChatSelection()
        runAction(scope) { [weak self] in
            for id in ids {
                _ = try await client.addChatToList(chatId: id, chatList: archive ? .chatListArchive : .chatListMain)
            }
            guard archive, let self, scope.isCurrent else { return }
            showUndoToast(L10n.telegram("ChatList.UndoArchiveTitle")) { [weak self] in
                self?.runAction(scope) {
                    for id in ids {
                        _ = try await client.addChatToList(chatId: id, chatList: .chatListMain)
                    }
                }
            }
        }
    }

    /// Delete for one selected chat runs its own sheet, as the chat's menu does; several go through Telegram's
    /// removePeerChats sheet: with a person or a secret chat among them Delete from both sides (where possible) and
    /// Delete for me, otherwise Delete N Chats.
    private func deleteSelectedChats() {
        guard let selected = selectedChatIDs else { return }
        let chats = selected.compactMap { chat(for: $0) }
        guard !chats.isEmpty else { return }
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        if chats.count == 1, let chat = chats.first {
            endChatSelection()
            deleteChat(chat, scope: scope, client: client)
            return
        }
        let privateChats = chats.filter { chat in
            switch chat.chat.type {
            case .chatTypePrivate,
                 .chatTypeSecret: true
            default: false
            }
        }
        let hasPrivate = !privateChats.isEmpty
        let hasNonPrivate = privateChats.count < chats.count
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if hasPrivate {
            sheet.addAction(UIAlertAction(
                title: L10n.telegram(hasNonPrivate ? "ChatList.DeleteForAllWhenPossible" : "ChatList.DeleteForAll"),
                style: .destructive,
            ) { [weak self] _ in self?.removeChats(chats, globally: true, scope: scope, client: client) })
        }
        sheet.addAction(UIAlertAction(
            title: hasPrivate
                ? L10n.telegram("ChatList.DeleteForMe")
                : L10n.telegramPlural("ChatList.DeleteConfirmation", count: chats.count),
            style: .destructive,
        ) { [weak self] _ in self?.removeChats(chats, globally: false, scope: scope, client: client) })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        if traitCollection.horizontalSizeClass == .regular {
            sheet.popoverPresentationController?.sourceView = view
        }
        chatListTopPresenter.present(sheet, animated: true)
    }

    /// removePeerChats behind "Deleted N chats" and Undo: the rows leave at once, and when the toast has gone a
    /// person's
    /// chat is deleted (for both sides when asked and TDLib can), a secret chat closed and deleted, a basic group left
    /// and deleted, and a supergroup or channel left.
    private func removeChats(_ chats: [CustomChat], globally: Bool, scope: ChatListActionScope, client: TDLibClient) {
        guard scope.isCurrent else { return }
        endChatSelection()
        var cancels = [() -> Void]()
        for chat in chats {
            let chatID = chat.id
            let type = chat.chat.type
            let revoke = globally && chat.chat.canBeDeletedForAllUsers
            let cancel = PendingChatRemovals.shared.schedule(
                PendingChatRemovals.Key(clientID: client.id, chatID: chatID),
                hides: true,
            ) { [weak self] in
                guard scope.isCurrent else { return }
                do {
                    switch type {
                    case .chatTypePrivate:
                        _ = try await scope.perform {
                            try await client.deleteChatHistory(chatId: chatID, removeFromChatList: true, revoke: revoke)
                        }
                    case .chatTypeSecret(let secret):
                        _ = try await scope.perform {
                            try await client.send(TDNativeRequests.closeSecretChat(secretChatId: secret.secretChatId))
                        }
                        _ = try await scope.perform {
                            try await client.deleteChatHistory(chatId: chatID, removeFromChatList: true, revoke: true)
                        }
                    case .chatTypeBasicGroup:
                        _ = try? await scope
                            .perform { try await client.send(TDNativeRequests.leaveChat(chatId: chatID)) }
                        _ = try await scope.perform {
                            try await client.deleteChatHistory(chatId: chatID, removeFromChatList: true, revoke: false)
                        }
                    case .chatTypeSupergroup:
                        _ = try await scope
                            .perform { try await client.send(TDNativeRequests.leaveChat(chatId: chatID)) }
                    }
                } catch {
                    guard scope.isCurrent, let self else { return }
                    presentChatListActionFailure()
                }
            }
            cancels.append(cancel)
        }
        showUndoToast(L10n.telegramPlural("ChatList.DeletedChats", count: chats.count)) {
            cancels.forEach { $0() }
        }
    }

    /// Leaves reorder mode and shows the list as TDLib now orders it.
    private func endPinnedReorder() {
        guard isReorderingPinnedChats else { return }
        // Edit reorders while it selects; both end together.
        if selectedChatIDs != nil { return endChatSelection() }
        isReorderingPinnedChats = false
        pressGesture?.isEnabled = true
        guard isViewLoaded else { return }
        tableView.setEditing(false, animated: true)
        updateSnapshot(animated: true)
    }

    /// Telegram (ChatListNode.reorderItem) rebuilds the list's whole pinned order around the drop target, including
    /// pinned chats this page does not show, and saves it at once. TDLib keeps a folder's pinned chats in the folder.
    private func commitPinnedMove(_ movedID: Int64, relativeTo referenceID: Int64, movedDown: Bool) {
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        guard scope.isCurrent else {
            endPinnedReorder()
            return
        }
        let chatList = folder.chatList
        var chatIDs = TelegramChatListStore.shared.pinnedChatIDs(in: chatList).filter { $0 != movedID }
        if let index = chatIDs.firstIndex(of: referenceID) {
            chatIDs.insert(movedID, at: movedDown ? index + 1 : index)
        } else {
            chatIDs.append(movedID)
        }
        let order = chatIDs
        runAction(scope, onFailure: { [weak self] _ in
            self?.endPinnedReorder()
            self?.presentChatListActionFailure()
        }) {
            _ = try await client.send(TDNativeRequests.setPinnedChats(chatList: chatList, chatIds: order))
        }
    }

    private func removeFromCurrentFolder(_ chat: CustomChat) {
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        guard scope.isCurrent, case .folder(let info, let definition) = folder.type else { return }
        let updated = definition.removing(chatID: chat.id)
        runAction(scope) {
            _ = try await client.editChatFolder(chatFolderId: info.id, folder: updated)
        }
    }

    /// Runs a row action on this page's client. A failure is reported unless its account, client or page changed.
    private func runAction(
        _ scope: ChatListActionScope,
        onFailure: ((any Swift.Error) -> Void)? = nil,
        _ request: @escaping @MainActor () async throws -> Void,
    ) {
        Task { [weak self] in
            do {
                try await scope.perform(request)
            } catch {
                guard scope.isCurrent, let self else { return }
                if let onFailure {
                    onFailure(error)
                } else {
                    presentChatListActionFailure()
                }
            }
        }
    }

    /// A TDLib limit gets Telegram's limit alert; anything else gets the generic error.
    private func presentFailure(limit: TDNativePremiumLimitType?, scope: ChatListActionScope, client: TDLibClient) {
        if let limit {
            presentLimit(limit, scope: scope, client: client)
        } else {
            presentChatListActionFailure()
        }
    }

    /// Telegram's limit screen (PremiumLimitScreen, subjects .pins and .chatsPerFolder) as an alert.
    private func presentLimit(_ limitType: TDNativePremiumLimitType, scope: ChatListActionScope, client: TDLibClient) {
        let isFolderLimit =
            if case .premiumLimitTypeChatFolderChosenChatCount = limitType {
                true
            } else {
                false
            }
        Task { [weak self] in
            let limit: TDNativePremiumLimit
            do {
                limit = try await scope.perform {
                    try await client.send(TDNativeRequests.getPremiumLimit(limitType: limitType))
                }
            } catch {
                guard scope.isCurrent else { return }
                self?.presentChatListActionFailure()
                return
            }
            let me = try? await scope.perform { try await client.getMe() }
            var premiumAvailable = true
            if case .optionValueBoolean(let value) = try? await scope.perform({
                try await client.getOption(name: "is_premium_available")
            }) {
                premiumAvailable = value.value
            }
            guard let self, scope.isCurrent else { return }
            let defaultValue = "\(limit.defaultValue)"
            let premiumValue = "\(limit.premiumValue)"
            let message =
                if !premiumAvailable {
                    L10n.telegram(
                        isFolderLimit ? "Premium.MaxChatsInFolderNoPremiumText" : "Premium.MaxPinsNoPremiumText",
                        defaultValue,
                    )
                } else if me?.isPremium == true {
                    L10n.telegram(
                        isFolderLimit ? "Premium.MaxChatsInFolderFinalText" : "Premium.MaxPinsFinalText",
                        premiumValue,
                    )
                } else {
                    L10n.telegram(
                        isFolderLimit ? "Premium.MaxChatsInFolderText" : "Premium.MaxPinsText",
                        defaultValue,
                        premiumValue,
                    )
                }
            let alert = UIAlertController(
                title: L10n.telegram("Premium.LimitReached"),
                message: message.withoutTelegramMarkup,
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
            chatListTopPresenter.present(alert, animated: true)
        }
    }
}

private extension CustomChat {
    /// TDLib lists the folders that hold a chat in chat_lists; a loaded folder also gives it a position there.
    func isListed(in list: ChatList) -> Bool {
        chat.chatLists.contains(list) || chat.positions.contains { $0.list == list && $0.order != 0 }
    }
}

private extension Swift.Error {
    func isTDLibLimit(_ fragment: String) -> Bool {
        (self as? TDLibError)?.message.contains(fragment) == true
    }
}

private extension ChatFolder {
    func adding(chatID: Int64) -> ChatFolder {
        copy(
            excludedChatIds: excludedChatIds.filter { $0 != chatID },
            includedChatIds: includedChatIds.contains(chatID) ? includedChatIds : includedChatIds + [chatID],
            pinnedChatIds: pinnedChatIds,
        )
    }

    func removing(chatID: Int64) -> ChatFolder {
        copy(
            excludedChatIds: excludedChatIds.contains(chatID) ? excludedChatIds : excludedChatIds + [chatID],
            includedChatIds: includedChatIds.filter { $0 != chatID },
            pinnedChatIds: pinnedChatIds.filter { $0 != chatID },
        )
    }

    private func copy(
        excludedChatIds: [Int64],
        includedChatIds: [Int64],
        pinnedChatIds: [Int64],
    ) -> ChatFolder {
        ChatFolder(
            colorId: colorId,
            excludeArchived: excludeArchived,
            excludeMuted: excludeMuted,
            excludeRead: excludeRead,
            excludedChatIds: excludedChatIds,
            icon: icon,
            includeBots: includeBots,
            includeChannels: includeChannels,
            includeContacts: includeContacts,
            includeGroups: includeGroups,
            includeNonContacts: includeNonContacts,
            includedChatIds: includedChatIds,
            isShareable: isShareable,
            name: name,
            pinnedChatIds: pinnedChatIds,
        )
    }
}

private extension ChatNotificationSettings {
    func withMuteFor(_ muteFor: Int) -> ChatNotificationSettings {
        ChatNotificationSettings(
            disableMentionNotifications: disableMentionNotifications,
            disablePinnedMessageNotifications: disablePinnedMessageNotifications,
            muteFor: muteFor,
            muteStories: muteStories,
            showPreview: showPreview,
            showStoryPoster: showStoryPoster,
            soundId: soundId,
            storySoundId: storySoundId,
            useDefaultDisableMentionNotifications: useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: false,
            useDefaultMuteStories: useDefaultMuteStories,
            useDefaultShowPreview: useDefaultShowPreview,
            useDefaultShowStoryPoster: useDefaultShowStoryPoster,
            useDefaultSound: useDefaultSound,
            useDefaultStorySound: useDefaultStorySound,
        )
    }
}

// MARK: - ArchiveViewController + TelegramGlassPlatterHost

extension ArchiveViewController: TelegramGlassPlatterHost {
    var telegramGlassPlatters: [TelegramGlassPlatter] { navigationBarView.glassPlatters }
}

// MARK: - ChatRowPressGestureDelegate

/// Keeps a chat row's long press off a touch that starts on an avatar with its own menu: both presses began, the
/// avatar's menu took the touch and the row stayed pressed.
private final class ChatRowPressGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if let avatar = current as? ProfileAvatarView, avatar.showsContextMenu { return false }
            if current is UITableViewCell { return true }
            view = current.superview
        }
        return true
    }
}

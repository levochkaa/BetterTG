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
    private var currentNavigationContentHeight = TelegramListNavigationBar.expandedContentHeight

    var navigationClientSource: TdUpdateSource? { actionAuthority.scope(owner: self).source }

    init(folder: CustomFolder, rootVM: RootVM, restoration: ClientRestorationState? = nil) {
        self.rootVM = rootVM
        self.query = restoration?.query ?? ""
        self.restoresSearchFocus = restoration?.searchWasFocused ?? false
        self.folderController = FolderViewController(
            folder: folder, rootVM: rootVM, showsStandaloneSearch: true,
            actionAuthority: actionAuthority, restorationViewport: restoration?.viewport,
        )
        folderController.setSearchActive(
            restoration?.searchWasFocused ?? false,
            animated: false,
            preservingViewport: true,
        )
        self.navigationBarView = TelegramListNavigationBar(
            title: folder.name,
            placeholder: L10n.betterTG("Folders.SearchIn", folder.name.lowercased()),
            leftImage: UIImage(systemName: "chevron.left"),
            rightImage: nil,
            leftAction: { NavigationStorage.shared.pop() },
            rightAction: nil,
            showsBackButton: true,
        )
        super.init(nibName: nil, bundle: nil)
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
            if !active, isShowingSearchResults {
                // The query stays on screen above its results; the archive list restored its own offset.
                navigationBarView.applyScroll(offset: 0, animated: true)
            }
            scheduleRestorationRetry()
        }
        navigationBarView.onVisibleHeightChange = { [weak self] contentHeight in
            guard let self else { return }
            currentNavigationContentHeight = contentHeight
            navigationBarHeightConstraint?.constant = view.safeAreaInsets.top + contentHeight
        }
        TDLib.shared
            .chatListNetworkStatus
            .sink { [weak self] status in self?.navigationBarView.setNetworkStatus(status) }
            .store(in: &cancellables)
        view.addSubview(navigationBarView)
        navigationBarHeightConstraint = navigationBarView.heightAnchor.constraint(
            equalToConstant: view.safeAreaInsets.top + TelegramListNavigationBar.expandedContentHeight,
        )

        NSLayoutConstraint.activate([
            navigationBarView.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBarHeightConstraint,
        ])
        configureSearchResults()
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
        navigationBarHeightConstraint?.constant = view.safeAreaInsets.top + currentNavigationContentHeight
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if actionAuthority.isCurrent, restoresSearchFocus {
            restoresSearchFocus = false
            isRestoringSearchFocus = true
            navigationBarView.focusSearch()
            isRestoringSearchFocus = false
        }
        scheduleRestorationRetry()
    }

    func prepareReplacementForReadyClient(_ source: TdUpdateSource) -> PreparedClientNavigationReplacement? {
        guard canRestoreClient(source), let folder = rootVM.archive else { return nil }
        let state = ClientRestorationState(
            query: query,
            searchWasFocused: isViewLoaded ? navigationBarView.isSearchActive : restoresSearchFocus,
            viewport: folderController.clientRestorationViewport(),
        )
        let rootVM = rootVM
        return PreparedClientNavigationReplacement(
            preflight: { [weak self] in
                self?.canRestoreClient(source) == true && rootVM.archive === folder
            },
            commit: {
                let replacement = ArchiveViewController(folder: folder, rootVM: rootVM, restoration: state)
                #if DEBUG
                    log("Archive client restoration: replacement accepted; search-focus=\(state.searchWasFocused)")
                #endif
                return replacement
            },
        )
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
            folder: folder, rootVM: rootVM, showsStandaloneSearch: true,
            actionAuthority: actionAuthority, restorationViewport: viewport,
        )
        folderController.setSearchActive(navigationBarView.isSearchActive, animated: false, preservingViewport: true)
        installFolderController()
        view.bringSubviewToFront(navigationBarView)
    }

    private func installFolderController() {
        folderController.isSearchActive = { [weak self] in self?.navigationBarView.isSearchActive == true }
        folderController.onSearchScrollOffsetChange = { [weak self] offset in
            guard let self, !isShowingSearchResults else { return }
            navigationBarView.applyScroll(offset: offset)
        }
        folderController.onListInteractionEnded = { [weak self] in self?.scheduleRestorationRetry() }
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

    private func configureSearchResults() {
        searchResultsController.chatMenu = { [weak self] chat in
            self?.folderController.searchResultMenu(for: chat) ?? []
        }
        addChild(searchResultsController)
        let resultsView = searchResultsController.view!
        resultsView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(resultsView, belowSubview: navigationBarView)
        searchResultsController.didMove(toParent: self)
        // Results end above the keyboard; without it they reach the bottom edge and inset for the home indicator.
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            resultsView.topAnchor.constraint(equalTo: navigationBarView.bottomAnchor),
            resultsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultsView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
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
            navigationBarView.applyScroll(offset: 0, animated: animated)
        } else {
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
    var onSearchScrollOffsetChange: ((CGFloat) -> Void)?
    var isSearchActive: (() -> Bool)?
    /// The main screen leaves a pan that starts near a side edge to folder paging, as Telegram's chat list does.
    var allowsRowSwipe: (() -> Bool)?
    var onListInteractionEnded: (() -> Void)?

    private let showsStandaloneSearch: Bool
    private let rootVM: RootVM
    private let actionAuthority: ChatListActionAuthority
    private var searchActive = false
    /// The height of the header panels under the navigation bar (the playback header), which the rows sit below.
    private var accessoryTopInset = CGFloat.zero
    private var didSetInitialSearchOffset = false
    private var initialSearchScrollOffset = ChatListNavigationSearchView.scrollHeight
    /// Where the page was before the shared search began. Search covers every page, as Telegram's search overlay
    /// does, and ending it returns each page there instead of scrolling it to the top with search revealed.
    private var viewportBeforeSearch: ChatListViewportSnapshot?
    private var initialSearchScrollOffsetBeforeSearch: CGFloat?
    private var clientViewportRestoration: ChatListViewportRestoration
    private var cancellables = Set<AnyCancellable>()
    private var prefetchTasks = [Int64: Task<Void, Never>]()
    private var chatsByID = [Int64: CustomChat]()
    private var pendingChangedChatIDs = Set<Int64>()
    private var chatUpdateScheduled = false
    private var isApplyingSnapshot = false
    private var snapshotNeedsApply = false
    private var pendingSnapshotAnimated = false
    private var pendingSnapshotChangedIDs = Set<Int64>()
    /// The last applied snapshot had no rows.
    private var showsNoRows = false
    private var emptyState: EmptyState?
    private var dataSource: ChatRowsDataSource!
    private var pressGesture: ContextMenuPressGestureRecognizer?
    /// Telegram's reorder mode for pinned chats; list updates wait until it ends so a drag is never interrupted.
    private var isReorderingPinnedChats = false
    private var reorderDoneButton: UIButton?

    var isInteractingWithList: Bool {
        guard isViewLoaded else { return false }
        // A tracking-only touch has no terminal scroll callback to retry from.
        return tableView.isDragging || tableView.isDecelerating
    }

    var searchScrollOffset: CGFloat {
        guard isViewLoaded, didSetInitialSearchOffset else { return initialSearchScrollOffset }
        return min(
            ChatListNavigationSearchView.scrollHeight,
            max(0, tableView.contentOffset.y + tableView.adjustedContentInset.top),
        )
    }

    private var orderedChats: [CustomChat] {
        folder.chats
            .sorted { $0.position.order == $1.position.order ? $0.id > $1.id : $0.position.order > $1.position.order }
    }

    private var isArchivePage: Bool {
        if case .archive = folder.type { return true }
        return false
    }

    /// The screen that owns this page: overlays sit there, above the folder picker on the main list.
    private var overlayHost: UIViewController {
        var host: UIViewController = self
        while let parent = host.parent, !(parent is UINavigationController) {
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

    init(
        folder: CustomFolder,
        rootVM: RootVM,
        showsStandaloneSearch: Bool,
        actionAuthority: ChatListActionAuthority? = nil,
        restorationViewport: ChatListViewportSnapshot? = nil,
    ) {
        self.folder = folder
        self.rootVM = rootVM
        self.actionAuthority = actionAuthority ?? ChatListActionAuthority()
        self.showsStandaloneSearch = showsStandaloneSearch
        self.clientViewportRestoration = ChatListViewportRestoration(restorationViewport)
        if let restorationViewport {
            self.initialSearchScrollOffset = min(
                ChatListNavigationSearchView.scrollHeight,
                max(0, restorationViewport.offsetFromTop),
            )
        }
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
        view.backgroundColor = .systemGroupedBackground
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .none
        tableView.rowHeight = ChatListCell.cardRowHeight
        tableView.keyboardDismissMode = .interactive
        tableView.alwaysBounceVertical = true
        let initialTopInset = searchActive
            ? ChatListNavigationSearchView.scrollHeight
            : TelegramListNavigationBar.expandedContentHeight
        tableView.contentInset.top = initialTopInset + accessoryTopInset
        tableView.contentInset.bottom = showsStandaloneSearch ? 0 : 58
        tableView.verticalScrollIndicatorInsets.top = initialTopInset + accessoryTopInset
        tableView.verticalScrollIndicatorInsets.bottom = showsStandaloneSearch ? 0 : 58
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        endPinnedReorder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didSetInitialSearchOffset,
              clientViewportRestoration.snapshotIsApplied,
              tableView.bounds.width > 0, tableView.bounds.height > 0,
              dataSource.snapshot().numberOfItems == 0 || tableView.contentSize.height > 0
        else { return }
        didSetInitialSearchOffset = true
        if let viewport = clientViewportRestoration.takeForLayout(usable: true) {
            viewport.restore(tableView: tableView) { dataSource.indexPath(for: $0) }
        } else {
            tableView.setContentOffset(
                CGPoint(x: 0, y: -tableView.adjustedContentInset.top + initialSearchScrollOffset),
                animated: false,
            )
        }
        onSearchScrollOffsetChange?(searchScrollOffset)
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        onSearchScrollOffsetChange?(searchScrollOffset)
    }

    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        clientViewportRestoration.cancel()
        didSetInitialSearchOffset = true
    }

    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView === tableView, !decelerate { onListInteractionEnded?() }
    }

    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView === tableView { onListInteractionEnded?() }
    }

    override func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity _: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>,
    ) {
        guard scrollView === tableView, isSearchActive?() != true else { return }
        let top = -scrollView.adjustedContentInset.top
        let distance = targetContentOffset.pointee.y - top
        guard distance > 0, distance < ChatListNavigationSearchView.scrollHeight else { return }
        let targetDistance = distance < ChatListNavigationSearchView.scrollHeight * 0.5
            ? CGFloat.zero
            : ChatListNavigationSearchView.scrollHeight
        targetContentOffset.pointee.y = top + targetDistance
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let chatID = dataSource.itemIdentifier(for: indexPath), let chat = chat(for: chatID) else { return }
        NavigationStorage.shared.push(.customChat(chat))
    }

    override func tableView(_ tableView: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= tableView.numberOfRows(inSection: indexPath.section) - 12 {
            loadMoreChatsIfNeeded()
        }
    }

    override func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt _: IndexPath,
    ) -> UITableViewCell.EditingStyle {
        // Reordering shows only the grip; outside it the style lets UIKit offer the row's swipe actions.
        tableView.isEditing ? .none : .delete
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

    func clientRestorationViewport() -> ChatListViewportSnapshot {
        guard isViewLoaded, didSetInitialSearchOffset else {
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
        tableView.verticalScrollIndicatorInsets.top += delta
        tableView.contentOffset.y = offset - delta
    }

    func setSearchActive(_ active: Bool, animated: Bool, preservingViewport: Bool = false) {
        if active { endPinnedReorder() }
        let wasActive = searchActive
        if active, !wasActive {
            viewportBeforeSearch = isViewLoaded && didSetInitialSearchOffset ? clientRestorationViewport() : nil
            initialSearchScrollOffsetBeforeSearch = initialSearchScrollOffset
        }
        let viewport = preservingViewport
            ? clientRestorationViewport()
            : (!active && wasActive ? viewportBeforeSearch : nil)
        searchActive = active
        if active {
            initialSearchScrollOffset = 0
        } else if wasActive {
            initialSearchScrollOffset = initialSearchScrollOffsetBeforeSearch ?? initialSearchScrollOffset
            viewportBeforeSearch = nil
            initialSearchScrollOffsetBeforeSearch = nil
        }
        guard isViewLoaded else { return }
        let targetTopInset = active
            ? ChatListNavigationSearchView.scrollHeight
            : TelegramListNavigationBar.expandedContentHeight
        let changes = {
            self.tableView.contentInset.top = targetTopInset + self.accessoryTopInset
            self.tableView.verticalScrollIndicatorInsets.top = targetTopInset + self.accessoryTopInset
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
        dataSource.canSwipeRow = { [weak self] indexPath in
            guard let self, !isReorderingPinnedChats, let id = dataSource.itemIdentifier(for: indexPath) else {
                return false
            }
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
        folder.chatDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] chatID in
                self?.scheduleChatUpdate(id: chatID)
            }
            .store(in: &cancellables)
    }

    private func rebuildChatIndex() {
        // Retain rows from the previous snapshot until its animations finish.
        chatsByID.merge(
            Dictionary(uniqueKeysWithValues: folder.chats.map { ($0.id, $0) }),
            uniquingKeysWith: { _, latest in latest },
        )
        let currentIDs = Set(folder.chats.map(\.id))
        for id in Array(prefetchTasks.keys) where !currentIDs.contains(id) {
            prefetchTasks[id]?.cancel()
            prefetchTasks[id] = nil
        }
    }

    private func scheduleChatUpdate(id: Int64) {
        pendingChangedChatIDs.insert(id)
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
        let displayedChats = orderedChats.filter {
            !PendingChatRemovals.shared.isHidden(clientID: clientID, chatID: $0.id)
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
            guard didSetInitialSearchOffset, clientViewportRestoration.pending == nil,
                  !isInteractingWithList, !tableView.isTracking
            else { return nil }
            let offset = tableView.contentOffset.y + tableView.adjustedContentInset.top
            return offset <= ChatListNavigationSearchView.scrollHeight + 0.5 ? offset : nil
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
            if !didSetInitialSearchOffset { view.setNeedsLayout() }
            let retainedIDs = Set(dataSource.snapshot().itemIdentifiers).union(folder.chats.map(\.id))
            chatsByID = chatsByID.filter { retainedIDs.contains($0.key) }
            loadMoreChatsIfNeeded()
            DispatchQueue.main.async { [weak self] in self?.applyPendingSnapshot() }
        }
        showsNoRows = displayedChats.isEmpty
        updateEmptyState()
    }

    /// The topmost visible row that stays among its neighbours: a chat that itself moves keeps no place to hold.
    private func stableVisibleRow(from previousIDs: [Int64], to nextIDs: [Int64]) -> VisibleRowAnchor? {
        guard didSetInitialSearchOffset, clientViewportRestoration.pending == nil, !isInteractingWithList,
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
            } else if folder.loadError != nil || !folder.hasMoreChats {
                .empty
            } else {
                .loading
            }
        guard state != emptyState else { return }
        emptyState = state
        tableView.backgroundView =
            switch state {
            case .empty: emptyLabel()
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

    private func emptyLabel() -> UIView {
        let label = UILabel()
        label.text = L10n.telegram("ChatList.EmptyChatListFilterTitle")
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        return label
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
        // Telegram offers Reorder on a pinned item (ChatContextMenus, Chat.InlineTopicMenu.Reorder); BetterTG has no
        // Edit mode, so this is the way into reordering pinned chats.
        if !inSearch, pinned, folder.chats.filter(\.position.isPinned).count > 1, isSearchActive?() != true {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Chat.InlineTopicMenu.Reorder"),
                image: UIImage(systemName: "arrow.up.arrow.down"),
            ) { [weak self] in
                self?.beginPinnedReorder()
            })
        }
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
        return actions
    }

    // MARK: Row actions

    private func swipeChat(at indexPath: IndexPath) -> CustomChat? {
        guard actionAuthority.scope(owner: self).isCurrent, !isReorderingPinnedChats, allowsRowSwipe?() != false,
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

    @objc private func chatLongPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              let chatID = dataSource.itemIdentifier(for: indexPath),
              let chat = chat(for: chatID),
              let cell = tableView.cellForRow(at: indexPath) as? ChatListCell
        else { return }
        // Telegram previews a forum with its topic list (ChatListController, previewing: true).
        let previewController: UIViewController =
            if chat.chat.viewAsTopics {
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
            actions: menu(for: chat),
            tracking: gesture,
            presentationStyle: .chatPreview,
            previewController: previewController,
        )
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

    private func beginPinnedReorder() {
        guard actionAuthority.scope(owner: self).isCurrent, !isReorderingPinnedChats, isSearchActive?() != true
        else { return }
        isReorderingPinnedChats = true
        pressGesture?.isEnabled = false
        tableView.setEditing(true, animated: true)

        var configuration = UIButton.Configuration.filled()
        configuration.title = L10n.telegram("Common.Done")
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 28, bottom: 10, trailing: 28)
        let button = UIButton(
            configuration: configuration,
            primaryAction: UIAction { [weak self] _ in self?.endPinnedReorder() },
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        let host: UIView = overlayHost.view
        host.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            button.bottomAnchor.constraint(
                equalTo: host.safeAreaLayoutGuide.bottomAnchor,
                constant: -overlayBottomInset,
            ),
        ])
        reorderDoneButton = button
        UIAccessibility.post(notification: .layoutChanged, argument: button)
    }

    /// Leaves reorder mode and shows the list as TDLib now orders it.
    private func endPinnedReorder() {
        guard isReorderingPinnedChats else { return }
        isReorderingPinnedChats = false
        pressGesture?.isEnabled = true
        reorderDoneButton?.removeFromSuperview()
        reorderDoneButton = nil
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

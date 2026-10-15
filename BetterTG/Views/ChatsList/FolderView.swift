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
        view.backgroundColor = .systemBackground

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
        let first = tableView.indexPathsForVisibleRows?.sorted().first
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

    private struct VisibleRowAnchor {
        let id: Int64
        let minYRelativeToOffset: CGFloat
        let previousIndex: Int
        let nextIndex: Int
    }

    // MARK: Internal

    let folder: CustomFolder
    var onSearchScrollOffsetChange: ((CGFloat) -> Void)?
    var isSearchActive: (() -> Bool)?
    var onListInteractionEnded: (() -> Void)?

    private let showsStandaloneSearch: Bool
    private let rootVM: RootVM
    private let actionAuthority: ChatListActionAuthority
    private var searchActive = false
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
    private var dataSource: UITableViewDiffableDataSource<Section, Int64>!

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
        view.backgroundColor = .systemBackground
        tableView.backgroundColor = .systemBackground
        tableView.separatorStyle = .none
        tableView.rowHeight = 76
        tableView.keyboardDismissMode = .interactive
        tableView.alwaysBounceVertical = true
        let initialTopInset = searchActive
            ? ChatListNavigationSearchView.scrollHeight
            : TelegramListNavigationBar.expandedContentHeight
        tableView.contentInset.top = initialTopInset
        tableView.contentInset.bottom = showsStandaloneSearch ? 0 : 58
        tableView.verticalScrollIndicatorInsets.top = initialTopInset
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

    func setSearchActive(_ active: Bool, animated: Bool, preservingViewport: Bool = false) {
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
            self.tableView.contentInset.top = targetTopInset
            self.tableView.verticalScrollIndicatorInsets.top = targetTopInset
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

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<
            Section,
            Int64,
        >(tableView: tableView) { [weak self] tableView, indexPath, id in
            guard let self, let chat = chat(for: id),
                  let cell = tableView.dequeueReusableCell(
                      withIdentifier: ChatListCell.reuseIdentifier,
                      for: indexPath,
                  ) as? ChatListCell
            else { return UITableViewCell() }
            cell.configure(chat: chat, isMuted: rootVM.isMuted(chat), client: actionAuthority.client)
            return cell
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
        guard snapshotNeedsApply, !isApplyingSnapshot else { return }
        snapshotNeedsApply = false
        let animated = pendingSnapshotAnimated
        let changedIDs = pendingSnapshotChangedIDs
        pendingSnapshotAnimated = false
        pendingSnapshotChangedIDs.removeAll()
        // Membership can change before a queued UI publisher runs. Populate the
        // provider cache before publishing new identifiers, including on scope updates.
        rebuildChatIndex()
        let displayedChats = orderedChats
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
        tableView.backgroundView = displayedChats.isEmpty ? emptyLabel() : nil
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
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.frame.size = CGSize(width: tableView.bounds.width, height: 44)
            spinner.startAnimating()
            tableView.tableFooterView = spinner
        } else {
            tableView.tableFooterView = nil
            loadMoreChatsIfNeeded()
        }
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

    private func menu(for chat: CustomChat) -> [TelegramContextMenuAction] {
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        guard scope.isCurrent else { return [] }
        let pinned = chat.position.isPinned
        let unread = chat.unreadCount > 0 || chat.chat.isMarkedAsUnread
        let archived = chat.chat.positions.contains { $0.list == .chatListArchive && $0.order != 0 }
        let muted = rootVM.isMuted(chat)
        let isCustomFolder =
            if case .folder = folder.type {
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
            // submenu of the same menu, and hides the item when there is none.
            let targets = rootVM.folders.compactMap { folder -> (id: Int, name: String, folder: ChatFolder)? in
                guard case .folder(let info, let definition) = folder.type,
                      !folder.chats.contains(where: { $0.id == chat.id })
                else { return nil }
                return (info.id, folder.name, definition)
            }
            if !targets.isEmpty {
                actions.append(TelegramContextMenuAction(
                    title: L10n.telegram("ChatList.Context.AddToFolder"),
                    image: UIImage(systemName: "folder.badge.plus"),
                    children: targets.map { target in
                        TelegramContextMenuAction(title: target.name, image: UIImage(systemName: "folder")) {
                            Task {
                                _ = try? await scope.perform {
                                    try await client.editChatFolder(
                                        chatFolderId: target.id,
                                        folder: target.folder.adding(chatID: chat.id),
                                    )
                                }
                            }
                        }
                    },
                ))
            }
        }
        actions += [
            TelegramContextMenuAction(
                title: unread
                    ? L10n.telegram("ChatList.Context.MarkAsRead")
                    : L10n.telegram("ChatList.Context.MarkAsUnread"),
                image: UIImage(systemName: unread ? "envelope.open" : "envelope.badge"),
            ) {
                Task {
                    if unread {
                        if let messageID = chat.lastMessage?.id {
                            _ = try? await scope.perform {
                                try await client.viewMessages(
                                    chatId: chat.id,
                                    forceRead: true,
                                    messageIds: [messageID],
                                    source: nil,
                                )
                            }
                        }
                        _ = try? await scope.perform {
                            try await client.toggleChatIsMarkedAsUnread(chatId: chat.id, isMarkedAsUnread: false)
                        }
                    } else {
                        _ = try? await scope.perform {
                            try await client.toggleChatIsMarkedAsUnread(chatId: chat.id, isMarkedAsUnread: true)
                        }
                    }
                }
            },
            TelegramContextMenuAction(
                title: archived
                    ? L10n.telegram("ChatList.Context.Unarchive")
                    : L10n.telegram("ChatList.Context.Archive"),
                image: UIImage(systemName: archived ? "tray.and.arrow.up" : "archivebox"),
            ) { [weak self] in
                Task { [weak self] in
                    let moved = await (try? scope.perform {
                        try await client.addChatToList(
                            chatId: chat.id,
                            chatList: archived ? .chatListMain : .chatListArchive,
                        )
                    }) != nil
                    // Telegram (ChatListController, archiveChats) offers Undo after archiving.
                    guard moved, !archived, let self, scope.isCurrent else { return }
                    showUndoToast(L10n.telegram("ChatList.UndoArchiveTitle")) {
                        Task {
                            _ = try? await scope.perform {
                                try await client.addChatToList(chatId: chat.id, chatList: .chatListMain)
                            }
                        }
                    }
                }
            },
            TelegramContextMenuAction(
                title: pinned
                    ? L10n.telegram("ChatList.Context.Unpin")
                    : L10n.telegram("ChatList.Context.Pin"),
                image: UIImage(systemName: pinned ? "pin.slash.fill" : "pin.fill"),
            ) { [weak self] in
                guard let self else { return }
                Task {
                    _ = try? await scope.perform {
                        try await client.toggleChatIsPinned(
                            chatId: chat.id,
                            chatList: self.folder.chatList,
                            isPinned: !pinned,
                        )
                    }
                }
            },
            TelegramContextMenuAction(
                title: muted
                    ? L10n.telegram("ChatList.Context.Unmute")
                    : L10n.telegram("ChatList.Context.Mute"),
                image: UIImage(systemName: muted ? "speaker.wave.2.fill" : "speaker.slash.fill"),
            ) {
                Task {
                    _ = try? await scope.perform {
                        try await client.setChatNotificationSettings(
                            chatId: chat.id,
                            notificationSettings: chat.chat.notificationSettings.withMuteFor(
                                muted ? 0 : Int(Int32.max),
                            ),
                        )
                    }
                }
            },
        ]

        if chat.chat.canBeDeletedOnlyForSelf || chat.chat.canBeDeletedForAllUsers {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.Context.Delete"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
                startsNewSection: true,
            ) { [weak self] in
                self?.confirmDelete(
                    chat: chat,
                    forAll: !chat.chat.canBeDeletedOnlyForSelf && chat.chat.canBeDeletedForAllUsers,
                )
            })
        }
        return actions
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
    private func showUndoToast(_ text: String, undo: @escaping () -> Void) {
        var host: UIViewController = self
        while let parent = host.parent, !(parent is UINavigationController) {
            host = parent
        }
        TelegramUndoToast.show(
            text: text,
            in: host.view,
            bottomInset: showsStandaloneSearch ? 12 : 64,
            undo: undo,
        )
    }

    private func removeFromCurrentFolder(_ chat: CustomChat) {
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        guard scope.isCurrent, case .folder(let info, let definition) = folder.type else { return }
        let updated = definition.removing(chatID: chat.id)
        Task {
            _ = try? await scope.perform {
                try await client.editChatFolder(chatFolderId: info.id, folder: updated)
            }
        }
    }

    private func confirmDelete(chat: CustomChat, forAll: Bool) {
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        guard scope.isCurrent else { return }
        let alert = UIAlertController(
            title: L10n.telegram("ChatList.DeleteChat"),
            message: L10n.telegram("ChatList.DeleteChatConfirmation", chat.displayTitle),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Delete"), style: .destructive) { _ in
            Task {
                _ = try? await scope.perform {
                    try await client.deleteChatHistory(
                        chatId: chat.id,
                        removeFromChatList: true,
                        revoke: forAll,
                    )
                }
            }
        })
        present(alert, animated: true)
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

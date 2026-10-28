// ForwardForumTopicsViewController.swift

import TDLibKit
import UIKit

// MARK: - ForwardForumTopicsViewController

@MainActor final class ForwardForumTopicsViewController: UIViewController, UITableViewDelegate {
    private enum Section {
        case topics
    }

    var onSelect: ((ForumTopic) -> Void)?

    #if DEBUG
    var probeReadPage: ((String, ForumTopicPageCursor) async throws -> ForumTopics)?
    var probeCurrentContext: (() -> Bool)?
    var probeInitialRights: Bool?
    var probeSnapshotCompletion: ((@escaping () -> Void) -> Void)?
    var probeError: ((String) -> Void)?
    var probeOmitCellModel = false
    private(set) var probeSnapshotStarts = 0
    var probeTable: UITableView { tableView }
    var probeSnapshotBusy: Bool { snapshotState.isApplying || snapshotState.hasPending }
    var probeIDs: [Int] { snapshotState.displayedIDs }
    var probeCursor: ForumTopicPageCursor { cursor }
    var probeLoading: Bool { loading }
    var probeRetired: Bool { retired }
    var probeWasContained: Bool { wasContained }
    var probeContextIsCurrent: Bool { contextIsCurrent }
    var probePinnedIDs: [Int] { pinnedOrder.ids }
    var probeTask: Task<Void, Never>? { loadTask }
    func probeTopic(_ id: Int) -> ForumTopic? { snapshotState.topic(id: id) }
    func probeSearch(_ text: String) { searchQueryChanged(text) }
    func probeLoadMore() { load(reset: false) }
    func probeSelect(_ row: Int) { tableView(tableView, didSelectRowAt: IndexPath(row: row, section: 0)) }
    func probeReconfigure() { applySnapshot() }
    #endif

    private let chat: Chat
    private let preparedForward: PreparedMessageForward
    private let client: TDLibClient
    private let accountID: UUID
    private let tableView = ForumTopicsTableView(frame: .zero, style: .plain)
    /// The main topic list's chrome: Telegram's list bar with a search field that hides under it.
    private lazy var navigationBarView = TelegramListNavigationBar(
        title: chat.title,
        placeholder: L10n.betterTG("Forum.SearchTopics"),
        leftImage: UIImage(systemName: "chevron.left"),
        rightImage: nil,
        leftAction: { [weak self] in self?.navigationController?.popViewController(animated: true) },
        rightAction: nil,
        showsBackButton: true,
    )
    private var navigationBarHeightConstraint: NSLayoutConstraint!
    private var didSetInitialSearchOffset = false
    private var dataSource: UITableViewDiffableDataSource<Section, Int>!
    private var snapshotState = ForumTopicsSnapshotState()
    private var pinnedOrder = ForumTopicPinnedOrder()
    private var topics = [ForumTopic]()
    private var selectedTopicIDs: Set<Int>
    private var allowedTopicIDs = Set<Int>()
    private var loadTask: Task<Void, Never>?
    private var generation = UInt64.zero
    private var cursor = ForumTopicPageCursor.zero
    private var requestedCursors = Set<ForumTopicPageCursor>()
    private var hasMore = true
    private var loading = false
    private var query = ""
    private var acceptedQuery: String?
    private var canManageTopics = false
    /// The user's standing in the forum, resolved together with `canManageTopics`.
    private var standing: MessageForwardDestinationStanding?
    private var rightsResolved = false
    private var retired = false
    private var wasContained = false

    private var contextIsCurrent: Bool {
        // Initial view loading may precede UIKit's first containment receipt. Once
        // attached, parent removal revokes admission immediately; didMove(nil) can lag.
        // Keep an interactive removal with a retained parent nonterminal.
        guard !retired, !wasContained || parent?.children.contains(where: { $0 === self }) == true else { return false }
        #if DEBUG
        if let probeCurrentContext { return probeCurrentContext() }
        #endif
        return TDLib.shared.activeAccountID == accountID
            && TDLib.shared.activeClient.id == client.id
    }

    private var destinationAllowsForward: Bool {
        if let standing {
            return MessageForwardingService.localEligibility(of: chat, standing: standing, for: preparedForward)
                .isAllowed
        }
        #if DEBUG
        // The snapshot probe injects rights without a TDLib supergroup.
        return probeInitialRights != nil
        #else
        return false
        #endif
    }

    init(
        chat: Chat,
        preparedForward: PreparedMessageForward,
        client: TDLibClient,
        accountID: UUID,
        selectedTopicIDs: Set<Int>,
    ) {
        self.chat = chat
        self.preparedForward = preparedForward
        self.client = client
        self.accountID = accountID
        self.selectedTopicIDs = selectedTopicIDs
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavigation()
        configureTable()
        configureDataSource()
        resolveRightsAndLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        guard parent == nil else {
            wasContained = true
            return
        }
        retired = true
        generation &+= 1
        loadTask?.cancel()
        loadTask = nil
        loading = false
        // UIKit may still ask for an outgoing row until its exact apply completes.
        if !snapshotState.isApplying { snapshotState.retire() }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateNavigationBar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didSetInitialSearchOffset, tableView.bounds.height > 0 else { return }
        didSetInitialSearchOffset = true
        tableView.setContentOffset(
            CGPoint(x: 0, y: -tableView.adjustedContentInset.top + ChatListNavigationSearchView.scrollHeight),
            animated: false,
        )
        updateNavigationBar()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView, withVelocity _: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>,
    ) {
        guard !navigationBarView.isSearchActive else { return }
        let top = -scrollView.adjustedContentInset.top
        let distance = targetContentOffset.pointee.y - top
        let searchHeight = ChatListNavigationSearchView.scrollHeight
        guard distance > 0, distance < searchHeight else { return }
        targetContentOffset.pointee.y = top + (distance < searchHeight / 2 ? 0 : searchHeight)
    }

    func scrollViewDidScroll(_: UIScrollView) {
        updateNavigationBar()
    }

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard contextIsCurrent, snapshotState.canSelect, acceptedQuery == query,
              let topicID = dataSource.itemIdentifier(for: indexPath),
              allowedTopicIDs.contains(topicID),
              let topic = snapshotState.topic(id: topicID)
        else { return }
        onSelect?(topic)
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        if contextIsCurrent, snapshotState.canSelect,
           indexPath.row >= max(0, snapshotState.displayedIDs.count - 5)
        {
            load(reset: false)
        }
    }

    private func updateNavigationBar() {
        guard navigationBarHeightConstraint != nil else { return }
        navigationBarView.applyScroll(offset: didSetInitialSearchOffset
            ? tableView.contentOffset.y + tableView.adjustedContentInset.top
            : ChatListNavigationSearchView.scrollHeight)
    }

    private func searchQueryChanged(_ searchText: String) {
        let updated = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard updated != query else { return }
        query = updated
        pinnedOrder.reset(keepingRanks: false)
        load(reset: true)
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 70
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 0)
        tableView.register(ForumTopicCell.self, forCellReuseIdentifier: ForumTopicCell.reuseID)
        tableView.contentInset.top = TelegramListNavigationBar.expandedContentHeight
        tableView.verticalScrollIndicatorInsets.top = TelegramListNavigationBar.expandedContentHeight
        view.insertSubview(tableView, belowSubview: navigationBarView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureNavigation() {
        navigationBarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationBarView)
        navigationBarHeightConstraint = navigationBarView.heightAnchor.constraint(
            equalToConstant: view.safeAreaInsets.top + TelegramListNavigationBar.titleHeight,
        )
        NSLayoutConstraint.activate([
            navigationBarView.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBarHeightConstraint,
        ])
        navigationBarView.onQueryChange = { [weak self] query in
            self?.searchQueryChanged(query)
        }
        navigationBarView.onVisibleHeightChange = { [weak self] height in
            guard let self else { return }
            navigationBarHeightConstraint.constant = view.safeAreaInsets.top + height
        }
        navigationBarView.onSearchActiveChange = { [weak self] active in
            guard let self else { return }
            tableView.searchScrollRange = active ? 0 : ChatListNavigationSearchView.scrollHeight
            let height = active
                ? ChatListNavigationSearchView.scrollHeight
                : TelegramListNavigationBar.expandedContentHeight
            tableView.contentInset.top = height
            tableView.verticalScrollIndicatorInsets.top = height
            tableView.layoutIfNeeded()
            tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
        }
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Int>(
            tableView: tableView,
        ) { [weak self] tableView, indexPath, topicID in
            var topic = self?.snapshotState.topic(id: topicID)
            #if DEBUG
            if self?.probeOmitCellModel == true { topic = nil }
            #endif
            let cell = ForumTopicCell.dequeue(
                from: tableView, at: indexPath, topic: topic, client: self?.snapshotState.client(id: topicID),
            )
            // Decoration uses the same transaction-owned model as the cell contents.
            let allowed = topic.map { self?.canPost(to: $0) == true } ?? false
            let selected = topic != nil && self?.selectedTopicIDs.contains(topicID) == true
            cell.accessoryType = selected ? .checkmark : .none
            cell.tintColor = .systemBlue
            cell.contentView.alpha = allowed ? 1 : 0.48
            cell.isUserInteractionEnabled = allowed
            cell.accessibilityValue = selected
                ? L10n.telegram("VoiceOver.Chat.Selected")
                : (allowed ? nil : L10n.betterTG("Forum.Closed"))
            return cell
        }
    }

    private func resolveRightsAndLoad() {
        #if DEBUG
        if let probeInitialRights {
            canManageTopics = probeInitialRights
            rightsResolved = true
            load(reset: true)
            return
        }
        #endif
        loadTask = Task { [weak self] in
            guard let self else { return }
            guard case .chatTypeSupergroup = chat.type,
                  let standing = try? await MessageForwardingService.standing(of: chat, client: client),
                  case .group(let group) = standing,
                  contextIsCurrent
            else {
                showError(L10n.betterTG("Forum.CheckFailed"))
                return
            }
            self.standing = standing
            canManageTopics = group.canManageTopics
            rightsResolved = true
            loadTask = nil
            load(reset: true)
        }
    }

    private func load(reset: Bool) {
        guard rightsResolved, contextIsCurrent, !loading || reset else { return }
        if reset {
            generation &+= 1
            loadTask?.cancel()
            cursor = .zero
            requestedCursors.removeAll()
            hasMore = true
        } else {
            guard hasMore else { return }
        }
        let requestedCursor = cursor
        guard requestedCursors.insert(requestedCursor).inserted else {
            hasMore = false
            return
        }
        let currentGeneration = generation
        let currentQuery = query
        let pinRevision = pinnedOrder.revision
        loading = true
        updateBackground()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await readPage(query: currentQuery, cursor: requestedCursor)
                guard !Task.isCancelled,
                      currentGeneration == generation,
                      currentQuery == query,
                      contextIsCurrent
                else { return }
                let incoming = page.topics.filter { $0.info.chatId == self.chat.id && $0.info.forumTopicId > 0 }
                if requestedCursor != .zero, acceptedQuery == currentQuery {
                    // Append can revoke a known rank, but membership alone never
                    // supplies the configured position of a newly pinned topic.
                    var previous = Dictionary(uniqueKeysWithValues: topics.map { ($0.info.forumTopicId, $0.isPinned) })
                    for topic in incoming {
                        let id = topic.info.forumTopicId
                        pinnedOrder.observeMembership(id: id, previous: previous[id], pinned: topic.isPinned)
                        previous[id] = topic.isPinned
                    }
                }
                // The topic list keeps a hidden General above its rows; it can't take messages, so the picker drops it.
                let merged = ForumTopicPageState.merging(
                    // A failed reset can be retried through loadMore with reset=false.
                    // A raw head always replaces the preceding query's accepted rows.
                    existing: requestedCursor == .zero || acceptedQuery != currentQuery ? [] : topics,
                    incoming: incoming,
                )
                .filter { !$0.info.isHidden }
                if requestedCursor == .zero {
                    pinnedOrder.acceptHead(
                        page.topics, eligible: Set(merged.map(\.info.forumTopicId)),
                        chatID: chat.id, after: pinRevision,
                    )
                }
                topics = pinnedOrder.applying(to: merged)
                acceptedQuery = currentQuery
                allowedTopicIDs = Set(topics.compactMap { topic in
                    self.canPost(to: topic) ? topic.info.forumTopicId : nil
                })
                cursor = ForumTopicPageCursor(response: page)
                hasMore = ForumTopicPageState.hasMore(
                    response: page,
                    requestedCursor: requestedCursor,
                )
                loading = false
                loadTask = nil
                applySnapshot()
            } catch is CancellationError {
                return
            } catch {
                guard currentGeneration == generation, currentQuery == query, contextIsCurrent else { return }
                requestedCursors.remove(requestedCursor)
                loading = false
                loadTask = nil
                updateBackground()
                showError(L10n.betterTG("Forum.LoadFailed"))
            }
        }
    }

    private func readPage(query: String, cursor: ForumTopicPageCursor) async throws -> ForumTopics {
        #if DEBUG
        if let probeReadPage { return try await probeReadPage(query, cursor) }
        #endif
        return try await client.getForumTopics(
            chatId: chat.id, limit: 50, offsetDate: cursor.date,
            offsetForumTopicId: cursor.forumTopicID, offsetMessageId: cursor.messageID, query: query,
        )
    }

    private func canPost(to topic: ForumTopic) -> Bool {
        let restricted = topic.info.isClosed || topic.info.isHidden
        return destinationAllowsForward && (!restricted || topic.info.isOutgoing || canManageTopics)
    }

    private func applySnapshot() {
        guard contextIsCurrent else { return }
        // As in Telegram's peer selection (ChatListNode, closed thread info), topics the forward may not enter
        // stay listed but disabled; selection still requires an allowed topic.
        snapshotState.enqueue(topics, client: client)
        drainSnapshot()
    }

    private func drainSnapshot() {
        guard contextIsCurrent, let batch = snapshotState.begin() else { return }
        #if DEBUG
        probeSnapshotStarts += 1
        #endif
        let previous = Set(dataSource.snapshot().itemIdentifiers)
        let ids = batch.ids
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int>()
        snapshot.appendSections([.topics])
        snapshot.appendItems(batch.ids)
        let retained = batch.ids.filter(previous.contains)
        if !retained.isEmpty {
            snapshot.reconfigureItems(retained)
        }
        dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
            let finish: () -> Void = { [weak self] in self?.completeSnapshot(batch.token) }
            #if DEBUG
            if let hold = self?.probeSnapshotCompletion { hold(finish)
                return
            }
            #endif
            finish()
        }
        updateBackground()
        if ids.count < 5, hasMore, !loading { load(reset: false) }
    }

    private func completeSnapshot(_ token: UUID) {
        guard snapshotState.complete(token) else { return }
        guard !retired else { snapshotState.retire()
            return
        }
        if snapshotState.hasPending { drainSnapshot()
            return
        }
        // willDisplay is ignored while UIKit owns a transaction. Resume pagination
        // once the latest displayed rows settle, without a second scroll gesture.
        if contextIsCurrent, view.window != nil, navigationController?.topViewController === self,
           tableView.indexPathsForVisibleRows?.contains(where: {
               $0.row >= max(0, snapshotState.displayedIDs.count - 5)
           }) == true { load(reset: false) }
    }

    private func updateBackground() {
        guard topics.isEmpty else {
            tableView.backgroundView = nil
            return
        }
        if loading {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            tableView.backgroundView = spinner
        } else {
            let label = UILabel()
            label.text = query.isEmpty ? L10n.betterTG("Forum.NoTopics") : L10n.betterTG("Forum.NoTopicsFound")
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            tableView.backgroundView = label
        }
    }

    private func showError(_ message: String) {
        guard !retired, contextIsCurrent else { return }
        #if DEBUG
        if let probeError { probeError(message)
            return
        }
        #endif
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: L10n.telegram("Conversation.ForwardTitle"),
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: TelegramGlassPlatterHost

extension ForwardForumTopicsViewController: TelegramGlassPlatterHost {
    var telegramGlassPlatters: [TelegramGlassPlatter] { navigationBarView.glassPlatters }
}

// ForumTopicsViewController.swift

import Combine
import Foundation
import TDLibKit
import UIKit

// MARK: - ForumTopicsViewController

@MainActor final class ForumTopicsViewController: UIViewController, UITableViewDelegate,
    ClientRestorableNavigationEntry
{
    /// `contextPreview` is Telegram's `ChatListControllerImpl(location: .forum, previewing: true)`: the topic list
    /// shown above a forum's chat-list context menu. The menu owns it, outside any navigation stack.
    enum PresentationMode {
        case standard
        case contextPreview
    }

    struct ClientRestorationState {
        let pages: ForumTopicsRestorationState
        let rawQuery: String
        let targetConsumed: Bool
        let viewport: ChatListViewportSnapshot
    }

    private enum Section {
        case topics
    }

    /// Moves rows only while the list reorders its pinned topics; the diffable source keeps its snapshot in step.
    private final class TopicRowsDataSource: UITableViewDiffableDataSource<Section, Int> {
        var canMoveRow: ((IndexPath) -> Bool)?
        /// The moved topic, the topic it was dropped onto, and whether it moved down.
        var didMoveRow: ((Int, Int, Bool) -> Void)?

        override func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
            canMoveRow?(indexPath) ?? false
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

    #if DEBUG
    var probeSnapshotCompletion: ((@escaping () -> Void) -> Void)?
    var probeModel: ForumTopicsVM { viewModel }
    var probeTable: UITableView { tableView }
    var probeSnapshotBusy: Bool { snapshotState.isApplying || snapshotState.hasPending }
    var probeIDs: [Int] { snapshotState.displayedIDs }
    var probeFailure: Bool { preparationFailure != nil }
    var probeCurrent: Bool { contextIsCurrent }
    var probeRetired: Bool { retired }
    var probePrepared: Bool { preparedClient != nil }
    private(set) var probeSearchDismissals = 0
    var probePreparationTask: Task<Void, Never>? { preparationTask }
    var probeActor: Int64? { actorID }
    var probePages: ForumTopicsRestorationState { restorationState().pages }
    var probeSearchField: UISearchTextField { navigationBarView.probeSearchField }
    func probeRetryEvent() { retryClientRestoration() }
    #endif

    private var viewModel: ForumTopicsVM

    private var bindingID = UUID()
    private var boundSource: TdUpdateSource?
    private let environment: ForumTopicsClientEnvironment
    private let presentationMode: PresentationMode
    private var actorID: Int64?
    private var readySource: TdUpdateSource?
    private var identityRevoked = false
    private let targetMessageID: Int64?
    private let targetQuote: MessageQuoteHighlight?
    private let tableView = ForumTopicsTableView(frame: .zero, style: .plain)
    private lazy var navigationBarView = TelegramListNavigationBar(
        title: viewModel.customChat.displayTitle,
        placeholder: L10n.betterTG("Forum.SearchTopics"),
        leftImage: UIImage(systemName: "chevron.left"),
        rightImage: UIImage(systemName: "ellipsis.circle"),
        leftAction: { [weak self] in self?.navigationController?.popViewController(animated: true) },
        rightAction: { [weak self] in self?.showMoreMenu() },
        showsBackButton: true,
        rightAccessibilityLabel: L10n.telegram("Common.More"),
    )
    private var navigationBarHeightConstraint: NSLayoutConstraint!
    private var searchQuery = ""
    private var didSetInitialSearchOffset = false
    private var dataSource: TopicRowsDataSource!
    private var pressGesture: ContextMenuPressGestureRecognizer?
    /// Telegram's reorder mode for pinned topics; list updates wait until it ends so a drag is never interrupted.
    private var isReorderingPinnedTopics = false
    private var reorderDoneButton: UIButton?
    private var pinnedOrderSave: Task<Void, Never>?
    private var snapshotState = ForumTopicsSnapshotState()
    private var cancellables = Set<AnyCancellable>()
    private var ownershipCancellables = Set<AnyCancellable>()
    private var targetResolutionTask: Task<Void, Never>?
    private var targetIntent: ForumTopicTargetIntent
    private let initialQuery: String
    private var previousSearchQuery: String
    private var viewportRestoration: ChatListViewportRestoration
    private var didPresentLoadError = false
    private var retired = false
    private var preparationTask: Task<Void, Never>?
    private var preparationSource: TdUpdateSource?
    private var preparationID: UUID?
    private var preparedClient: ForumTopicsClientEnvironment.Metadata?
    private var preparationFailure: (id: UUID, source: TdUpdateSource, binding: UUID)?
    private var retryScheduled = false
    /// Measures the hidden General's row so it rests exactly under the top, like the search field.
    private lazy var sizingCell = ForumTopicCell(style: .default, reuseIdentifier: nil)
    private var hiddenRowHeightCache: (key: String, height: CGFloat)?

    var displayedChatID: Int64 { viewModel.customChat.id }

    var navigationClientSource: TdUpdateSource? {
        boundSource
    }

    private var routeIsRetained: Bool {
        guard !retired else { return false }
        if presentationMode == .contextPreview { return parent != nil }
        return chatListActionOwnerIsAttached
            && navigationController?.viewControllers.contains(where: { $0 === self }) == true
    }

    private var contextIsCurrent: Bool {
        guard let source = navigationClientSource else { return false }
        return routeIsRetained && !identityRevoked && (actorID == nil || actorID == environment.currentActor())
            && source == environment.currentSource() && source == readySource
            && environment.currentAccount() == viewModel.location.accountID
    }

    /// The resting offset from the top that hides the search field and a hidden General below it.
    private var collapsedTopOffset: CGFloat {
        ChatListNavigationSearchView.scrollHeight + hiddenTopRowHeight
    }

    private var hiddenTopRowHeight: CGFloat {
        let first = IndexPath(row: 0, section: 0)
        guard tableView.numberOfSections > 0, tableView.numberOfRows(inSection: 0) > 0,
              hiddenTopic(at: first) != nil else { return 0 }
        return tableView.rectForRow(at: first).height
    }

    init(
        customChat: CustomChat,
        location: ChatLocation,
        client: TDLibClient,
        targetMessageID: Int64? = nil,
        targetQuote: MessageQuoteHighlight? = nil,
        restoration: ClientRestorationState? = nil,
        environment: ForumTopicsClientEnvironment? = nil,
        presentationMode: PresentationMode = .standard,
    ) {
        let environment = environment ?? .live
        self.environment = environment
        self.presentationMode = presentationMode
        self.actorID = environment.currentActor()
        self.boundSource = location.accountID.map { .init(accountID: $0, clientID: location.clientID) }
        self.viewModel = environment.model(customChat, location, client, restoration?.pages)
        self.targetMessageID = targetMessageID
        self.targetQuote = targetQuote
        self.targetIntent = ForumTopicTargetIntent(consumed: restoration?.targetConsumed ?? false)
        self.initialQuery = restoration?.rawQuery ?? ""
        self.previousSearchQuery = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        self.viewportRestoration = ChatListViewportRestoration(restoration?.viewport)
        super.init(nibName: nil, bundle: nil)
        observeOwnership()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        targetResolutionTask?.cancel()
        preparationTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.customChat.displayTitle
        view.backgroundColor = .systemBackground
        configureTable()
        configureSearch()
        configureDataSource()
        updateBackgroundView()
        observeState()
        viewModel.start()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        resolveTargetIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        endPinnedReorder()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateNavigationBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resolveTargetIfNeeded()
        retryClientRestoration()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        guard parent == nil else { return }
        retired = true
        retireModel()
        cancelPreparation()
        ownershipCancellables.removeAll()
        if !snapshotState.isApplying { snapshotState.retire() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didSetInitialSearchOffset, tableView.bounds.height > 0 {
            didSetInitialSearchOffset = true
            tableView.setContentOffset(
                CGPoint(x: 0, y: -tableView.adjustedContentInset.top + collapsedTopOffset),
                animated: false,
            )
            updateNavigationBar()
        }
        if contextIsCurrent { restoreViewportIfNeeded() }
        retryClientRestoration()
    }

    /// Telegram's `muteForIntervalString` / `mutedForTimeIntervalString`: hours below a day, days above.
    private static func intervalText(_ prefix: String, seconds: Int) -> String {
        let (key, count) = seconds < 24 * 60 * 60
            ? ("\(prefix).Hours", max(1, seconds / (60 * 60)))
            : ("\(prefix).Days", max(1, seconds / (24 * 60 * 60)))
        return L10n.telegramPlural(key, count: count, formattedCount: count.formatted(.number))
    }

    /// RootVM.isMuted for the forum's latest settings: its own mute, else its scope's.
    private static func forumIsMuted(_ settings: ChatNotificationSettings, scope: ScopeNotificationSettings?) -> Bool {
        if settings.useDefaultMuteFor, let scope { return scope.muteFor > 0 }
        return settings.muteFor > 0
    }

    private static func savePinnedOrder(
        client: TDLibClient, chatID: Int64, movedID: Int, referenceID: Int, movedDown: Bool,
    ) async -> Bool {
        do {
            // The unfiltered first page holds every pinned topic in TDLib's order.
            let page = try await client.getForumTopics(
                chatId: chatID, limit: 100, offsetDate: 0, offsetForumTopicId: 0, offsetMessageId: 0, query: "",
            )
            var ids = page.topics.filter(\.isPinned).map(\.info.forumTopicId).filter { $0 != movedID }
            if let index = ids.firstIndex(of: referenceID) {
                ids.insert(movedID, at: movedDown ? index + 1 : index)
            } else {
                ids.append(movedID)
            }
            _ = try await client.send(TDNativeRequests.setPinnedForumTopics(chatId: chatID, forumTopicIds: ids))
            return true
        } catch {
            return false
        }
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView, withVelocity _: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>,
    ) {
        guard !navigationBarView.isSearchActive else { return }
        let top = -scrollView.adjustedContentInset.top
        let distance = targetContentOffset.pointee.y - top
        let searchHeight = ChatListNavigationSearchView.scrollHeight
        let hiddenHeight = hiddenTopRowHeight
        if distance > 0, distance < searchHeight {
            targetContentOffset.pointee.y = top + (distance < searchHeight / 2 ? 0 : searchHeight)
        } else if hiddenHeight > 0, distance > searchHeight, distance < searchHeight + hiddenHeight {
            // A hidden General pulled past half its height stays revealed; otherwise it tucks back under the top.
            targetContentOffset.pointee.y = top + searchHeight
                + (distance - searchHeight < hiddenHeight / 2 ? 0 : hiddenHeight)
        }
    }

    func tableView(_: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        hiddenTopic(at: indexPath).map(hiddenRowHeight) ?? UITableView.automaticDimension
    }

    func tableView(_: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        // An exact estimate keeps the hidden row's offset right before UIKit ever displays it.
        hiddenTopic(at: indexPath).map(hiddenRowHeight) ?? tableView.estimatedRowHeight
    }

    func tableView(_: UITableView, editingStyleForRowAt _: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    func tableView(_: UITableView, shouldIndentWhileEditingRowAt _: IndexPath) -> Bool {
        false
    }

    /// Telegram (ChatListNode.reorderItem) moves a pinned topic only among the pinned topics.
    func tableView(
        _: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath,
    ) -> IndexPath {
        let ids = dataSource.snapshot().itemIdentifiers
        let pinnedRows = ids.indices.filter { row in
            snapshotState.topic(id: ids[row]).map { $0.isPinned && !$0.info.isHidden } == true
        }
        guard let first = pinnedRows.first, let last = pinnedRows.last else { return sourceIndexPath }
        return IndexPath(
            row: min(max(proposedDestinationIndexPath.row, first), last),
            section: sourceIndexPath.section,
        )
    }

    func scrollViewDidScroll(_: UIScrollView) {
        updateNavigationBar()
    }

    func scrollViewWillBeginDragging(_: UIScrollView) { viewportRestoration.cancel() }
    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { retryClientRestoration() }
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) { retryClientRestoration() }

    func prepareReplacementForReadyClient(_ source: TdUpdateSource) -> PreparedClientNavigationReplacement? {
        guard canRestoreClient(source) else { return nil }
        guard let preparedClient, preparedClient.source == source else {
            prepareClientMetadata(source)
            return nil
        }
        let state = restorationState()
        let model = viewModel
        let binding = bindingID
        return PreparedClientNavigationReplacement(
            preflight: { [weak self] in
                self?.owns(model, binding: binding, current: false) == true && self?.canRestoreClient(source) == true
            },
            commit: { [self] in
                guard owns(model, binding: binding, current: false), canRestoreClient(source) else { return nil }
                let replacement = ForumTopicsViewController(
                    customChat: preparedClient.chat, location: renewedLocation(source), client: preparedClient.client,
                    targetMessageID: targetMessageID, targetQuote: targetQuote, restoration: state,
                    environment: environment,
                )
                retired = true
                snapshotState.retire()
                retireModel()
                cancelPreparation()
                ownershipCancellables.removeAll()
                #if DEBUG
                log("ForumTopics client restoration: replacement accepted")
                #endif
                return replacement
            },
        )
    }

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard presentationMode == .standard, snapshotState.canSelect,
              let topicID = dataSource.itemIdentifier(for: indexPath),
              let displayed = snapshotState.topic(id: topicID),
              snapshotState.client(id: topicID)?.id == viewModel.client.id,
              let topic = viewModel.topicForOpening(displayed)
        else { return }
        open(topic: topic, targetMessageID: nil, quote: nil, model: viewModel, binding: bindingID)
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        if contextIsCurrent, snapshotState.canSelect, indexPath.row >= max(0, snapshotState.displayedIDs.count - 5) {
            viewModel.loadMore()
        }
    }

    private func searchQueryChanged(_ query: String) {
        searchQuery = query
        guard !retired else { return }
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized != previousSearchQuery {
            viewportRestoration.cancel()
            previousSearchQuery = normalized
        }
        if contextIsCurrent { viewModel.search(query) }
        retryClientRestoration()
    }

    private func searchActivityChanged(_ active: Bool) {
        if active { endPinnedReorder() }
        if !active {
            #if DEBUG
            probeSearchDismissals += 1
            #endif
            resolveTargetIfNeeded()
        }
        retryClientRestoration()
    }

    private func updateNavigationBar() {
        guard navigationBarHeightConstraint != nil else { return }
        navigationBarView.applyScroll(offset: didSetInitialSearchOffset
            ? tableView.contentOffset.y + tableView.adjustedContentInset.top
            : ChatListNavigationSearchView.scrollHeight)
    }

    /// The hidden General, kept as the first row: Telegram leaves it above the list until it is pulled down
    /// (ChatListNode's hidden thread entry, ChatListItem `hiddenOffset`).
    private func hiddenTopic(at indexPath: IndexPath) -> ForumTopic? {
        guard indexPath.section == 0, indexPath.row == 0, let id = dataSource?.itemIdentifier(for: indexPath),
              let topic = snapshotState.topic(id: id), topic.info.isHidden else { return nil }
        return topic
    }

    private func hiddenRowHeight(_ topic: ForumTopic) -> CGFloat {
        let width = tableView.bounds.width
        let key = "\(width)|\(topic.info.name)|\(traitCollection.preferredContentSizeCategory.rawValue)"
        if let cache = hiddenRowHeightCache, cache.key == key { return cache.height }
        sizingCell.configure(
            topic: topic,
            client: snapshotState.client(id: topic.info.forumTopicId) ?? viewModel.client,
            muted: isMuted(topic),
        )
        sizingCell.bounds.size = CGSize(width: width, height: tableView.estimatedRowHeight)
        sizingCell.layoutIfNeeded()
        let height = sizingCell.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        .height
        .rounded(.up)
        hiddenRowHeightCache = (key, height)
        return height
    }

    /// Short lists get enough travel to tuck the search field and a hidden General under the top.
    private func updateSearchTravel() {
        tableView.searchScrollRange = navigationBarView.isSearchActive ? 0 : collapsedTopOffset
    }

    private func restorationState() -> ClientRestorationState {
        let query = isViewLoaded ? searchQuery : initialQuery
        let pages = viewModel.restorationState(rawQuery: query)
        let viewport = viewportRestoration.pending ?? (isViewLoaded
            ? ChatListViewportSnapshot.capture(
                tableView: tableView, chatID: { dataSource.itemIdentifier(for: $0).map(Int64.init) },
            )
            : .init(chatID: nil, rowMinYRelativeToViewport: 0, offsetFromTop: 0))
        return ClientRestorationState(
            pages: pages, rawQuery: query,
            targetConsumed: targetIntent.consumed,
            viewport: pages.topics.isEmpty
                ? .init(chatID: nil, rowMinYRelativeToViewport: 0, offsetFromTop: 0)
                : viewport,
        )
    }

    private func canRestoreClient(_ source: TdUpdateSource) -> Bool {
        canRenewIdentity(source)
            && presentedViewController == nil && transitionCoordinator == nil && !navigationBarView.isSearchActive
            && !tableView.isTracking && !tableView.isDragging && !tableView.isDecelerating
            && !snapshotState.isApplying && !snapshotState.hasPending
            && !navigationBarView.hasMarkedText && !isReorderingPinnedTopics
    }

    private func canRenewIdentity(_ source: TdUpdateSource) -> Bool {
        routeIsRetained && !identityRevoked && actorID != nil && actorID == environment.currentActor()
            && source == environment.currentSource() && source == readySource
            && source.accountID == viewModel.location.accountID && source != boundSource
            && environment.currentAccount() == source.accountID && !isBeingDismissed && !isMovingFromParent
    }

    private func canRenewSearch(_ source: TdUpdateSource, requiresIdleSnapshot: Bool = true) -> Bool {
        guard canRenewIdentity(source), isViewLoaded, view.window != nil,
              navigationController?.topViewController === self, navigationBarView.isSearchActive,
              transitionCoordinator == nil, !navigationBarView.hasMarkedText,
              !tableView.isTracking, !tableView.isDragging, !tableView.isDecelerating,
              !requiresIdleSnapshot || !snapshotState.isApplying && !snapshotState.hasPending else { return false }
        var owner: UIViewController? = self
        while let candidate = owner {
            if candidate.presentedViewController != nil { return false }
            owner = candidate.parent
        }
        return true
    }

    private func renewedLocation(_ source: TdUpdateSource) -> ChatLocation {
        ChatLocation(
            accountID: source.accountID,
            chatID: viewModel.location.chatID,
            clientID: source.clientID,
            topic: viewModel.location.topic,
        )
    }

    private func owns(_ model: ForumTopicsVM, binding: UUID, current: Bool = true) -> Bool {
        !retired && bindingID == binding && viewModel === model && (!current || contextIsCurrent)
    }

    private func retireModel() {
        targetIntent.cancel()
        targetResolutionTask?.cancel()
        targetResolutionTask = nil
        cancellables.removeAll()
        viewModel.retire()
    }

    private func renewSearch(_ source: TdUpdateSource) {
        guard canRenewSearch(source) else { return }
        guard let preparedClient, preparedClient.source == source else { prepareClientMetadata(source)
            return
        }
        let state = restorationState()
        let model = environment.model(preparedClient.chat, renewedLocation(source), preparedClient.client, state.pages)
        retireModel()
        viewModel = model
        boundSource = source
        bindingID = UUID()
        cancelPreparation()
        viewportRestoration = ChatListViewportRestoration(state.viewport)
        previousSearchQuery = state.rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        title = preparedClient.chat.displayTitle
        applySnapshot(model.topics, client: model.client)
        observeState()
        model.start()
        #if DEBUG
        log("ForumTopics client restoration: search binding accepted")
        #endif
    }

    private func prepareClientMetadata(_ source: TdUpdateSource) {
        guard preparationSource != source, preparationFailure == nil,
              canRestoreClient(source) || canRenewSearch(source) else { return }
        cancelPreparation()
        let chatID = viewModel.location.chatID
        let model = viewModel
        let binding = bindingID
        let requestID = UUID()
        let readMetadata = environment.metadata
        preparationSource = source
        preparationID = requestID
        preparationTask = Task { [weak self] in
            defer {
                if let self, preparationID == requestID {
                    preparationTask = nil
                    preparationSource = nil
                    preparationID = nil
                }
            }
            guard !Task.isCancelled, self?.owns(model, binding: binding, current: false) == true,
                  self?.preparationID == requestID, self?.canRenewIdentity(source) == true else { return }
            let metadata = await readMetadata(source, chatID)
            guard let self, !Task.isCancelled, owns(model, binding: binding, current: false),
                  preparationID == requestID, canRenewIdentity(source) else { return }
            guard let metadata, metadata.source == source, metadata.chat.chat.id == chatID,
                  metadata.chat.chat.viewAsTopics
            else {
                preparationFailure = (requestID, source, binding)
                if isViewLoaded {
                    if viewportRestoration.pending == nil {
                        viewportRestoration = ChatListViewportRestoration(restorationState().viewport)
                    }
                    applySnapshot([], client: model.client)
                }
                return
            }
            preparedClient = metadata
            retryClientRestoration()
        }
    }

    private func cancelPreparation(clearFailure: Bool = true) {
        preparationTask?.cancel()
        preparationTask = nil
        preparationSource = nil
        preparationID = nil
        preparedClient = nil
        if clearFailure { preparationFailure = nil }
    }

    private func observeOwnership() {
        environment.activeChanges
            .sink { [weak self] source in self?.receiveOwnership(source) }
            .store(in: &ownershipCancellables)
        environment.accountChanges
            .sink { [weak self] in
                guard let self else { return }
                receiveOwnership(environment.currentSource())
            }
            .store(in: &ownershipCancellables)
        environment.readyChanges
            .sink { [weak self] source in
                guard let self else { return }
                readySource = source
                observeIdentity(environment.currentSource())
                if source == nil { cancelPreparation(clearFailure: false) }
                if contextIsCurrent, isViewLoaded {
                    viewModel.search(searchQuery)
                    applySnapshot(viewModel.topics, client: viewModel.client)
                }
                retryClientRestoration()
            }
            .store(in: &ownershipCancellables)
    }

    private func receiveOwnership(_ source: TdUpdateSource?) {
        observeIdentity(source)
        cancelPreparation(clearFailure: source != preparationFailure?.source)
        if !contextIsCurrent {
            targetIntent.cancel()
            targetResolutionTask?.cancel()
            targetResolutionTask = nil
        }
        retryClientRestoration()
    }

    private func observeIdentity(_ source: TdUpdateSource?) {
        let actor = environment.currentActor()
        if source?.accountID != viewModel.location.accountID
            || environment.currentAccount() != viewModel.location.accountID
            || actorID != nil && actor != nil && actor != actorID
            || actorID == nil && source != boundSource { identityRevoked = true }
        // Before identity is known the binding cannot renew, so boundSource is
        // still the original epoch. Never learn an actor from its replacement.
        if !identityRevoked, actorID == nil, source == boundSource,
           source == readySource, source == environment.currentSource()
        {
            actorID = actor
        }
    }

    private func retryClientRestoration() {
        // A preview never rebuilds navigation; the menu closes with its client.
        guard presentationMode == .standard, !retired, !identityRevoked, !retryScheduled,
              let source = readySource, source == environment.currentSource(), source != boundSource,
              source.accountID == viewModel.location.accountID else { return }
        retryScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            retryScheduled = false
            // Coalesced ownership events re-read the latest epoch; an older
            // queued retry must not swallow a newer Ready notification.
            guard routeIsRetained, !identityRevoked, let source = readySource,
                  source == environment.currentSource(), source != boundSource else { return }
            if navigationBarView.isSearchActive { renewSearch(source) }
            else { environment.retryNavigation() }
        }
    }

    private func restoreViewportIfNeeded() {
        guard !retired, let viewport = viewportRestoration.takeForLayout(
            usable: tableView.bounds.height > 0 && !tableView.isDragging && !tableView.isDecelerating,
        ) else { return }
        viewport.restore(tableView: tableView, indexPath: { id in
            Int(exactly: id).flatMap { dataSource.indexPath(for: $0) }
        })
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 70
        tableView.alwaysBounceVertical = true
        tableView.keyboardDismissMode = .onDrag
        tableView.allowsSelection = presentationMode == .standard
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 0)
        if presentationMode == .standard {
            let press = ContextMenuPressGestureRecognizer(target: self, action: #selector(topicLongPressed(_:)))
            press.pressedViewProvider = { [weak self] gesture in
                guard let self, let path = tableView.indexPathForRow(at: gesture.location(in: tableView)),
                      let cell = tableView.cellForRow(at: path) as? ForumTopicCell
                else { return nil }
                return cell.contextPreviewView
            }
            tableView.addGestureRecognizer(press)
            pressGesture = press
        }
        tableView.register(ForumTopicCell.self, forCellReuseIdentifier: ForumTopicCell.reuseID)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureSearch() {
        tableView.contentInset.top = TelegramListNavigationBar.expandedContentHeight
        tableView.verticalScrollIndicatorInsets.top = TelegramListNavigationBar.expandedContentHeight
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
            tableView.searchScrollRange = active ? 0 : collapsedTopOffset
            let height = active
                ? ChatListNavigationSearchView.scrollHeight
                : TelegramListNavigationBar.expandedContentHeight
            tableView.contentInset.top = height
            tableView.verticalScrollIndicatorInsets.top = height
            tableView.layoutIfNeeded()
            tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
            searchActivityChanged(active)
        }
        searchQuery = initialQuery
        if !initialQuery.isEmpty { navigationBarView.restoreSearchQuery(initialQuery) }
        if presentationMode == .contextPreview {
            navigationBarView.isUserInteractionEnabled = false
            navigationBarView.setLeftButtonHidden(true)
        } else {
            navigationBarView.onTitleTap = { [weak self] in self?.openGroupInfo() }
        }
        updateNavigationBar()
    }

    private func configureDataSource() {
        dataSource = TopicRowsDataSource(tableView: tableView) { [weak self] tableView, indexPath, topicID in
            let topic = self?.snapshotState.topic(id: topicID)
            return ForumTopicCell.dequeue(
                from: tableView, at: indexPath,
                topic: topic, client: self?.snapshotState.client(id: topicID),
                muted: topic.map { self?.isMuted($0) == true } ?? false,
            )
        }
        dataSource.canMoveRow = { [weak self] indexPath in
            guard let self, isReorderingPinnedTopics, let id = dataSource.itemIdentifier(for: indexPath),
                  let topic = snapshotState.topic(id: id) else { return false }
            return topic.isPinned && !topic.info.isHidden
        }
        dataSource.didMoveRow = { [weak self] movedID, referenceID, movedDown in
            self?.commitPinnedMove(movedID, relativeTo: referenceID, movedDown: movedDown)
        }
    }

    private func observeState() {
        let model = viewModel
        let binding = bindingID
        model.$memberCount
            .combineLatest(model.$onlineMemberCount)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, owns(model, binding: binding, current: false) else { return }
                navigationBarView.setSubtitle(model.headerStatus)
            }
            .store(in: &cancellables)
        // Rows on the default mute inherit the forum's; Telegram's thread index view re-emits with the peer's
        // notification settings. Reconfigure them when that inherited state changes.
        let scope = model.customChat.notificationSettingsScope
        model.$chatNotificationSettings
            .combineLatest(RootVM.shared.$scopeNotificationSettings.map { $0[scope] })
            .map { Self.forumIsMuted($0, scope: $1) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, owns(model, binding: binding) else { return }
                applySnapshot(model.topics, client: model.client)
            }
            .store(in: &cancellables)
        model.$topics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] topics in
                guard let self, owns(model, binding: binding) else { return }
                applySnapshot(topics, client: model.client)
            }
            .store(in: &cancellables)
        model.$loading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, owns(model, binding: binding) else { return }
                updateBackgroundView()
            }
            .store(in: &cancellables)
        model.$errorMessage
            .compactMap(\.self)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.presentLoadError(message, model: model, binding: binding)
            }
            .store(in: &cancellables)
    }

    private func applySnapshot(_ topics: [ForumTopic], client: TDLibClient) {
        guard !retired else { return }
        snapshotState.enqueue(topics, client: client)
        drainSnapshot()
    }

    private func drainSnapshot() {
        guard !retired, !isReorderingPinnedTopics, let batch = snapshotState.begin() else { return }
        let previousIDs = Set(dataSource.snapshot().itemIdentifiers)
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int>()
        snapshot.appendSections([.topics])
        snapshot.appendItems(batch.ids)
        let retainedIDs = batch.ids.filter(previousIDs.contains)
        if !retainedIDs.isEmpty {
            snapshot.reconfigureItems(retainedIDs)
        }
        let token = viewportRestoration.beginApply()
        let model = viewModel
        let binding = bindingID
        // A page covered by a pushed chat (a topic just created and opened) has no window. An animated diff there
        // left the table showing the old rows on return, so the new topic only appeared after reopening the forum.
        let animated = viewportRestoration.pending == nil && view.window != nil
        // A list resting at its top keeps showing the top, as Telegram's chat list does (FolderView's
        // restingTopOffset): a topic that moves or arrives above the first row appears there instead of sliding under
        // the navigation bar while UIKit anchors the previous first row. A list resting with the search field and a
        // hidden General tucked under the top keeps them there as that row arrives, changes height or leaves.
        let previousCollapsedOffset = navigationBarView.isSearchActive ? 0 : collapsedTopOffset
        let restingTopOffset: CGFloat? = {
            guard didSetInitialSearchOffset, viewportRestoration.pending == nil,
                  !tableView.isTracking, !tableView.isDragging, !tableView.isDecelerating else { return nil }
            let offset = tableView.contentOffset.y + tableView.adjustedContentInset.top
            return offset <= previousCollapsedOffset + 0.5 ? offset : nil
        }()
        let tucksTop = !navigationBarView.isSearchActive
            && restingTopOffset.map { abs($0 - previousCollapsedOffset) <= 0.5 } == true
        let restingTarget: () -> CGFloat? = { [weak self] in
            guard let self, let restingTopOffset else { return nil }
            return tucksTop ? collapsedTopOffset : restingTopOffset
        }
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            // UIKit can re-anchor the previous first row during the update animation; bring the top back.
            if let self, let target = restingTarget(), !tableView.isTracking, !tableView.isDecelerating {
                restoreRestingTop(target, animated: true)
            }
            let finish: () -> Void = { [weak self] in
                self?.completeSnapshot(batch.token, viewportToken: token, model: model, binding: binding)
            }
            #if DEBUG
            if let hold = self?.probeSnapshotCompletion { hold(finish)
            return
            }
            #endif
            finish()
        }
        updateSearchTravel()
        if let target = restingTarget() { restoreRestingTop(target, animated: false) }
        updateBackgroundView()
    }

    private func restoreRestingTop(_ offset: CGFloat, animated: Bool) {
        let target = -tableView.adjustedContentInset.top + offset
        guard abs(tableView.contentOffset.y - target) > 0.5 else { return }
        tableView.setContentOffset(CGPoint(x: tableView.contentOffset.x, y: target), animated: animated)
    }

    private func completeSnapshot(_ token: UUID, viewportToken: UUID, model: ForumTopicsVM, binding: UUID) {
        // Native UIKit ownership must close even when this binding has departed.
        guard snapshotState.complete(token) else { return }
        viewportRestoration.completeApply(viewportToken)
        guard !retired else { snapshotState.retire()
            return
        }
        if snapshotState.hasPending { drainSnapshot()
            return
        }
        // A removed row can move the table while its animation runs without the bar following; after a topic was
        // deleted the search slot stayed open with the search field collapsed, leaving an empty band.
        updateNavigationBar()
        if owns(model, binding: binding) {
            restoreViewportIfNeeded()
            if view.window != nil, navigationController?.topViewController === self,
               tableView.indexPathsForVisibleRows?.contains(where: {
                   $0.row >= max(0, self.snapshotState.displayedIDs.count - 5)
               }) == true { model.loadMore() }
        }
        retryClientRestoration()
    }

    private func updateBackgroundView() {
        if let failure = preparationFailure {
            let button = UIButton(type: .system)
            button.setTitle(L10n.betterTG("Forum.ReconnectFailed"), for: .normal)
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.textAlignment = .center
            button.addAction(UIAction { [weak self] _ in
                guard let self, preparationFailure?.id == failure.id, bindingID == failure.binding,
                      canRenewSearch(failure.source, requiresIdleSnapshot: false) || canRestoreClient(failure.source)
                else { return }
                preparationFailure = nil
                updateBackgroundView()
                retryClientRestoration()
            }, for: .touchUpInside)
            tableView.backgroundView = button
            return
        }
        guard viewModel.topics.isEmpty else {
            tableView.backgroundView = nil
            return
        }
        if viewModel.loading {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            tableView.backgroundView = spinner
        } else {
            let label = UILabel()
            label.text = !searchQuery.isEmpty
                ? L10n.betterTG("Forum.NoTopicsFound")
                : L10n.betterTG("Forum.NoTopics")
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            tableView.backgroundView = label
        }
    }

    private func resolveTargetIfNeeded() {
        guard contextIsCurrent, let targetMessageID, targetResolutionTask == nil,
              !navigationBarView.isSearchActive,
              navigationController?.topViewController === self, let attempt = targetIntent.begin()
        else { return }
        let model = viewModel
        let binding = bindingID
        let client = model.client
        let location = model.location
        targetResolutionTask = Task { [weak self] in
            defer {
                if let self, owns(model, binding: binding, current: false), targetIntent.owns(attempt) {
                    targetIntent.finish(attempt)
                    targetResolutionTask = nil
                }
            }
            guard self?.owns(model, binding: binding) == true, self?.targetIntent.owns(attempt) == true,
                  !Task.isCancelled else { return }
            let message = try? await client.getMessage(
                chatId: location.chatID,
                messageId: targetMessageID,
            )
            guard !Task.isCancelled, self?.owns(model, binding: binding) == true,
                  self?.targetIntent.owns(attempt) == true else { return }
            guard let message, message.chatId == location.chatID, message.id == targetMessageID,
                  case .messageTopicForum(let forumTopic) = message.topicId
            else {
                self?.presentLoadError(L10n.betterTG("Forum.MessageTopicOpenFailed"), model: model, binding: binding)
                return
            }
            let topic = try? await client.getForumTopic(chatId: location.chatID, forumTopicId: forumTopic.forumTopicId)
            guard let self, !Task.isCancelled, owns(model, binding: binding), targetIntent.owns(attempt) else { return }
            guard let topic, topic.info.chatId == location.chatID,
                  topic.info.forumTopicId == forumTopic.forumTopicId
            else {
                presentLoadError(L10n.betterTG("Forum.MessageTopicOpenFailed"), model: model, binding: binding)
                return
            }
            let opened = open(
                topic: topic,
                targetMessageID: targetMessageID,
                quote: targetQuote,
                model: model,
                binding: binding,
            )
            targetIntent.finish(attempt, opened: opened)
            targetResolutionTask = nil
        }
    }

    @discardableResult private func open(
        topic: ForumTopic,
        targetMessageID: Int64?,
        quote: MessageQuoteHighlight?,
        model: ForumTopicsVM,
        binding: UUID,
    ) -> Bool {
        guard owns(model, binding: binding), targetMessageID == nil || !navigationBarView.isSearchActive,
              navigationController?.topViewController === self else { return false }
        let location = model.location.withForumTopic(id: topic.info.forumTopicId)
        NavigationStorage.shared.push(.customChat(
            model.customChat,
            location: location,
            forumTopic: topic,
            targetMessageID: targetMessageID,
            targetQuote: quote,
        ))
        return true
    }

    /// Telegram's forum title opens the group's info (ChatListController.updateForum, tapped).
    private func openGroupInfo() {
        guard presentationMode == .standard, contextIsCurrent, let accountID = viewModel.location.accountID,
              let navigationController, navigationController.topViewController === self else { return }
        let profile = PeerProfileViewController(
            customChat: viewModel.customChat,
            topic: nil,
            client: viewModel.client,
            accountID: accountID,
        )
        profile.configureOpensChatItself()
        navigationController.pushViewController(profile, animated: true)
    }

    /// Telegram's forum More menu (ChatListControllerImpl.openMoreMenu, isViewingAsTopics: true). Add Member needs a
    /// member picker BetterTG doesn't have yet.
    private func showMoreMenu() {
        guard presentationMode == .standard, contextIsCurrent, presentedViewController == nil,
              navigationController?.topViewController === self else { return }
        var actions = [
            TelegramContextMenuAction(
                title: L10n.telegram("Chat.ContextViewAsTopics"),
                image: UIImage(systemName: "checkmark"),
            ),
            TelegramContextMenuAction(title: L10n.telegram("Chat.ContextViewAsMessages"), image: UIImage()) {
                [weak self] in self?.viewAsMessages()
            },
            TelegramContextMenuAction(
                title: L10n.telegram("GroupInfo.Title"),
                image: UIImage(systemName: "person.2"),
                startsNewSection: true,
            ) { [weak self] in self?.openGroupInfo() },
        ]
        if viewModel.customChat.canCreateForumTopics {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Chat.CreateTopic"),
                image: UIImage(systemName: "square.and.pencil"),
                startsNewSection: true,
            ) { [weak self] in self?.presentCreateTopic() })
        }
        presentTelegramContextMenu(
            sourceView: navigationBarView.rightButtonView,
            actions: actions,
            presentationStyle: .sourceMorph,
        )
    }

    private func presentCreateTopic() {
        guard presentationMode == .standard, contextIsCurrent, presentedViewController == nil else { return }
        let model = viewModel
        let binding = bindingID
        ForumCreateTopicViewController.present(
            from: self,
            customChat: model.customChat,
            location: model.location,
            client: model.client,
            canOpen: { [weak self] in
                guard let self else { return false }
                return owns(model, binding: binding) && navigationController?.topViewController === self
            },
        )
    }

    /// Telegram replaces the topic list with the forum's message history and stores the choice on the server.
    private func viewAsMessages() {
        guard presentationMode == .standard, contextIsCurrent else { return }
        let model = viewModel
        let binding = bindingID
        let client = model.client
        let chatID = model.location.chatID
        Task { [weak self] in
            guard await (try? client.send(TDNativeRequests.toggleChatViewAsTopics(chatId: chatID, viewAsTopics: false)))
                != nil,
                let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client),
                !chat.chat.viewAsTopics, let self, owns(model, binding: binding),
                let navigationController,
                let index = navigationController.viewControllers.firstIndex(where: { $0 === self })
            else { return }
            var stack = navigationController.viewControllers
            stack[index] = ChatViewController(customChat: chat, location: model.location)
            navigationController.setViewControllers(stack, animated: false)
        }
    }

    private func presentLoadError(_ message: String, model: ForumTopicsVM, binding: UUID) {
        guard owns(model, binding: binding), navigationController?.topViewController === self,
              !didPresentLoadError, presentedViewController == nil else { return }
        didPresentLoadError = true
        let alert = UIAlertController(
            title: L10n.telegram("ChatList.Search.FilterTopics"),
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("ChatImportActivity.Retry"), style: .default) { [
            weak self,
            weak alert,
        ] _ in
            guard let self, let alert, owns(model, binding: binding, current: false),
                  presentedViewController === alert else { return }
            didPresentLoadError = false
            if owns(model, binding: binding) { model.loadInitial()
                resolveTargetIfNeeded()
            }
            dismiss(animated: true) { [weak self] in self?.retryClientRestoration() }
        })
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { [
            weak self,
            weak alert,
        ] _ in
            guard let self, let alert, owns(model, binding: binding, current: false),
                  presentedViewController === alert else { return }
            didPresentLoadError = false
            dismiss(animated: true) { [weak self] in self?.retryClientRestoration() }
        })
        present(alert, animated: true)
    }

    // MARK: Topic context menu

    /// A topic's mute state as Telegram resolves it: the topic's own setting, else the forum's.
    private func isMuted(_ topic: ForumTopic) -> Bool {
        let settings = topic.notificationSettings
        guard settings.useDefaultMuteFor else { return settings.muteFor > 0 }
        return Self.forumIsMuted(
            viewModel.chatNotificationSettings,
            scope: RootVM.shared.scopeNotificationSettings[viewModel.customChat.notificationSettingsScope],
        )
    }

    /// Telegram's topic menu (ChatListController, `.forum` item) over a preview of the topic's chat.
    @objc private func topicLongPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began, presentationMode == .standard, contextIsCurrent,
              presentedViewController == nil,
              let path = tableView.indexPathForRow(at: gesture.location(in: tableView)),
              let topicID = dataSource.itemIdentifier(for: path),
              let topic = snapshotState.topic(id: topicID),
              let cell = tableView.cellForRow(at: path) as? ForumTopicCell
        else { return }
        let preview = ChatViewController(
            customChat: viewModel.customChat,
            location: viewModel.location.withForumTopic(id: topicID),
            forumTopic: topic,
            presentationMode: .contextPreview,
        )
        presentTelegramContextMenu(
            sourceView: cell.contextPreviewView,
            actions: topicMenu(for: topic),
            tracking: gesture,
            presentationStyle: .chatPreview,
            previewController: preview,
        )
    }

    /// Telegram's `chatForumTopicMenuItems`. Select and the notification exceptions screen aren't ported.
    private func topicMenu(for topic: ForumTopic) -> [TelegramContextMenuAction] {
        let chat = viewModel.customChat
        let id = topic.info.forumTopicId
        let isGeneral = topic.info.isGeneral
        let canManage = chat.canManageForumTopics
        let canOpenClose = canManage || topic.info.isOutgoing
        var actions = [TelegramContextMenuAction]()
        if canManage, !topic.info.isHidden, !topic.info.isClosed || isGeneral {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(topic.isPinned ? "ChatList.Context.Unpin" : "ChatList.Context.Pin"),
                image: UIImage(systemName: topic.isPinned ? "pin.slash.fill" : "pin.fill"),
            ) { [weak self] in self?.togglePinned(topic) })
        }
        // Telegram offers Reorder on a pinned topic (chatForumTopicMenuItems, Chat.InlineTopicMenu.Reorder); BetterTG
        // has no Edit mode, so this is the way into reordering pinned topics. The full list is needed for that.
        if canManage, topic.isPinned, !topic.info.isHidden, !navigationBarView.isSearchActive,
           searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           viewModel.topics.count(where: { $0.isPinned && !$0.info.isHidden }) > 1
        {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Chat.InlineTopicMenu.Reorder"),
                image: UIImage(systemName: "arrow.up.arrow.down"),
            ) { [weak self] in self?.beginPinnedReorder() })
        }
        // Telegram offers this as General's swipe action (forumGeneralRevealOptions) to the creator and topic managers.
        if isGeneral, canManage {
            let hidden = topic.info.isHidden
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(hidden ? "ChatList.ThreadUnhideAction" : "ChatList.ThreadHideAction"),
                image: UIImage(systemName: hidden ? "eye" : "eye.slash"),
            ) { [weak self] in self?.setGeneralHidden(!hidden) })
        }
        if topic.unreadCount > 0, let lastMessageID = topic.lastMessage?.id {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.Context.MarkAsRead"),
                image: UIImage(systemName: "envelope.open"),
            ) { [weak self] in
                self?.performTopicRequest { client, chatID in
                    _ = try await client.viewMessages(
                        chatId: chatID,
                        forceRead: true,
                        messageIds: [lastMessageID],
                        source: .messageSourceForumTopicHistory,
                    )
                }
            })
        }
        if !isGeneral, canOpenClose {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("Chat.InlineTopicMenu.Edit"),
                image: UIImage(systemName: "pencil"),
            ) { [weak self] in
                guard let self, contextIsCurrent, presentedViewController == nil else { return }
                ForumCreateTopicViewController.presentEdit(
                    from: self, topic: topic, chatID: viewModel.location.chatID, client: viewModel.client,
                )
            })
        }
        actions.append(muteAction(for: topic))
        if !isGeneral, canOpenClose {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(topic.info.isClosed
                    ? "ChatList.Context.ReopenTopic"
                    : "ChatList.Context.CloseTopic"),
                image: UIImage(systemName: topic.info.isClosed ? "play" : "pause"),
            ) { [weak self] in
                self?.performTopicRequest { client, chatID in
                    _ = try await client.send(TDNativeRequests.toggleForumTopicIsClosed(
                        chatId: chatID, forumTopicId: id, isClosed: !topic.info.isClosed,
                    ))
                }
            })
        }
        if !isGeneral, chat.canDeleteAllMessages {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.Context.Delete"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
            ) { [weak self] in self?.confirmDelete(topicID: id) })
        }
        return actions
    }

    /// Muted: a direct Unmute. Otherwise Telegram's submenu: Mute for… presets, the sound toggle and Mute Forever.
    private func muteAction(for topic: ForumTopic) -> TelegramContextMenuAction {
        let settings = topic.notificationSettings
        guard !isMuted(topic) else {
            return TelegramContextMenuAction(
                title: L10n.telegram("ChatList.Context.Unmute"),
                image: UIImage(systemName: "speaker.wave.2.fill"),
            ) { [weak self] in self?.updateNotifications(of: topic, to: settings.replacingMuteFor(0)) }
        }
        let presets = [60 * 60, 8 * 60 * 60, 24 * 60 * 60, 7 * 24 * 60 * 60]
        let soundEnabled = settings.useDefaultSound || settings.soundId != 0
        return TelegramContextMenuAction(
            title: L10n.telegram("ChatList.Context.Mute"),
            image: UIImage(systemName: "speaker.slash.fill"),
            children: [
                TelegramContextMenuAction(
                    title: L10n.telegram("PeerInfo.MuteFor"),
                    image: UIImage(systemName: "clock"),
                    children: presets.map { seconds in
                        TelegramContextMenuAction(title: Self.intervalText(
                            "MuteFor",
                            seconds: seconds,
                        )) { [weak self] in
                            self?.updateNotifications(
                                of: topic,
                                to: settings.replacingMuteFor(seconds),
                                toast: L10n.telegram(
                                    "PeerInfo.TooltipMutedFor",
                                    Self.intervalText("MutedForTime", seconds: seconds),
                                ),
                            )
                        }
                    },
                ),
                TelegramContextMenuAction(
                    title: L10n.telegram(soundEnabled ? "PeerInfo.DisableSound" : "PeerInfo.EnableSound"),
                    image: UIImage(systemName: soundEnabled ? "bell.slash" : "bell"),
                    startsNewSection: true,
                ) { [weak self] in
                    self?.updateNotifications(
                        of: topic,
                        to: settings.replacingSound(enabled: !soundEnabled),
                        toast: L10n.telegram(
                            soundEnabled ? "PeerInfo.TooltipSoundDisabled" : "PeerInfo.TooltipSoundEnabled",
                        ),
                    )
                },
                TelegramContextMenuAction(
                    title: L10n.telegram("PeerInfo.MuteForever"),
                    image: UIImage(systemName: "speaker.slash.fill"),
                    isDestructive: true,
                ) { [weak self] in
                    self?.updateNotifications(
                        of: topic,
                        to: settings.replacingMuteFor(Int(Int32.max)),
                        toast: L10n.telegram("PeerInfo.TooltipMutedForever"),
                    )
                },
            ],
        )
    }

    private func updateNotifications(
        of topic: ForumTopic,
        to settings: ChatNotificationSettings,
        toast: String? = nil,
    ) {
        let id = topic.info.forumTopicId
        performTopicRequest { client, chatID in
            _ = try await client.send(TDNativeRequests.setForumTopicNotificationSettings(
                chatId: chatID, forumTopicId: id, notificationSettings: settings,
            ))
        } onSuccess: { [weak self] in
            guard let self, let toast else { return }
            TelegramUndoToast.show(text: toast, in: view, bottomInset: 12, undo: nil)
        }
    }

    private func togglePinned(_ topic: ForumTopic) {
        let id = topic.info.forumTopicId
        let model = viewModel
        let pinning = !topic.isPinned
        performTopicRequest { client, chatID in
            _ = try await client.send(TDNativeRequests.toggleForumTopicIsPinned(
                chatId: chatID, forumTopicId: id, isPinned: pinning,
            ))
            guard pinning else { return }
            // Telegram (toggleForumChannelTopicPinned) puts a new pin first; TDLib appends it. Reorder from the
            // unfiltered first page, which holds every pinned topic, so a search filter can't drop other pins.
            // Best effort: the pin itself succeeded, so a failed reorder must not read as the pin limit.
            guard let page = try? await client.getForumTopics(
                chatId: chatID, limit: 100, offsetDate: 0, offsetForumTopicId: 0, offsetMessageId: 0, query: "",
            ) else { return }
            let others = page.topics.filter { $0.isPinned && $0.info.forumTopicId != id }.map(\.info.forumTopicId)
            _ = try? await client.send(TDNativeRequests.setPinnedForumTopics(
                chatId: chatID, forumTopicIds: [id] + others,
            ))
        }
        // A live pin update carries no rank; the first page brings TDLib's pinned order without dropping later pages.
        onSuccess: {
            model.refreshHead()
        } onFailure: { [weak self] in
            guard !topic.isPinned else { return }
            self?.presentPinLimit()
        }
    }

    private func beginPinnedReorder() {
        guard presentationMode == .standard, contextIsCurrent, !isReorderingPinnedTopics,
              !navigationBarView.isSearchActive, !snapshotState.isApplying else { return }
        isReorderingPinnedTopics = true
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
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        reorderDoneButton = button
        UIAccessibility.post(notification: .layoutChanged, argument: button)
    }

    /// Leaves reorder mode and shows the list as the model now orders it.
    private func endPinnedReorder() {
        guard isReorderingPinnedTopics else { return }
        isReorderingPinnedTopics = false
        pressGesture?.isEnabled = true
        reorderDoneButton?.removeFromSuperview()
        reorderDoneButton = nil
        guard isViewLoaded, !retired else { return }
        tableView.setEditing(false, animated: true)
        applySnapshot(viewModel.topics, client: viewModel.client)
    }

    /// Telegram (ChatListNode.reorderItem) reads the forum's pinned topics, puts the dropped one beside its drop target
    /// and saves the whole order (setForumChannelPinnedTopics). Drops save one after another.
    private func commitPinnedMove(_ movedID: Int, relativeTo referenceID: Int, movedDown: Bool) {
        guard contextIsCurrent else {
            endPinnedReorder()
            return
        }
        let model = viewModel
        let binding = bindingID
        let client = model.client
        let chatID = model.location.chatID
        let previous = pinnedOrderSave
        pinnedOrderSave = Task { [weak self] in
            await previous?.value
            let saved = await Self.savePinnedOrder(
                client: client, chatID: chatID, movedID: movedID, referenceID: referenceID, movedDown: movedDown,
            )
            guard let self, owns(model, binding: binding) else { return }
            // The head read brings TDLib's pinned order for the rows shown once reorder mode ends.
            model.refreshHead()
            guard !saved else { return }
            endPinnedReorder()
            presentChatListActionFailure()
        }
    }

    /// Telegram's setPeerThreadHidden: General moves above the list or back into it, with Telegram's toast.
    /// updateForumTopicInfo then moves the row; a list resting at its top keeps the hidden General tucked away.
    private func setGeneralHidden(_ hidden: Bool) {
        performTopicRequest { client, chatID in
            _ = try await client.send(TDNativeRequests.toggleGeneralForumTopicIsHidden(
                chatId: chatID,
                isHidden: hidden,
            ))
        } onSuccess: { [weak self] in
            guard let self else { return }
            let text = hidden
                ? L10n.telegram("ChatList.GeneralHidden") + "\n" + L10n.telegram("ChatList.GeneralHiddenInfo")
                : L10n.telegram("ChatList.GeneralUnhidden")
            TelegramUndoToast.show(text: text, in: view, bottomInset: 12, undo: nil)
        }
    }

    /// Telegram's limit alert when pinning fails (ChatList.MaxThreadPinsFinalText).
    private func presentPinLimit() {
        let model = viewModel
        let binding = bindingID
        Task { [weak self] in
            guard case .optionValueInteger(let limit) = try? await model.client.getOption(
                name: "pinned_forum_topic_count_max",
            ), limit.value > 0, let self, owns(model, binding: binding), presentedViewController == nil
            else { return }
            let count = Int(limit.value)
            let alert = UIAlertController(
                title: L10n.telegram("Premium.LimitReached"),
                message: L10n.telegramPlural(
                    "ChatList.MaxThreadPinsFinalText", count: count, formattedCount: count.formatted(.number),
                ),
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
            present(alert, animated: true)
        }
    }

    /// Telegram asks in an action sheet before deleting a topic with all its messages.
    private func confirmDelete(topicID: Int) {
        guard contextIsCurrent, presentedViewController == nil else { return }
        let sheet = UIAlertController(
            title: nil,
            message: L10n.telegram("ChatList.DeleteTopicConfirmationText"),
            preferredStyle: .actionSheet,
        )
        sheet.addAction(UIAlertAction(
            title: L10n.telegram("ChatList.DeleteTopicConfirmationAction"),
            style: .destructive,
        ) { [weak self] _ in
            guard let self else { return }
            let model = viewModel
            performTopicRequest { client, chatID in
                _ = try await client.send(TDNativeRequests.deleteForumTopic(chatId: chatID, forumTopicId: topicID))
            } onSuccess: {
                model.removeDeletedTopic(id: topicID)
            }
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 0,
            height: 0,
        )
        present(sheet, animated: true)
    }

    /// Runs a topic request on this page's client and chat; results are dropped once the page no longer owns them.
    private func performTopicRequest(
        _ request: @escaping (TDLibClient, Int64) async throws -> Void,
        onSuccess: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil,
    ) {
        guard contextIsCurrent else { return }
        let model = viewModel
        let binding = bindingID
        let chatID = model.location.chatID
        Task { [weak self] in
            let succeeded = await (try? request(model.client, chatID)) != nil
            guard let self, owns(model, binding: binding) else { return }
            if succeeded { onSuccess?() } else { onFailure?() }
        }
    }
}

// MARK: - ForumTopicsTableView

private extension ChatNotificationSettings {
    /// Telegram's Enable/Disable Sound: the default sound, or none (TDLib's sound id 0).
    func replacingSound(enabled: Bool) -> ChatNotificationSettings {
        ChatNotificationSettings(
            disableMentionNotifications: disableMentionNotifications,
            disablePinnedMessageNotifications: disablePinnedMessageNotifications,
            muteFor: muteFor,
            muteStories: muteStories,
            showPreview: showPreview,
            showStoryPoster: showStoryPoster,
            soundId: enabled ? soundId : 0,
            storySoundId: storySoundId,
            useDefaultDisableMentionNotifications: useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: useDefaultMuteFor,
            useDefaultMuteStories: useDefaultMuteStories,
            useDefaultShowPreview: useDefaultShowPreview,
            useDefaultShowStoryPoster: useDefaultShowStoryPoster,
            useDefaultSound: enabled,
            useDefaultStorySound: useDefaultStorySound,
        )
    }
}

// MARK: - ForumTopicsTableView

/// A native footer gives short lists enough travel to hide search. UITableView
/// must own contentSize: overriding it makes its self-sizing row layout repeatedly
/// reconcile different content extents and animate the rows while idle.
final class ForumTopicsTableView: UITableView {
    var searchScrollRange = ChatListNavigationSearchView.scrollHeight {
        didSet { updateScrollExtent() }
    }

    private let searchTravelFooter = UIView()

    override func layoutSubviews() {
        super.layoutSubviews()
        updateScrollExtent()
    }

    override func adjustedContentInsetDidChange() {
        super.adjustedContentInsetDidChange()
        updateScrollExtent()
    }

    private func updateScrollExtent() {
        guard bounds.height > 0 else { return }
        let minimumHeight = max(
            0,
            bounds.height - adjustedContentInset.top
                - adjustedContentInset.bottom + searchScrollRange,
        )
        // Section geometry excludes the table footer, so its own height cannot
        // feed back into the next calculation as contentSize would.
        let rowsBottom = numberOfSections > 0
            ? rect(forSection: numberOfSections - 1).maxY
            : tableHeaderView?.frame.maxY ?? 0
        let height = max(0, minimumHeight - rowsBottom)
        guard tableFooterView !== searchTravelFooter
            || abs(searchTravelFooter.frame.height - height) > 0.5
            || searchTravelFooter.frame.width != bounds.width else { return }
        searchTravelFooter.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        tableFooterView = searchTravelFooter
    }
}

// MARK: - ForumTopicCell

final class ForumTopicCell: UITableViewCell {
    static let reuseID = "ForumTopicCell"

    private let iconView = ForumTopicIconView()
    private let titleLabel = UILabel()
    private let previewLabel = UILabel()
    private let dateLabel = UILabel()
    private let unreadBadge = TelegramUnreadBadgeLabel(minimumDiameter: 20, horizontalPadding: 8)
    /// Telegram's mention, reaction or poll-vote badge, left of the unread count (ChatListItem, mentionBadgeNode).
    private let mentionBadgeView = UIImageView()
    private var mentionBesideCountConstraint: NSLayoutConstraint!
    private var mentionAtEdgeConstraint: NSLayoutConstraint!
    private let pinView = UIImageView(image: UIImage(systemName: "pin.fill"))
    private let closedView = UIImageView(image: UIImage(systemName: "lock.fill"))
    private let muteView = UIImageView(image: UIImage(systemName: "speaker.slash.fill"))
    private var configuredMuted = false
    /// The topic a late sender name re-applies, if the cell still shows it.
    private var configuredTopic: ForumTopic?
    private var configuredClient: TDLibClient?

    /// The part of the row the context menu lifts.
    var contextPreviewView: UIView { contentView }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        isAccessibilityElement = true
        // Pinned rows show a reorder handle while the list reorders them.
        showsReorderControl = true
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.prepareForReuse()
    }

    static func dequeue(
        from tableView: UITableView, at indexPath: IndexPath, topic: ForumTopic?, client: TDLibClient?,
        muted: Bool = false,
    ) -> ForumTopicCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseID, for: indexPath) as! ForumTopicCell
        if let topic, let client { cell.configure(topic: topic, client: client, muted: muted) }
        else { cell.configureUnavailable() }
        return cell
    }

    private static func draftPreview(_ content: DraftMessageContent) -> String {
        switch content {
        case .draftMessageContentText(let text):
            L10n.betterTG("Forum.DraftPreview", text.text.text)
        case .draftMessageContentInputRichMessage, .draftMessageContentRichMessage:
            L10n.betterTG("Forum.DraftPreview", L10n.betterTG("Message.Rich"))
        case .draftMessageContentVideoNote:
            L10n.betterTG("Forum.DraftPreview", L10n.telegram("VoiceOver.Chat.VideoMessage"))
        case .draftMessageContentVoiceNote:
            L10n.betterTG("Forum.DraftPreview", L10n.telegram("VoiceOver.Chat.VoiceMessage"))
        }
    }

    private static func dateText(timestamp: Int) -> String {
        let date = Foundation.Date(timeIntervalSince1970: TimeInterval(timestamp))
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    func configure(topic: ForumTopic, client: TDLibClient, muted: Bool = false) {
        iconView.isHidden = false
        selectionStyle = .default
        iconView.configure(info: topic.info, client: client)
        titleLabel.text = topic.info.name
        configuredTopic = topic
        configuredClient = client
        configuredMuted = muted
        previewLabel.textColor = topic.draftMessage == nil ? .secondaryLabel : .systemRed
        if let draft = topic.draftMessage {
            previewLabel.text = Self.draftPreview(draft.content)
        } else if let message = topic.lastMessage {
            previewLabel.attributedText = preview(for: message, topicID: topic.info.forumTopicId, client: client)
        } else {
            previewLabel.text = L10n.betterTG("Forum.PreviewUnavailable")
        }
        dateLabel.text = topic.lastMessage.map { Self.dateText(timestamp: $0.date) }
        let hasUnreadIndicator = topic.unreadCount > 0
            || topic.unreadMentionCount > 0
            || topic.unreadReactionCount > 0
            || topic.unreadPollVoteCount > 0
        pinView.isHidden = !topic.isPinned || hasUnreadIndicator
        closedView.isHidden = !topic.info.isClosed
        muteView.isHidden = !muted
        // Telegram (ChatListItem) shows the count and, separately, an unseen mention, else reactions, else poll
        // votes. A muted topic greys its count, reaction and poll-vote badges; the mention badge stays blue.
        unreadBadge.backgroundColor = muted ? .systemGray : .systemBlue
        unreadBadge.text = topic.unreadCount > 0 ? compactNumericCountString(topic.unreadCount) : nil
        unreadBadge.isHidden = topic.unreadCount == 0
        mentionBadgeView.image =
            if topic.unreadMentionCount > 0 {
                ChatListMentionBadge.image(.mention, inactive: false)
            } else if topic.unreadReactionCount > 0 {
                ChatListMentionBadge.image(.reaction, inactive: muted)
            } else if topic.unreadPollVoteCount > 0 {
                ChatListMentionBadge.image(.pollVote, inactive: muted)
            } else {
                nil
            }
        mentionBadgeView.isHidden = mentionBadgeView.image == nil
        // Telegram keeps 6 pt between the mention badge and the unread count.
        mentionAtEdgeConstraint.isActive = false
        mentionBesideCountConstraint.isActive = !unreadBadge.isHidden
        mentionAtEdgeConstraint.isActive = unreadBadge.isHidden
        backgroundColor = topic.isPinned ? .secondarySystemBackground : .systemBackground
        contentView.backgroundColor = backgroundColor
        accessibilityLabel = [
            topic.info.name,
            topic.info.isClosed ? L10n.betterTG("Forum.Closed") : nil,
            muted ? L10n.betterTG("Accessibility.Muted") : nil,
            topic.isPinned ? L10n.betterTG("Accessibility.Pinned") : nil,
            topic.unreadCount > 0
                ? L10n
                    .telegramPlural("VoiceOver.Chat.UnreadMessages", count: topic.unreadCount)
                : nil,
            topic.unreadMentionCount > 0
                ? L10n.betterTG("Accessibility.UnreadMentions", topic.unreadMentionCount)
                : nil,
            topic.unreadReactionCount > 0
                ? L10n.betterTG("Accessibility.UnreadReactions", topic.unreadReactionCount)
                : nil,
            topic.unreadPollVoteCount > 0
                ? L10n.betterTG("Accessibility.UnreadPollVotes", topic.unreadPollVoteCount)
                : nil,
            previewLabel.text,
        ]
            .compactMap(\.self)
            .joined(separator: ", ")
        accessibilityIdentifier = "forum-topic-\(topic.info.forumTopicId)"
        accessibilityTraits = [.button]
    }

    /// Topic rows are forum (group) rows: Telegram names the sender and words service actions with names.
    private func preview(for message: Message, topicID: Int, client: TDLibClient) -> NSAttributedString {
        var missing = [Int64]()
        defer { requestUsers(missing, topicID: topicID, client: client) }
        let secondary: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.secondaryLabel]
        if let service = ChatPreviewText.serviceText(
            for: message, chatTitle: nil, isChannel: false, client: client, missing: &missing,
        ) {
            return NSAttributedString(string: service, attributes: secondary)
        }
        let summary = NSAttributedString(string: ChatSummary.summary(for: message), attributes: secondary)
        return ChatPreviewText.prefixed(
            ChatPreviewText.authorPrefix(for: message, client: client, missing: &missing),
            summary,
        )
    }

    private func requestUsers(_ ids: [Int64], topicID: Int, client: TDLibClient) {
        for id in Set(ids) {
            ChatListSenderNames.shared.resolve(userID: id, client: client) { [weak self] in
                guard let self, let topic = configuredTopic, topic.info.forumTopicId == topicID,
                      let client = configuredClient
                else { return }
                configure(topic: topic, client: client, muted: configuredMuted)
            }
        }
    }

    private func configureUnavailable() {
        configuredTopic = nil
        iconView.prepareForReuse()
        iconView.isHidden = true
        titleLabel.text = L10n.betterTG("Forum.TopicUnavailable")
        previewLabel.text = nil
        dateLabel.text = nil
        unreadBadge.text = nil
        unreadBadge.isHidden = true
        mentionBadgeView.image = nil
        mentionBadgeView.isHidden = true
        pinView.isHidden = true
        closedView.isHidden = true
        muteView.isHidden = true
        backgroundColor = .systemBackground
        contentView.backgroundColor = backgroundColor
        selectionStyle = .none
        accessibilityLabel = L10n.betterTG("Forum.TopicUnavailable")
        accessibilityIdentifier = nil
        accessibilityTraits = [.staticText]
    }

    private func configureViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 16, weight: .medium),
            maximumPointSize: 17,
        )
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 2
        titleLabel.isAccessibilityElement = false
        contentView.addSubview(titleLabel)

        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .regular),
            maximumPointSize: 17,
        )
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.isAccessibilityElement = false
        contentView.addSubview(previewLabel)

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 14, weight: .regular),
            maximumPointSize: 17,
        )
        dateLabel.textColor = .secondaryLabel
        dateLabel.isAccessibilityElement = false
        contentView.addSubview(dateLabel)

        for imageView in [pinView, closedView, muteView] {
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.tintColor = .secondaryLabel
            imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            imageView.isAccessibilityElement = false
            contentView.addSubview(imageView)
        }
        muteView.isHidden = true

        unreadBadge.translatesAutoresizingMaskIntoConstraints = false
        unreadBadge.backgroundColor = .systemBlue
        unreadBadge.textColor = .white
        unreadBadge.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        unreadBadge.isAccessibilityElement = false
        contentView.addSubview(unreadBadge)
        mentionBadgeView.translatesAutoresizingMaskIntoConstraints = false
        mentionBadgeView.contentMode = .scaleAspectFit
        mentionBadgeView.isHidden = true
        mentionBadgeView.isAccessibilityElement = false
        contentView.addSubview(mentionBadgeView)
        mentionBesideCountConstraint = mentionBadgeView.trailingAnchor.constraint(
            equalTo: unreadBadge.leadingAnchor,
            constant: -6,
        )
        mentionAtEdgeConstraint = mentionBadgeView.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor,
            constant: -14,
        )

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 60),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 80),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            // Telegram puts the mute icon right after the title; pin and lock stay beside the date.
            muteView.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            muteView.trailingAnchor.constraint(lessThanOrEqualTo: pinView.leadingAnchor, constant: -5),
            muteView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            muteView.widthAnchor.constraint(equalToConstant: 12),
            muteView.heightAnchor.constraint(equalToConstant: 12),
            pinView.trailingAnchor.constraint(equalTo: closedView.leadingAnchor, constant: -5),
            pinView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            pinView.widthAnchor.constraint(equalToConstant: 12),
            pinView.heightAnchor.constraint(equalToConstant: 12),
            closedView.trailingAnchor.constraint(equalTo: dateLabel.leadingAnchor, constant: -6),
            closedView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closedView.widthAnchor.constraint(equalToConstant: 12),
            closedView.heightAnchor.constraint(equalToConstant: 12),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            dateLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            previewLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            previewLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: unreadBadge.leadingAnchor, constant: -8),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: mentionBadgeView.leadingAnchor, constant: -8),
            previewLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
            unreadBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            unreadBadge.centerYAnchor.constraint(equalTo: previewLabel.centerYAnchor),
            unreadBadge.heightAnchor.constraint(equalToConstant: 20),
            mentionAtEdgeConstraint,
            mentionBadgeView.centerYAnchor.constraint(equalTo: previewLabel.centerYAnchor),
            mentionBadgeView.widthAnchor.constraint(equalToConstant: ChatListMentionBadge.diameter),
            mentionBadgeView.heightAnchor.constraint(equalToConstant: ChatListMentionBadge.diameter),
        ])
    }
}

// MARK: - ForumTopicIconView

final class ForumTopicIconView: UIView {
    private let backgroundView = UIView()
    private let fallbackLabel = UILabel()
    private let fallbackImageView = UIImageView()
    private var customEmojiView: CustomEmojiInlineView?
    private var loadTask: Task<Void, Never>?
    private var generation = UInt64.zero
    private var representedEmojiID: Int64?
    private var representedClientID: Int32?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.layer.cornerRadius = 16
        backgroundView.layer.cornerCurve = .continuous
        addSubview(backgroundView)
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        fallbackLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        fallbackLabel.textColor = .white
        fallbackLabel.textAlignment = .center
        addSubview(fallbackLabel)
        fallbackImageView.translatesAutoresizingMaskIntoConstraints = false
        fallbackImageView.contentMode = .center
        fallbackImageView.tintColor = .white
        addSubview(fallbackImageView)
        NSLayoutConstraint.activate([
            backgroundView.centerXAnchor.constraint(equalTo: centerXAnchor),
            backgroundView.centerYAnchor.constraint(equalTo: centerYAnchor),
            backgroundView.widthAnchor.constraint(equalToConstant: 32),
            backgroundView.heightAnchor.constraint(equalToConstant: 32),
            fallbackLabel.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            fallbackLabel.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            fallbackLabel.widthAnchor.constraint(equalToConstant: 32),
            fallbackLabel.heightAnchor.constraint(equalToConstant: 32),
            fallbackImageView.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            fallbackImageView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            fallbackImageView.widthAnchor.constraint(equalToConstant: 32),
            fallbackImageView.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        customEmojiView?.setPlaybackVisible(window != nil)
    }

    func configure(info: ForumTopicInfo, client: TDLibClient) {
        let sameIcon = representedEmojiID == info.icon.customEmojiId && representedClientID == client.id
        if !sameIcon {
            prepareForReuse()
            representedEmojiID = info.icon.customEmojiId
            representedClientID = client.id
        }
        backgroundView.backgroundColor = UIColor(rgb: info.icon.color)
        if info.isGeneral {
            fallbackImageView.image = UIImage(
                systemName: "bubble.left.and.bubble.right.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold),
            )
            if !backgroundView.isHidden {
                fallbackImageView.isHidden = false
                fallbackLabel.isHidden = true
            }
        } else {
            fallbackLabel.text = info.name.first.map { String($0).uppercased() }
            fallbackImageView.isHidden = true
            fallbackLabel.isHidden = backgroundView.isHidden
        }
        guard !sameIcon, info.icon.customEmojiId != 0 else { return }
        loadEmoji(info.icon.customEmojiId, client: client)
    }

    func prepareForReuse() {
        generation &+= 1
        representedEmojiID = nil
        representedClientID = nil
        loadTask?.cancel()
        loadTask = nil
        customEmojiView?.prepareForReuse()
        customEmojiView?.removeFromSuperview()
        customEmojiView = nil
        backgroundView.isHidden = false
        fallbackLabel.isHidden = false
        fallbackLabel.text = nil
        fallbackImageView.isHidden = true
        fallbackImageView.image = nil
    }

    /// The icon of a topic being created: its color and first letter (Telegram's `.topic` icon content), or the
    /// chosen custom emoji once it has drawn.
    func configureDraft(name: String, color: Int, customEmojiID: Int64 = 0, client: TDLibClient? = nil) {
        let emojiID = client == nil ? 0 : customEmojiID
        let sameIcon = representedEmojiID == emojiID && representedClientID == client?.id
        if !sameIcon {
            prepareForReuse()
            representedEmojiID = emojiID
            representedClientID = client?.id
        }
        backgroundView.backgroundColor = UIColor(rgb: color)
        fallbackImageView.isHidden = true
        fallbackLabel.text = name.first.map { String($0).uppercased() }
        fallbackLabel.isHidden = backgroundView.isHidden
        guard !sameIcon, emojiID != 0, let client else { return }
        loadEmoji(emojiID, client: client)
    }

    private func loadEmoji(_ identifier: Int64, client: TDLibClient) {
        let currentGeneration = generation
        loadTask = Task { [weak self] in
            let sticker = await CustomEmojiStickerRepository.shared.stickers(
                for: [identifier],
                client: client,
            )[identifier]
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.generation == currentGeneration,
                      let sticker
                else { return }
                self.install(sticker, client: client)
            }
        }
    }

    private func install(_ sticker: Sticker, client: TDLibClient) {
        let view = CustomEmojiInlineView()
        customEmojiView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: centerXAnchor),
            view.centerYAnchor.constraint(equalTo: centerYAnchor),
            view.widthAnchor.constraint(equalToConstant: 24),
            view.heightAnchor.constraint(equalToConstant: 24),
        ])
        view.onFirstFrameReady = { [weak self, weak view] in
            guard let self, customEmojiView === view else { return }
            backgroundView.isHidden = true
            fallbackLabel.isHidden = true
            fallbackImageView.isHidden = true
        }
        view.configure(sticker: sticker, client: client)
        view.setPlaybackVisible(window != nil)
    }
}

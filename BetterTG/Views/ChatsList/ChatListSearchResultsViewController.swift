// ChatListSearchResultsViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ChatListSearchResultsViewController

/// Telegram's chat list search (ChatListSearchListPaneNode, Chats pane) over TDLib: chats and contacts, global public
/// chats, then messages from the searched chat list. Every result belongs to the client that issued its query.
@MainActor final class ChatListSearchResultsViewController: UIViewController, UITableViewDelegate {
    private enum Section: Hashable {
        /// The empty search's People row and recently found chats (ChatListSearchListPaneNode with no query).
        case topPeers
        case recent
        case localPeers
        case globalPeers
        case messages
    }

    private enum Item: Hashable {
        case topPeers
        case recentPeer(Int64)
        case localPeer(Int64)
        case globalPeer(Int64)
        case message(MessageKey)
        case messagesLoading
    }

    private struct MessageKey: Hashable {
        let chatID: Int64
        let messageID: Int64
    }

    /// Telegram collapses global results above this count behind Show More.
    private static let collapsedGlobalCount = 3
    /// Remote requests wait for typing to pause; TDLib cannot cancel a request it has sent.
    private static let remoteSearchDelay = Duration.milliseconds(400)
    private static let messagesFirstPageLimit = 50
    private static let messagesPageLimit = 80
    private static let loadingRowHeight: CGFloat = 44
    private static let peerRowHeight: CGFloat = 56
    private static let messageRowHeight: CGFloat = 76

    /// The chat list's own menu for a chat the account has (ChatContextMenus with the `.search` source), from the
    /// page under the search.
    var chatMenu: ((CustomChat) -> [TelegramContextMenuAction])?

    /// The height of the bar above the results, from the top of the screen. The results fill the screen and scroll
    /// under the bar's blur, as Telegram's search container does, starting below it.
    var topBarHeight: CGFloat = 0 {
        didSet {
            guard topBarHeight != oldValue, isViewLoaded else { return }
            view.setNeedsLayout()
        }
    }

    private let rootVM: RootVM
    private let chatList: ChatList
    private let actionAuthority: ChatListActionAuthority
    private let tableView = TelegramListTableView(frame: .zero, style: .plain)
    /// ChatListSearchFiltersContainerNode's tabs, in BetterTG's folder strip: at the bottom like the chat list's
    /// folders, and 8 pt above the keyboard while it is up.
    private let filterPicker = FolderPickerView()
    /// The filter strip's place without the keyboard, above the screen's own bottom inset.
    private var filterRestingTopConstraint: NSLayoutConstraint?
    private var isApplyingSafeArea = false
    private let filterResults = ChatListSearchFilterResultsView()
    private let downloadsView = ChatListDownloadsView()
    /// Whether TDLib's download list has files, which adds the Downloads tab (`hasDownloads`).
    private var hasDownloads = false
    private var filter = ChatListSearchFilter.chats
    /// The chat type the table's search ran with: none for Chats, channels or bots for their tabs.
    private var searchedChatType: SearchChatTypeFilter?
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let emptyView = ChatListSearchEmptyView()
    private var dataSource: UITableViewDiffableDataSource<Section, Item>!
    private var cancellables = Set<AnyCancellable>()
    private var query = ""
    private var generation = UInt64.zero
    private var completedGeneration: UInt64?
    private var searchTask: Task<Void, Never>?
    private var moreMessagesTask: Task<Void, Never>?
    /// Chats shown by results, loaded once per search session through the owning root.
    private var chatsByID = [Int64: CustomChat]()
    private var localChatIDs = [Int64]()
    private var globalChatIDs = [Int64]()
    private var isGlobalExpanded = false
    private var messageKeys = [MessageKey]()
    /// Row models for found messages; a row keeps its model while it may re-apply a late sender name.
    private var messageChats = [MessageKey: CustomChat]()
    private var nextMessagesOffset = ""
    private var isLoadingMessages = false
    /// TDLib's top chats with people and recently found chats, shown before a query is typed.
    private var topPeerIDs = [Int64]()
    private var recentChatIDs = [Int64]()
    private var emptyStateTask: Task<Void, Never>?

    /// ChatListSearchPaneContainerNode's tabs: Downloads only while the download list has files.
    private var visibleFilters: [ChatListSearchFilter] {
        ChatListSearchFilter.allCases.filter { $0 != .downloads || hasDownloads }
    }

    init(rootVM: RootVM, chatList: ChatList, actionAuthority: ChatListActionAuthority) {
        self.rootVM = rootVM
        self.chatList = chatList
        self.actionAuthority = actionAuthority
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        searchTask?.cancel()
        moreMessagesTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureTableView()
        observeDownloads()
        TDLib.shared
            .activeClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                guard let self, source != actionAuthority.source else { return }
                discardResults()
            }
            .store(in: &cancellables)
        applySnapshot()
        if !query.isEmpty { startSearch() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A search started before this screen joined the navigation stack had no owner to deliver to.
        if !query.isEmpty, searchTask == nil, completedGeneration != generation { startSearch() }
    }

    /// The lists start below the bar and end above the filter strip, and the keyboard under it, through the safe
    /// area, which their scroll views inset by. Hidden results follow nothing: `restAtTop` lays them out as they come
    /// into view.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The pass this one starts below only carries the new safe area down to the lists.
        guard !isApplyingSafeArea, !view.isHidden else { return }
        isApplyingSafeArea = true
        defer { isApplyingSafeArea = false }
        // The screen's safe area, as the results fill it. Taking this view's own less its additions would feed the
        // result back: UIKit keeps its safe area through a change of a rounding error, so on a fractional inset that
        // difference drifts on every pass and never settles.
        let outer = parent?.view.safeAreaInsets ?? .zero
        let restingTop = -FolderPickerView.barHeight - outer.bottom
        if filterRestingTopConstraint?.constant != restingTop {
            filterRestingTopConstraint?.constant = restingTop
            view.layoutIfNeeded()
        }
        let insets = UIEdgeInsets(
            top: max(0, topBarHeight - outer.top),
            left: 0,
            bottom: max(0, view.bounds.maxY - filterPicker.frame.minY - outer.bottom),
            right: 0,
        )
        guard additionalSafeAreaInsets != insets else { return }
        let previousTop = tableView.adjustedContentInset.top
        let wasAtTop = tableView.contentOffset.y <= -previousTop + 1
        additionalSafeAreaInsets = insets
        // Inside this pass the list keeps the previous safe area until another pass reaches it.
        view.setNeedsLayout()
        view.layoutIfNeeded()
        // A list resting at its top stays there as the bar above it changes height.
        if wasAtTop, !tableView.isTracking {
            tableView.contentOffset.y = -tableView.adjustedContentInset.top
        }
    }

    /// Telegram's ContactsPeerItem status: a global result shows its address and audience, a local bot its users
    /// once Telegram counts them, or that it is a bot.
    private static func subtitle(for chat: CustomChat, isGlobal: Bool) -> String? {
        let botUsers = chat.bot.flatMap { bot in
            bot.activeUserCount > 0
                ? L10n.telegramPlural("Conversation.StatusBotSubscribers", count: bot.activeUserCount)
                : nil
        }
        guard isGlobal else {
            return chat.bot == nil ? nil : botUsers ?? L10n.telegram("Bot.GenericBotStatus")
        }
        var parts = [String]()
        if let username = (chat.supergroup?.usernames ?? chat.user?.usernames)?.activeUsernames.first,
           !username.isEmpty
        {
            parts.append("@" + username)
        }
        if let botUsers {
            parts.append(botUsers)
        }
        if let supergroup = chat.supergroup, supergroup.memberCount > 0 {
            parts.append(L10n.telegramPlural(
                supergroup.isChannel ? "Conversation.StatusSubscribers" : "Conversation.StatusMembers",
                count: supergroup.memberCount,
                formattedCount: supergroup.memberCount.formatted(.number),
            ))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func matchesSavedMessages(_ query: String) -> Bool {
        let lowercased = query.lowercased()
        guard lowercased.count > 1 else { return false }
        return L10n.telegram("Conversation.SavedMessages").lowercased().hasPrefix(lowercased)
            || "saved messages".hasPrefix(lowercased)
    }

    private static func deduplicated(_ ids: [Int64]) -> [Int64] {
        var seen = Set<Int64>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// Results coming into view start at their top, under the bar as it is now: hidden, they didn't follow it.
    func restAtTop() {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        tableView.contentOffset.y = -tableView.adjustedContentInset.top
    }

    /// Search opened with no query: its People row and recent chats reload, as they may have changed since.
    func refreshEmptyState() {
        guard isViewLoaded else { return }
        // The list's files can change while the search is closed, and the first check can come before TDLib starts.
        refreshDownloadsAvailability()
        guard query.isEmpty else { return }
        loadEmptyState()
    }

    func updateQuery(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != self.query else { return }
        self.query = query
        if query.isEmpty {
            isGlobalExpanded = false
            chatsByID.removeAll()
        }
        guard isViewLoaded else { return }
        startSearch()
        applyFilter()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard actionAuthority.scope(owner: self).isCurrent,
              let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .topPeers:
            return
        case .recentPeer(let chatID):
            guard let chat = chatsByID[chatID] else { return }
            openFoundChat(chat)
        case .globalPeer(let chatID),
             .localPeer(let chatID):
            guard let chat = chatsByID[chatID] else { return }
            openFoundChat(chat)
        case .message(let key):
            guard let chat = chatsByID[key.chatID] else { return }
            NavigationStorage.shared.push(.customChat(chat, targetMessageID: key.messageID), fromList: true)
        case .messagesLoading:
            return
        }
    }

    func tableView(_: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .topPeers: ChatListSearchTopPeersCell.height
        case .globalPeer,
             .localPeer,
             .recentPeer: Self.peerRowHeight
        case .message: Self.messageRowHeight
        case .messagesLoading,
             nil: Self.loadingRowHeight
        }
    }

    /// A recently found chat comes off the list with a swipe (removeRecentlySearchedPeer).
    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        guard case .recentPeer(let chatID) = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let client = actionAuthority.client
        let delete = UIContextualAction(style: .destructive, title: L10n.telegram("Common.Delete")) {
            [weak self] _, _, completion in
            Task { _ = try? await client.removeRecentlyFoundChat(chatId: chatID) }
            self?.recentChatIDs.removeAll { $0 == chatID }
            self?.applySnapshot()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .messagesLoading
    }

    func tableView(_: UITableView, heightForHeaderInSection _: Int) -> CGFloat {
        ChatListSearchSectionHeaderView.height
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let identifier = dataSource.sectionIdentifier(for: section),
              let header = tableView.dequeueReusableHeaderFooterView(
                  withIdentifier: ChatListSearchSectionHeaderView.reuseIdentifier,
              ) as? ChatListSearchSectionHeaderView
        else { return nil }
        switch identifier {
        case .topPeers:
            header.configure(title: L10n.telegram("DialogList.RecentTitlePeople"), actionTitle: nil, action: nil)
        case .recent:
            header.configure(
                title: L10n.telegram("DialogList.SearchSectionRecent"),
                actionTitle: L10n.telegram("WebSearch.RecentSectionClear"),
                actionInGlass: true,
                action: { [weak self] source in self?.confirmClearingRecent(from: source) },
            )
        case .localPeers:
            header.configure(title: L10n.telegram("DialogList.SearchSectionDialogs"), actionTitle: nil, action: nil)
        case .globalPeers:
            let actionTitle: String? =
                if globalChatIDs.count > Self.collapsedGlobalCount {
                    L10n.telegram(isGlobalExpanded ? "ChatList.Search.ShowLess" : "ChatList.Search.ShowMore")
                } else {
                    nil
                }
            header.configure(
                title: L10n.telegram("DialogList.SearchSectionGlobal"),
                actionTitle: actionTitle,
                action: { [weak self] in self?.toggleGlobalExpansion() },
            )
        case .messages:
            header.configure(title: L10n.telegram("DialogList.SearchSectionMessages"), actionTitle: nil, action: nil)
        }
        return header
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard dataSource.sectionIdentifier(for: indexPath.section) == .messages,
              indexPath.row >= dataSource.snapshot().numberOfItems(inSection: .messages) - 5
        else { return }
        loadMoreMessages()
    }

    /// The Chats tab shows the chats and messages found; another tab its kind of message from all chats.
    private func applyFilter() {
        let showsDownloads = filter == .downloads
        let showsMessages = !filter.listsChats && !showsDownloads
        tableView.isHidden = showsMessages || showsDownloads
        filterResults.isHidden = !showsMessages
        downloadsView.isHidden = !showsDownloads
        if showsDownloads {
            filterResults.reset()
            guard actionAuthority.scope(owner: self).isCurrent else { return }
            downloadsView.show(query: query, client: actionAuthority.client)
            return
        }
        downloadsView.reset()
        guard showsMessages, actionAuthority.scope(owner: self).isCurrent else {
            if !showsMessages { filterResults.reset() }
            return
        }
        filterResults.show(filter: filter, query: query, client: actionAuthority.client, chatList: chatList)
    }

    private func updateFilterPicker() {
        if !hasDownloads, filter == .downloads {
            filter = .chats
            applyFilter()
        }
        filterPicker.configure(
            items: visibleFilters.map { .init(id: $0.rawValue, title: $0.title) },
            selectedID: filter.rawValue,
        )
    }

    private func refreshDownloadsAvailability() {
        let client = actionAuthority.client
        Task { [weak self] in
            let has = await FileDownloads.hasDownloads(client: client)
            guard let self, client.id == actionAuthority.client.id, has != hasDownloads else { return }
            hasDownloads = has
            updateFilterPicker()
        }
    }

    /// The download list's file counts as TDLib reports them, then as its updates change them.
    private func observeDownloads() {
        refreshDownloadsAvailability()
        let apply: (DownloadedFileCounts, Int32) -> Void = { [weak self] counts, clientID in
            guard let self, clientID == actionAuthority.client.id else { return }
            let has = counts.activeCount + counts.pausedCount + counts.completedCount > 0
            guard has != hasDownloads else { return }
            hasDownloads = has
            updateFilterPicker()
        }
        nc.scopedPublisher(&cancellables, for: .updateFileAddedToDownloads) { event in
            apply(event.value.counts, event.source.clientID)
        }
        nc.scopedPublisher(&cancellables, for: .updateFileRemovedFromDownloads) { event in
            apply(event.value.counts, event.source.clientID)
        }
        nc.scopedPublisher(&cancellables, for: .updateFileDownload) { event in
            apply(event.value.counts, event.source.clientID)
        }
    }

    private func openFilteredMessage(_ message: Message) {
        let scope = actionAuthority.scope(owner: self)
        guard scope.isCurrent else { return }
        let client = actionAuthority.client
        Task { [weak self] in
            guard let self,
                  let chat = await rootVM.getCustomChatForNavigation(from: message.chatId, client: client),
                  scope.isCurrent, chat.id == message.chatId else { return }
            NavigationStorage.shared.push(.customChat(chat, targetMessageID: message.id), fromList: true)
        }
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemBackground
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 0
        tableView.keyboardDismissMode = .none
        tableView.alwaysBounceVertical = true
        tableView.delegate = self
        let pressGesture = ContextMenuPressGestureRecognizer(target: self, action: #selector(chatLongPressed(_:)))
        pressGesture.pressedViewProvider = { [weak self] gesture in
            self?.pressedChat(at: gesture.location(in: self?.tableView))?.view
        }
        tableView.addGestureRecognizer(pressGesture)
        tableView.register(ChatListSearchPeerCell.self, forCellReuseIdentifier: ChatListSearchPeerCell.reuseIdentifier)
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseIdentifier)
        tableView.register(
            ChatListSearchTopPeersCell.self,
            forCellReuseIdentifier: ChatListSearchTopPeersCell.reuseIdentifier,
        )
        tableView.register(
            ChatListSearchLoadingCell.self,
            forCellReuseIdentifier: ChatListSearchLoadingCell.reuseIdentifier,
        )
        tableView.register(
            ChatListSearchSectionHeaderView.self,
            forHeaderFooterViewReuseIdentifier: ChatListSearchSectionHeaderView.reuseIdentifier,
        )
        view.addSubview(tableView)
        filterPicker.translatesAutoresizingMaskIntoConstraints = false
        filterPicker.configure(
            items: visibleFilters.map { .init(id: $0.rawValue, title: $0.title) },
            selectedID: filter.rawValue,
        )
        filterPicker.onSelection = { [weak self] id in
            guard let self, let filter = ChatListSearchFilter(rawValue: id), filter != self.filter else { return }
            let restartsChats = filter.listsChats && filter.chatTypeFilter != searchedChatType
            self.filter = filter
            if restartsChats { startSearch() }
            applyFilter()
        }
        view.addSubview(filterPicker)
        filterResults.translatesAutoresizingMaskIntoConstraints = false
        filterResults.isHidden = true
        filterResults.onOpen = { [weak self] message in self?.openFilteredMessage(message) }
        view.addSubview(filterResults)
        downloadsView.translatesAutoresizingMaskIntoConstraints = false
        downloadsView.isHidden = true
        downloadsView.onOpen = { [weak self] message in self?.openFilteredMessage(message) }
        downloadsView.onManageStorage = { [weak self] in
            self?.navigationController?.pushViewController(StorageUsageViewController(), animated: true)
        }
        downloadsView.presenter = { [weak self] in self }
        view.addSubview(downloadsView)
        // Above the lists: they scroll under its blur.
        view.bringSubviewToFront(filterPicker)
        // ChatListSearchContainerNode's filterContainerFrame: 8 pt above the keyboard, or where the folders rest
        // without it, whichever is higher.
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        let restingTop = filterPicker.topAnchor.constraint(
            lessThanOrEqualTo: view.bottomAnchor,
            constant: -FolderPickerView.barHeight,
        )
        filterRestingTopConstraint = restingTop
        let lowestTop = filterPicker.topAnchor.constraint(equalTo: view.bottomAnchor)
        lowestTop.priority = .defaultLow
        NSLayoutConstraint.activate([
            filterPicker.topAnchor.constraint(
                lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor,
                constant: -FolderPickerView.barHeight,
            ),
            restingTop,
            lowestTop,
            filterPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterPicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterPicker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            filterResults.topAnchor.constraint(equalTo: view.topAnchor),
            filterResults.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterResults.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterResults.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            downloadsView.topAnchor.constraint(equalTo: view.topAnchor),
            downloadsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            downloadsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            downloadsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        dataSource = UITableViewDiffableDataSource<
            Section,
            Item,
        >(tableView: tableView) { [weak self] table, indexPath, item in
            self?.cell(for: item, at: indexPath, in: table) ?? UITableViewCell()
        }
        dataSource.defaultRowAnimation = .fade
    }

    private func cell(for item: Item, at indexPath: IndexPath, in table: UITableView) -> UITableViewCell {
        let client = actionAuthority.client
        switch item {
        case .topPeers:
            guard let cell = table.dequeueReusableCell(
                withIdentifier: ChatListSearchTopPeersCell.reuseIdentifier,
                for: indexPath,
            ) as? ChatListSearchTopPeersCell else { return UITableViewCell() }
            cell.configure(chats: topPeerIDs.compactMap { chatsByID[$0] }, client: client)
            cell.onSelect = { [weak self] chat in self?.openFoundChat(chat) }
            return cell
        case .recentPeer(let chatID):
            guard let chat = chatsByID[chatID],
                  let cell = table.dequeueReusableCell(
                      withIdentifier: ChatListSearchPeerCell.reuseIdentifier,
                      for: indexPath,
                  ) as? ChatListSearchPeerCell
            else { return UITableViewCell() }
            cell.configure(
                chat: chat,
                subtitle: Self.subtitle(for: chat, isGlobal: false),
                unreadCount: chat.unreadCount,
                isMuted: rootVM.isMuted(chat),
                client: client,
            )
            return cell
        case .globalPeer(let chatID),
             .localPeer(let chatID):
            guard let chat = chatsByID[chatID],
                  let cell = table.dequeueReusableCell(
                      withIdentifier: ChatListSearchPeerCell.reuseIdentifier,
                      for: indexPath,
                  ) as? ChatListSearchPeerCell
            else { return UITableViewCell() }
            let isGlobal =
                if case .globalPeer = item {
                    true
                } else {
                    false
                }
            cell.configure(
                chat: chat,
                subtitle: Self.subtitle(for: chat, isGlobal: isGlobal),
                // Telegram badges only chats the account already has.
                unreadCount: isGlobal ? 0 : chat.unreadCount,
                isMuted: rootVM.isMuted(chat),
                client: client,
            )
            return cell
        case .message(let key):
            guard let chat = messageChats[key],
                  let cell = table.dequeueReusableCell(
                      withIdentifier: ChatListCell.reuseIdentifier,
                      for: indexPath,
                  ) as? ChatListCell
            else { return UITableViewCell() }
            cell.usesCardStyle = false
            cell.configure(chat: chat, isMuted: false, showsAvatarBadges: false, client: client)
            return cell
        case .messagesLoading:
            return table.dequeueReusableCell(withIdentifier: ChatListSearchLoadingCell.reuseIdentifier, for: indexPath)
        }
    }

    // MARK: Query

    private func startSearch() {
        searchTask?.cancel()
        searchTask = nil
        moreMessagesTask?.cancel()
        moreMessagesTask = nil
        generation &+= 1
        let requestGeneration = generation
        let query = query
        let tableFilter = filter.listsChats ? filter : .chats
        searchedChatType = tableFilter.chatTypeFilter
        globalChatIDs = []
        messageKeys = []
        messageChats = [:]
        nextMessagesOffset = ""
        guard !query.isEmpty else {
            localChatIDs = []
            isLoadingMessages = false
            applySnapshot()
            loadEmptyState()
            return
        }
        // Chats and contacts stay until this query's offline results replace them a moment later.
        isLoadingMessages = true
        applySnapshot()
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        searchTask = Task { [weak self] in
            await self?.search(
                query: query,
                filter: tableFilter,
                generation: requestGeneration,
                scope: scope,
                client: client,
            )
        }
    }

    private func search(
        query: String,
        filter: ChatListSearchFilter,
        generation requestGeneration: UInt64,
        scope: ChatListActionScope,
        client: TDLibClient,
    ) async {
        defer {
            if requestGeneration == generation {
                searchTask = nil
                isLoadingMessages = false
                applySnapshot()
                scheduleMoreMessagesCheck()
            }
        }
        guard isCurrent(requestGeneration, scope) else { return }
        let accountUserID = TDLib.shared.activeAccount?.userID

        // Chats and contacts: TDLib's offline search, then contacts without a chat in any list.
        var ids = [Int64]()
        let typeFilter = filter.chatTypeFilter
        if filter == .chats, Self.matchesSavedMessages(query), let accountUserID,
           let saved = try? await client.createPrivateChat(force: false, userId: accountUserID)
        {
            ids.append(saved.id)
        }
        let chats = try? await client.searchChats(limit: 50, query: query, typeFilter: typeFilter)
        guard isCurrent(requestGeneration, scope) else { return }
        // Telegram lists the account itself only as Saved Messages, matched by that title above.
        ids += (chats?.chatIds ?? []).filter { $0 != accountUserID }
        // Contacts are people, which the Channels and Apps tabs leave out.
        let contacts = filter == .chats ? try? await client.searchContacts(query: query, limit: 50) : nil
        guard isCurrent(requestGeneration, scope) else { return }
        for userID in contacts?.userIds ?? [] where userID != accountUserID && !ids.contains(userID) {
            // A private chat's ID is its user's ID. TDLib opens a contact's chat locally, as searchChats does.
            let chat = try? await client.createPrivateChat(force: false, userId: userID)
            guard isCurrent(requestGeneration, scope) else { return }
            if let chat { ids.append(chat.id) }
        }
        guard let local = await hydrate(
            Self.deduplicated(ids),
            generation: requestGeneration,
            scope: scope,
            client: client,
        )
        else { return }
        localChatIDs = local
        applySnapshot()

        do {
            try await Task.sleep(for: Self.remoteSearchDelay)
        } catch {
            return
        }
        guard isCurrent(requestGeneration, scope) else { return }

        let chatList = chatList
        let messagesLimit = Self.messagesFirstPageLimit
        async let serverChats = client.searchChatsOnServer(limit: 50, query: query, typeFilter: typeFilter)
        async let publicChats = client.searchPublicChats(query: query, typeFilter: typeFilter)
        // The Channels tab finds channel posts too; the Apps tab finds no messages.
        let messageTypeFilter: SearchMessagesChatTypeFilter? = filter == .channels
            ? .searchMessagesChatTypeFilterChannel
            : nil
        async let foundMessages = filter == .apps
            ? nil
            : client.searchMessages(
                chatList: chatList,
                query: query,
                offset: "",
                limit: messagesLimit,
                filter: nil,
                chatTypeFilter: messageTypeFilter,
                minDate: 0,
                maxDate: 0,
            )

        // The account's own chats found on the server join the local section, as Telegram's remote peers do.
        let server = try? await serverChats
        guard isCurrent(requestGeneration, scope) else { return }
        let serverIDs = Self.deduplicated((server?.chatIds ?? []).filter {
            $0 != accountUserID && !localChatIDs.contains($0)
        })
        guard let hydratedServer = await hydrate(
            serverIDs, generation: requestGeneration, scope: scope, client: client,
        ) else { return }
        localChatIDs += hydratedServer

        let publicResult = try? await publicChats
        guard isCurrent(requestGeneration, scope) else { return }
        let publicIDs = Self.deduplicated((publicResult?.chatIds ?? []).filter {
            $0 != accountUserID && !localChatIDs.contains($0)
        })
        guard let hydratedPublic = await hydrate(
            publicIDs, generation: requestGeneration, scope: scope, client: client,
        ) else { return }
        globalChatIDs = hydratedPublic
        applySnapshot()

        let found = try? await foundMessages
        guard isCurrent(requestGeneration, scope) else { return }
        if let found {
            guard await appendMessages(found.messages, generation: requestGeneration, scope: scope, client: client)
            else { return }
            nextMessagesOffset = found.nextOffset
        }
        completedGeneration = requestGeneration
    }

    private func loadMoreMessages() {
        guard searchTask == nil, moreMessagesTask == nil, !nextMessagesOffset.isEmpty, !query.isEmpty else { return }
        let requestGeneration = generation
        let query = query
        let offset = nextMessagesOffset
        let chatList = chatList
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        // The task starts after this display callback, so the loading row is not inserted mid-display.
        moreMessagesTask = Task { [weak self] in
            guard let self else { return }
            isLoadingMessages = true
            applySnapshot()
            defer {
                if requestGeneration == generation {
                    moreMessagesTask = nil
                    isLoadingMessages = false
                    applySnapshot()
                    scheduleMoreMessagesCheck()
                }
            }
            let channelPosts =
                if case .searchChatTypeFilterChannel? = searchedChatType {
                    true
                } else {
                    false
                }
            let found = try? await client.searchMessages(
                chatList: chatList,
                query: query,
                offset: offset,
                limit: Self.messagesPageLimit,
                filter: nil,
                chatTypeFilter: channelPosts ? .searchMessagesChatTypeFilterChannel : nil,
                minDate: 0,
                maxDate: 0,
            )
            guard isCurrent(requestGeneration, scope) else { return }
            guard let found else {
                // A failed page ends paging instead of retrying from every displayed row.
                nextMessagesOffset = ""
                return
            }
            guard await appendMessages(found.messages, generation: requestGeneration, scope: scope, client: client)
            else { return }
            nextMessagesOffset = found.nextOffset
        }
    }

    /// A short page leaves its last rows on screen with no later display callback to request the next page.
    private func scheduleMoreMessagesCheck() {
        guard !nextMessagesOffset.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in self?.loadMoreMessagesIfNeeded() }
    }

    private func loadMoreMessagesIfNeeded() {
        guard let section = dataSource.snapshot().indexOfSection(.messages) else { return }
        let lastRows = tableView.numberOfRows(inSection: section) - 5
        guard tableView.indexPathsForVisibleRows?
            .contains(where: { $0.section == section && $0.row >= lastRows }) == true
        else { return }
        loadMoreMessages()
    }

    /// Loads each chat once through the root, which drops a chat that completes after an account or client switch.
    /// Returns nil when the query or its client is no longer current.
    private func hydrate(
        _ chatIDs: [Int64],
        generation requestGeneration: UInt64,
        scope: ChatListActionScope,
        client: TDLibClient,
    ) async -> [Int64]? {
        var hydrated = [Int64]()
        for chatID in chatIDs {
            if chatsByID[chatID] == nil {
                let chat = await rootVM.getCustomChatForNavigation(from: chatID, client: client)
                guard isCurrent(requestGeneration, scope) else { return nil }
                guard let chat, chat.id == chatID else { continue }
                chatsByID[chatID] = chat
            }
            hydrated.append(chatID)
        }
        return hydrated
    }

    private func appendMessages(
        _ messages: [Message],
        generation requestGeneration: UInt64,
        scope: ChatListActionScope,
        client: TDLibClient,
    ) async -> Bool {
        guard await hydrate(
            Self.deduplicated(messages.map(\.chatId)),
            generation: requestGeneration,
            scope: scope,
            client: client,
        ) != nil else { return false }
        var known = Set(messageKeys)
        for message in messages {
            let key = MessageKey(chatID: message.chatId, messageID: message.id)
            guard let chat = chatsByID[message.chatId], known.insert(key).inserted else { continue }
            // A found message shows as its chat's row with that message, as Telegram's ChatListItem does.
            messageChats[key] = CustomChat(
                chat: chat.chat,
                position: ChatPosition(isPinned: false, list: chatList, order: 0, source: nil),
                unreadCount: 0,
                type: chat.type,
                lastMessage: message,
            )
            messageKeys.append(key)
        }
        return true
    }

    /// ChatListSearchContainerNode before a query: TDLib's top people and the chats found recently.
    private func loadEmptyState() {
        emptyStateTask?.cancel()
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        let requestGeneration = generation
        emptyStateTask = Task { [weak self] in
            async let top = client.getTopChats(category: .topChatCategoryUsers, limit: 30)
            async let recent = client.searchRecentlyFoundChats(query: "", typeFilter: nil, limit: 50)
            let topIDs = await (try? top)?.chatIds ?? []
            let recentIDs = await (try? recent)?.chatIds ?? []
            guard let self, isCurrent(requestGeneration, scope), query.isEmpty,
                  let hydratedTop = await hydrate(topIDs, generation: requestGeneration, scope: scope, client: client),
                  let hydratedRecent = await hydrate(
                      recentIDs,
                      generation: requestGeneration,
                      scope: scope,
                      client: client,
                  )
            else { return }
            topPeerIDs = hydratedTop
            recentChatIDs = hydratedRecent
            applySnapshot(reloadingSections: [.topPeers])
        }
    }

    /// The chat under `point` in the table: a found chat's row or a person in the People row.
    private func pressedChat(at point: CGPoint) -> (chat: CustomChat, view: UIView, isTopPeer: Bool)? {
        guard let indexPath = tableView.indexPathForRow(at: point),
              let cell = tableView.cellForRow(at: indexPath)
        else { return nil }
        switch dataSource.itemIdentifier(for: indexPath) {
        case .globalPeer(let chatID)?,
             .localPeer(let chatID)?,
             .recentPeer(let chatID)?:
            return chatsByID[chatID].map { ($0, cell.contentView, false) }
        case .topPeers?:
            return (cell as? ChatListSearchTopPeersCell)?.peer(at: point, in: tableView)
                .map { ($0.chat, $0.view, true) }
        default:
            return nil
        }
    }

    /// ChatListSearchListPaneNode's peer context action: the chat's preview over ChatContextMenus' items for the
    /// `.search` source.
    @objc private func chatLongPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began, actionAuthority.scope(owner: self).isCurrent,
              let pressed = pressedChat(at: gesture.location(in: tableView))
        else { return }
        let actions = menu(for: pressed.chat, isTopPeer: pressed.isTopPeer)
        guard !actions.isEmpty else { return }
        presentTelegramContextMenu(
            sourceView: pressed.view,
            actions: actions,
            tracking: gesture,
            presentationStyle: .chatPreview,
            previewController: ChatViewController(customChat: pressed.chat, presentationMode: .contextPreview),
        )
    }

    /// Remove from Recents for a recently found chat, Add to Contacts for someone not in them, then the chat list's
    /// items for a chat the account has or Join for a channel or group it hasn't joined.
    private func menu(for chat: CustomChat, isTopPeer: Bool) -> [TelegramContextMenuAction] {
        let client = actionAuthority.client
        var actions = [TelegramContextMenuAction]()
        if !isTopPeer, recentChatIDs.contains(chat.id) {
            let chatID = chat.id
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.Context.RemoveFromRecents"),
                image: UIImage(systemName: "xmark.circle"),
                isDestructive: true,
            ) { [weak self] in
                Task { _ = try? await client.removeRecentlyFoundChat(chatId: chatID) }
                self?.recentChatIDs.removeAll { $0 == chatID }
                self?.applySnapshot()
            })
        }
        if let user = chat.user, !user.isContact, !chat.isSavedMessages, user.id != 777_000 {
            let isPerson =
                switch user.type {
                case .userTypeRegular: true
                default: false
                }
            if isPerson {
                actions.append(TelegramContextMenuAction(
                    title: L10n.telegram("ChatList.Context.AddToContacts"),
                    image: UIImage(systemName: "person.badge.plus"),
                    startsNewSection: !actions.isEmpty,
                ) { [weak self] in
                    self?.presentAddContact(user)
                })
            }
        }
        let isJoined = !chat.chat.positions.isEmpty
        if isJoined {
            var chatActions = chatMenu?(chat) ?? []
            if !actions.isEmpty, !chatActions.isEmpty { chatActions[0].startsNewSection = true }
            if isTopPeer {
                // A person in the People row leaves it with Remove from Recents, before Delete (removeRecentPeer).
                let chatID = chat.id
                let deleteIndex = chatActions.lastIndex { $0.isDestructive } ?? chatActions.endIndex
                chatActions.insert(TelegramContextMenuAction(
                    title: L10n.telegram("ChatList.Context.RemoveFromRecents"),
                    image: UIImage(systemName: "xmark.circle"),
                    isDestructive: true,
                    startsNewSection: true,
                ) { [weak self] in
                    Task { _ = try? await client.removeTopChat(category: .topChatCategoryUsers, chatId: chatID) }
                    self?.topPeerIDs.removeAll { $0 == chatID }
                    self?.applySnapshot(reloadingSections: [.topPeers])
                }, at: deleteIndex)
                if chatActions.indices
                    .contains(deleteIndex + 1) { chatActions[deleteIndex + 1].startsNewSection = false }
            }
            actions.append(contentsOf: chatActions)
        } else if let supergroup = chat.supergroup {
            let chatID = chat.id
            actions.append(TelegramContextMenuAction(
                title: L10n
                    .telegram(supergroup.isChannel ? "ChatList.Context.JoinChannel" : "ChatList.Context.JoinChat"),
                image: UIImage(systemName: "plus.circle"),
                startsNewSection: !actions.isEmpty,
            ) { [weak self] in
                self?.join(chatID: chatID, chat: chat)
            })
        }
        return actions
    }

    /// Join for a channel or group found by search: once joined, the chat opens.
    private func join(chatID: Int64, chat: CustomChat) {
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        Task { [weak self] in
            do {
                _ = try await client.joinChat(chatId: chatID)
                guard let self, scope.isCurrent else { return }
                openFoundChat(chat)
            } catch {
                guard let self, scope.isCurrent, presentedViewController == nil else { return }
                let alert = UIAlertController(
                    title: nil,
                    message: L10n.telegram("Login.UnknownError"),
                    preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    /// openAddPersonContact: the person's name to keep, then `addContact` without sharing the phone number.
    private func presentAddContact(_ user: User) {
        guard presentedViewController == nil else { return }
        let client = actionAuthority.client
        let scope = actionAuthority.scope(owner: self)
        let alert = UIAlertController(title: L10n.telegram("AddContact.Title"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = L10n.telegram("UserInfo.FirstNamePlaceholder")
            field.text = user.firstName
            field.autocapitalizationType = .words
        }
        alert.addTextField { field in
            field.placeholder = L10n.telegram("UserInfo.LastNamePlaceholder")
            field.text = user.lastName
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        let done = UIAlertAction(title: L10n.telegram("Common.Done"), style: .default) { [weak self, weak alert] _ in
            let firstName = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lastName = alert?.textFields?.last?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !firstName.isEmpty || !lastName.isEmpty else { return }
            let contact = ImportedContact(
                firstName: firstName,
                lastName: lastName,
                note: FormattedText(entities: [], text: ""),
                phoneNumber: user.phoneNumber,
            )
            Task { [weak self] in
                let added = await (
                    try? client.addContact(contact: contact, sharePhoneNumber: false, userId: user.id)
                ) !=
                    nil
                guard let self, scope.isCurrent else { return }
                if added {
                    let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
                    showToast(L10n.telegram("AddContact.StatusSuccess", name))
                }
            }
        }
        alert.addAction(done)
        alert.preferredAction = done
        present(alert, animated: true)
    }

    private func showToast(_ text: String) {
        TelegramUndoToast.show(text: text, in: view, bottomInset: 8, undo: nil)
    }

    /// A chat picked from the results joins the recently found ones, as Telegram's addRecentlySearchedPeer does.
    private func openFoundChat(_ chat: CustomChat) {
        let client = actionAuthority.client
        let chatID = chat.id
        Task { _ = try? await client.addRecentlyFoundChat(chatId: chatID) }
        NavigationStorage.shared.push(.customChat(chat), fromList: true)
    }

    /// ChatListSearchContainerNode.clearRecentSearch: a menu from Clear asks before clearing the list.
    private func confirmClearingRecent(from source: UIView) {
        let client = actionAuthority.client
        let actions = [
            {
                var title = TelegramContextMenuAction(title: L10n.telegram("ChatList.ClearSearchHistory"))
                title.isInformational = true
                return title
            }(),
            TelegramContextMenuAction(
                title: L10n.telegram("ChatList.ClearSearchHistory.Confirm"),
                isDestructive: true,
            ) {
                [weak self] in
                Task { [weak self] in
                    _ = try? await client.clearRecentlyFoundChats()
                    guard let self else { return }
                    recentChatIDs = []
                    applySnapshot()
                }
            },
        ]
        // Telegram's menu grows out of the Clear it was opened from (ChatListSearchClearRecentReferenceContentSource).
        presentTelegramContextMenu(sourceView: source, actions: actions, presentationStyle: .sourceMorph)
    }

    private func isCurrent(_ requestGeneration: UInt64, _ scope: ChatListActionScope) -> Bool {
        requestGeneration == generation && scope.isCurrent
    }

    /// Results of another account or client are never shown or opened.
    private func discardResults() {
        searchTask?.cancel()
        searchTask = nil
        moreMessagesTask?.cancel()
        moreMessagesTask = nil
        generation &+= 1
        chatsByID.removeAll()
        localChatIDs = []
        globalChatIDs = []
        messageKeys = []
        messageChats = [:]
        nextMessagesOffset = ""
        isLoadingMessages = false
        if isViewLoaded { applySnapshot() }
    }

    private func toggleGlobalExpansion() {
        isGlobalExpanded.toggle()
        applySnapshot(reloadingSections: [.globalPeers])
    }

    private func applySnapshot(reloadingSections: [Section] = []) {
        guard isViewLoaded else { return }
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if query.isEmpty {
            if !topPeerIDs.isEmpty {
                snapshot.appendSections([.topPeers])
                snapshot.appendItems([.topPeers])
            }
            if !recentChatIDs.isEmpty {
                snapshot.appendSections([.recent])
                snapshot.appendItems(recentChatIDs.map(Item.recentPeer))
            }
        }
        if !localChatIDs.isEmpty {
            snapshot.appendSections([.localPeers])
            snapshot.appendItems(localChatIDs.map(Item.localPeer))
        }
        let visibleGlobalIDs = isGlobalExpanded ? globalChatIDs : Array(globalChatIDs.prefix(Self.collapsedGlobalCount))
        if !visibleGlobalIDs.isEmpty {
            snapshot.appendSections([.globalPeers])
            snapshot.appendItems(visibleGlobalIDs.map(Item.globalPeer))
        }
        var messageItems = messageKeys.map(Item.message)
        if isLoadingMessages { messageItems.append(.messagesLoading) }
        if !messageItems.isEmpty {
            snapshot.appendSections([.messages])
            snapshot.appendItems(messageItems)
        }
        let reloaded = reloadingSections.filter { snapshot.sectionIdentifiers.contains($0) }
        if !reloaded.isEmpty { snapshot.reloadSections(reloaded) }
        dataSource.apply(snapshot, animatingDifferences: !reloaded.isEmpty)
        updateBackgroundView()
    }

    private func updateBackgroundView() {
        guard dataSource.snapshot().numberOfItems == 0, !query.isEmpty, actionAuthority.isCurrent else {
            activityIndicator.stopAnimating()
            tableView.backgroundView = nil
            return
        }
        if searchTask != nil {
            activityIndicator.startAnimating()
            tableView.backgroundView = activityIndicator
        } else {
            activityIndicator.stopAnimating()
            emptyView.configure(query: query)
            tableView.backgroundView = emptyView
        }
    }
}

// MARK: - TelegramListTableView

/// A plain table whose section headers scroll with their rows, as Telegram's list headers do
/// (ChatListSearchItemHeader's
/// `isSticky` is false): with no fill of their own, a floating header would lie over the rows.
// swiftformat:disable:next preferFinalClasses
class TelegramListTableView: UITableView {
    @objc(allowsHeaderViewsToFloat) private var allowsHeaderViewsToFloat: Bool { false }
}

// MARK: - ChatListSearchSectionHeaderView

/// Telegram 13's ChatListSearchItemHeader (ListSectionHeaderNode): an uppercased 13 pt caption 16 pt in, over no fill,
/// and an optional trailing action in the caption's colour. An action that opens a menu, such as Clear, is a small
/// glass
/// capsule the menu grows out of.
final class ChatListSearchSectionHeaderView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "ChatListSearchSectionHeaderView"
    static let height: CGFloat = 28

    private static let glassActionHeight: CGFloat = 24

    private let titleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let glassAction: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let view = UIVisualEffectView(effect: effect)
        view.cornerConfiguration = .capsule()
        return view
    }()

    private let glassActionLabel = UILabel()
    private var action: ((UIView) -> Void)?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        backgroundConfiguration = .clear()
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        action = nil
    }

    override func accessibilityActivate() -> Bool {
        guard let action else { return false }
        action(glassAction.isHidden ? actionButton : glassAction)
        return true
    }

    func configure(title: String, actionTitle: String?, action: (() -> Void)?) {
        configure(title: title, actionTitle: actionTitle, actionInGlass: false, action: action.map { action in
            { _ in action() }
        })
    }

    /// `action` receives the view it was triggered from, which a menu grows out of.
    func configure(title: String, actionTitle: String?, actionInGlass: Bool, action: ((UIView) -> Void)?) {
        titleLabel.text = title.uppercased()
        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.isHidden = actionTitle == nil || actionInGlass
        glassActionLabel.text = actionTitle
        glassAction.isHidden = actionTitle == nil || !actionInGlass
        glassAction.accessibilityLabel = actionTitle
        self.action = actionTitle == nil ? nil : action
    }

    private func configureViews() {
        for subview in [titleLabel, actionButton, glassAction] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabel
        titleLabel.accessibilityTraits = .header
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 13)
        actionButton.tintColor = .secondaryLabel
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)

        glassActionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        glassActionLabel.textColor = .label
        glassActionLabel.translatesAutoresizingMaskIntoConstraints = false
        glassAction.contentView.addSubview(glassActionLabel)
        glassAction.isAccessibilityElement = true
        glassAction.accessibilityTraits = .button
        glassAction.isHidden = true
        // The glass takes the touch, as UIKit swells interactive glass only under a touch inside it.
        glassAction.contentView.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(glassActionPressed),
        ))
        glassAction.setContentCompressionResistancePriority(.required, for: .horizontal)

        let inset: CGFloat = 16
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(
                equalTo: contentView.safeAreaLayoutGuide.leadingAnchor,
                constant: inset,
            ),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: glassAction.leadingAnchor, constant: -8),
            actionButton.trailingAnchor.constraint(
                equalTo: contentView.safeAreaLayoutGuide.trailingAnchor,
                constant: -inset,
            ),
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            // The capsule's edge lines up with the bar's buttons above it.
            glassAction.trailingAnchor.constraint(
                equalTo: contentView.safeAreaLayoutGuide.trailingAnchor,
                constant: -TelegramGlassPlatter.edgeInset,
            ),
            glassAction.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            glassAction.heightAnchor.constraint(equalToConstant: Self.glassActionHeight),
            glassActionLabel.leadingAnchor.constraint(equalTo: glassAction.contentView.leadingAnchor, constant: 10),
            glassActionLabel.trailingAnchor.constraint(equalTo: glassAction.contentView.trailingAnchor, constant: -10),
            glassActionLabel.centerYAnchor.constraint(equalTo: glassAction.contentView.centerYAnchor),
        ])
    }

    @objc private func actionPressed() {
        action?(actionButton)
    }

    @objc private func glassActionPressed() {
        action?(glassAction)
    }
}

// MARK: - ChatListSearchPeerCell

/// A chat or contact result, after Telegram's ContactsPeerItem in general search.
private final class ChatListSearchPeerCell: UITableViewCell {
    static let reuseIdentifier = "ChatListSearchPeerCell"

    private let avatarView = ProfileAvatarView()
    private let labels = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let unreadLabel = TelegramUnreadBadgeLabel(minimumDiameter: 20, horizontalPadding: 10)
    private let separatorView = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .systemBackground
        let selectedBackground = UIView()
        selectedBackground.backgroundColor = .tertiarySystemFill
        selectedBackgroundView = selectedBackground
        isAccessibilityElement = true
        accessibilityTraits = .button
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(chat: CustomChat, subtitle: String?, unreadCount: Int, isMuted: Bool, client: TDLibClient) {
        titleLabel.attributedText = PeerCredibilityBadge.title(
            chat.displayTitle,
            badge: PeerCredibilityBadge(chat: chat),
            font: titleLabel.font,
            color: .label,
        )
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        unreadLabel.text = unreadCount > 0 ? compactNumericCountString(unreadCount) : nil
        unreadLabel.backgroundColor = isMuted ? .systemGray : .systemBlue
        unreadLabel.isHidden = unreadCount == 0
        avatarView.configure(
            file: chat.chat.photo?.small,
            minithumbnail: chat.chat.photo?.minithumbnail,
            placeholder: chat.telegramAvatarPlaceholder,
            client: client,
        )
        accessibilityLabel = [
            chat.displayTitle,
            subtitle,
            unreadCount > 0 ? L10n.telegramPlural("VoiceOver.Chat.UnreadMessages", count: unreadCount) : nil,
        ]
            .compactMap(\.self)
            .joined(separator: ", ")
    }

    private func configureViews() {
        for subview in [avatarView, labels, unreadLabel, separatorView] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        labels.axis = .vertical
        labels.spacing = 1
        labels.addArrangedSubview(titleLabel)
        labels.addArrangedSubview(subtitleLabel)
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .semibold),
            maximumPointSize: 19,
        )
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 14),
            maximumPointSize: 16,
        )
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingTail
        unreadLabel.textColor = .white
        unreadLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        unreadLabel.isHidden = true
        separatorView.backgroundColor = .separator
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            labels.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: unreadLabel.leadingAnchor, constant: -8),
            unreadLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            unreadLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            separatorView.leadingAnchor.constraint(equalTo: labels.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
        ])
    }
}

// MARK: TelegramContextExpansionSource

extension ChatListSearchPeerCell: TelegramContextExpansionSource {
    var contextExpansionTitle: UILabel? { titleLabel }
    var contextExpansionTitleAccessories: [UIView] { [] }
}

// MARK: - ChatListSearchLoadingCell

/// Stands in for Telegram's message placeholders while messages load.
final class ChatListSearchLoadingCell: UITableViewCell {
    static let reuseIdentifier = "ChatListSearchLoadingCell"

    private let indicator = UIActivityIndicatorView(style: .medium)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .systemBackground
        selectionStyle = .none
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        contentView.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        indicator.startAnimating()
    }
}

// MARK: - ChatListSearchEmptyView

/// Telegram's empty search result: No Results and the query it searched for.
private final class ChatListSearchEmptyView: UIView {
    private let titleLabel = UILabel()
    private let textLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [titleLabel, textLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        addSubview(stack)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.text = L10n.telegram("ChatList.Search.NoResults")
        textLabel.font = .systemFont(ofSize: 15)
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(query: String) {
        titleLabel.text = L10n.telegram("ChatList.Search.NoResults")
        textLabel.text = L10n.telegram("ChatList.Search.NoResultsQueryDescription", query)
    }
}

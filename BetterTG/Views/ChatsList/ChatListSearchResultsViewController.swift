// ChatListSearchResultsViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ChatListSearchResultsViewController

/// Telegram's chat list search (ChatListSearchListPaneNode, Chats pane) over TDLib: chats and contacts, global public
/// chats, then messages from the searched chat list. Every result belongs to the client that issued its query.
@MainActor final class ChatListSearchResultsViewController: UIViewController, UITableViewDelegate {
    private enum Section: Hashable {
        case localPeers
        case globalPeers
        case messages
    }

    private enum Item: Hashable {
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

    private let rootVM: RootVM
    private let chatList: ChatList
    private let actionAuthority: ChatListActionAuthority
    private let tableView = UITableView(frame: .zero, style: .plain)
    /// ChatListSearchFiltersContainerNode's tabs, in BetterTG's folder strip.
    private let filterPicker = FolderPickerView()
    private let filterResults = ChatListSearchFilterResultsView()
    private var filter = ChatListSearchFilter.chats
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

    /// Telegram's ContactsPeerItem status: a global result shows its address and audience, a local bot says so.
    private static func subtitle(for chat: CustomChat, isGlobal: Bool) -> String? {
        guard isGlobal else { return chat.bot == nil ? nil : L10n.telegram("Bot.GenericBotStatus") }
        var parts = [String]()
        if let username = (chat.supergroup?.usernames ?? chat.user?.usernames)?.activeUsernames.first,
           !username.isEmpty
        {
            parts.append("@" + username)
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
        case .globalPeer(let chatID),
             .localPeer(let chatID):
            guard let chat = chatsByID[chatID] else { return }
            NavigationStorage.shared.push(.customChat(chat))
        case .message(let key):
            guard let chat = chatsByID[key.chatID] else { return }
            NavigationStorage.shared.push(.customChat(chat, targetMessageID: key.messageID))
        case .messagesLoading:
            return
        }
    }

    func tableView(_: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .globalPeer,
             .localPeer: Self.peerRowHeight
        case .message: Self.messageRowHeight
        case .messagesLoading,
             nil: Self.loadingRowHeight
        }
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
        let showsMessages = filter != .chats
        tableView.isHidden = showsMessages
        filterResults.isHidden = !showsMessages
        guard showsMessages, !query.isEmpty, actionAuthority.scope(owner: self).isCurrent else {
            if !showsMessages { filterResults.reset() }
            return
        }
        filterResults.show(filter: filter, query: query, client: actionAuthority.client, chatList: chatList)
    }

    private func openFilteredMessage(_ message: Message) {
        let scope = actionAuthority.scope(owner: self)
        guard scope.isCurrent else { return }
        let client = actionAuthority.client
        Task { [weak self] in
            guard let self,
                  let chat = await rootVM.getCustomChatForNavigation(from: message.chatId, client: client),
                  scope.isCurrent, chat.id == message.chatId else { return }
            NavigationStorage.shared.push(.customChat(chat, targetMessageID: message.id))
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
        tableView.register(ChatListSearchPeerCell.self, forCellReuseIdentifier: ChatListSearchPeerCell.reuseIdentifier)
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseIdentifier)
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
            items: ChatListSearchFilter.allCases.map { .init(id: $0.rawValue, title: $0.title) },
            selectedID: filter.rawValue,
        )
        filterPicker.onSelection = { [weak self] id in
            guard let self, let filter = ChatListSearchFilter(rawValue: id), filter != self.filter else { return }
            self.filter = filter
            applyFilter()
        }
        view.addSubview(filterPicker)
        filterResults.translatesAutoresizingMaskIntoConstraints = false
        filterResults.isHidden = true
        filterResults.onOpen = { [weak self] message in self?.openFilteredMessage(message) }
        view.addSubview(filterResults)
        NSLayoutConstraint.activate([
            filterPicker.topAnchor.constraint(equalTo: view.topAnchor),
            filterPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterPicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterPicker.heightAnchor.constraint(equalToConstant: 58),
            tableView.topAnchor.constraint(equalTo: filterPicker.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            filterResults.topAnchor.constraint(equalTo: filterPicker.bottomAnchor),
            filterResults.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterResults.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterResults.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
        globalChatIDs = []
        messageKeys = []
        messageChats = [:]
        nextMessagesOffset = ""
        guard !query.isEmpty else {
            localChatIDs = []
            isLoadingMessages = false
            applySnapshot()
            return
        }
        // Chats and contacts stay until this query's offline results replace them a moment later.
        isLoadingMessages = true
        applySnapshot()
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        searchTask = Task { [weak self] in
            await self?.search(query: query, generation: requestGeneration, scope: scope, client: client)
        }
    }

    private func search(
        query: String,
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
        if Self.matchesSavedMessages(query), let accountUserID,
           let saved = try? await client.createPrivateChat(force: false, userId: accountUserID)
        {
            ids.append(saved.id)
        }
        let chats = try? await client.searchChats(limit: 50, query: query, typeFilter: nil)
        guard isCurrent(requestGeneration, scope) else { return }
        // Telegram lists the account itself only as Saved Messages, matched by that title above.
        ids += (chats?.chatIds ?? []).filter { $0 != accountUserID }
        let contacts = try? await client.searchContacts(query: query, limit: 50)
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
        async let serverChats = client.searchChatsOnServer(limit: 50, query: query, typeFilter: nil)
        async let publicChats = client.searchPublicChats(query: query, typeFilter: nil)
        async let foundMessages = client.searchMessages(
            chatList: chatList,
            query: query,
            offset: "",
            limit: messagesLimit,
            filter: nil,
            chatTypeFilter: nil,
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
            let found = try? await client.searchMessages(
                chatList: chatList,
                query: query,
                offset: offset,
                limit: Self.messagesPageLimit,
                filter: nil,
                chatTypeFilter: nil,
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

// MARK: - ChatListSearchSectionHeaderView

/// Telegram's ChatListSearchItemHeader: an uppercased caption with an optional trailing action.
final class ChatListSearchSectionHeaderView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "ChatListSearchSectionHeaderView"
    static let height: CGFloat = 28

    private let titleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var action: (() -> Void)?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = .secondarySystemBackground
        backgroundConfiguration = background
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        action = nil
    }

    func configure(title: String, actionTitle: String?, action: (() -> Void)?) {
        titleLabel.text = title.uppercased()
        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.isHidden = actionTitle == nil
        self.action = actionTitle == nil ? nil : action
    }

    private func configureViews() {
        for subview in [titleLabel, actionButton] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabel
        titleLabel.accessibilityTraits = .header
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 13)
        actionButton.tintColor = .systemBlue
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -8),
            actionButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @objc private func actionPressed() {
        action?()
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

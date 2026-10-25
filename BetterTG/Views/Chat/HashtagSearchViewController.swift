// HashtagSearchViewController.swift

import TDLibKit
import UIKit

// MARK: - HashtagSearchViewController

/// Telegram's HashtagSearchController: the hashtag in a search field with Cancel, and the messages that carry it under
/// This Chat, My Messages and Public Posts tabs (HashtagSearchNavigationContentNode), each a list of found messages as
/// chat rows (`alwaysShowSearchResultsAsList`). A hashtag naming a chat searches that chat only, without tabs.
@MainActor final class HashtagSearchViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
UITextFieldDelegate, TelegramEmbeddedNavigationChrome {
    enum Tab: Int, CaseIterable {
        case thisChat
        case myMessages
        case publicPosts

        var title: String {
            switch self {
            case .thisChat: L10n.telegram("HashtagSearch.ThisChat")
            case .myMessages: L10n.telegram("HashtagSearch.MyMessages")
            case .publicPosts: L10n.telegram("HashtagSearch.PublicPosts")
            }
        }
    }

    private struct Results {
        var rows = [CustomChat]()
        var keys = Set<String>()
        /// searchChatMessages pages by message, the others by TDLib's offset string; nil when there are no more.
        var nextOffset: String? = ""
        var nextFromMessageID: Int64 = 0
        var isLoading = false
        var hasLoaded = false
    }

    private struct Page {
        let messages: [Message]
        let nextOffset: String?
        let nextFromMessageID: Int64
    }

    private static let pageLimit = 50
    private static let rowHeight: CGFloat = 76
    private static let queryDelay = Duration.milliseconds(400)

    private let client: TDLibClient
    private let chat: CustomChat?
    private let tabs: [Tab]
    private var selectedTab: Tab
    private var query: String
    private var results = [Tab: Results]()
    private var chatsByID = [Int64: CustomChat]()
    private var generation = 0
    private var searchTask: Task<Void, Never>?
    private var queryTask: Task<Void, Never>?

    private let headerView = UIView()
    private let searchField = UISearchTextField()
    private let cancelButton = UIButton(type: .system)
    private let tabPicker = FolderPickerView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let emptyTitleLabel = UILabel()
    private let emptyTextLabel = UILabel()
    private lazy var emptyStack = UIStackView(arrangedSubviews: [emptyTitleLabel, emptyTextLabel])

    /// `chat` is the chat the hashtag was tapped in; `chatOnly` leaves the other tabs out, as for "#tag@chat".
    /// `startsOnPublicPosts` opens Public Posts first, as from a public channel.
    init(query: String, chat: CustomChat?, chatOnly: Bool, startsOnPublicPosts: Bool, client: TDLibClient) {
        self.query = query
        self.chat = chat
        self.client = client
        self.tabs =
            if chatOnly, chat != nil {
                [.thisChat]
            } else {
                chat == nil ? [.myMessages, .publicPosts] : Tab.allCases
            }
        self.selectedTab = startsOnPublicPosts && !chatOnly ? .publicPosts : (tabs.first ?? .myMessages)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        searchTask?.cancel()
        queryTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureHeader()
        configureTable()
        search()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private nonisolated static func page(
        tab: Tab,
        query: String,
        chatID: Int64?,
        offset: String,
        fromMessageID: Int64,
        client: TDLibClient,
    ) async -> Page {
        switch tab {
        case .thisChat:
            guard let chatID, let found = try? await client.send(TDNativeRequests.searchChatMessages(
                chatId: chatID, topicId: nil, query: query, senderId: nil, fromMessageId: fromMessageID,
                offset: 0, limit: pageLimit, filter: nil,
            )) else { return Page(messages: [], nextOffset: nil, nextFromMessageID: 0) }
            let next = found.nextFromMessageId
            return Page(messages: found.messages, nextOffset: next == 0 ? nil : "", nextFromMessageID: next)
        case .myMessages:
            guard let found = try? await client.searchMessages(
                chatList: nil, query: query, offset: offset, limit: pageLimit, filter: nil, chatTypeFilter: nil,
                minDate: 0, maxDate: 0,
            ) else { return Page(messages: [], nextOffset: nil, nextFromMessageID: 0) }
            return Page(
                messages: found.messages,
                nextOffset: found.nextOffset.isEmpty ? nil : found.nextOffset,
                nextFromMessageID: 0,
            )
        case .publicPosts:
            guard let found = try? await client.send(TDNativeRequests.searchPublicMessagesByTag(
                tag: query, offset: offset, limit: pageLimit,
            )) else { return Page(messages: [], nextOffset: nil, nextFromMessageID: 0) }
            return Page(
                messages: found.messages,
                nextOffset: found.nextOffset.isEmpty ? nil : found.nextOffset,
                nextFromMessageID: 0,
            )
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        results[selectedTab]?.rows.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let rows = results[selectedTab]?.rows, rows.indices.contains(indexPath.row),
              let cell = tableView.dequeueReusableCell(
                  withIdentifier: ChatListCell.reuseIdentifier,
                  for: indexPath,
              ) as? ChatListCell
        else { return UITableViewCell() }
        cell.usesCardStyle = false
        cell.configure(chat: rows[indexPath.row], isMuted: false, showsAvatarBadges: false, client: client)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = results[selectedTab]?.rows[safe: indexPath.row], let message = row.lastMessage,
              let chat = chatsByID[row.id] else { return }
        NavigationStorage.shared.push(.customChat(chat, targetMessageID: message.id))
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let count = results[selectedTab]?.rows.count, indexPath.row >= count - 5 else { return }
        search(more: true)
    }

    // MARK: Header

    private func configureHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.text = query
        searchField.placeholder = L10n.telegram("HashtagSearch.SearchPlaceholder")
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        headerView.addSubview(searchField)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle(L10n.telegram("Common.Cancel"), for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)
        cancelButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        cancelButton.addAction(UIAction { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        }, for: .touchUpInside)
        headerView.addSubview(cancelButton)
        tabPicker.translatesAutoresizingMaskIntoConstraints = false
        tabPicker.isHidden = tabs.count < 2
        tabPicker.configure(
            items: tabs.map { .init(id: $0.rawValue, title: $0.title) },
            selectedID: selectedTab.rawValue,
        )
        tabPicker.onSelection = { [weak self] id in
            guard let self, let tab = Tab(rawValue: id), tab != selectedTab else { return }
            select(tab)
        }
        headerView.addSubview(tabPicker)
        let tabsHeight: CGFloat = tabs.count < 2 ? 0 : 58
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchField.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            searchField.heightAnchor.constraint(equalToConstant: 36),
            cancelButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 10),
            cancelButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            cancelButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            tabPicker.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            tabPicker.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            tabPicker.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            tabPicker.heightAnchor.constraint(equalToConstant: tabsHeight),
            tabPicker.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
        ])
    }

    @objc private func queryChanged() {
        let text = searchField.text ?? ""
        queryTask?.cancel()
        queryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.queryDelay)
            guard let self, !Task.isCancelled, text != query else { return }
            query = text
            results = [:]
            search()
        }
    }

    private func select(_ tab: Tab) {
        selectedTab = tab
        tableView.reloadData()
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
        if results[tab]?.hasLoaded != true { search() } else { updateEmptyState() }
    }

    // MARK: Table

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = Self.rowHeight
        tableView.keyboardDismissMode = .onDrag
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseIdentifier)
        view.insertSubview(tableView, belowSubview: headerView)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        emptyTitleLabel.font = .preferredFont(forTextStyle: .headline)
        emptyTitleLabel.textAlignment = .center
        emptyTextLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyTextLabel.textColor = .secondaryLabel
        emptyTextLabel.textAlignment = .center
        emptyTextLabel.numberOfLines = 0
        emptyStack.axis = .vertical
        emptyStack.spacing = 6
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyStack.isHidden = true
        view.addSubview(emptyStack)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 40),
            emptyStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStack.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 80),
            emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
        ])
    }

    // MARK: Search

    private func search(more: Bool = false) {
        let tab = selectedTab
        var state = results[tab] ?? Results()
        guard !state.isLoading, !(more && state.nextOffset == nil) else { return }
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            results[tab] = Results(nextOffset: nil, hasLoaded: true)
            tableView.reloadData()
            updateEmptyState()
            return
        }
        if !more { generation += 1 }
        let requestGeneration = generation
        state.isLoading = true
        results[tab] = state
        updateEmptyState()
        let client = client
        let chatID = chat?.id
        let offset = state.nextOffset ?? ""
        let fromMessageID = state.nextFromMessageID
        searchTask = Task { [weak self] in
            let page = await Self.page(
                tab: tab, query: query, chatID: chatID, offset: offset, fromMessageID: fromMessageID, client: client,
            )
            guard let self, requestGeneration == generation, !Task.isCancelled else { return }
            await append(page, to: tab)
        }
    }

    /// A found message shows as its chat's row with that message, as Telegram's ChatListItem does.
    private func append(_ page: Page, to tab: Tab) async {
        for chatID in Set(page.messages.map(\.chatId)) where chatsByID[chatID] == nil {
            if let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client) {
                chatsByID[chatID] = chat
            }
        }
        var state = results[tab] ?? Results()
        for message in page.messages {
            let key = "\(message.chatId):\(message.id)"
            guard let chat = chatsByID[message.chatId], state.keys.insert(key).inserted else { continue }
            state.rows.append(CustomChat(
                chat: chat.chat,
                position: ChatPosition(isPinned: false, list: .chatListMain, order: 0, source: nil),
                unreadCount: 0,
                type: chat.type,
                lastMessage: message,
            ))
        }
        state.nextOffset = page.messages.isEmpty ? nil : page.nextOffset
        state.nextFromMessageID = page.nextFromMessageID
        state.isLoading = false
        state.hasLoaded = true
        results[tab] = state
        guard tab == selectedTab else { return }
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        let state = results[selectedTab]
        if state?.isLoading == true, state?.rows.isEmpty != false {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        let isEmpty = state?.hasLoaded == true && state?.rows.isEmpty == true && state?.isLoading != true
        emptyStack.isHidden = !isEmpty
        emptyTitleLabel.text = L10n.telegram("HashtagSearch.NoResults")
        emptyTextLabel.text = L10n.telegram(
            query.hasPrefix("$")
                ? "HashtagSearch.NoResultsQueryCashtagDescription"
                : "HashtagSearch.NoResultsQueryDescription",
            query,
        )
    }
}

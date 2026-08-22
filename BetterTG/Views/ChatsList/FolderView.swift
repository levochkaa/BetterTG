// FolderView.swift

import Combine
import TDLibKit
import UIKit

final class FolderViewController: UITableViewController, UITableViewDataSourcePrefetching, UISearchBarDelegate {
    // MARK: Lifecycle

    init(folder: CustomFolder, rootVM: RootVM, showsStandaloneSearch: Bool) {
        self.folder = folder
        self.rootVM = rootVM
        self.showsStandaloneSearch = showsStandaloneSearch
        super.init(style: .plain)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        prefetchTasks.values.forEach { $0.cancel() }
    }

    // MARK: Internal

    let folder: CustomFolder

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        tableView.backgroundColor = .black
        tableView.separatorStyle = .none
        tableView.rowHeight = 84
        tableView.keyboardDismissMode = .interactive
        tableView.contentInset.bottom = showsStandaloneSearch ? 0 : 48
        tableView.verticalScrollIndicatorInsets.bottom = showsStandaloneSearch ? 0 : 48
        tableView.prefetchDataSource = self
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseIdentifier)
        configureDataSource()
        configureSearch()
        if showsStandaloneSearch {
            title = folder.name
        }
        updateSnapshot(animated: false)
        startStateUpdates()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        warmVisibleChats()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard searchBar.frame.width != tableView.bounds.width else { return }
        searchBar.frame.size.width = tableView.bounds.width
        tableView.tableHeaderView = searchBar
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let chatID = dataSource.itemIdentifier(for: indexPath), let chat = chat(for: chatID) else { return }
        NavigationStorage.shared.push(.customChat(chat))
    }

    override func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let chatID = dataSource.itemIdentifier(for: indexPath), let chat = chat(for: chatID) else { return nil }
        return UIContextMenuConfiguration(identifier: NSNumber(value: chatID), previewProvider: nil) { [weak self] _ in
            self?.menu(for: chat)
        }
    }

    func tableView(_: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let id = dataSource.itemIdentifier(for: indexPath), prefetchTasks[id] == nil else { continue }
            prefetchTasks[id] = Task { [weak self] in
                _ = try? await td.getChatHistory(
                    chatId: id,
                    fromMessageId: 0,
                    limit: 30,
                    offset: 0,
                    onlyLocal: false,
                )
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

    func searchBar(_: UISearchBar, textDidChange searchText: String) {
        if !showsStandaloneSearch {
            rootVM.query = searchText
        }
        updateQuery(searchText)
    }

    func updateQuery(_ query: String) {
        guard self.query != query else { return }
        self.query = query
        if searchBar.text != query {
            searchBar.text = query
        }
        updateSnapshot(animated: true)
    }

    func scrollToTop() {
        guard !filteredChats.isEmpty else { return }
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: true)
    }

    // MARK: Private

    private enum Section {
        case main
    }

    private let rootVM: RootVM
    private let showsStandaloneSearch: Bool
    private let searchBar = UISearchBar(frame: CGRect(x: 0, y: 0, width: 0, height: 52))
    private var query = ""
    private var cancellables = Set<AnyCancellable>()
    private var chatCancellables = Set<AnyCancellable>()
    private var prefetchTasks = [Int64: Task<Void, Never>]()
    private var dataSource: UITableViewDiffableDataSource<Section, Int64>!

    private var filteredChats: [CustomChat] {
        folder.chats
            .sorted { $0.position.order > $1.position.order }
            .filter {
                query.isEmpty
                    || $0.chat.title.localizedCaseInsensitiveContains(query)
                    || $0.user?.firstName.localizedCaseInsensitiveContains(query) == true
                    || $0.user?.lastName.localizedCaseInsensitiveContains(query) == true
            }
    }

    private func configureSearch() {
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = showsStandaloneSearch ? "Search \(folder.name.lowercased())…" : "Search chats…"
        searchBar.autocapitalizationType = .none
        let initialQuery = showsStandaloneSearch ? "" : rootVM.query
        searchBar.text = initialQuery
        query = initialQuery
        tableView.tableHeaderView = searchBar
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<
            Section,
            Int64,
        >(tableView: tableView) { [weak self] tableView, indexPath, id in
            guard let self,
                  let cell = tableView.dequeueReusableCell(
                      withIdentifier: ChatListCell.reuseIdentifier,
                      for: indexPath,
                  ) as? ChatListCell,
                  let chat = chat(for: id)
            else { return UITableViewCell() }
            cell.configure(chat: chat, folder: folder)
            return cell
        }
    }

    private func startStateUpdates() {
        rootVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.updateSnapshot(animated: true) }
            }
            .store(in: &cancellables)
        folder.$chats
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateSnapshot(animated: true) }
            .store(in: &cancellables)
        subscribeToChats()
    }

    private func subscribeToChats() {
        chatCancellables.removeAll()
        for chat in folder.chats {
            chat.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    DispatchQueue.main.async { self?.updateSnapshot(animated: true, reloadVisible: true) }
                }
                .store(in: &chatCancellables)
        }
    }

    private func updateSnapshot(animated: Bool, reloadVisible: Bool = false) {
        guard isViewLoaded else { return }
        subscribeToChats()
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.main])
        snapshot.appendItems(filteredChats.map(\.id))
        if reloadVisible {
            let current = Set(dataSource.snapshot().itemIdentifiers)
            let visible = snapshot.itemIdentifiers.filter { current.contains($0) }
            snapshot.reloadItems(visible)
        }
        dataSource.apply(snapshot, animatingDifferences: animated)
        tableView.backgroundView = filteredChats.isEmpty ? emptyLabel() : nil
    }

    private func emptyLabel() -> UIView {
        let label = UILabel()
        label.text = "Empty folder :("
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        return label
    }

    private func chat(for id: Int64) -> CustomChat? {
        folder.chats.first(where: { $0.id == id })
    }

    private func warmVisibleChats() {
        tableView(tableView, prefetchRowsAt: tableView.indexPathsForVisibleRows ?? [])
    }

    private func menu(for chat: CustomChat) -> UIMenu {
        let pinned = chat.position.isPinned
        let pin = UIAction(
            title: pinned ? "Unpin" : "Pin",
            image: UIImage(systemName: pinned ? "pin.slash.fill" : "pin.fill"),
        ) { _ in
            Task {
                try? await td.toggleChatIsPinned(
                    chatId: chat.id,
                    chatList: self.folder.chatList,
                    isPinned: !pinned,
                )
            }
        }

        var actions: [UIMenuElement] = [pin]
        let deleteOnlyForSelf = UIAction(
            title: "Delete only for me",
            image: UIImage(systemName: "trash"),
            attributes: .destructive,
        ) { [weak self] _ in self?.confirmDelete(chat: chat, forAll: false) }
        let deleteForAll = UIAction(
            title: "Delete for everyone",
            image: UIImage(systemName: "trash.fill"),
            attributes: .destructive,
        ) { [weak self] _ in self?.confirmDelete(chat: chat, forAll: true) }

        if chat.chat.canBeDeletedOnlyForSelf, chat.chat.canBeDeletedForAllUsers {
            actions.append(UIMenu(title: "Delete", image: UIImage(systemName: "trash"), children: [
                deleteOnlyForSelf,
                deleteForAll,
            ]))
        } else if chat.chat.canBeDeletedForAllUsers {
            actions.append(deleteForAll)
        } else if chat.chat.canBeDeletedOnlyForSelf {
            actions.append(deleteOnlyForSelf)
        }
        return UIMenu(children: actions)
    }

    private func confirmDelete(chat: CustomChat, forAll: Bool) {
        let alert = UIAlertController(
            title: "Delete chat?",
            message: "Are you sure you want to delete chat with \(chat.chat.title)?",
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            Task {
                try? await td.deleteChatHistory(
                    chatId: chat.id,
                    removeFromChatList: true,
                    revoke: forAll,
                )
            }
        })
        present(alert, animated: true)
    }
}

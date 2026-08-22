// FolderView.swift

import Combine
import TDLibKit
import UIKit

final class ArchiveViewController: UIViewController {
    init(folder: CustomFolder, rootVM: RootVM) {
        folderController = FolderViewController(folder: folder, rootVM: rootVM, showsStandaloneSearch: true)
        navigationBarView = TelegramListNavigationBar(
            title: folder.name,
            placeholder: "Search \(folder.name.lowercased())…",
            leftImage: UIImage(systemName: "chevron.left"),
            rightImage: nil,
            leftAction: { NavigationStorage.shared.pop() },
            rightAction: nil,
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        addChild(folderController)
        folderController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(folderController.view)
        folderController.didMove(toParent: self)

        navigationBarView.translatesAutoresizingMaskIntoConstraints = false
        navigationBarView.onQueryChange = { [weak self] query in self?.folderController.updateQuery(query) }
        navigationBarView.onSearchActiveChange = { [weak self] active in
            guard active else { return }
            self?.folderController.revealSearch(animated: true)
        }
        navigationBarView.onVisibleHeightChange = { [weak self] contentHeight in
            guard let self else { return }
            navigationBarHeightConstraint.constant = view.safeAreaInsets.top + contentHeight
        }
        folderController.isSearchActive = { [weak self] in self?.navigationBarView.isSearchActive == true }
        folderController.onSearchScrollOffsetChange = { [weak self] offset in
            self?.navigationBarView.applyScroll(offset: offset)
        }
        view.addSubview(navigationBarView)
        navigationBarHeightConstraint = navigationBarView.heightAnchor.constraint(
            equalToConstant: view.safeAreaInsets.top + TelegramListNavigationBar.expandedContentHeight,
        )

        NSLayoutConstraint.activate([
            folderController.view.topAnchor.constraint(equalTo: view.topAnchor),
            folderController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            folderController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            folderController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            navigationBarView.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBarHeightConstraint,
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        navigationBarHeightConstraint?.constant = view.safeAreaInsets.top
            + TelegramListNavigationBar.expandedContentHeight
            - folderController.searchScrollOffset
    }

    private let folderController: FolderViewController
    private let navigationBarView: TelegramListNavigationBar
    private var navigationBarHeightConstraint: NSLayoutConstraint!
}

final class FolderViewController: UITableViewController, UITableViewDataSourcePrefetching {
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
    var onSearchScrollOffsetChange: ((CGFloat) -> Void)?
    var isSearchActive: (() -> Bool)?

    var searchScrollOffset: CGFloat {
        guard isViewLoaded else { return 0 }
        return min(
            ChatListNavigationSearchView.scrollHeight,
            max(0, tableView.contentOffset.y + tableView.adjustedContentInset.top),
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        tableView.backgroundColor = .black
        tableView.separatorStyle = .none
        tableView.rowHeight = 84
        tableView.keyboardDismissMode = .interactive
        tableView.contentInset.top = TelegramListNavigationBar.expandedContentHeight
        tableView.contentInset.bottom = showsStandaloneSearch ? 0 : 58
        tableView.verticalScrollIndicatorInsets.top = TelegramListNavigationBar.expandedContentHeight
        tableView.verticalScrollIndicatorInsets.bottom = showsStandaloneSearch ? 0 : 58
        tableView.prefetchDataSource = self
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseIdentifier)
        tableView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(chatLongPressed(_:))))
        configureDataSource()
        updateSnapshot(animated: false)
        startStateUpdates()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        warmVisibleChats()
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
        guard !didSetInitialSearchOffset else { return }
        didSetInitialSearchOffset = true
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
        onSearchScrollOffsetChange?(0)
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        onSearchScrollOffsetChange?(searchScrollOffset)
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

    func updateQuery(_ query: String) {
        guard self.query != query else { return }
        self.query = query
        updateSnapshot(animated: false)
    }

    func scrollToTop() {
        guard !filteredChats.isEmpty else { return }
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: true)
    }

    func revealSearch(animated: Bool) {
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: animated)
    }

    // MARK: Private

    private enum Section {
        case main
    }

    private let rootVM: RootVM
    private let showsStandaloneSearch: Bool
    private var query = ""
    private var didSetInitialSearchOffset = false
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

    private func menu(for chat: CustomChat) -> [TelegramContextMenuAction] {
        let pinned = chat.position.isPinned
        let pin = TelegramContextMenuAction(
            title: pinned ? "Unpin" : "Pin",
            image: UIImage(systemName: pinned ? "pin.slash.fill" : "pin.fill"),
        ) {
            Task {
                try? await td.toggleChatIsPinned(
                    chatId: chat.id,
                    chatList: self.folder.chatList,
                    isPinned: !pinned,
                )
            }
        }

        var actions = [pin]
        let deleteOnlyForSelf = TelegramContextMenuAction(
            title: "Delete only for me",
            image: UIImage(systemName: "trash"),
            isDestructive: true,
            startsNewSection: true,
        ) { [weak self] in self?.confirmDelete(chat: chat, forAll: false) }
        let deleteForAll = TelegramContextMenuAction(
            title: "Delete for everyone",
            image: UIImage(systemName: "trash.fill"),
            isDestructive: true,
            startsNewSection: true,
        ) { [weak self] in self?.confirmDelete(chat: chat, forAll: true) }

        if chat.chat.canBeDeletedOnlyForSelf, chat.chat.canBeDeletedForAllUsers {
            actions.append(deleteOnlyForSelf)
            actions.append(TelegramContextMenuAction(
                title: deleteForAll.title,
                image: deleteForAll.image,
                isDestructive: true,
            ) { [weak self] in self?.confirmDelete(chat: chat, forAll: true) })
        } else if chat.chat.canBeDeletedForAllUsers {
            actions.append(deleteForAll)
        } else if chat.chat.canBeDeletedOnlyForSelf {
            actions.append(deleteOnlyForSelf)
        }
        return actions
    }

    @objc private func chatLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              let chatID = dataSource.itemIdentifier(for: indexPath),
              let chat = chat(for: chatID),
              let cell = tableView.cellForRow(at: indexPath) as? ChatListCell
        else { return }
        presentTelegramContextMenu(sourceView: cell.contextPreviewView, actions: menu(for: chat), tracking: gesture)
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

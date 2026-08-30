// FolderView.swift

import Combine
import TDLibKitDynamic
import UIKit

// MARK: - ArchiveViewController

final class ArchiveViewController: UIViewController {
    // MARK: Lifecycle

    init(folder: CustomFolder, rootVM: RootVM) {
        self.folderController = FolderViewController(folder: folder, rootVM: rootVM, showsStandaloneSearch: true)
        self.navigationBarView = TelegramListNavigationBar(
            title: folder.name,
            placeholder: "Search \(folder.name.lowercased())…",
            leftImage: UIImage(systemName: "chevron.left"),
            rightImage: nil,
            leftAction: { NavigationStorage.shared.pop() },
            rightAction: nil,
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

        addChild(folderController)
        folderController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(folderController.view)
        folderController.didMove(toParent: self)

        navigationBarView.translatesAutoresizingMaskIntoConstraints = false
        navigationBarView.onQueryChange = { [weak self] query in self?.folderController.updateQuery(query) }
        navigationBarView.onSearchActiveChange = { [weak self] active in
            self?.folderController.setSearchActive(active, animated: true)
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

    // MARK: Private

    private let folderController: FolderViewController
    private let navigationBarView: TelegramListNavigationBar
    private var navigationBarHeightConstraint: NSLayoutConstraint!
}

// MARK: - FolderViewController

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
        view.backgroundColor = .systemBackground
        tableView.backgroundColor = .systemBackground
        tableView.separatorStyle = .none
        tableView.rowHeight = 84
        tableView.keyboardDismissMode = .interactive
        let initialTopInset = searchActive
            ? TelegramListNavigationBar.titleHeight
            : TelegramListNavigationBar.expandedContentHeight
        tableView.contentInset.top = initialTopInset
        tableView.contentInset.bottom = showsStandaloneSearch ? 0 : 58
        tableView.verticalScrollIndicatorInsets.top = initialTopInset
        tableView.verticalScrollIndicatorInsets.bottom = showsStandaloneSearch ? 0 : 58
        tableView.prefetchDataSource = self
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseIdentifier)
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(chatLongPressed(_:)))
        longPressGesture.minimumPressDuration = 0.3
        tableView.addGestureRecognizer(longPressGesture)
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

    func setSearchActive(_ active: Bool, animated: Bool) {
        searchActive = active
        guard isViewLoaded else { return }
        let targetTopInset = active
            ? TelegramListNavigationBar.titleHeight
            : TelegramListNavigationBar.expandedContentHeight
        let changes = {
            self.tableView.contentInset.top = targetTopInset
            self.tableView.verticalScrollIndicatorInsets.top = targetTopInset
            self.tableView.layoutIfNeeded()
            self.tableView.contentOffset = CGPoint(x: 0, y: -self.tableView.adjustedContentInset.top)
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

    // MARK: Private

    private enum Section {
        case main
    }

    private let showsStandaloneSearch: Bool
    private let rootVM: RootVM
    private var query = ""
    private var searchActive = false
    private var didSetInitialSearchOffset = false
    private var cancellables = Set<AnyCancellable>()
    private var chatCancellables = Set<AnyCancellable>()
    private var prefetchTasks = [Int64: Task<Void, Never>]()
    private var pendingChangedChatIDs = Set<Int64>()
    private var chatUpdateScheduled = false
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
        folder.$chats
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.subscribeToChats()
                    self?.updateSnapshot(animated: true)
                }
            }
            .store(in: &cancellables)
        subscribeToChats()
    }

    private func subscribeToChats() {
        chatCancellables.removeAll()
        for chat in folder.chats {
            chat.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self, chatID = chat.id] in self?.scheduleChatUpdate(id: chatID) }
                .store(in: &chatCancellables)
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
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.main])
        snapshot.appendItems(filteredChats.map(\.id))
        if !changedIDs.isEmpty {
            let current = Set(dataSource.snapshot().itemIdentifiers)
            let reconfigured = snapshot.itemIdentifiers.filter { changedIDs.contains($0) && current.contains($0) }
            if !reconfigured.isEmpty {
                snapshot.reconfigureItems(reconfigured)
            }
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
        let unread = chat.unreadCount > 0 || chat.chat.isMarkedAsUnread
        let archived = chat.chat.positions.contains { $0.list == .chatListArchive && $0.order != 0 }
        let muted = chat.chat.notificationSettings.muteFor > 0
        let isCustomFolder =
            if case .folder = folder.type {
                true
            } else {
                false
            }

        var actions = [
            TelegramContextMenuAction(
                title: isCustomFolder ? "Remove from Folder" : "Add to Folder",
                image: UIImage(systemName: isCustomFolder ? "folder.badge.minus" : "folder.badge.plus"),
            ) { [weak self] in
                self?.performFolderAction(for: chat)
            },
            TelegramContextMenuAction(
                title: unread ? "Mark as Read" : "Mark as Unread",
                image: UIImage(systemName: unread ? "envelope.open" : "envelope.badge"),
            ) {
                Task {
                    if unread {
                        if let messageID = chat.lastMessage?.id {
                            _ = try? await td.viewMessages(
                                chatId: chat.id,
                                forceRead: true,
                                messageIds: [messageID],
                                source: nil,
                            )
                        }
                        _ = try? await td.toggleChatIsMarkedAsUnread(
                            chatId: chat.id,
                            isMarkedAsUnread: false,
                        )
                    } else {
                        _ = try? await td.toggleChatIsMarkedAsUnread(
                            chatId: chat.id,
                            isMarkedAsUnread: true,
                        )
                    }
                }
            },
            TelegramContextMenuAction(
                title: archived ? "Unarchive" : "Archive",
                image: UIImage(systemName: archived ? "tray.and.arrow.up" : "archivebox"),
            ) {
                Task {
                    try? await td.addChatToList(
                        chatId: chat.id,
                        chatList: archived ? .chatListMain : .chatListArchive,
                    )
                }
            },
            TelegramContextMenuAction(
                title: pinned ? "Unpin" : "Pin",
                image: UIImage(systemName: pinned ? "pin.slash.fill" : "pin.fill"),
            ) { [weak self] in
                guard let self else { return }
                Task {
                    try? await td.toggleChatIsPinned(
                        chatId: chat.id,
                        chatList: self.folder.chatList,
                        isPinned: !pinned,
                    )
                }
            },
            TelegramContextMenuAction(
                title: muted ? "Unmute" : "Mute",
                image: UIImage(systemName: muted ? "speaker.wave.2.fill" : "speaker.slash.fill"),
            ) {
                Task {
                    try? await td.setChatNotificationSettings(
                        chatId: chat.id,
                        notificationSettings: chat.chat.notificationSettings.withMuteFor(
                            muted ? 0 : Int(Int32.max),
                        ),
                    )
                }
            },
        ]

        if chat.chat.canBeDeletedOnlyForSelf || chat.chat.canBeDeletedForAllUsers {
            actions.append(TelegramContextMenuAction(
                title: "Delete",
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

    @objc private func chatLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              let chatID = dataSource.itemIdentifier(for: indexPath),
              let chat = chat(for: chatID),
              let cell = tableView.cellForRow(at: indexPath) as? ChatListCell
        else { return }
        let previewController = ChatViewController(customChat: chat, presentationMode: .contextPreview)
        presentTelegramContextMenu(
            sourceView: cell.contextPreviewView,
            actions: menu(for: chat),
            tracking: gesture,
            presentationStyle: .chatPreview,
            previewController: previewController,
        )
    }

    private func performFolderAction(for chat: CustomChat) {
        if case .folder(let info, let definition) = folder.type {
            let updated = definition.removing(chatID: chat.id)
            Task { try? await td.editChatFolder(chatFolderId: info.id, folder: updated) }
            return
        }

        let targets = rootVM.folders.compactMap { folder -> (Int, String, ChatFolder)? in
            guard case .folder(let info, let definition) = folder.type,
                  !folder.chats.contains(where: { $0.id == chat.id })
            else { return nil }
            return (info.id, folder.name, definition)
        }
        guard !targets.isEmpty else { return }
        let picker = UIAlertController(title: "Add to Folder", message: nil, preferredStyle: .actionSheet)
        for target in targets {
            picker.addAction(UIAlertAction(title: target.1, style: .default) { _ in
                Task {
                    try? await td.editChatFolder(
                        chatFolderId: target.0,
                        folder: target.2.adding(chatID: chat.id),
                    )
                }
            })
        }
        picker.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        picker.popoverPresentationController?.sourceView = view
        picker.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.maxY - view.safeAreaInsets.bottom,
            width: 1,
            height: 1,
        )
        present(picker, animated: true)
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

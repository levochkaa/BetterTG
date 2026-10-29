// MainView.swift

import Combine
import TDLibKit
import UIKit

// MARK: - MainViewController

final class MainViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
    ClientRestorableNavigationEntry
{
    struct ClientRestorationState {
        let searchQuery: String
        let searchWasFocused: Bool
        let folderViewports: [Int: ChatListViewportSnapshot]
    }

    #if DEBUG
        private static var didOpenForumListForSmoke = false
        private static var didCheckAllMessagesForumForSmoke = false
        private var allMessagesForumSmokeAttemptID: UUID?
    #endif

    // MARK: Private

    private let rootVM: RootVM
    private let actionAuthority = ChatListActionAuthority()
    private let pageController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
    )
    private let folderPicker = FolderPickerView()
    /// Telegram's media header panel (ChatListControllerNode, MediaPlaybackHeaderPanelComponent) under the navigation
    /// bar while a voice note keeps playing after its chat closed.
    private let headerPanels = TelegramHeaderPanelsView()
    private let navigationBackground = TelegramBarBackgroundView(edge: .top)
    private var headerPanelsHeightConstraint: NSLayoutConstraint?
    private var voicePlaybackOpenTask: Task<Void, Never>?
    /// This client's shared live locations, newest first.
    private var liveLocationBroadcasts = [LiveLocationBroadcast]()
    private var liveLocationChatTitles = [Int64: String]()
    private var liveLocationTitleTask: Task<Void, Never>?
    private var liveLocationOpenTask: Task<Void, Never>?
    private lazy var customNavigationBar = TelegramListNavigationBar(
        title: "BetterTG",
        placeholder: L10n.telegram("DialogList.SearchLabel"),
        leftImage: UIImage(systemName: "archivebox"),
        rightImage: UIImage(systemName: "gearshape"),
        leftAction: { [weak self] in self?.openArchive() },
        rightAction: { [weak self] in self?.openSettings() },
        // Telegram's compose button (ChatListController's pencil); Settings keeps the right edge.
        secondaryRightImage: UIImage(systemName: "square.and.pencil"),
        secondaryRightAction: { [weak self] in self?.openCompose() },
        secondaryRightAccessibilityLabel: L10n.telegram("Compose.NewMessage"),
        leftAccessibilityLabel: L10n.telegram("ChatList.ArchivedChatsTitle"),
        rightAccessibilityLabel: L10n.telegram("Settings.Title"),
    )
    private var navigationBarHeightConstraint: NSLayoutConstraint!
    private var currentNavigationContentHeight = TelegramListNavigationBar.expandedContentHeight
    private var folderControllers = [FolderViewController]()
    private var cancellables = Set<AnyCancellable>()
    private var searchQuery = ""
    private lazy var searchResultsController = ChatListSearchResultsViewController(
        rootVM: rootVM,
        chatList: .chatListMain,
        actionAuthority: actionAuthority,
    )
    /// A non-empty query shows TDLib results over every folder page, as Telegram's search container does.
    private var isShowingSearchResults = false
    private var pageScrollObservation: NSKeyValueObservation?
    private let pagingEdgeGate = FolderPagingEdgeGate()
    private var interactiveFolderTransition: (
        fromID: Int,
        toID: Int,
        fromSearchOffset: CGFloat,
        toSearchOffset: CGFloat,
    )?
    private var folderUnreadStates = [ChatList: FolderUnreadState]()
    private let isClientRestoration: Bool
    private var restoresSearchFocus = false
    private var isRestoringSearchFocus = false
    private var restorationViewports = [Int: ChatListViewportSnapshot]()
    /// While a list selects chats, Telegram's toolbar takes the folder tabs' place and the pages stay put.
    private var isSelectingChats = false

    var navigationClientSource: TdUpdateSource? {
        actionAuthority.scope(owner: self).source
    }

    private var voicePlaybackHeader: VoicePlaybackHeaderView { headerPanels.voiceHeader }
    /// Telegram's live location panel (LiveLocationHeaderPanelComponent in the chat list) under the media header
    /// while the account shares a live location.
    private var liveLocationPanel: LiveLocationPanelView { headerPanels.liveLocationPanel }

    private var currentFolderController: FolderViewController? {
        pageController.viewControllers?.first as? FolderViewController
    }

    /// The chats seeing the live location, newest message first.
    private var liveLocationChatIDs: [Int64] {
        var seen = Set<Int64>()
        return liveLocationBroadcasts.map(\.chatID).filter { seen.insert($0).inserted }
    }

    init(rootVM: RootVM, restoration: ClientRestorationState? = nil) {
        self.rootVM = rootVM
        self.isClientRestoration = restoration != nil
        self.searchQuery = restoration?.searchQuery ?? ""
        self.restoresSearchFocus = restoration?.searchWasFocused ?? false
        self.restorationViewports = restoration?.folderViewports ?? [:]
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configurePageController()
        configureNavigationBar()
        configureFolderPicker()
        configureSearchResults()
        configureHeaderPanels()
        configureVoicePlaybackHeader()
        configureLiveLocationPanel()

        rootVM.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    reloadFromState()
                    NavigationStorage.shared.retryClientRestoration()
                }
            }
            .store(in: &cancellables)
        FolderUnreadStore.shared
            .objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.reloadFolderUnreadStates() }
            }
            .store(in: &cancellables)
        FolderTabAppearance.shared
            .changes
            .sink { [weak self] in
                guard let self, actionAuthority.isCurrent else { return }
                folderPicker.configure(
                    folders: rootVM.folders,
                    selectedID: rootVM.currentFolder,
                    unreadStates: folderUnreadStates,
                )
            }
            .store(in: &cancellables)
        folderUnreadStates = FolderUnreadStore.shared.states(for: actionAuthority.client.id)
        reloadFromState()
        updateHeaderPanels(animated: false)
        if !isClientRestoration { configureAutomatedSmokeRoute() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if actionAuthority.isCurrent, restoresSearchFocus {
            restoresSearchFocus = false
            isRestoringSearchFocus = true
            customNavigationBar.focusSearch()
            isRestoringSearchFocus = false
        }
        // A modal or interactive navigation transition can defer epoch recovery.
        DispatchQueue.main.async { NavigationStorage.shared.retryClientRestoration() }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateNavigationBarHeight(contentHeight: currentNavigationContentHeight)
    }

    /// Telegram's compactDisplayTitle of a private chat's user, for the live location description; nil elsewhere.
    private static func liveLocationPeerName(chatID: Int64, client: TDLibClient) async -> String? {
        guard let chat = try? await client.getChat(chatId: chatID), case .chatTypePrivate(let info) = chat.type,
              let user = try? await client.getUser(userId: info.userId) else { return nil }
        let firstName = user.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !firstName.isEmpty { return firstName }
        let lastName = user.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastName.isEmpty ? chat.title : lastName
    }

    func prepareReplacementForReadyClient(_ source: TdUpdateSource) -> PreparedClientNavigationReplacement? {
        guard canRestoreClient(source) else { return nil }
        let state = ClientRestorationState(
            searchQuery: searchQuery,
            searchWasFocused: isViewLoaded ? customNavigationBar.isSearchActive : restoresSearchFocus,
            folderViewports: restorationViewports.merging(
                Dictionary(uniqueKeysWithValues: folderControllers.map {
                    ($0.folder.id, $0.clientRestorationViewport())
                }),
                uniquingKeysWith: { _, current in current },
            ),
        )
        let rootVM = rootVM
        return PreparedClientNavigationReplacement(
            preflight: { [weak self] in self?.canRestoreClient(source) == true },
            commit: { MainViewController(rootVM: rootVM, restoration: state) },
        )
    }

    func pageViewController(
        _: UIPageViewController,
        viewControllerBefore viewController: UIViewController,
    ) -> UIViewController? {
        guard let index = folderControllers.firstIndex(where: { $0 === viewController }), index > 0 else { return nil }
        return folderControllers[index - 1]
    }

    func pageViewController(
        _: UIPageViewController,
        viewControllerAfter viewController: UIViewController,
    ) -> UIViewController? {
        guard let index = folderControllers.firstIndex(where: { $0 === viewController }),
              index + 1 < folderControllers.count else { return nil }
        return folderControllers[index + 1]
    }

    func pageViewController(
        _: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController],
    ) {
        guard let currentFolderController,
              let targetController = pendingViewControllers.first as? FolderViewController
        else { return }
        interactiveFolderTransition = (
            fromID: currentFolderController.folder.id,
            toID: targetController.folder.id,
            fromSearchOffset: currentFolderController.searchScrollOffset,
            toSearchOffset: targetController.searchScrollOffset,
        )
    }

    func pageViewController(
        _: UIPageViewController,
        didFinishAnimating _: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool,
    ) {
        defer {
            interactiveFolderTransition = nil
            DispatchQueue.main.async { NavigationStorage.shared.retryClientRestoration() }
        }
        guard completed, let folder = (pageController.viewControllers?.first as? FolderViewController)?.folder else {
            let previousID = (previousViewControllers.first as? FolderViewController)?.folder.id
            folderPicker.select(id: previousID, animated: true)
            if let interactiveFolderTransition {
                applySearchScrollOffset(
                    offset: interactiveFolderTransition.fromSearchOffset,
                    animated: true,
                )
            }
            return
        }
        rootVM.currentFolder = folder.id
        folderPicker.select(id: folder.id, animated: true)
        if let currentFolderController {
            applySearchScrollOffset(offset: currentFolderController.searchScrollOffset, animated: true)
        }
    }

    private func canRestoreClient(_ source: TdUpdateSource) -> Bool {
        source == TDLib.shared.activeUpdateSource
            && source.accountID == navigationClientSource?.accountID
            && source.accountID == rootVM.activeAccountID
            && interactiveFolderTransition == nil
    }

    private func configureAutomatedSmokeRoute() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-smoke-forum-all-messages") {
            configureAllMessagesForumSmoke()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-smoke-forum-list") {
            guard !Self.didOpenForumListForSmoke else { return }
            let source = TDLib.shared.activeUpdateSource
            rootVM.$folders
                .compactMap { folders in
                    folders.lazy.flatMap(\.chats).first {
                        $0.supergroup?.isForum == true && $0.chat.viewAsTopics
                    }
                }
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] chat in
                    guard let self, !Self.didOpenForumListForSmoke, source != nil,
                          TDLib.shared.activeUpdateSource == source,
                          navigationController?.topViewController === self else { return }
                    Self.didOpenForumListForSmoke = true
                    NavigationStorage.shared.push(.customChat(chat), animated: false)
                    log("Forum list smoke: opened existing topics route; no topic selected")
                }
                .store(in: &cancellables)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-smoke-forum-topic-write") {
            let client = TDLib.shared.activeClient
            let accountID = TDLib.shared.activeAccountID
            rootVM.$folders
                .compactMap { folders -> [CustomChat]? in
                    let chats = folders.lazy.flatMap(\.chats)
                    var seen = Set<Int64>()
                    let forums = Array(chats.filter { chat in
                        seen.insert(chat.id).inserted && chat.supergroup?.isForum == true
                    })
                    return forums.isEmpty ? nil : forums
                }
                .first()
                .receive(on: DispatchQueue.main)
                .sink { forums in
                    Task { @MainActor in
                        for chat in forums {
                            guard TDLib.shared.activeAccountID == accountID,
                                  TDLib.shared.activeClient.id == client.id
                            else { return }
                            guard let page = try? await client.getForumTopics(
                                chatId: chat.id,
                                limit: 100,
                                offsetDate: 0,
                                offsetForumTopicId: 0,
                                offsetMessageId: 0,
                                query: "",
                            ) else { continue }
                            let canManageTopics = chat.adminRights?.canManageTopics == true
                                || {
                                    if case .chatMemberStatusCreator = chat.supergroup?.status {
                                        true
                                    } else {
                                        false
                                    }
                                }()
                            guard chat.chat.permissions.canSendBasicMessages,
                                  let topic = page.topics.first(where: { topic in
                                      let restricted = topic.info.isClosed || topic.info.isHidden
                                      return !restricted || topic.info.isOutgoing || canManageTopics
                                  })
                            else { continue }
                            guard TDLib.shared.activeAccountID == accountID,
                                  TDLib.shared.activeClient.id == client.id
                            else { return }
                            NavigationStorage.shared.push(
                                .customChat(
                                    chat,
                                    location: ChatLocation.current(
                                        chatID: chat.id,
                                        topic: .messageTopicForum(MessageTopicForum(
                                            forumTopicId: topic.info.forumTopicId,
                                        )),
                                        client: client,
                                    ),
                                    forumTopic: topic,
                                ),
                                animated: false,
                            )
                            self.writeForumTopicWriteProbe(
                                "Forum topic write route: writable=true, topic=\(topic.info.forumTopicId), "
                                    + "draft-scoped=true, uikit=true",
                            )
                            return
                        }
                        self.writeForumTopicWriteProbe("Forum topic write route: unavailable")
                    }
                }
                .store(in: &cancellables)
            return
        }
        guard ProcessInfo.processInfo.arguments.contains("-ui-smoke-chat") else { return }
        rootVM.$folders
            .compactMap { folders in folders.lazy.flatMap(\.chats).first }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { chat in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    NavigationStorage.shared.push(.customChat(chat), animated: false)
                }
            }
            .store(in: &cancellables)
        #endif
    }

    #if DEBUG
        private func configureAllMessagesForumSmoke() {
            guard !Self.didCheckAllMessagesForumForSmoke,
                  let source = TDLib.shared.activeUpdateSource else { return }
            let client = TDLib.shared.activeClient
            let attemptID = UUID()
            allMessagesForumSmokeAttemptID = attemptID
            TDLib.shared
.activeClientChanges
                .sink { [weak self] current in
                    guard current != source, self?.allMessagesForumSmokeAttemptID == attemptID else { return }
                    self?.allMessagesForumSmokeAttemptID = nil
                }
                .store(in: &cancellables)
            // Bound UI authority even when an underlying TDLib read ignores cancellation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, allMessagesForumSmokeAttemptID == attemptID else { return }
                writeAllMessagesForumSmoke("Forum all-messages smoke: 15s attempt expired; late navigation revoked")
            }
            rootVM.$folders
                .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
                .filter { $0.contains { !$0.chats.isEmpty } }
                .first()
                .sink { [weak self] folders in
                    guard self?.permitsAllMessagesForumSmoke(source, attemptID: attemptID) == true else { return }
                    Self.didCheckAllMessagesForumForSmoke = true
                    var seen = Set<Int64>()
                    let forums = folders.flatMap(\.chats).filter {
                        seen.insert($0.id).inserted && $0.supergroup?.isForum == true
                    }
                    let candidates = forums.filter {
                        $0.unreadCount == 0 && Self.isSafeAllMessagesForumSmokeChat($0.chat)
                    }
                    let counts = "loaded-forums=\(forums.count), eligible=\(candidates.count)"
                    Task { @MainActor [weak self] in
                        for candidate in candidates.prefix(8) {
                            guard self?.permitsAllMessagesForumSmoke(source, attemptID: attemptID) == true
                                else { return }
                            guard let fresh = try? await client.getChat(chatId: candidate.id),
                                  fresh.id == candidate.id, Self.isSafeAllMessagesForumSmokeChat(fresh),
                                  case .chatTypeSupergroup(let peer) = fresh.type, !peer.isChannel
                            else { continue }
                            guard self?.permitsAllMessagesForumSmoke(source, attemptID: attemptID) == true
                                else { return }
                            guard let group = try? await client.getSupergroup(supergroupId: peer.supergroupId),
                                  group.id == peer.supergroupId, group.isForum,
                                  !group.isChannel, !group.isDirectMessagesGroup
                            else { continue }
                            guard let self, permitsAllMessagesForumSmoke(source, attemptID: attemptID),
                                  rootVM.folders.contains(where: { $0.chats.contains { $0 === candidate } }),
                                  candidate.chat.type == fresh.type, candidate.unreadCount == 0,
                                  Self.isSafeAllMessagesForumSmokeChat(candidate.chat),
                                  candidate.supergroup?.id == group.id, candidate.supergroup?.isForum == true,
                                  candidate.supergroup?.isChannel == false,
                                  candidate.supergroup?.isDirectMessagesGroup == false
                            else { return }
                            NavigationStorage.shared.push(.customChat(candidate), animated: false)
                            writeAllMessagesForumSmoke(
                                "Forum all-messages smoke: opened existing route; \(counts); no mode toggle or send",
                            )
                            return
                        }
                        guard self?.permitsAllMessagesForumSmoke(source, attemptID: attemptID) == true else { return }
                        self?.writeAllMessagesForumSmoke(
                            "Forum all-messages smoke: unavailable in loaded safe candidates; \(counts); "
                                + "fresh candidates checked<=8; not an account-wide absence proof",
                        )
                    }
                }
                .store(in: &cancellables)
        }

        private func permitsAllMessagesForumSmoke(_ source: TdUpdateSource, attemptID: UUID) -> Bool {
            allMessagesForumSmokeAttemptID == attemptID
                && TDLib.shared.activeUpdateSource == source && actionAuthority.scope(owner: self).isCurrent
                && navigationController?.topViewController === self
                && navigationController?.presentedViewController == nil && presentedViewController == nil
        }

        private static func isSafeAllMessagesForumSmokeChat(_ chat: Chat) -> Bool {
            !chat.viewAsTopics && !chat.isMarkedAsUnread && chat.unreadCount == 0
                && chat.unreadMentionCount == 0 && chat.unreadReactionCount == 0 && chat.unreadPollVoteCount == 0
        }

        private func writeAllMessagesForumSmoke(_ result: String) {
            allMessagesForumSmokeAttemptID = nil
            log(result)
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                else { return }
            try? result.write(
                to: documents.appendingPathComponent("forum-all-messages-route-probe.txt"),
                atomically: true, encoding: .utf8,
            )
        }

        private func writeForumTopicWriteProbe(_ result: String) {
            log(result)
            guard let documents = FileManager.default
.urls(
    for: .documentDirectory,
    in: .userDomainMask,
)
.first else { return }
            try? result.write(
                to: documents.appendingPathComponent("forum-topic-write-route-probe.txt"),
                atomically: true,
                encoding: .utf8,
            )
        }
    #endif

    private func setChatSelectionEditing(title: String?, done: (() -> Void)?) {
        customNavigationBar.setEditing(title: title, done: done)
        isSelectingChats = done != nil
        if let scrollView = pageController.view.subviews.compactMap({ $0 as? UIScrollView }).first {
            scrollView.isScrollEnabled = !isSelectingChats
        }
        folderPicker.isUserInteractionEnabled = !isSelectingChats
        folderPicker.alpha = isSelectingChats ? 0 : 1
    }

    private func configurePageController() {
        pageController.dataSource = self
        pageController.delegate = self
        addChild(pageController)
        pageController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageController.view)
        pageController.didMove(toParent: self)
        if let scrollView = pageController.view.subviews.compactMap({ $0 as? UIScrollView }).first {
            pageScrollObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                self?.updateInteractiveFolderSelection(from: scrollView)
            }
            // A pan from an edge zone belongs to the row's swipe actions, one from the middle to folder paging.
            pagingEdgeGate.onTouchBegan = { [weak self, weak scrollView] atEdge in
                guard let self, let scrollView, !scrollView.isDragging, !scrollView.isDecelerating else { return }
                scrollView.isScrollEnabled = !isSelectingChats && (!atEdge || folderControllers.count <= 1)
            }
            pageController.view.addGestureRecognizer(pagingEdgeGate)
        }
        NSLayoutConstraint.activate([
            pageController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureNavigationBar() {
        customNavigationBar.translatesAutoresizingMaskIntoConstraints = false
        customNavigationBar.restoreSearchQuery(searchQuery)
        customNavigationBar.onQueryChange = { [weak self] query in
            guard let self else { return }
            searchQuery = query
            updateSearchResults(animated: true)
        }
        customNavigationBar.onSearchActiveChange = { [weak self] active in
            guard let self else { return }
            updateHeaderPanels(animated: !isRestoringSearchFocus, searchActive: active)
            for folderController in folderControllers {
                folderController.setSearchActive(
                    active,
                    animated: !isRestoringSearchFocus && folderController === currentFolderController,
                    preservingViewport: isRestoringSearchFocus,
                )
            }
            updateSearchResults(animated: !isRestoringSearchFocus, searchActive: active)
            if active {
                customNavigationBar.applyScroll(offset: 0, animated: true)
            } else if isShowingSearchResults {
                // The query stays on screen above its results; folder pages restored their own offsets.
                customNavigationBar.applyScroll(offset: 0, animated: true)
            }
        }
        customNavigationBar.onVisibleHeightChange = { [weak self] contentHeight in
            self?.updateNavigationBarHeight(contentHeight: contentHeight)
        }
        customNavigationBar.onRightLongPress = { [weak self] source, gesture in
            self?.showAccountSwitcher(from: source, tracking: gesture)
        }
        TDLib.shared
            .chatListNetworkStatus
            .sink { [weak self] status in self?.customNavigationBar.setNetworkStatus(status) }
            .store(in: &cancellables)
        customNavigationBar.onLockTap = { AppPasscode.shared.lockNow() }
        AppPasscode.shared
            .$isSet
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSet in self?.customNavigationBar.setLockVisible(isSet) }
            .store(in: &cancellables)
        customNavigationBar.onProxyTap = { [weak self] in
            self?.navigationController?.pushViewController(ProxySettingsViewController(), animated: true)
        }
        TDLib.shared
            .chatListProxyStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.customNavigationBar.setProxyStatus(status) }
            .store(in: &cancellables)
        ProxyStatusStore.shared.refresh()
        view.addSubview(customNavigationBar)
        navigationBarHeightConstraint = customNavigationBar.heightAnchor.constraint(
            equalToConstant: currentNavigationContentHeight + view.safeAreaInsets.top,
        )
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBarHeightConstraint,
        ])
    }

    private func configureFolderPicker() {
        folderPicker.translatesAutoresizingMaskIntoConstraints = false
        folderPicker.onSelection = { [weak self] id in self?.selectFolder(id: id, animated: true) }
        folderPicker.onReselection = { [weak self] id in
            self?.folderControllers.first(where: { $0.folder.id == id })?.scrollToTop()
        }
        folderPicker.onAction = { [weak self] action, folder in
            self?.performFolderAction(action, for: folder)
        }
        view.addSubview(folderPicker)
        NSLayoutConstraint.activate([
            folderPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            folderPicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            folderPicker.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -FolderPickerView.barHeight,
            ),
            folderPicker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        view.bringSubviewToFront(customNavigationBar)
        view.bringSubviewToFront(folderPicker)
    }

    private func configureSearchResults() {
        searchResultsController.chatMenu = { [weak self] chat in
            self?.currentFolderController?.searchResultMenu(for: chat) ?? []
        }
        addChild(searchResultsController)
        let resultsView = searchResultsController.view!
        resultsView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(resultsView, aboveSubview: pageController.view)
        searchResultsController.didMove(toParent: self)
        // The results fill the screen, under the bar and the keyboard, and inset their lists for both.
        NSLayoutConstraint.activate([
            resultsView.topAnchor.constraint(equalTo: view.topAnchor),
            resultsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        resultsView.alpha = 0
        resultsView.isHidden = true
        updateSearchResults(animated: false)
    }

    /// Telegram shows the search's recent and top people as soon as search is focused, before a query.
    private func updateSearchResults(animated: Bool, searchActive: Bool? = nil) {
        searchResultsController.updateQuery(searchQuery)
        let showsResults = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (searchActive ?? customNavigationBar.isSearchActive)
        guard showsResults != isShowingSearchResults else { return }
        isShowingSearchResults = showsResults
        updateHeaderPanels(animated: animated)
        let resultsView = searchResultsController.view!
        if showsResults {
            searchResultsController.refreshEmptyState()
            resultsView.isHidden = false
            customNavigationBar.applyScroll(offset: 0, animated: animated)
        } else if let currentFolderController {
            applySearchScrollOffset(offset: currentFolderController.searchScrollOffset, animated: animated)
        }
        // Telegram hides the folder tabs while search results are shown.
        folderPicker.isUserInteractionEnabled = !showsResults
        let changes = {
            resultsView.alpha = showsResults ? 1 : 0
            self.folderPicker.alpha = showsResults ? 0 : 1
        }
        guard animated else {
            changes()
            resultsView.isHidden = !showsResults
            return
        }
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes,
        ) { _ in
            // A later query may have shown the results again.
            resultsView.isHidden = !self.isShowingSearchResults
        }
    }

    private func updateNavigationBarHeight(contentHeight: CGFloat) {
        currentNavigationContentHeight = contentHeight
        navigationBarHeightConstraint?.constant = view.safeAreaInsets.top + contentHeight
        searchResultsController.topBarHeight = view.safeAreaInsets.top + contentHeight
    }

    private func configureHeaderPanels() {
        customNavigationBar.useSharedBackground()
        navigationBackground.translatesAutoresizingMaskIntoConstraints = false
        headerPanels.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(navigationBackground, belowSubview: customNavigationBar)
        view.insertSubview(headerPanels, belowSubview: customNavigationBar)
        let height = headerPanels.heightAnchor.constraint(equalToConstant: 0)
        headerPanelsHeightConstraint = height
        NSLayoutConstraint.activate([
            headerPanels.topAnchor.constraint(equalTo: customNavigationBar.bottomAnchor),
            headerPanels.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerPanels.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            height,
            navigationBackground.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBackground.bottomAnchor.constraint(equalTo: headerPanels.bottomAnchor),
        ])
    }

    private func configureVoicePlaybackHeader() {
        voicePlaybackHeader.onTogglePlayback = { Media.shared.togglePlayback() }
        voicePlaybackHeader.onCycleRate = { Media.shared.cyclePlaybackRate() }
        voicePlaybackHeader.onClose = { Media.shared.close() }
        voicePlaybackHeader.onPlayNext = { Media.shared.swipeTrack(toNext: true) }
        voicePlaybackHeader.onPlayPrevious = { Media.shared.swipeTrack(toNext: false) }
        voicePlaybackHeader.onOpen = { [weak self] in self?.openVoicePlaybackMessage() }
        Publishers.CombineLatest4(
            Media.shared.$nowPlaying,
            Media.shared.$isPlaying,
            Media.shared.$playbackPosition,
            Media.shared.$playbackRate,
        )
        .combineLatest(Media.shared.$nowPlayingDisplay)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.updateHeaderPanels(animated: true) }
        .store(in: &cancellables)
    }

    private func configureLiveLocationPanel() {
        liveLocationPanel.onOpen = { [weak self] in self?.openLiveLocation() }
        liveLocationPanel.onClose = { [weak self] in self?.closeLiveLocation() }
        LiveLocationManager.shared
            .$broadcasts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] broadcasts in
                guard let self else { return }
                let source = navigationClientSource
                liveLocationBroadcasts = broadcasts
                    .filter { $0.source == source }
                    .sorted { $0.date > $1.date }
                updateHeaderPanels(animated: true)
            }
            .store(in: &cancellables)
    }

    /// The media header and the live location panel. The note's chat named it while it was open; Telegram hides the
    /// header panels while search is shown.
    private func updateHeaderPanels(animated: Bool, searchActive: Bool? = nil) {
        guard let heightConstraint = headerPanelsHeightConstraint else { return }
        let media = Media.shared
        let display = media.nowPlayingDisplay.flatMap { display in
            display.item == media.nowPlaying && display.item.accountID == navigationClientSource?.accountID
                ? display
                : nil
        }
        if let display {
            let duration = media.playbackDuration
            voicePlaybackHeader.configure(.init(
                title: display.title,
                subtitle: display.subtitle,
                isPlaying: media.isPlaying,
                progress: duration > 0 ? CGFloat(media.playbackPosition / duration) : 0,
                rate: media.playbackRate,
                showsRate: display.showsRate,
                isMusic: display.item.isMusic,
            ))
        }
        let searching = searchActive ?? customNavigationBar.isSearchActive
        let shows = display != nil && !searching && !isShowingSearchResults
        let showsLiveLocation = updateLiveLocationPanelContent() && !searching && !isShowingSearchResults
        guard headerPanels.setVisiblePanels(voice: shows, liveLocation: showsLiveLocation) else { return }
        heightConstraint.constant = headerPanels.contentHeight
        let changes = {
            for folderController in self.folderControllers {
                folderController.setAccessoryTopInset(self.headerPanels.contentHeight)
            }
            self.view.layoutIfNeeded()
        }
        guard animated, view.window != nil, !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes,
        )
    }

    /// LocationBroadcastNavigationAccessoryPanel's summary: "sharing with" the chat, or how many chats see the
    /// location. False while nothing is shared.
    private func updateLiveLocationPanelContent() -> Bool {
        let chatIDs = liveLocationChatIDs
        guard let firstChatID = chatIDs.first else { return false }
        let subtitle = chatIDs.count == 1
            ? L10n.telegram("DialogList.LiveLocationSharingTo", liveLocationChatTitles[firstChatID] ?? "")
            : L10n.telegramPlural("DialogList.LiveLocationChatsCount", count: chatIDs.count)
        liveLocationPanel.configure(subtitle: subtitle, isAccent: false)
        loadLiveLocationChatTitles(chatIDs)
        return true
    }

    private func loadLiveLocationChatTitles(_ chatIDs: [Int64]) {
        let missing = chatIDs.filter { liveLocationChatTitles[$0] == nil }
        guard !missing.isEmpty, liveLocationTitleTask == nil else { return }
        let client = actionAuthority.client
        liveLocationTitleTask = Task { [weak self] in
            var titles = [Int64: String]()
            for chatID in missing {
                // A chat that can't be read keeps an empty title instead of being asked for again.
                titles[chatID] = await (try? client.getChat(chatId: chatID))?.title ?? ""
            }
            guard let self, !Task.isCancelled else { return }
            liveLocationTitleTask = nil
            liveLocationChatTitles.merge(titles) { _, new in new }
            updateHeaderPanels(animated: false)
        }
    }

    /// LiveLocationHeaderPanelComponent's tap in the chat list: one live location opens in the location viewer, and
    /// several are listed with Stop All.
    private func openLiveLocation() {
        if liveLocationBroadcasts.count == 1, let broadcast = liveLocationBroadcasts.first {
            openLiveLocationChat(broadcast)
        } else if !liveLocationBroadcasts.isEmpty {
            presentLiveLocationMenu()
        }
    }

    /// LiveLocationHeaderPanelComponent's close: the chats with Stop All when there are several, else Stop Sharing
    /// Location.
    private func closeLiveLocation() {
        if liveLocationChatIDs.count > 1 {
            presentLiveLocationMenu()
        } else if let broadcast = liveLocationBroadcasts.first {
            let sheet = LiveLocationPanelView.stopSheet(sourceView: liveLocationPanel) {
                LiveLocationManager.shared.stop(chatID: broadcast.chatID, source: broadcast.source)
            }
            view.endEditing(true)
            present(sheet, animated: true)
        }
    }

    /// "You are sharing Live Location with N chats.", a row per chat that opens it, Stop All, and Cancel.
    private func presentLiveLocationMenu() {
        let broadcasts = liveLocationChatIDs.compactMap { chatID in
            liveLocationBroadcasts.first(where: { $0.chatID == chatID })
        }
        guard !broadcasts.isEmpty else { return }
        let sheet = UIAlertController(
            title: nil,
            message: L10n.telegramPlural("LiveLocation.MenuChatsCount", count: broadcasts.count),
            preferredStyle: .actionSheet,
        )
        for broadcast in broadcasts {
            let title = liveLocationChatTitles[broadcast.chatID].flatMap { $0.isEmpty ? nil : $0 }
                ?? L10n.telegram("Message.LiveLocation")
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.openLiveLocationChat(broadcast)
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.telegram("LiveLocation.MenuStopAll"), style: .destructive) { _ in
            for broadcast in broadcasts {
                LiveLocationManager.shared.stop(chatID: broadcast.chatID, source: broadcast.source)
            }
        })
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = liveLocationPanel
            popover.sourceRect = liveLocationPanel.bounds
        }
        view.endEditing(true)
        present(sheet, animated: true)
    }

    /// LiveLocationHeaderPanelComponent's presentLiveLocationController: the live location message opens in the
    /// location viewer with every live location in its chat shown, and a new live location goes to that chat.
    private func openLiveLocationChat(_ broadcast: LiveLocationBroadcast) {
        let scope = actionAuthority.scope(owner: self)
        guard scope.isCurrent, navigationController?.topViewController === self,
              broadcast.source == scope.source else { return }
        let client = actionAuthority.client
        liveLocationOpenTask?.cancel()
        liveLocationOpenTask = Task { [weak self] in
            let message = try? await client.getMessage(chatId: broadcast.chatID, messageId: broadcast.messageID)
            let peerName = await Self.liveLocationPeerName(chatID: broadcast.chatID, client: client)
            guard let self, !Task.isCancelled, let message, let subject = LocationViewSubject(message: message),
                  scope.isCurrent, navigationController?.topViewController === self,
                  presentedViewController == nil else { return }
            liveLocationOpenTask = nil
            view.endEditing(true)
            let viewer = LocationViewController(
                subject: subject,
                client: client,
                source: broadcast.source,
                canShareLiveLocation: true,
                peerName: peerName,
                showsAllLiveLocations: true,
            ) { content in
                Task {
                    _ = try? await client.sendMessage(
                        chatId: broadcast.chatID,
                        inputMessageContent: content,
                        options: nil,
                        replyMarkup: nil,
                        replyTo: nil,
                        topicId: nil,
                    )
                }
            }
            present(viewer.makeNavigationController(), animated: true)
        }
    }

    /// Tapping the header opens the note's chat at the note, and music opens the expanded player, as
    /// MediaPlaybackHeaderPanelComponent's tapAction does.
    private func openVoicePlaybackMessage() {
        let scope = actionAuthority.scope(owner: self)
        guard scope.isCurrent, navigationController?.topViewController === self,
              let item = Media.shared.nowPlaying, item.accountID == scope.source?.accountID else { return }
        if item.isMusic {
            voicePlaybackOpenTask?.cancel()
            voicePlaybackOpenTask = nil
            MusicPlayerViewController.present(from: self)
            return
        }
        let client = actionAuthority.client
        let rootVM = rootVM
        voicePlaybackOpenTask?.cancel()
        voicePlaybackOpenTask = Task { [weak self] in
            let chat = await rootVM.getCustomChatForNavigation(from: item.chatID, client: client)
            guard let self, let chat, scope.isCurrent, navigationController?.topViewController === self else { return }
            voicePlaybackOpenTask = nil
            NavigationStorage.shared.push(.customChat(chat, targetMessageID: item.messageID))
        }
    }

    private func applySearchScrollOffset(offset: CGFloat, animated: Bool) {
        // Search results keep the query field revealed; the folder page under them does not move it.
        guard !isShowingSearchResults else { return }
        guard animated else {
            customNavigationBar.applyScroll(offset: offset)
            return
        }
        view.layoutIfNeeded()
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.customNavigationBar.applyScroll(offset: offset)
            self.view.layoutIfNeeded()
        }
    }

    private func reloadFromState() {
        guard actionAuthority.isCurrent else { return }
        let currentIDs = folderControllers.map(\.folder.id)
        let newIDs = rootVM.folders.map(\.id)
        customNavigationBar.setLeftButtonHidden(rootVM.archive == nil)

        let sameFolderObjects = folderControllers.map(\.folder).elementsEqual(rootVM.folders, by: { $0 === $1 })
        guard currentIDs != newIDs || !sameFolderObjects else {
            folderPicker.configure(
                folders: rootVM.folders,
                selectedID: rootVM.currentFolder,
                unreadStates: folderUnreadStates,
            )
            return
        }

        // A folder whose object survives keeps its controller, so a configuration reload (as after a client renewal)
        // neither reloads nor repositions its list.
        let survivingControllers = Dictionary(
            folderControllers.map { (ObjectIdentifier($0.folder), $0) },
            uniquingKeysWith: { first, _ in first },
        )
        for controller in folderControllers where !rootVM.folders.contains(where: { $0 === controller.folder }) {
            restorationViewports[controller.folder.id] = controller.clientRestorationViewport()
        }
        folderControllers = rootVM.folders.map { folder in
            if let controller = survivingControllers[ObjectIdentifier(folder)] { return controller }
            let controller = FolderViewController(
                folder: folder, rootVM: rootVM, showsStandaloneSearch: false, actionAuthority: actionAuthority,
                restorationViewport: restorationViewports.removeValue(forKey: folder.id),
            )
            controller.setSearchActive(customNavigationBar.isSearchActive, animated: false, preservingViewport: true)
            controller.setAccessoryTopInset(headerPanels.contentHeight)
            controller.isSearchActive = { [weak self] in self?.customNavigationBar.isSearchActive == true }
            controller.onSelectionEditingChange = { [weak self] title, done in
                self?.setChatSelectionEditing(title: title, done: done)
            }
            controller.allowsRowSwipe = { [weak self] in
                guard let self else { return false }
                return folderControllers.count <= 1 || pagingEdgeGate.touchStartedAtEdge
            }
            controller.onSearchScrollOffsetChange = { [weak self, weak controller] offset in
                guard let self, currentFolderController === controller, !isShowingSearchResults else { return }
                customNavigationBar.applyScroll(offset: offset)
            }
            return controller
        }
        folderPicker.configure(
            folders: rootVM.folders,
            selectedID: rootVM.currentFolder,
            unreadStates: folderUnreadStates,
        )
        guard let selected = rootVM.currentFolder ?? rootVM.folders.first?.id else { return }
        selectFolder(id: selected, animated: false)
    }

    private func reloadFolderUnreadStates() {
        guard actionAuthority.isCurrent else { return }
        let states = FolderUnreadStore.shared.states(for: actionAuthority.client.id)
        guard folderUnreadStates != states else { return }
        folderUnreadStates = states
        folderPicker.configure(
            folders: rootVM.folders,
            selectedID: rootVM.currentFolder,
            unreadStates: folderUnreadStates,
        )
    }

    private func selectFolder(id: Int, animated: Bool) {
        guard let targetIndex = folderControllers.firstIndex(where: { $0.folder.id == id }) else { return }
        let previousIndex = folderControllers.firstIndex(where: { $0.folder.id == rootVM.currentFolder }) ?? targetIndex
        let direction: UIPageViewController.NavigationDirection = targetIndex >= previousIndex ? .forward : .reverse
        rootVM.currentFolder = id
        folderPicker.select(id: id, animated: animated)
        applySearchScrollOffset(offset: folderControllers[targetIndex].searchScrollOffset, animated: animated)
        guard currentFolderController !== folderControllers[targetIndex] else { return }
        pageController.setViewControllers([folderControllers[targetIndex]], direction: direction, animated: animated)
    }

    private func updateInteractiveFolderSelection(from scrollView: UIScrollView) {
        guard let transition = interactiveFolderTransition,
              scrollView.bounds.width > 0,
              scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        else { return }
        let fraction = min(1, abs(scrollView.contentOffset.x - scrollView.bounds.width) / scrollView.bounds.width)
        let searchScrollOffsetDelta = transition.toSearchOffset - transition.fromSearchOffset
        if abs(searchScrollOffsetDelta) >= 1 {
            customNavigationBar.applyScroll(
                offset: transition.fromSearchOffset + searchScrollOffsetDelta * fraction,
            )
        }
        folderPicker.updateSelectionTransition(
            fromID: transition.fromID,
            toID: transition.toID,
            fraction: fraction,
        )
    }

    @objc private func openArchive() {
        guard let archive = rootVM.archive else { return }
        NavigationStorage.shared.push(.archive(archive))
    }

    /// Swiftgram's account switcher on a long press of Settings, morphing out of its glass circle: Add Account and
    /// the current account, then the other accounts in a section of their own.
    private func showAccountSwitcher(from source: UIView, tracking gesture: UIGestureRecognizer) {
        let tdlib = TDLib.shared
        var actions = [TelegramContextMenuAction(
            title: L10n.telegram("Settings.AddAccount"),
            image: UIImage(systemName: "plus"),
        ) { [weak self] in
            do {
                try tdlib.addAccount()
            } catch {
                self?.showAccountError(error)
            }
        }]
        if let current = tdlib.accounts.first(where: { $0.id == tdlib.activeAccountID }) {
            actions.append(TelegramContextMenuAction(
                title: current.localizedTitle,
                image: UIImage(systemName: "person.crop.circle"),
            ))
        }
        for (index, account) in tdlib.accounts.filter({ $0.id != tdlib.activeAccountID }).enumerated() {
            actions.append(TelegramContextMenuAction(
                title: account.localizedTitle,
                image: UIImage(systemName: "person.crop.circle"),
                startsNewSection: index == 0,
            ) { [weak self] in
                do {
                    try tdlib.switchToAccount(account.id)
                } catch {
                    self?.showAccountError(error)
                }
            })
        }
        presentTelegramContextMenu(
            sourceView: source,
            actions: actions,
            tracking: gesture,
            presentationStyle: .sourceMorph,
        )
    }

    private func showAccountError(_ error: Error) {
        let alert = UIAlertController(title: nil, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }

    @objc private func openSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: true)
    }

    /// ChatListController.composePressed: Telegram's New Message.
    private func openCompose() {
        guard actionAuthority.scope(owner: self).isCurrent,
              navigationController?.topViewController === self
        else { return }
        navigationController?.pushViewController(NewMessageViewController(), animated: true)
    }

    private func performFolderAction(_ action: FolderMenuAction, for folder: CustomFolder) {
        guard actionAuthority.scope(owner: self).isCurrent else { return }
        switch action {
        case .editFolders:
            pushFolderController(ChatFoldersViewController(rootVM: rootVM, actionAuthority: actionAuthority))
        case .reorderTabs:
            pushFolderController(ChatFolderOrderViewController(rootVM: rootVM, actionAuthority: actionAuthority))
        case .editIcon:
            editMainIcon()
        case .editFolder:
            guard case .folder = folder.type else { return }
            pushFolderController(ChatFolderEditorViewController(
                rootVM: rootVM, folder: folder, actionAuthority: actionAuthority,
            ))
        case .addChats:
            addChats(to: folder)
        case .readAll:
            markAllChatsAsRead(in: folder)
        case .toggleMute:
            setAllChatsMuted(!folder.areAllChatsMuted, in: folder)
        case .remove:
            confirmFolderRemoval(folder)
        }
    }

    /// All Chats has no TDLib folder to keep an icon, so its choice stays on this device.
    private func editMainIcon() {
        let appearance = FolderTabAppearance.shared
        let accountID = rootVM.activeAccountID
        pushFolderController(ChatFolderIconViewController(
            choice: .init(
                icon: appearance.mainIcon(accountID: accountID),
                style: appearance.style(of: 0, accountID: accountID),
            ),
            automaticIcon: .all,
            footer: L10n.betterTG("Folders.Icon.MainFooter"),
        ) { choice in
            appearance.setMainIcon(choice.icon, accountID: accountID)
            appearance.setStyle(choice.style, of: 0, accountID: accountID)
        })
    }

    private func pushFolderController(_ controller: UIViewController) {
        if let navigationController {
            navigationController.pushViewController(controller, animated: true)
        } else {
            present(TelegramNavigationController(rootViewController: controller), animated: true)
        }
    }

    private func addChats(to folder: CustomFolder) {
        let scope = actionAuthority.scope(owner: self)
        guard scope.isCurrent, case .folder(_, let definition) = folder.type else { return }
        let folderID = folder.id
        let controller = ChatFolderChatSelectionViewController(
            session: .live(rootVM: rootVM, authority: actionAuthority),
            title: L10n.telegram("ChatList.AddChatsToFolder"),
            selectedChatIDs: Set(definition.alwaysIncludedChatIDs),
        ) { [weak self] selector, selectedChatIDs in
            // The folder may have changed while the picker was open; the edit starts from its current definition.
            // A folder deleted meanwhile closes the picker without a write.
            guard let self,
                  case .folder(let info, let current) = rootVM.folders.first(where: { $0.id == folderID })?.type
            else { return true }
            selector.submitFolderEdit(id: info.id, folder: current.replacingIncludedChatIDs(selectedChatIDs))
            return false
        }
        pushFolderController(controller)
    }

    private func markAllChatsAsRead(in folder: CustomFolder) {
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        Task { @MainActor [weak self] in
            do {
                _ = try await scope.perform { try await client.readChatList(chatList: folder.chatList) }
            } catch {
                guard scope.isCurrent else { return }
                self?.presentFolderError(error)
            }
        }
    }

    private func setAllChatsMuted(_ muted: Bool, in folder: CustomFolder) {
        guard case .folder(_, let definition) = folder.type else { return }
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        Task { @MainActor [weak self] in
            do {
                let chatCount = try await scope.perform {
                    try await client.getChatFolderChatCount(folder: definition).count
                }
                guard chatCount <= 200 else {
                    self?.presentFolderNotice(
                        title: L10n.betterTG("Folders.TooManyChatsTitle"),
                        message: L10n.betterTG("Folders.MuteAllLimit"),
                    )
                    return
                }
                let chatIDs = try await scope.perform {
                    try await client.getChats(chatList: folder.chatList, limit: 200).chatIds
                }
                try await scope.updateEach(
                    ids: chatIDs,
                    read: { try await client.getChat(chatId: $0) },
                    write: { chatID, chat in
                        _ = try await client.setChatNotificationSettings(
                            chatId: chatID,
                            notificationSettings: chat.notificationSettings.replacingMuteFor(
                                muted ? Int(Int32.max) : 0,
                            ),
                        )
                    },
                )
                // The toast with the folder's name in bold (ChatList.ToastFolderMutedV2 / UnmutedV2).
                guard let self, scope.isCurrent else { return }
                let text = L10n.telegram(muted ? "ChatList.ToastFolderMutedV2" : "ChatList.ToastFolderUnmutedV2")
                    .replacing("{folder}", with: "**\(folder.name.replacing("**", with: ""))**")
                TelegramUndoToast.show(text: text, in: view, bottomInset: 66, undo: nil)
            } catch {
                guard scope.isCurrent else { return }
                self?.presentFolderError(error)
            }
        }
    }

    private func confirmFolderRemoval(_ folder: CustomFolder) {
        let scope = actionAuthority.scope(owner: self)
        let client = actionAuthority.client
        guard scope.isCurrent, case .folder(let info, let definition) = folder.type else { return }
        ChatFolderRemoval.confirm(
            info: info,
            folder: definition,
            from: self,
            scope: scope,
            client: client,
            toastPlacement: { [weak self] in
                guard let view = self?.view else { return nil }
                return ChatFolderRemoval.ToastPlacement(host: view, bottomInset: 64)
            },
            remove: { [weak self] leaveChatIDs, finished in
                Task { @MainActor [weak self] in
                    defer { finished() }
                    do {
                        _ = try await scope.perform {
                            try await client.deleteChatFolder(chatFolderId: info.id, leaveChatIds: leaveChatIDs)
                        }
                        guard scope.isCurrent else { return }
                        if self?.rootVM.currentFolder == folder.id {
                            self?.rootVM.currentFolder = self?.rootVM.folders.first(where: { $0.id == 0 })?.id
                        }
                    } catch {
                        guard scope.isCurrent else { return }
                        self?.presentFolderError(error)
                    }
                }
            },
            failure: { [weak self] error in self?.presentFolderError(error) },
        )
    }

    private func presentFolderError(_ error: any Swift.Error) {
        presentFolderNotice(title: L10n.betterTG("Folders.UpdateError"), message: error.localizedDescription)
    }

    private func presentFolderNotice(title: String, message: String) {
        guard actionAuthority.scope(owner: self).isCurrent, presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - FolderMenuAction

enum FolderMenuAction {
    case editFolders
    case reorderTabs
    case editIcon
    case editFolder
    case addChats
    case readAll
    case toggleMute
    case remove
}

// MARK: - FolderPickerView

/// Telegram's iOS 26 folder strip: an interactive glass capsule of content-sized (or evenly filled) tabs that
/// scroll under UIKit's liquid lens (`LiquidLens`). A tap lifts the lens and carries it to the tapped folder,
/// a page swipe moves it with the swipe, and where UIKit has no lens a glass selection moves instead.
final class FolderPickerView: UIView {
    // MARK: Internal

    struct Item: Equatable {
        let id: Int
        let title: String
        /// The icon before the title; a tab that doesn't show its title shows only the icon.
        var icon: FolderIcon?
        var showsTitle = true
    }

    /// The strip's height above the bottom inset: the blur above the capsule, the capsule and the same gap under it.
    static let barHeight: CGFloat = 58

    // MARK: Private

    private static let springDuration: TimeInterval = 0.4
    /// The least time the lens stays lifted after a tap, so that it crosses the strip as a lens, as Telegram's
    /// folder tabs do.
    private static let liftDuration: TimeInterval = 0.3
    private static let restingTintFadeDuration: TimeInterval = 0.2
    private static let selectionTint = UIColor.label.withAlphaComponent(0.08)
    /// The blur above the folder strip.
    private static let controlTopInset: CGFloat = 8

    var onSelection: ((Int) -> Void)?
    var onReselection: ((Int) -> Void)?
    var onAction: ((FolderMenuAction, CustomFolder) -> Void)?
    /// The capsule's distance from the safe area's sides; the composer's media panel keeps its keys beside it.
    var controlHorizontalInset: CGFloat = 16 {
        didSet {
            controlLeadingConstraint.constant = controlHorizontalInset
            controlTrailingConstraint.constant = -controlHorizontalInset
        }
    }

    /// Whether segments give up their padding to fit the capsule before it scrolls. The composer's media tabs fit
    /// beside the globe and backspace keys, as Telegram's keyboard tabs do; the chat list's folders scroll instead.
    var compressesSegmentsToFit = false {
        didSet {
            updateResolvedWidths()
            layoutSelection(animated: false)
        }
    }

    /// Whether a touch lifts the lens onto the touched segment, the lens follows the finger and letting go selects
    /// the segment under it, as Telegram's keyboard tabs (EntityKeyboardBottomPanelComponent) do; such a strip does
    /// not scroll. The composer's media tabs fit; the chat list's folders scroll and keep holding for their menus.
    var dragsSelection = false {
        didSet {
            tabGesture.isEnabled = dragsSelection
            controlContainer.isScrollEnabled = !dragsSelection
        }
    }

    // MARK: Private

    private let blurView = TelegramBarBackgroundView(edge: .bottom)
    /// Where the lifted lens is drawn: it holds the capsule and does not clip.
    private let liftedContainer = UIView()
    private let controlEffectView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return UIVisualEffectView(effect: effect)
    }()

    private let controlContainer = FolderPickerScrollView()
    /// The scrolled content: the folders, the lens and the selected copies the lens shows.
    private let stripView = UIView()
    private let selectedLabelsView = UIView()
    /// The selected folder's background, which the lens cuts to its shape at rest.
    private let restingTintView = UIView()
    private let selectedButtonStack = UIStackView()
    private let labelsView = UIView()
    private let buttonStack = UIStackView()
    private let selectionEffectView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        effect.tintColor = FolderPickerView.selectionTint
        return UIVisualEffectView(effect: effect)
    }()

    private var lens: LiquidLens?
    private var isLifted = false
    private var lowering: DispatchWorkItem?
    private var stripWidthConstraint: NSLayoutConstraint!
    private var controlLeadingConstraint: NSLayoutConstraint!
    private var controlTrailingConstraint: NSLayoutConstraint!
    private var folders = [CustomFolder]()
    private var items = [Item]()
    private var selectedID: Int?
    private var naturalSegmentWidths = [CGFloat]()
    private var resolvedSegmentWidths = [CGFloat]()
    private var segmentWidthConstraints = [NSLayoutConstraint]()
    private var selectedSegmentWidthConstraints = [NSLayoutConstraint]()
    private var buttons = [FolderButton]()
    private var selectedButtons = [FolderButton]()
    private var unreadStates = [FolderUnreadState]()
    private var interactiveSelection: (fromID: Int, toID: Int, fraction: CGFloat)?
    private lazy var tabGesture: LiquidLensTabRecognizer = {
        let gesture = LiquidLensTabRecognizer(target: self, action: #selector(stripTouched(_:)))
        gesture.isEnabled = false
        return gesture
    }()

    /// The touched segment's frame and when the touch began, while a finger carries the lens.
    private var drag: (frame: CGRect, time: CFTimeInterval)?
    /// The lens's frame while a finger carries it.
    private var heldFrame: CGRect?
    /// The segment under the carried lens.
    private var heldIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateResolvedWidths()
        layoutSelection(animated: false)
    }

    func configure(
        folders: [CustomFolder],
        selectedID: Int?,
        unreadStates: [ChatList: FolderUnreadState],
    ) {
        let displayedUnreadStates: [FolderUnreadState] = folders.map { folder in
            if case .folder = folder.type {
                unreadStates[folder.chatList] ?? FolderUnreadState.empty
            } else {
                FolderUnreadState.empty
            }
        }
        self.folders = folders
        applyItems(
            folders.map { folder in
                let style = folder.tabStyle
                return Item(
                    id: folder.id,
                    title: folder.name,
                    icon: style == .nameOnly ? nil : folder.icon,
                    showsTitle: style != .iconOnly,
                )
            },
            selectedID: selectedID,
            unreadStates: displayedUnreadStates,
        )
    }

    func configure(items: [Item], selectedID: Int?) {
        folders = []
        applyItems(items, selectedID: selectedID, unreadStates: items.map { _ in .empty })
    }

    func select(id: Int?, animated: Bool = true) {
        let selectionChanged = selectedID != id
        // A cancelled page swipe returns the selection from where the swipe left it.
        let wasInteractive = interactiveSelection != nil
        selectedID = id
        interactiveSelection = nil
        updateButtonAppearance()
        layoutSelection(animated: animated && (selectionChanged || wasInteractive))
        if selectionChanged {
            scrollSelectedSegmentIntoView(animated: animated)
        }
    }

    func updateSelectionTransition(fromID: Int, toID: Int, fraction: CGFloat) {
        interactiveSelection = (fromID, toID, min(max(0, fraction), 1))
        layoutSelection(animated: false)
        updateButtonAppearance()
    }

    private func applyItems(_ items: [Item], selectedID: Int?, unreadStates: [FolderUnreadState]) {
        let needsRebuild = self.items != items
        let unreadStatesChanged = self.unreadStates != unreadStates
        self.items = items
        self.unreadStates = unreadStates
        let resolvedSelectedID = selectedID ?? items.first?.id
        guard needsRebuild else {
            if unreadStatesChanged { updateButtonContents(animated: true) }
            select(id: resolvedSelectedID, animated: true)
            return
        }
        self.selectedID = resolvedSelectedID
        rebuildControl()
    }

    private func configureViews() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        liftedContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(liftedContainer)

        controlEffectView.translatesAutoresizingMaskIntoConstraints = false
        controlEffectView.layer.cornerCurve = .continuous
        controlEffectView.layer.cornerRadius = 21
        controlEffectView.cornerConfiguration = .capsule()
        controlEffectView.clipsToBounds = true
        liftedContainer.addSubview(controlEffectView)

        controlContainer.translatesAutoresizingMaskIntoConstraints = false
        // The capsule keeps the strip off the screen's edges; a safe area around it, such as the search filters' over
        // the keyboard, must not shift it.
        controlContainer.contentInsetAdjustmentBehavior = .never
        controlContainer.showsHorizontalScrollIndicator = false
        controlContainer.isDirectionalLockEnabled = true
        controlContainer.delaysContentTouches = false
        controlContainer.canCancelContentTouches = true
        controlContainer.clipsToBounds = true
        controlContainer.layer.cornerCurve = .continuous
        controlEffectView.contentView.addSubview(controlContainer)

        stripView.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.addSubview(stripView)
        // The lens takes the two layers over, so they follow the strip by their autoresizing masks and keep no
        // constraints to it.
        for layer in [selectedLabelsView, labelsView] {
            layer.frame = stripView.bounds
            layer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            stripView.addSubview(layer)
        }
        selectedLabelsView.isUserInteractionEnabled = false
        selectedLabelsView.accessibilityElementsHidden = true
        restingTintView.frame = selectedLabelsView.bounds
        restingTintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        restingTintView.backgroundColor = Self.selectionTint
        selectedLabelsView.addSubview(restingTintView)
        for (stack, layer) in [(selectedButtonStack, selectedLabelsView), (buttonStack, labelsView)] {
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.axis = .horizontal
            stack.alignment = .fill
            stack.distribution = .fill
            stack.spacing = 0
            layer.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: layer.topAnchor),
                stack.leadingAnchor.constraint(equalTo: layer.leadingAnchor),
                stack.bottomAnchor.constraint(equalTo: layer.bottomAnchor),
            ])
        }
        controlContainer.addGestureRecognizer(tabGesture)
        controlContainer.onViewportWidthChange = { [weak self] in
            self?.updateResolvedWidths()
            self?.layoutSelection(animated: false)
            // An offset centred while the strip had no width yet, such as the search filters' before they first
            // show, would leave the first segment cut off.
            self?.scrollSelectedSegmentIntoView(animated: false)
        }

        stripWidthConstraint = stripView.widthAnchor.constraint(equalToConstant: 0)
        controlLeadingConstraint = controlEffectView.leadingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.leadingAnchor,
            constant: controlHorizontalInset,
        )
        controlTrailingConstraint = controlEffectView.trailingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.trailingAnchor,
            constant: -controlHorizontalInset,
        )
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            liftedContainer.topAnchor.constraint(equalTo: topAnchor),
            liftedContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            liftedContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            liftedContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            controlEffectView.topAnchor.constraint(equalTo: topAnchor, constant: Self.controlTopInset),
            controlLeadingConstraint,
            controlTrailingConstraint,
            controlEffectView.heightAnchor.constraint(equalToConstant: 42),
            controlContainer.topAnchor.constraint(equalTo: controlEffectView.contentView.topAnchor, constant: 3),
            controlContainer.leadingAnchor.constraint(
                equalTo: controlEffectView.contentView.leadingAnchor,
                constant: 3,
            ),
            controlContainer.trailingAnchor.constraint(
                equalTo: controlEffectView.contentView.trailingAnchor,
                constant: -3,
            ),
            controlContainer.bottomAnchor.constraint(equalTo: controlEffectView.contentView.bottomAnchor, constant: -3),
            stripView.topAnchor.constraint(equalTo: controlContainer.contentLayoutGuide.topAnchor),
            stripView.leadingAnchor.constraint(equalTo: controlContainer.contentLayoutGuide.leadingAnchor),
            stripView.trailingAnchor.constraint(equalTo: controlContainer.contentLayoutGuide.trailingAnchor),
            stripView.bottomAnchor.constraint(equalTo: controlContainer.contentLayoutGuide.bottomAnchor),
            stripView.heightAnchor.constraint(equalTo: controlContainer.frameLayoutGuide.heightAnchor),
            stripWidthConstraint,
        ])

        lens = LiquidLens(liftedContainer: liftedContainer, liftedContent: selectedLabelsView, punchout: labelsView)
        if lens == nil {
            selectedLabelsView.removeFromSuperview()
            selectionEffectView.isUserInteractionEnabled = false
            selectionEffectView.layer.cornerCurve = .continuous
            selectionEffectView.clipsToBounds = true
            stripView.insertSubview(selectionEffectView, belowSubview: labelsView)
        }
    }

    private func rebuildControl() {
        for stack in [buttonStack, selectedButtonStack] {
            for arrangedSubview in stack.arrangedSubviews {
                stack.removeArrangedSubview(arrangedSubview)
                arrangedSubview.removeFromSuperview()
            }
        }
        segmentWidthConstraints.removeAll()
        selectedSegmentWidthConstraints.removeAll()
        buttons.removeAll()
        selectedButtons.removeAll()
        naturalSegmentWidths = items.indices.map { index in
            naturalSegmentWidth(for: items[index], unreadState: unreadStates[index])
        }
        resolvedSegmentWidths = naturalSegmentWidths
        stripWidthConstraint.constant = naturalSegmentWidths.reduce(0, +)
        for (index, folder) in items.enumerated() {
            let button = FolderButton(type: .system)
            button.tag = index
            button.configure(item: folder, unreadState: unreadStates[index], animated: false)
            button.addTarget(self, action: #selector(folderPressed(_:)), for: .touchUpInside)
            let press = ContextMenuPressGestureRecognizer(target: self, action: #selector(folderLongPressed(_:)))
            // A text-only segment has no shape of its own to cast the platter shadow.
            press.castsShadow = false
            if !folders.isEmpty { button.addGestureRecognizer(press) }
            buttonStack.addArrangedSubview(button)
            let width = button.widthAnchor.constraint(equalToConstant: naturalSegmentWidths[index])
            width.isActive = true
            segmentWidthConstraints.append(width)
            buttons.append(button)
            // Under the lens the selected copy shows through.
            guard lens != nil else { continue }
            let selectedButton = FolderButton(type: .system)
            selectedButton.isUserInteractionEnabled = false
            selectedButton.configure(item: folder, unreadState: unreadStates[index], animated: false)
            selectedButtonStack.addArrangedSubview(selectedButton)
            let selectedWidth = selectedButton.widthAnchor.constraint(equalToConstant: naturalSegmentWidths[index])
            selectedWidth.isActive = true
            selectedSegmentWidthConstraints.append(selectedWidth)
            selectedButtons.append(selectedButton)
        }
        layoutIfNeeded()
        updateResolvedWidths()
        updateButtonAppearance()
        layoutSelection(animated: false)
        scrollSelectedSegmentIntoView(animated: false)
    }

    private func updateButtonContents(animated: Bool) {
        guard items.count == buttons.count, unreadStates.count == buttons.count else { return }
        for copies in [buttons, selectedButtons] where copies.count == items.count {
            for index in copies.indices {
                copies[index].configure(item: items[index], unreadState: unreadStates[index], animated: animated)
            }
        }
        naturalSegmentWidths = items.indices.map { index in
            naturalSegmentWidth(for: items[index], unreadState: unreadStates[index])
        }
        updateResolvedWidths()
        layoutSelection(animated: animated)
    }

    /// A tab showing only its icon may be narrower than a titled one.
    private func naturalSegmentWidth(for folder: Item, unreadState: FolderUnreadState) -> CGFloat {
        let contentWidth = ceil(FolderButton.contentWidth(item: folder, unreadCount: unreadState.count)) + 32
        return folder.showsTitle ? max(60, contentWidth) : contentWidth
    }

    private func scrollSelectedSegmentIntoView(animated: Bool) {
        guard let index = items.firstIndex(where: { $0.id == selectedID }),
              buttons.indices.contains(index) else { return }
        layoutIfNeeded()
        guard controlContainer.bounds.width > 0 else { return }
        let selectedFrame = segmentFrame(at: index)
        let maximumOffset = max(0, controlContainer.contentSize.width - controlContainer.bounds.width)
        let centeredOffset = selectedFrame.midX - controlContainer.bounds.width / 2
        let targetOffset = min(max(0, centeredOffset), maximumOffset)
        controlContainer.setContentOffset(CGPoint(x: targetOffset, y: 0), animated: animated)
    }

    private func updateResolvedWidths() {
        guard !buttons.isEmpty, controlContainer.bounds.width > 0 else { return }
        let naturalTotal = naturalSegmentWidths.reduce(0, +)
        let availableWidth = controlContainer.bounds.width
        var widths = naturalSegmentWidths
        if naturalTotal <= availableWidth {
            let regularWidth = floor(availableWidth / CGFloat(buttons.count))
            if naturalSegmentWidths.allSatisfy({ $0 <= regularWidth }) {
                widths = buttons.indices.map { index in
                    index == buttons.count - 1
                        ? availableWidth - regularWidth * CGFloat(buttons.count - 1)
                        : regularWidth
                }
            } else {
                // A title too long for an equal share keeps its natural width; the rest of the room is shared out.
                let extra = floor((availableWidth - naturalTotal) / CGFloat(buttons.count))
                widths = naturalSegmentWidths.map { $0 + extra }
                widths[widths.count - 1] += availableWidth - widths.reduce(0, +)
            }
        } else if compressesSegmentsToFit {
            widths = compressedSegmentWidths(availableWidth: availableWidth)
        }
        guard widths != resolvedSegmentWidths else { return }
        resolvedSegmentWidths = widths
        for (constraint, width) in zip(segmentWidthConstraints, widths) {
            constraint.constant = width
        }
        for (constraint, width) in zip(selectedSegmentWidthConstraints, widths) {
            constraint.constant = width
        }
        stripWidthConstraint.constant = widths.reduce(0, +)
        controlContainer.alwaysBounceHorizontal = widths.reduce(0, +) > availableWidth + 0.5
        controlContainer.layoutIfNeeded()
    }

    /// The natural widths shrunk toward the title with 8 pt a side, each in proportion to the padding it gives up;
    /// when even that doesn't fit, the compact widths scroll.
    private func compressedSegmentWidths(availableWidth: CGFloat) -> [CGFloat] {
        let compact = items.indices.map { index in
            ceil(FolderButton.contentWidth(item: items[index], unreadCount: unreadStates[index].count)) + 16
        }
        let compactTotal = compact.reduce(0, +)
        let naturalTotal = naturalSegmentWidths.reduce(0, +)
        guard compactTotal < availableWidth, naturalTotal > compactTotal else { return compact }
        let ratio = (availableWidth - compactTotal) / (naturalTotal - compactTotal)
        var widths = zip(compact, naturalSegmentWidths).map { compact, natural in
            floor(compact + (natural - compact) * ratio)
        }
        widths[widths.count - 1] += availableWidth - widths.reduce(0, +)
        return widths
    }

    private func segmentFrame(at index: Int) -> CGRect {
        // Constraints may not have reached the button frames during the viewport
        // layout callback. The resolved widths own both buttons and selection.
        CGRect(
            x: resolvedSegmentWidths.prefix(index).reduce(0, +),
            y: 0,
            width: resolvedSegmentWidths[index],
            height: controlContainer.bounds.height,
        )
    }

    private func layoutSelection(animated: Bool) {
        let frame = selectionFrame()
        if let lens {
            // A lifted lens is clear glass, as the system's is.
            let restingAlpha: CGFloat = isLifted ? 0 : 1
            if restingTintView.alpha != restingAlpha {
                if animated {
                    UIView.animate(
                        withDuration: Self.restingTintFadeDuration,
                        delay: 0,
                        options: [.beginFromCurrentState, .allowUserInteraction],
                    ) {
                        self.restingTintView.alpha = restingAlpha
                    }
                } else {
                    restingTintView.alpha = restingAlpha
                }
            }
            lens.place(frame, isLifted: isLifted, springDuration: animated ? Self.springDuration : nil)
            return
        }
        guard let frame else {
            selectionEffectView.alpha = 0
            return
        }
        let changes = {
            self.selectionEffectView.frame = frame.insetBy(dx: 1, dy: 1)
            self.selectionEffectView.layer.cornerRadius = self.selectionEffectView.bounds.height / 2
            self.selectionEffectView.alpha = 1
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes,
        )
    }

    /// The selected folder's frame in the strip, under the finger during a hold, or the frame between two folders
    /// during a page swipe.
    private func selectionFrame() -> CGRect? {
        if let heldFrame { return heldFrame }
        if let interactiveSelection,
           let fromIndex = items.firstIndex(where: { $0.id == interactiveSelection.fromID }),
           let toIndex = items.firstIndex(where: { $0.id == interactiveSelection.toID }),
           buttons.indices.contains(fromIndex), buttons.indices.contains(toIndex)
        {
            let fromFrame = segmentFrame(at: fromIndex)
            let toFrame = segmentFrame(at: toIndex)
            let fraction = interactiveSelection.fraction
            return CGRect(
                x: fromFrame.minX + (toFrame.minX - fromFrame.minX) * fraction,
                y: 0,
                width: fromFrame.width + (toFrame.width - fromFrame.width) * fraction,
                height: stripView.bounds.height,
            )
        }
        guard let index = items.firstIndex(where: { $0.id == selectedID }), buttons.indices.contains(index)
        else { return nil }
        return segmentFrame(at: index)
    }

    private func updateButtonAppearance() {
        if lens != nil {
            // The lens shows the selected copies, so every folder keeps its plain title.
            for button in buttons {
                button.updateAppearance(titleColor: UIColor.label.withAlphaComponent(0.68))
            }
            for button in selectedButtons {
                button.updateAppearance(titleColor: .label)
            }
            return
        }
        for (index, button) in buttons.enumerated() {
            let selectedAlpha: CGFloat =
                if let interactiveSelection,
                let fromIndex = items
                    .firstIndex(where: { $0.id == interactiveSelection.fromID }),
                   let toIndex = items
                    .firstIndex(where: { $0.id == interactiveSelection.toID })
                {
                    if index == fromIndex {
                        1 - interactiveSelection.fraction
                    } else if index == toIndex {
                        interactiveSelection.fraction
                    } else {
                        0
                    }
                } else {
                    items[index].id == selectedID ? 1 : 0
                }
            button.updateAppearance(
                titleColor: UIColor.label.withAlphaComponent(0.68 + selectedAlpha * 0.32),
            )
        }
    }

    @objc private func folderPressed(_ sender: FolderButton) {
        guard items.indices.contains(sender.tag) else { return }
        let folder = items[sender.tag]
        if selectedID == folder.id {
            scrollSelectedSegmentIntoView(animated: true)
            onReselection?(folder.id)
        } else {
            lift()
            select(id: folder.id, animated: true)
            onSelection?(folder.id)
            lower(after: Self.liftDuration)
        }
    }

    /// The lens lifts onto the touched segment and follows the finger by as much as it moves; letting go selects the
    /// segment under the lens, or scrolls the selected one's page to the top. A quick tap still carries the lens
    /// lifted for `liftDuration`, as a tap on a folder does.
    @objc private func stripTouched(_ gesture: LiquidLensTabRecognizer) {
        guard !resolvedSegmentWidths.isEmpty, resolvedSegmentWidths.count == items.count else { return }
        switch gesture.state {
        case .began:
            let index = segmentIndex(at: gesture.location(in: stripView).x)
            let frame = segmentFrame(at: index)
            drag = (frame, CACurrentMediaTime())
            heldFrame = frame
            heldIndex = index
            lift()
            layoutSelection(animated: true)
        case .changed:
            guard let drag else { return }
            let maxX = max(0, stripView.bounds.width - drag.frame.width)
            let frame = drag.frame.offsetBy(
                dx: min(max(drag.frame.minX + gesture.translation.x, 0), maxX) - drag.frame.minX,
                dy: 0,
            )
            heldFrame = frame
            let index = segmentIndex(at: frame.midX)
            if index != heldIndex {
                UISelectionFeedbackGenerator().selectionChanged()
                heldIndex = index
            }
            layoutSelection(animated: false)
        case .ended:
            guard let drag else { return }
            let index = heldIndex
            self.drag = nil
            heldFrame = nil
            heldIndex = nil
            if let index, items.indices.contains(index), items[index].id != selectedID {
                select(id: items[index].id, animated: true)
                onSelection?(items[index].id)
            } else {
                layoutSelection(animated: true)
                if let index, items.indices.contains(index) { onReselection?(items[index].id) }
            }
            lower(after: max(0, Self.liftDuration - (CACurrentMediaTime() - drag.time)))
        default:
            drag = nil
            heldFrame = nil
            heldIndex = nil
            layoutSelection(animated: true)
            lower(after: 0)
        }
    }

    private func segmentIndex(at x: CGFloat) -> Int {
        var maxX: CGFloat = 0
        for (index, width) in resolvedSegmentWidths.enumerated() {
            maxX += width
            if x < maxX { return index }
        }
        return resolvedSegmentWidths.count - 1
    }

    private func lift() {
        lowering?.cancel()
        lowering = nil
        isLifted = lens != nil
    }

    private func lower(after delay: TimeInterval) {
        lowering?.cancel()
        let lowering = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lowering = nil
            isLifted = false
            layoutSelection(animated: true)
        }
        self.lowering = lowering
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: lowering)
    }

    @objc private func folderLongPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began,
              let button = gesture.view as? FolderButton,
              folders.indices.contains(button.tag)
        else { return }
        let folder = folders[button.tag]
        nearestViewController?.presentTelegramContextMenu(
            sourceView: button,
            actions: folderActions(for: folder),
            tracking: gesture,
            presentationStyle: .menuOnly,
            menuAnchorView: controlEffectView,
            menuSpacing: Self.controlTopInset / 2,
        )
        button.accessibilityHint = L10n.betterTG("Accessibility.FolderActions", folder.name)
    }

    private func folderActions(for folder: CustomFolder) -> [TelegramContextMenuAction] {
        if case .main = folder.type {
            var actions = [
                TelegramContextMenuAction(
                    title: L10n.telegram("ChatList.EditFolders"),
                    image: UIImage(systemName: "square.and.pencil"),
                ) { [weak self] in self?.onAction?(.editFolders, folder) },
                TelegramContextMenuAction(
                    title: L10n.betterTG("Folders.Icon.Change"),
                    image: UIImage(systemName: "square.grid.2x2"),
                ) { [weak self] in self?.onAction?(.editIcon, folder) },
            ]
            if folders.count > 1 {
                actions.append(TelegramContextMenuAction(
                    title: L10n.telegram("ChatList.ReorderTabs"),
                    image: UIImage(systemName: "arrow.up.arrow.down"),
                    startsNewSection: true,
                ) { [weak self] in self?.onAction?(.reorderTabs, folder) })
            }
            return actions
        }
        var actions = [
            TelegramContextMenuAction(
                title: L10n.telegram("ChatList.EditFolder"),
                image: UIImage(systemName: "square.and.pencil"),
            ) { [weak self] in self?.onAction?(.editFolder, folder) },
            TelegramContextMenuAction(
                title: L10n.telegram("ChatList.AddChatsToFolder"),
                image: UIImage(systemName: "person.badge.plus"),
            ) { [weak self] in self?.onAction?(.addChats, folder) },
        ]
        if folder.hasUnreadChats {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.ReadAll"),
                image: UIImage(systemName: "envelope.open"),
            ) { [weak self] in self?.onAction?(.readAll, folder) })
        }
        actions.append(contentsOf: [
            TelegramContextMenuAction(
                title: folder.areAllChatsMuted
                    ? L10n.telegram("ChatList.ContextUnmuteAll")
                    : L10n.telegram("ChatList.ContextMuteAll"),
                image: UIImage(systemName: folder.areAllChatsMuted ? "bell" : "bell.slash"),
            ) { [weak self] in self?.onAction?(.toggleMute, folder) },
            TelegramContextMenuAction(
                title: L10n.telegram("ChatList.RemoveFolderAction"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
            ) { [weak self] in self?.onAction?(.remove, folder) },
        ])
        if folders.count > 1 {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("ChatList.ReorderTabs"),
                image: UIImage(systemName: "arrow.up.arrow.down"),
                startsNewSection: true,
            ) { [weak self] in self?.onAction?(.reorderTabs, folder) })
        }
        return actions
    }
}

// MARK: - FolderPickerScrollView

private final class FolderPickerScrollView: UIScrollView {
    var onViewportWidthChange: (() -> Void)?

    private var previousViewportWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        if abs(previousViewportWidth - bounds.width) > 0.5 {
            previousViewportWidth = bounds.width
            onViewportWidthChange?()
        }
    }

    override func touchesShouldCancel(in _: UIView) -> Bool {
        true
    }
}

// MARK: - FolderButton

/// A folder does not dim while pressed: the lens and the interactive capsule answer the touch.
private final class FolderButton: UIButton {
    // MARK: Private

    private static let titleFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
    private static let badgeFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
    private static let activeBadgeTextColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    }

    private static let iconSpacing: CGFloat = 5

    private let contentStack = UIStackView()
    private let iconView = UIImageView()
    private let folderTitleLabel = UILabel()
    private let unreadBadgeView = FolderUnreadBadgeView()
    private var unreadHasUnmuted = false
    private var resolvedTitleColor = UIColor.label

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func contentWidth(item: FolderPickerView.Item, unreadCount: Int) -> CGFloat {
        var width = item.showsTitle
            ? (item.title as NSString).size(withAttributes: [.font: titleFont]).width
            : 0
        if item.icon != nil {
            width += FolderIcon.side + (item.showsTitle ? iconSpacing : 0)
        }
        guard unreadCount > 0 else { return width }
        let badgeTextWidth = ("\(unreadCount)" as NSString).size(withAttributes: [.font: badgeFont]).width
        return width + 4 + max(18, badgeTextWidth + 8)
    }

    func configure(item: FolderPickerView.Item, unreadState: FolderUnreadState, animated: Bool) {
        folderTitleLabel.text = item.title
        folderTitleLabel.isHidden = !item.showsTitle
        iconView.image = item.icon?.image
        iconView.isHidden = item.icon == nil
        accessibilityLabel = item.title
        accessibilityValue = unreadState.count > 0
            ? L10n.telegramPlural("VoiceOver.Chat.UnreadMessages", count: unreadState.count)
            : nil
        unreadHasUnmuted = unreadState.hasUnmuted

        let wasHidden = unreadBadgeView.isHidden
        let shouldHide = unreadState.count == 0
        // A badge fading out keeps its last count, and a folder without unread messages has no "0" to read.
        if !shouldHide { unreadBadgeView.text = "\(unreadState.count)" }
        updateAppearance(titleColor: resolvedTitleColor)

        guard animated, wasHidden != shouldHide else {
            unreadBadgeView.isHidden = shouldHide
            unreadBadgeView.alpha = shouldHide ? 0 : 1
            unreadBadgeView.transform = shouldHide
                ? CGAffineTransform(scaleX: 0.4, y: 0.4)
                : .identity
            return
        }
        if !shouldHide {
            unreadBadgeView.isHidden = false
            unreadBadgeView.alpha = 0
            unreadBadgeView.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        }
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.76,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.unreadBadgeView.alpha = shouldHide ? 0 : 1
            self.unreadBadgeView.transform = shouldHide
                ? CGAffineTransform(scaleX: 0.4, y: 0.4)
                : .identity
        } completion: { _ in
            self.unreadBadgeView.isHidden = shouldHide
        }
    }

    func updateAppearance(titleColor: UIColor) {
        resolvedTitleColor = titleColor
        folderTitleLabel.textColor = titleColor
        iconView.tintColor = titleColor
        if unreadHasUnmuted {
            unreadBadgeView.backgroundColor = .label
            unreadBadgeView.textColor = Self.activeBadgeTextColor
        } else {
            unreadBadgeView.backgroundColor = .tertiarySystemFill
            unreadBadgeView.textColor = .secondaryLabel
        }
    }

    private func configureViews() {
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 4
        contentStack.isUserInteractionEnabled = false

        iconView.contentMode = .center
        iconView.isHidden = true
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: FolderIcon.side),
            iconView.heightAnchor.constraint(equalToConstant: FolderIcon.side),
        ])
        folderTitleLabel.font = Self.titleFont
        folderTitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        unreadBadgeView.font = Self.badgeFont
        unreadBadgeView.isHidden = true
        unreadBadgeView.alpha = 0
        // The button's accessibility value reads the count.
        unreadBadgeView.accessibilityElementsHidden = true

        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(folderTitleLabel)
        contentStack.addArrangedSubview(unreadBadgeView)
        contentStack.setCustomSpacing(Self.iconSpacing, after: iconView)
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }
}

// MARK: - FolderUnreadBadgeView

/// The capsule is a separate view behind a clear label: a `UILabel` with its own background colour draws as
/// a solid blob of its text colour here, hiding the count.
private final class FolderUnreadBadgeView: UIView {
    // MARK: Private

    private static let height: CGFloat = 18

    override var intrinsicContentSize: CGSize {
        CGSize(width: max(Self.height, countLabel.intrinsicContentSize.width + 8), height: Self.height)
    }

    private let countLabel = UILabel()

    // MARK: Internal

    var text: String? {
        get { countLabel.text }
        set {
            guard countLabel.text != newValue else { return }
            countLabel.text = newValue
            invalidateIntrinsicContentSize()
        }
    }

    var textColor: UIColor {
        get { countLabel.textColor }
        set { countLabel.textColor = newValue }
    }

    var font: UIFont {
        get { countLabel.font }
        set {
            countLabel.font = newValue
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = Self.height / 2
        clipsToBounds = true
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.textAlignment = .center
        addSubview(countLabel)
        NSLayoutConstraint.activate([
            countLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - MainViewController + TelegramGlassPlatterHost

extension MainViewController: TelegramGlassPlatterHost {
    var telegramGlassPlatters: [TelegramGlassPlatter] { customNavigationBar.glassPlatters }
}

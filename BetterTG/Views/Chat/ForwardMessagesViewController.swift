// ForwardMessagesViewController.swift

import Combine
import TDLibKit
import UIKit

@MainActor final class ForwardMessagesViewController: UIViewController, UIPageViewControllerDataSource,
UIPageViewControllerDelegate, TelegramEmbeddedNavigationChrome {
    /// What the chosen chat receives.
    enum Purpose: Equatable {
        case forward
        /// ChatMessageActionOptions' Reply in Another Chat: a chat the user can write to, for a reply to the
        /// request's message.
        case replyInAnotherChat
        /// A switch inline button's chosen chat (`targetChatChosen`): a chat of the allowed kinds the user can write
        /// to, whose composer gets the bot's query.
        case switchInline(InlineTargetChatTypes)
        /// An attachment menu bot link's chosen chat (OpenResolvedUrl's `.startAttach` peer selection, titled Select
        /// Chat): a chat of the kinds both the link and the bot allow, which the user can write to.
        case attachmentMenuBot(InlineTargetChatTypes)
        /// A story's Share (StoryItemSetContainerViewSendMessage.performShareAction): a chat the user can write to
        /// outside secret chats, which receives the story.
        case shareStory
        /// A game's Share (GameControllerNode's ShareController): a chat the user can write to outside secret chats,
        /// which receives the game's link or the game with the player's score.
        case shareGame
    }

    var onSelect: ((CustomChat, ForumTopic?, PendingMessageForward) -> Void)?
    /// The chat chosen in the reply, switch inline and story share purposes.
    var onChosenChat: ((CustomChat, ForumTopic?) -> Void)?

    private let request: MessageForwardRequest
    private let purpose: Purpose
    private let client: TDLibClient
    private let accountID: UUID
    private let seedChats: [Chat]
    /// Change Recipient keeps the options chosen in the composer.
    private let initialMode: MessageForwardMode?
    private let pageController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private let folderPicker = FolderPickerView()
    private lazy var customNavigationBar = TelegramListNavigationBar(
        title: pickerTitle,
        placeholder: L10n.telegram("Common.Search"),
        leftImage: UIImage(systemName: "xmark"),
        rightImage: nil,
        leftAction: { [weak self] in self?.cancelPicker() },
        rightAction: nil,
        leftAccessibilityLabel: L10n.telegram("Common.Close"),
    )
    private var navigationHeight: NSLayoutConstraint!
    private var contentHeight = TelegramListNavigationBar.expandedContentHeight
    private var pages = [ForwardDestinationListViewController]()
    private var preparedForward: PreparedMessageForward?
    private var mode = MessageForwardMode.forward
    private var preparationTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var accountCancellable: AnyCancellable?
    private var clientCancellable: AnyCancellable?
    private var folderBarCancellable: AnyCancellable?
    private var scrollObservation: NSKeyValueObservation?
    private var transition: (from: Int, to: Int, fromOffset: CGFloat, toOffset: CGFloat)?
    private var isChangingPage = false
    private var query = ""

    private var currentPage: ForwardDestinationListViewController? {
        pageController.viewControllers?.first as? ForwardDestinationListViewController
    }

    private var allowedChatTypes: InlineTargetChatTypes? {
        switch purpose {
        case .attachmentMenuBot(let types), .switchInline(let types): types.isEmpty ? nil : types
        case .forward, .replyInAnotherChat, .shareGame, .shareStory: nil
        }
    }

    /// PeerSelectionController's title: Choose User, Bot, Group or Channel for one requested kind, Select Chat for
    /// several or an attachment menu bot, and Forward otherwise.
    private var pickerTitle: String {
        if purpose == .replyInAnotherChat { return L10n.telegram("Conversation.MoveReplyToAnotherChatTitle") }
        if case .attachmentMenuBot = purpose { return L10n.telegram("WebApp.SelectChat") }
        if purpose == .shareStory || purpose == .shareGame { return L10n.telegram("ShareMenu.ShareTo") }
        guard let types = allowedChatTypes else { return L10n.betterTG("Forward.Title") }
        let titles = [
            (types.users, "RequestPeer.ChooseUserTitle"),
            (types.bots, "RequestPeer.ChooseBotTitle"),
            (types.channels, "RequestPeer.ChooseChannelTitle"),
            (types.groups, "RequestPeer.ChooseGroupTitle"),
        ].filter(\.0)
        return L10n.telegram(titles.count == 1 ? titles[0].1 : "ChatImport.Title")
    }

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    init(
        request: MessageForwardRequest,
        client: TDLibClient,
        accountID: UUID,
        seedChats: [Chat],
        initialMode: MessageForwardMode? = nil,
        purpose: Purpose = .forward,
    ) {
        self.request = request
        self.purpose = purpose
        self.client = client
        self.accountID = accountID
        self.seedChats = seedChats
        self.initialMode = initialMode
        super.init(nibName: nil, bundle: nil)
    }

    /// A picker that only chooses a chat, with no messages behind it. Only the forward purpose reads its request, so
    /// the others take a stand-in.
    convenience init?(choosingChatFor purpose: Purpose, client: TDLibClient, accountID: UUID, seedChats: [Chat]) {
        guard purpose != .forward, let request = try? MessageForwardRequest(sourceChatID: 0, messageIDs: [1])
        else { return nil }
        self.init(request: request, client: client, accountID: accountID, seedChats: seedChats, purpose: purpose)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }
    deinit { preparationTask?.cancel()
        selectionTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        pageController.dataSource = self
        pageController.delegate = self
        addChild(pageController)
        for child in [pageController.view!, customNavigationBar, folderPicker] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        pageController.didMove(toParent: self)
        navigationHeight = customNavigationBar.heightAnchor
            .constraint(equalToConstant: contentHeight + view.safeAreaInsets.top)
        NSLayoutConstraint.activate([
            customNavigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            customNavigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customNavigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor), navigationHeight,
            pageController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            folderPicker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -58),
            folderPicker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            folderPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            folderPicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        customNavigationBar.onVisibleHeightChange = { [weak self] height in
            guard let self else { return }
            contentHeight = height
            navigationHeight.constant = view.safeAreaInsets.top + height
        }
        customNavigationBar.onQueryChange = { [weak self] query in
            self?.query = query
            self?.pages.forEach { $0.updateQuery(query) }
        }
        customNavigationBar.onSearchActiveChange = { [weak self] active in
            guard let self else { return }
            pages.forEach { $0.setSearchActive(active, animated: $0 === self.currentPage) }
            if active { customNavigationBar.applyScroll(offset: 0, animated: true) }
        }
        folderPicker.onSelection = { [weak self] id in self?.selectFolder(id) }
        folderPicker.onReselection = { [weak self] _ in self?.currentPage?.scrollToTop() }
        if let scroll = pageController.view.subviews.compactMap({ $0 as? UIScrollView }).first {
            scrollObservation = scroll.observe(\.contentOffset) { [weak self] scroll, _ in
                MainActor.assumeIsolated { self?.updateInteractiveSelection(scroll) }
            }
        }

        accountCancellable = NotificationCenter.default
            .publisher(for: .telegramAccountsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !contextIsCurrent else { return }
                cancelPicker()
            }
        // Returning from the background renews the account's TDLib client without an accounts change. The chat that
        // presented the picker is rebuilt on the new client and drops a choice made here, so the picker closes
        // instead of staying on screen with every tap and page load rejected.
        clientCancellable = TDLib.shared
            .activeClientChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !contextIsCurrent else { return }
                cancelPicker()
            }
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.center = view.center
        spinner.autoresizingMask = [
            .flexibleLeftMargin,
            .flexibleRightMargin,
            .flexibleTopMargin,
            .flexibleBottomMargin,
        ]
        view.addSubview(spinner)
        spinner.startAnimating()
        preparationTask = Task { [weak self] in
            guard let self else { return }
            defer { spinner.removeFromSuperview() }
            do {
                let prepared: PreparedMessageForward =
                    if purpose != .forward {
                        // moveReplyMessageToAnotherChat's and switch inline's onlyWriteable chats: text must be
                        // allowed there, and secret chats take no replies to other chats or inline queries.
                        PreparedMessageForward(
                            request: request,
                            canForward: true,
                            canCopy: true,
                            canCopyToSecretChat: false,
                            contentRequirements: [.basic],
                            hasCaptions: false,
                        )
                    } else {
                        try await MessageForwardingService.prepare(request: request, client: client)
                    }
                guard !Task.isCancelled, contextIsCurrent else { return }
                preparedForward = prepared
                mode = initialMode.flatMap { prepared.supports($0) ? $0 : nil } ?? prepared.defaultMode
                var folders = RootVM.shared.folders
                if !folders
                    .contains(where: { $0.id == 0 }) { folders.insert(CustomFolder(chats: [], type: .main), at: 0) }
                pages = folders.map { folder in
                    let page = ForwardDestinationListViewController(
                        folder: folder,
                        prepared: prepared,
                        client: self.client,
                        accountID: self.accountID,
                        seedChats: self.seedChats,
                        chatTypes: self.allowedChatTypes,
                    )
                    page.updateQuery(self.query)
                    page.setSearchActive(self.customNavigationBar.isSearchActive, animated: false)
                    page.onSelect = { [weak self] chat, forum in self?.selectChat(chat, isForum: forum) }
                    page.onScroll = { [weak self, weak page] offset in
                        guard let self, currentPage === page else { return }
                        customNavigationBar.applyScroll(offset: offset)
                    }
                    return page
                }
                configureFolderBar(folders, selectedID: folders.first?.id)
                // The main screen's folder bar: unread counters and renamed folders follow the account's state.
                folderBarCancellable = FolderUnreadStore.shared
                    .objectWillChange
                    .map { _ in () }
                    .merge(with: RootVM.shared.$folders.dropFirst().map { _ in () })
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] in
                        DispatchQueue.main.async { [weak self] in
                            self?.refreshFolderBar()
                        }
                    }
                if let first = pages.first { pageController.setViewControllers(
                    [first],
                    direction: .forward,
                    animated: false,
                ) }
            } catch { showError(error.localizedDescription) }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        navigationHeight?.constant = view.safeAreaInsets.top + contentHeight
    }

    func pageViewController(
        _: UIPageViewController,
        viewControllerBefore viewController: UIViewController,
    ) -> UIViewController? {
        guard let index = pages.firstIndex(where: { $0 === viewController }), index > 0 else { return nil }
        return pages[index - 1]
    }

    func pageViewController(
        _: UIPageViewController,
        viewControllerAfter viewController: UIViewController,
    ) -> UIViewController? {
        guard let index = pages.firstIndex(where: { $0 === viewController }),
              index + 1 < pages.count else { return nil }
        return pages[index + 1]
    }

    func pageViewController(_: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        guard let from = currentPage,
              let to = pendingViewControllers.first as? ForwardDestinationListViewController else { return }
        transition = (from.folder.id, to.folder.id, from.searchOffset, to.searchOffset)
        isChangingPage = true
    }

    func pageViewController(
        _: UIPageViewController,
        didFinishAnimating _: Bool,
        previousViewControllers _: [UIViewController],
        transitionCompleted _: Bool,
    ) {
        transition = nil
        isChangingPage = false
        folderPicker.select(id: currentPage?.folder.id, animated: true)
        customNavigationBar.applyScroll(offset: currentPage?.searchOffset ?? 0)
    }

    private func updateInteractiveSelection(_ scroll: UIScrollView) {
        guard let transition, scroll.bounds.width > 0 else { return }
        let fraction = min(1, abs(scroll.contentOffset.x - scroll.bounds.width) / scroll.bounds.width)
        folderPicker.updateSelectionTransition(fromID: transition.from, toID: transition.to, fraction: fraction)
        customNavigationBar
            .applyScroll(offset: transition.fromOffset + (transition.toOffset - transition.fromOffset) * fraction)
    }

    private func applySearchOffset(_ offset: CGFloat, animated: Bool) {
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

    private func selectFolder(_ id: Int) {
        guard !isChangingPage, let index = pages.firstIndex(where: { $0.folder.id == id }) else { return }
        let old = pages.firstIndex(where: { $0 === currentPage }) ?? index
        isChangingPage = true
        folderPicker.select(id: id)
        applySearchOffset(pages[index].searchOffset, animated: true)
        pageController.setViewControllers(
            [pages[index]],
            direction: index >= old ? .forward : .reverse,
            animated: true,
        ) { [weak self] _ in self?.isChangingPage = false }
    }

    private func selectChat(_ chat: Chat, isForum: Bool) {
        guard selectionTask == nil, let preparedForward, contextIsCurrent else { return }
        view.endEditing(true)
        if isForum {
            let picker = ForwardForumTopicsViewController(
                chat: chat,
                preparedForward: preparedForward,
                client: client,
                accountID: accountID,
                selectedTopicIDs: [],
            )
            picker.onSelect = { [weak self] topic in self?.openDestination(chat, topic: topic) }
            navigationController?.pushViewController(picker, animated: true)
        } else { openDestination(chat, topic: nil) }
    }

    private func refreshFolderBar() {
        guard contextIsCurrent else { return }
        configureFolderBar(pages.map(\.folder), selectedID: currentPage?.folder.id)
    }

    /// The pages keep the folders they were built with; a renamed folder takes its current name and custom emoji.
    private func configureFolderBar(_ folders: [CustomFolder], selectedID: Int?) {
        let current = Dictionary(RootVM.shared.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        folderPicker.configure(
            folders: folders.map { current[$0.id] ?? $0 },
            selectedID: selectedID,
            unreadStates: FolderUnreadStore.shared.states(for: client.id),
        )
    }

    private func cancelPicker() {
        selectionTask?.cancel()
        preparationTask?.cancel()
        dismiss(animated: true)
    }

    private func openDestination(_ chat: Chat, topic: ForumTopic?) {
        guard selectionTask == nil, let preparedForward, contextIsCurrent else { return }
        if purpose != .forward {
            selectionTask = Task { [weak self] in
                guard let self else { return }
                defer { selectionTask = nil }
                guard let customChat = await RootVM.shared.getCustomChatForNavigation(from: chat.id, client: client),
                      !Task.isCancelled, contextIsCurrent else { return }
                dismiss(animated: true) { [onChosenChat] in onChosenChat?(customChat, topic) }
            }
            return
        }
        selectionTask = Task { [weak self] in
            guard let self else { return }
            defer { selectionTask = nil }
            guard let customChat = await RootVM.shared.getCustomChatForNavigation(from: chat.id, client: client),
                  let firstID = request.messageIDs.first,
                  let message = try? await client.getMessage(chatId: request.sourceChatID, messageId: firstID)
            else {
                if !Task.isCancelled,
                   contextIsCurrent { showError(L10n.betterTG("Forward.SourceUnavailable")) }
                return
            }
            guard !Task.isCancelled, contextIsCurrent else { return }
            let authors = await forwardAuthors()
            guard !Task.isCancelled, contextIsCurrent else { return }
            let draft = PendingMessageForward(
                prepared: preparedForward,
                mode: mode,
                authors: authors.joined(separator: ", "),
                authorCount: authors.count,
                messageSummary: ChatSummary.summary(for: message),
            )
            dismiss(animated: true) { [onSelect] in onSelect?(customChat, topic, draft) }
        }
    }

    /// ForwardAccessoryPanelNode's author list: the original author of a forwarded message (its sender when the
    /// origin is hidden), each once in message order, "You" for the account, a user's first name and a chat's title.
    private func forwardAuthors() async -> [String] {
        let accountUserID = TDLib.shared.activeAccount?.userID
        var seen = Set<Int64>()
        var names = [String]()
        for messageID in request.messageIDs {
            guard let message = try? await client.getMessage(chatId: request.sourceChatID, messageId: messageID)
            else { continue }
            let author: MessageSender =
                switch message.forwardInfo?.origin {
                case .messageOriginUser(let origin):
                    .messageSenderUser(MessageSenderUser(userId: origin.senderUserId))
                case .messageOriginChat(let origin):
                    .messageSenderChat(MessageSenderChat(chatId: origin.senderChatId))
                case .messageOriginChannel(let origin):
                    .messageSenderChat(MessageSenderChat(chatId: origin.chatId))
                case .messageOriginHiddenUser, nil:
                    message.senderId
                }
            switch author {
            case .messageSenderUser(let sender):
                guard seen.insert(sender.userId).inserted else { continue }
                if sender.userId == accountUserID {
                    names.append(L10n.telegram("DialogList.You"))
                } else if let user = try? await client.getUser(userId: sender.userId) {
                    names.append(user.firstName.isEmpty ? user.lastName : user.firstName)
                } else {
                    names.append(L10n.betterTG("Forward.UnknownSender"))
                }
            case .messageSenderChat(let sender):
                guard seen.insert(sender.chatId).inserted else { continue }
                await names.append(
                    (try? client.getChat(chatId: sender.chatId))?.title
                        ?? L10n.betterTG("Chat.FallbackChatTitle"),
                )
            }
        }
        return names
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: L10n.betterTG("Chat.CantForward"),
            message: message,
            preferredStyle: .alert,
        )
        alert
            .addAction(UIAlertAction(title: L10n.telegram("Common.Close"), style: .default) { [weak self] _ in
                self?.dismiss(animated: true)
            })
        (navigationController?.topViewController ?? self).present(alert, animated: true)
    }
}

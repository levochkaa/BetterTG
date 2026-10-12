// ForwardMessagesViewController.swift

import Combine
import TDLibKit
import UIKit

@MainActor final class ForwardMessagesViewController: UIViewController, UIPageViewControllerDataSource,
UIPageViewControllerDelegate, TelegramEmbeddedNavigationChrome {
    var onSelect: ((CustomChat, ForumTopic?, PendingMessageForward) -> Void)?

    private let request: MessageForwardRequest
    private let client: TDLibClient
    private let accountID: UUID
    private let seedChats: [Chat]
    private let pageController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private let folderPicker = FolderPickerView()
    private lazy var customNavigationBar = TelegramListNavigationBar(
        title: L10n.betterTG("Forward.Title"), placeholder: L10n.telegram("Common.Search"),
        leftImage: UIImage(systemName: "xmark"),
        rightImage: UIImage(systemName: "ellipsis"),
        leftAction: { [weak self] in self?.cancelPicker() },
        rightAction: { [weak self] in self?.showOptions() },
    )
    private var navigationHeight: NSLayoutConstraint!
    private var contentHeight = TelegramListNavigationBar.expandedContentHeight
    private var pages = [ForwardDestinationListViewController]()
    private var preparedForward: PreparedMessageForward?
    private var mode = MessageForwardMode.forward
    private var preparationTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var accountCancellable: AnyCancellable?
    private var scrollObservation: NSKeyValueObservation?
    private var transition: (from: Int, to: Int, fromOffset: CGFloat, toOffset: CGFloat)?
    private var isChangingPage = false
    private var query = ""

    private var currentPage: ForwardDestinationListViewController? {
        pageController.viewControllers?.first as? ForwardDestinationListViewController
    }

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    init(request: MessageForwardRequest, client: TDLibClient, accountID: UUID, seedChats: [Chat]) {
        self.request = request
        self.client = client
        self.accountID = accountID
        self.seedChats = seedChats
        super.init(nibName: nil, bundle: nil)
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
                let prepared = try await MessageForwardingService.prepare(request: request, client: client)
                guard !Task.isCancelled, contextIsCurrent else { return }
                preparedForward = prepared
                mode = prepared.defaultMode
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
                folderPicker.configure(
                    items: folders.map { .init(id: $0.id, title: $0.name) },
                    selectedID: folders.first?.id,
                )
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

    private func cancelPicker() {
        selectionTask?.cancel()
        preparationTask?.cancel()
        dismiss(animated: true)
    }

    private func openDestination(_ chat: Chat, topic: ForumTopic?) {
        guard selectionTask == nil, let preparedForward, contextIsCurrent else { return }
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
            let sender: String =
                switch message.senderId {
                case .messageSenderUser(let user):
                    await (try? client.getUser(userId: user.userId))
                        .map { [$0.firstName, $0.lastName].filter { !$0.isEmpty }.joined(separator: " ") } ?? L10n
                        .betterTG("Forward.UnknownSender")
                case .messageSenderChat(let source):
                    await (try? client.getChat(chatId: source.chatId))?.title ?? L10n.betterTG("Chat.FallbackChatTitle")
                }
            guard !Task.isCancelled, contextIsCurrent else { return }
            let draft = PendingMessageForward(
                prepared: preparedForward,
                mode: mode,
                summary: "\(sender): \(ChatSummary.summary(for: message))",
            )
            dismiss(animated: true) { [onSelect] in onSelect?(customChat, topic, draft) }
        }
    }

    private func showOptions() {
        guard let preparedForward else { return }
        let sheet = UIAlertController(
            title: L10n.betterTG("Forward.OptionsTitle"),
            message: nil,
            preferredStyle: .actionSheet,
        )
        func add(_ title: String, _ value: MessageForwardMode) {
            sheet
                .addAction(UIAlertAction(title: title + (mode == value ? " ✓" : ""), style: .default) { [weak self] _ in
                    self?.mode = value
                })
        }
        if preparedForward.canForward { add(L10n.telegram("Conversation.ForwardOptions.ShowSendersName"), .forward) }
        if preparedForward.canCopy {
            add(L10n.telegram("Conversation.ForwardOptions.HideSendersName"), .copy(removeCaption: false))
            if preparedForward.hasCaptions {
                add(L10n.betterTG("Forward.HideSenderAndCaptions"), .copy(removeCaption: true))
            }
        }
        sheet.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = customNavigationBar
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: customNavigationBar.bounds.maxX - 44,
            y: 44,
            width: 44,
            height: 44,
        )
        present(sheet, animated: true)
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

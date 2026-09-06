// ForwardMessagesViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ForwardMessagesViewController

@MainActor final class ForwardMessagesViewController: UIViewController, UITableViewDelegate,
    UISearchBarDelegate
{
    private enum Section {
        case chats
    }

    private struct DeliveryFailure {
        let destination: MessageForwardDestination
        let description: String
        let retryable: Bool
    }

    var onFinished: ((Int) -> Void)?

    private let request: MessageForwardRequest
    private let client: TDLibClient
    private let accountID: UUID
    private let seedChats: [Chat]
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let folderScrollView = UIScrollView()
    private let folderStack = UIStackView()
    private let folderUnderline = UIView()
    private var folderWidthConstraints = [Int: NSLayoutConstraint]()
    private var folders = [CustomFolder]()
    private var selectedFolderID = 0
    private var folderChatLimit = 100
    private var hasMoreFolderChats = true
    private var isLoadingChats = false
    private var unavailablePrivateChatIDs = Set<Int64>()
    private let commentContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let commentTextView = FormattedTextView(placeholder: "Add a comment…")
    private let commentInputBackground = UIView()
    private let actionToolbar = ForwardDestinationToolbar()
    private let searchBar = UISearchBar()
    private let optionsButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var actionToolbarHeightConstraint: NSLayoutConstraint!
    private var commentContainerHeightConstraint: NSLayoutConstraint!
    private var dataSource: UITableViewDiffableDataSource<Section, Int64>!
    private var chatsByID = [Int64: Chat]()
    private var forumChatIDs = Set<Int64>()
    private var checkedSupergroupChatIDs = Set<Int64>()
    private var forumLookupFailedChatIDs = Set<Int64>()
    private var topicNames = [MessageForwardDestination: String]()
    private var eligibilityByChatID = [Int64: MessageForwardDestinationEligibility]()
    private var visibleChatIDs = [Int64]()
    private var selectedDestinations = Set<MessageForwardDestination>()
    private var preparedForward: PreparedMessageForward?
    private var mode = MessageForwardMode.forward
    private var queryGeneration = UInt64.zero
    private var queryTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var accountCancellable: AnyCancellable?
    private var contentSizeCancellable: AnyCancellable?
    private var isSending = false
    private var deliveredCommentByDestination = [MessageForwardDestination: FormattedText]()

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID
            && TDLib.shared.activeClient.id == client.id
    }

    init(
        request: MessageForwardRequest,
        client: TDLibClient,
        accountID: UUID,
        seedChats: [Chat],
    ) {
        self.request = request
        self.client = client
        self.accountID = accountID
        self.seedChats = seedChats
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        queryTask?.cancel()
        preparationTask?.cancel()
        deliveryTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Forward to"
        view.backgroundColor = .systemBackground
        configureNavigation()
        configureTable()
        configureFolders()
        configureToolbar()
        observeContentSizeCategory()
        observeAccount()
        for chat in seedChats {
            chatsByID[chat.id] = chat
        }
        prepareMessages()
        loadChats(query: "")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateToolbarKeyboardAttachment()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFolderUnderline(animated: false)
        updateToolbarKeyboardAttachment()
    }

    func searchBar(_: UISearchBar, textDidChange searchText: String) {
        loadChats(query: searchText)
    }

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isSending,
              let preparedForward,
              let chatID = dataSource.itemIdentifier(for: indexPath),
              eligibilityByChatID[chatID]?.isAllowed == true
        else { return }
        if forumChatIDs.contains(chatID), let chat = chatsByID[chatID] {
            let selectedTopicIDs = Set(selectedDestinations.compactMap { destination in
                destination.chatID == chatID ? destination.forumTopicID : nil
            })
            let picker = ForwardForumTopicsViewController(
                chat: chat,
                preparedForward: preparedForward,
                client: client,
                accountID: accountID,
                selectedTopicIDs: selectedTopicIDs,
            )
            picker.onToggle = { [weak self] topic, selected in
                guard let self else { return }
                let destination = MessageForwardDestination(
                    chatID: chatID,
                    topic: .messageTopicForum(MessageTopicForum(forumTopicId: topic.info.forumTopicId)),
                )
                if selected {
                    selectedDestinations.insert(destination)
                    topicNames[destination] = topic.info.name
                } else {
                    selectedDestinations.remove(destination)
                    topicNames[destination] = nil
                }
                reconfigure(chatIDs: [chatID])
                updateToolbar()
            }
            navigationController?.pushViewController(picker, animated: true)
            return
        }
        let destination = MessageForwardDestination(chatID: chatID, topic: nil)
        if selectedDestinations.contains(destination) {
            selectedDestinations.remove(destination)
        } else {
            selectedDestinations.insert(destination)
        }
        reconfigure(chatIDs: [chatID])
        updateToolbar()
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard !isLoadingChats, hasMoreFolderChats,
              (searchBar.text ?? "").isEmpty,
              indexPath.row >= dataSource.snapshot().numberOfItems - 10
        else { return }
        folderChatLimit += 100
        loadChats(query: "")
    }

    private func configureNavigation() {
        applyClassicNavigationAppearance()
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        cancelButton.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: cancelButton)
        optionsButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        optionsButton.accessibilityLabel = "Forward Options"
        optionsButton.showsMenuAsPrimaryAction = true
        optionsButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        optionsButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            customView: optionsButton,
        )
        optionsButton.isEnabled = false
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 76, bottom: 0, right: 16)
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.register(ForwardDestinationCell.self, forCellReuseIdentifier: ForwardDestinationCell.reuseID)
        searchBar.delegate = self
        searchBar.placeholder = "Search"
        searchBar.autocapitalizationType = .none
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.searchTextField.backgroundColor = .tertiarySystemFill
        view.addSubview(searchBar)
        view.addSubview(tableView)
        dataSource = UITableViewDiffableDataSource<Section, Int64>(
            tableView: tableView,
        ) { [weak self] tableView, indexPath, chatID in
            guard let self,
                  let cell = tableView.dequeueReusableCell(
                      withIdentifier: ForwardDestinationCell.reuseID,
                      for: indexPath,
                  ) as? ForwardDestinationCell,
                  let chat = chatsByID[chatID]
            else { return UITableViewCell() }
            let eligibility = eligibilityByChatID[chatID]
            cell.configure(
                chat: chat,
                subtitle: subtitle(for: chat, eligibility: eligibility),
                selected: selectedDestinations.contains(where: { $0.chatID == chatID }),
                enabled: eligibility?.isAllowed == true,
                client: client,
            )
            return cell
        }
    }

    private func configureFolders() {
        folders = RootVM.shared.allFolders
        if !folders.contains(where: { $0.id == 0 }) {
            folders.insert(CustomFolder(chats: [], type: .main), at: 0)
        }
        folderScrollView.translatesAutoresizingMaskIntoConstraints = false
        folderScrollView.showsHorizontalScrollIndicator = false
        folderScrollView.backgroundColor = .systemBackground
        folderStack.translatesAutoresizingMaskIntoConstraints = false
        folderStack.axis = .horizontal
        folderStack.spacing = 0
        folderScrollView.addSubview(folderStack)
        folderUnderline.backgroundColor = .systemBlue
        folderUnderline.layer.cornerRadius = 1.5
        folderScrollView.addSubview(folderUnderline)
        view.addSubview(folderScrollView)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            searchBar.heightAnchor.constraint(equalToConstant: 52),
            folderScrollView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            folderScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            folderScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            folderScrollView.heightAnchor.constraint(equalToConstant: 44),
            folderStack.topAnchor.constraint(equalTo: folderScrollView.contentLayoutGuide.topAnchor),
            folderStack.bottomAnchor.constraint(equalTo: folderScrollView.contentLayoutGuide.bottomAnchor),
            folderStack.leadingAnchor.constraint(
                equalTo: folderScrollView.contentLayoutGuide.leadingAnchor,
                constant: 8,
            ),
            folderStack.trailingAnchor.constraint(
                equalTo: folderScrollView.contentLayoutGuide.trailingAnchor,
                constant: -8,
            ),
            folderStack.heightAnchor.constraint(equalTo: folderScrollView.frameLayoutGuide.heightAnchor),
        ])
        for folder in folders {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tag = folder.id
            let width = button.widthAnchor.constraint(equalToConstant: 44)
            width.isActive = true
            folderWidthConstraints[folder.id] = width
            button.accessibilityIdentifier = "forward-folder-\(folder.id)"
            button.addAction(UIAction { [weak self] _ in
                guard let self, !isSending, selectedFolderID != folder.id else { return }
                selectedFolderID = folder.id
                folderChatLimit = 100
                hasMoreFolderChats = true
                updateFolderButtons(animated: true)
                apply(chatIDs: [])
                loadChats(query: searchBar.text ?? "")
            }, for: .touchUpInside)
            folderStack.addArrangedSubview(button)
        }
        updateFolderButtons()
    }

    private func updateFolderButtons(animated: Bool = false) {
        for case let button as UIButton in folderStack.arrangedSubviews {
            let selected = button.tag == selectedFolderID
            let title = folders.first(where: { $0.id == button.tag })?.name ?? ""
            let font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(
                ofSize: 15,
                weight: .semibold,
            ))
            // Telegram measures each tab from its label.
            folderWidthConstraints[button.tag]?.constant = max(
                44,
                ceil((title as NSString).size(withAttributes: [.font: font]).width) + 28,
            )
            var configuration = UIButton.Configuration.plain()
            configuration.title = title
            configuration.baseForegroundColor = selected ? .systemBlue : .secondaryLabel
            configuration.buttonSize = .small
            configuration.background.backgroundColor = .clear
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = font
                return attributes
            }
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 10, trailing: 14)
            button.configuration = configuration
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
        folderStack.layoutIfNeeded()
        updateFolderUnderline(animated: animated)
    }

    private func updateFolderUnderline(animated: Bool) {
        guard let button = folderStack.arrangedSubviews.first(where: { $0.tag == selectedFolderID }),
              button.bounds.width > 0 else { return }
        let rect = button.convert(button.bounds, to: folderScrollView)
        let update = { self.folderUnderline.frame = CGRect(
            x: rect.minX + 12,
            y: rect.maxY - 3,
            width: max(16, rect.width - 24),
            height: 3,
        ) }
        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: update,
            )
            folderScrollView.scrollRectToVisible(rect.insetBy(dx: -8, dy: 0), animated: true)
        } else { update() }
    }

    private func configureToolbar() {
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        commentContainer.translatesAutoresizingMaskIntoConstraints = false
        commentTextView.translatesAutoresizingMaskIntoConstraints = false
        commentInputBackground.translatesAutoresizingMaskIntoConstraints = false
        commentInputBackground.backgroundColor = .tertiarySystemFill
        commentInputBackground.layer.cornerRadius = 18
        commentInputBackground.layer.cornerCurve = .continuous
        commentInputBackground.isUserInteractionEnabled = false
        commentContainer.contentView.addSubview(commentInputBackground)
        commentTextView.onTextChange = { [weak self] _ in
            self?.updateCommentHeight()
        }
        commentContainer.contentView.addSubview(commentTextView)
        view.addSubview(commentContainer)
        commentContainerHeightConstraint = commentContainer.heightAnchor.constraint(equalToConstant: 52)

        actionToolbar.translatesAutoresizingMaskIntoConstraints = false
        actionToolbar.onSend = { [weak self] in
            self?.sendSelected()
        }
        view.addSubview(actionToolbar)
        actionToolbarHeightConstraint = actionToolbar.heightAnchor.constraint(
            equalToConstant: ForwardDestinationToolbar.contentHeight + view.safeAreaInsets.bottom,
        )
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: folderScrollView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: commentContainer.topAnchor),
            commentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commentContainer.bottomAnchor.constraint(equalTo: actionToolbar.topAnchor),
            commentContainerHeightConstraint,
            commentInputBackground.topAnchor.constraint(equalTo: commentContainer.contentView.topAnchor, constant: 6),
            commentInputBackground.leadingAnchor.constraint(
                equalTo: commentContainer.contentView.leadingAnchor,
                constant: 12,
            ),
            commentInputBackground.trailingAnchor.constraint(
                equalTo: commentContainer.contentView.trailingAnchor,
                constant: -12,
            ),
            commentInputBackground.bottomAnchor.constraint(
                equalTo: commentContainer.contentView.bottomAnchor,
                constant: -6,
            ),
            commentTextView.topAnchor.constraint(equalTo: commentContainer.contentView.topAnchor, constant: 6),
            commentTextView.leadingAnchor.constraint(equalTo: commentContainer.contentView.leadingAnchor, constant: 20),
            commentTextView.trailingAnchor.constraint(
                equalTo: commentContainer.contentView.trailingAnchor,
                constant: -20,
            ),
            commentTextView.bottomAnchor.constraint(equalTo: commentContainer.contentView.bottomAnchor, constant: -6),
            actionToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionToolbar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            actionToolbarHeightConstraint,
        ])
        updateToolbar()
    }

    private func updateCommentHeight() {
        let desiredHeight = min(132, max(52, commentTextView.intrinsicContentSize.height + 12))
        guard abs(commentContainerHeightConstraint.constant - desiredHeight) > 0.5 else { return }
        commentContainerHeightConstraint.constant = desiredHeight
        view.setNeedsLayout()
    }

    private func observeAccount() {
        accountCancellable = NotificationCenter.default
            .publisher(for: .telegramAccountsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !contextIsCurrent else { return }
                abortForAccountChange()
            }
    }

    private func observeContentSizeCategory() {
        contentSizeCancellable = NotificationCenter.default
            .publisher(for: UIContentSizeCategory.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateCommentHeight()
                    self?.updateFolderButtons()
                }
            }
    }

    private func updateToolbarKeyboardAttachment() {
        guard actionToolbarHeightConstraint != nil else { return }
        let keyboardAttached = view.keyboardLayoutGuide.layoutFrame.minY
            < view.bounds.maxY - view.safeAreaInsets.bottom - 1
        actionToolbarHeightConstraint.constant = ForwardDestinationToolbar.contentHeight
            + (keyboardAttached ? 0 : view.safeAreaInsets.bottom)
    }

    private func prepareMessages() {
        activityIndicator.startAnimating()
        tableView.backgroundView = activityIndicator
        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await MessageForwardingService.prepare(
                    request: request,
                    client: client,
                )
                try Task.checkCancellation()
                guard contextIsCurrent else {
                    throw MessageForwardingError.accountChanged
                }
                preparedForward = prepared
                mode = prepared.defaultMode
                loadChats(query: searchBar.text ?? "")
                configureOptionsMenu()
                updateToolbar()
                updateBackgroundView()
            } catch is CancellationError {
                return
            } catch {
                presentPreparationError(error)
            }
        }
    }

    private func loadChats(query rawQuery: String) {
        queryGeneration &+= 1
        let generation = queryGeneration
        queryTask?.cancel()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = folders.first(where: { $0.id == selectedFolderID })
        let chatList = folder?.chatList ?? .chatListMain
        isLoadingChats = true
        updateBackgroundView()
        queryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == queryGeneration {
                    isLoadingChats = false
                    updateBackgroundView()
                    if !Task.isCancelled, contextIsCurrent, query.isEmpty, hasMoreFolderChats,
                       dataSource.snapshot().numberOfItems < 10
                    {
                        folderChatLimit += 100
                        loadChats(query: "")
                    }
                }
            }
            if !query.isEmpty {
                try? await Task<Never, Never>.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            // TDLib must load a list before getChats can enumerate it (including custom folders).
            _ = try? await client.send(TDNativeRequests.loadChats(chatList: chatList, limit: 100))
            guard !Task.isCancelled, generation == queryGeneration, contextIsCurrent else { return }
            var ids = folder?.chats.map(\.id) ?? []
            if let page = try? await client.getChats(chatList: chatList, limit: folderChatLimit) {
                ids = deduplicated(page.chatIds + ids)
                hasMoreFolderChats = page.chatIds.count >= folderChatLimit
            } else { hasMoreFolderChats = false }
            if !query.isEmpty {
                if let offline = try? await client.searchChats(limit: 100, query: query, typeFilter: nil) {
                    ids = offline.chatIds
                } else { ids = seedChatIDs(matching: query) }
                if let server = try? await client.searchChatsOnServer(limit: 100, query: query, typeFilter: nil) {
                    ids.append(contentsOf: server.chatIds)
                }
            }
            await hydrateAndApply(ids: ids, generation: generation, chatList: chatList, query: query)
        }
    }

    private func hydrateAndApply(
        ids: [Int64],
        generation: UInt64,
        chatList: ChatList,
        query: String,
    ) async {
        let uniqueIDs = deduplicated(ids)
        for chatID in uniqueIDs {
            guard !Task.isCancelled else { return }
            if let chat = try? await client.getChat(chatId: chatID) {
                chatsByID[chatID] = chat
            }
            if let chat = chatsByID[chatID],
               case .chatTypeSupergroup(let type) = chat.type,
               !checkedSupergroupChatIDs.contains(chatID)
            {
                if chat.viewAsTopics {
                    forumChatIDs.insert(chatID)
                    checkedSupergroupChatIDs.insert(chatID)
                    forumLookupFailedChatIDs.remove(chatID)
                } else if let supergroup = try? await client.getSupergroup(supergroupId: type.supergroupId) {
                    checkedSupergroupChatIDs.insert(chatID)
                    forumLookupFailedChatIDs.remove(chatID)
                    if supergroup.isForum {
                        forumChatIDs.insert(chatID)
                    }
                } else {
                    forumLookupFailedChatIDs.insert(chatID)
                }
            }
        }
        guard !Task.isCancelled,
              generation == queryGeneration,
              contextIsCurrent
        else { return }
        let hydratedIDs = uniqueIDs.filter { chatID in
            guard let chat = chatsByID[chatID] else { return false }
            // All Chats search can discover a recipient; a custom folder/archive search stays in that list.
            return !query.isEmpty && chatList == .chatListMain
                || chat.positions.contains { $0.list == chatList && $0.order != 0 }
        }
        for chatID in hydratedIDs {
            guard !Task.isCancelled, generation == queryGeneration, contextIsCurrent else { return }
            guard let chat = chatsByID[chatID], case .chatTypePrivate = chat.type,
                  let preparedForward else { continue }
            let eligibility = await MessageForwardingService.eligibility(
                of: chat, topic: nil, for: preparedForward, client: client,
            )
            guard !Task.isCancelled, generation == queryGeneration, contextIsCurrent else { return }
            if eligibility.isAllowed { unavailablePrivateChatIDs.remove(chatID) }
            else { unavailablePrivateChatIDs.insert(chatID) }
        }
        apply(chatIDs: prioritizeSavedMessages(hydratedIDs))
    }

    private func apply(chatIDs: [Int64]) {
        visibleChatIDs = chatIDs
        rebuildEligibility()
    }

    private func rebuildEligibility() {
        guard let preparedForward else {
            applyEligibleSnapshot()
            return
        }
        var updated = [Int64: MessageForwardDestinationEligibility]()
        for chatID in visibleChatIDs {
            guard let chat = chatsByID[chatID] else { continue }
            updated[chatID] =
                if forumLookupFailedChatIDs.contains(chatID) || unavailablePrivateChatIDs.contains(chatID) {
                    MessageForwardDestinationEligibility(
                        isAllowed: false,
                        reason: "This destination is unavailable.",
                        forcedMode: nil,
                    )
                } else {
                    MessageForwardingService.localEligibility(
                        of: chat,
                        for: preparedForward,
                    )
                }
        }
        eligibilityByChatID.merge(updated, uniquingKeysWith: { _, new in new })
        let invalidSelection = selectedDestinations.filter { updated[$0.chatID]?.isAllowed == false }
        selectedDestinations.subtract(invalidSelection)
        applyEligibleSnapshot()
        updateToolbar()
    }

    private func applyEligibleSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.chats])
        snapshot.appendItems(visibleChatIDs.filter { eligibilityByChatID[$0]?.isAllowed == true })
        dataSource.apply(snapshot, animatingDifferences: true)
        updateBackgroundView()
    }

    private func configureOptionsMenu() {
        guard let preparedForward else { return }
        var actions = [UIAction]()
        if preparedForward.canForward {
            actions.append(UIAction(
                title: "Show Sender Name",
                image: UIImage(systemName: "person.text.rectangle"),
                state: mode == .forward ? .on : .off,
            ) { [weak self] _ in
                self?.setMode(.forward)
            })
        }
        if preparedForward.canCopy {
            actions.append(UIAction(
                title: "Hide Sender Name",
                image: UIImage(systemName: "person.crop.circle.badge.xmark"),
                state: mode == .copy(removeCaption: false) ? .on : .off,
            ) { [weak self] _ in
                self?.setMode(.copy(removeCaption: false))
            })
            if preparedForward.hasCaptions {
                actions.append(UIAction(
                    title: "Hide Sender and Captions",
                    image: UIImage(systemName: "captions.bubble.fill"),
                    state: mode == .copy(removeCaption: true) ? .on : .off,
                ) { [weak self] _ in
                    self?.setMode(.copy(removeCaption: true))
                })
            }
        }
        optionsButton.menu = UIMenu(title: "Forward Options", children: actions)
        optionsButton.isEnabled = actions.count > 1 && !isSending
    }

    private func setMode(_ mode: MessageForwardMode) {
        guard preparedForward?.supports(mode) == true else { return }
        self.mode = mode
        configureOptionsMenu()
        updateToolbar()
    }

    private func sendSelected() {
        guard !isSending,
              let preparedForward,
              !selectedDestinations.isEmpty,
              contextIsCurrent
        else { return }
        let attributedComment = ComposerText.value(commentTextView.attributedText)
        let comment: FormattedText? = attributedComment.string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            ? nil
            : FormattedText(
                entities: getEntities(from: attributedComment),
                text: attributedComment.string,
            )
        isSending = true
        isModalInPresentation = true
        searchBar.isUserInteractionEnabled = false
        commentTextView.isEditable = false
        commentTextView.isSelectable = false
        navigationItem.leftBarButtonItem?.isEnabled = false
        configureOptionsMenu()
        updateToolbar()
        let destinations = selectedDestinations.sorted { lhs, rhs in
            if lhs.chatID != rhs.chatID {
                return lhs.chatID < rhs.chatID
            }
            return (lhs.forumTopicID ?? 0) < (rhs.forumTopicID ?? 0)
        }
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            var failures = [DeliveryFailure]()
            var completedCount = 0
            for destination in destinations {
                guard !Task.isCancelled else { break }
                guard contextIsCurrent else {
                    failures.append(DeliveryFailure(
                        destination: destination,
                        description: MessageForwardingError.accountChanged.localizedDescription,
                        retryable: true,
                    ))
                    continue
                }
                do {
                    if let comment, deliveredCommentByDestination[destination] != comment {
                        _ = try await MessageForwardingService.sendComment(
                            comment,
                            prepared: preparedForward,
                            to: destination,
                            client: client,
                            accountID: accountID,
                        )
                        deliveredCommentByDestination[destination] = comment
                    }
                    _ = try await MessageForwardingService.send(
                        preparedForward,
                        to: destination,
                        mode: mode,
                        client: client,
                        accountID: accountID,
                    )
                    completedCount += 1
                    selectedDestinations.remove(destination)
                    deliveredCommentByDestination[destination] = nil
                } catch is DecodingError {
                    selectedDestinations.remove(destination)
                    deliveredCommentByDestination[destination] = nil
                    failures.append(DeliveryFailure(
                        destination: destination,
                        description: "TDLib returned an ambiguous partial result.",
                        retryable: false,
                    ))
                } catch let error as MessageForwardingError {
                    let retryable: Bool
                    if case .partialDelivery = error {
                        retryable = false
                        selectedDestinations.remove(destination)
                        deliveredCommentByDestination[destination] = nil
                    } else {
                        retryable = true
                    }
                    failures.append(DeliveryFailure(
                        destination: destination,
                        description: error.localizedDescription,
                        retryable: retryable,
                    ))
                } catch {
                    failures.append(DeliveryFailure(
                        destination: destination,
                        description: "Couldn't forward messages. Try again.",
                        retryable: true,
                    ))
                }
            }
            finishDelivery(
                destinationCount: destinations.count,
                completedCount: completedCount,
                failures: failures,
            )
        }
    }

    private func finishDelivery(
        destinationCount: Int,
        completedCount: Int,
        failures: [DeliveryFailure],
    ) {
        isSending = false
        isModalInPresentation = false
        searchBar.isUserInteractionEnabled = true
        commentTextView.isEditable = true
        commentTextView.isSelectable = true
        navigationItem.leftBarButtonItem?.isEnabled = true
        configureOptionsMenu()
        reconfigure(chatIDs: visibleChatIDs)
        updateToolbar()
        guard !failures.isEmpty else {
            dismiss(animated: true) { [onFinished] in
                onFinished?(destinationCount)
            }
            return
        }

        let descriptions = failures.prefix(3).map { failure in
            let chatTitle = chatsByID[failure.destination.chatID]?.title ?? "Chat"
            let title = topicNames[failure.destination].map { "\(chatTitle) › \($0)" } ?? chatTitle
            let retry = failure.retryable ? "" : " It won't be retried automatically."
            return "\(title): \(failure.description)\(retry)"
        }
        let extraCount = failures.count - descriptions.count
        let suffix = extraCount > 0 ? "\n…and \(extraCount) more." : ""
        let alert = UIAlertController(
            title: completedCount > 0 ? "Partly Forwarded" : "Couldn't Forward",
            message: descriptions.joined(separator: "\n") + suffix,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func updateToolbar() {
        actionToolbar.update(
            selectedCount: selectedDestinations.count,
            messageCount: request.messageIDs.count,
            isSending: isSending,
        )
    }

    private func updateBackgroundView() {
        if preparedForward == nil || isLoadingChats && dataSource.snapshot().numberOfItems == 0 {
            activityIndicator.startAnimating()
            tableView.backgroundView = activityIndicator
        } else if dataSource.snapshot().numberOfItems == 0 {
            let label = UILabel()
            label.text = "No chats found"
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
    }

    private func reconfigure(chatIDs: [Int64]) {
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        let existing = chatIDs.filter { snapshot.indexOfItem($0) != nil }
        guard !existing.isEmpty else { return }
        snapshot.reconfigureItems(existing)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func seedChatIDs(matching query: String) -> [Int64] {
        seedChats.compactMap { chat in
            query.isEmpty || chat.title.localizedCaseInsensitiveContains(query) ? chat.id : nil
        }
    }

    private func deduplicated(_ chatIDs: [Int64]) -> [Int64] {
        var seen = Set<Int64>()
        return chatIDs.filter { seen.insert($0).inserted }
    }

    private func prioritizeSavedMessages(_ chatIDs: [Int64]) -> [Int64] {
        guard let accountUserID = TDLib.shared.activeAccount?.userID,
              let savedIndex = chatIDs.firstIndex(where: { chatID in
                  guard let chat = chatsByID[chatID],
                        case .chatTypePrivate(let privateChat) = chat.type
                  else { return false }
                  return privateChat.userId == accountUserID
              })
        else { return chatIDs }
        var prioritized = chatIDs
        let savedID = prioritized.remove(at: savedIndex)
        prioritized.insert(savedID, at: 0)
        return prioritized
    }

    private func subtitle(
        for chat: Chat,
        eligibility: MessageForwardDestinationEligibility?,
    ) -> String {
        if let reason = eligibility?.reason {
            return reason
        }
        if forumChatIDs.contains(chat.id) {
            let names = selectedDestinations
                .filter { $0.chatID == chat.id }
                .compactMap { topicNames[$0] }
                .sorted()
            if names.isEmpty {
                return "Forum · Choose a topic"
            }
            if names.count == 1, let name = names.first {
                return name
            }
            return "\(names.count) topics selected"
        }
        if let message = chat.lastMessage { return ChatSummary.summary(for: message) }
        switch chat.type {
        case .chatTypeBasicGroup:
            return "Group"
        case .chatTypePrivate:
            return "Private Chat"
        case .chatTypeSecret:
            return "Secret Chat · Sender name will be hidden"
        case .chatTypeSupergroup(let supergroup):
            return supergroup.isChannel ? "Channel" : "Group"
        }
    }

    private func presentPreparationError(_ error: Swift.Error) {
        guard presentedViewController == nil else { return }
        let message =
            if let forwardingError = error as? MessageForwardingError {
                forwardingError.localizedDescription
            } else {
                "The selected messages couldn't be prepared for forwarding."
            }
        let alert = UIAlertController(title: "Can't Forward", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func abortForAccountChange() {
        queryTask?.cancel()
        preparationTask?.cancel()
        guard !isSending else { return }
        deliveryTask?.cancel()
        guard presentedViewController == nil else {
            dismiss(animated: true)
            return
        }
        let alert = UIAlertController(
            title: "Account Changed",
            message: MessageForwardingError.accountChanged.localizedDescription,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: "Close", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func applyClassicNavigationAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = .clear
        appearance.shadowColor = .separator
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.compactScrollEdgeAppearance = appearance
        navigationController?.navigationBar.isTranslucent = true
    }

    @objc private func cancelPressed() {
        guard !isSending else { return }
        queryGeneration &+= 1
        queryTask?.cancel()
        preparationTask?.cancel()
        dismiss(animated: true)
    }
}

// MARK: - ForwardDestinationCell

private final class ForwardDestinationCell: UITableViewCell {
    static let reuseID = "ForwardDestinationCell"

    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let labels = UIStackView()
    private let selectionIndicator = MessageSelectionIndicatorView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        isAccessibilityElement = true
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(
        chat: Chat,
        subtitle: String,
        selected: Bool,
        enabled: Bool,
        client: TDLibClient,
    ) {
        titleLabel.text = chat.title
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = enabled ? .secondaryLabel : .systemRed
        selectionIndicator.setSelected(selected)
        selectionIndicator.layer.borderColor = (selected ? UIColor.systemBlue : UIColor.tertiaryLabel).cgColor
        selectionIndicator.layer.borderWidth = selected ? 0 : 1.5
        selectionIndicator.layer.cornerRadius = 11
        selectionIndicator.alpha = enabled ? 1 : 0.3
        contentView.alpha = enabled ? 1 : 0.62
        isUserInteractionEnabled = enabled
        accessibilityLabel = "\(chat.title), \(subtitle)"
        accessibilityValue = selected ? "Selected" : nil
        accessibilityTraits = selected ? [.button, .selected] : [.button]

        let peerID =
            switch chat.type {
            case .chatTypePrivate(let privateChat):
                privateChat.userId
            case .chatTypeSecret(let secretChat):
                secretChat.userId
            case .chatTypeBasicGroup, .chatTypeSupergroup:
                chat.id
            }
        let firstLetter = chat.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0).uppercased() }
        avatarView.configure(
            file: chat.photo?.small,
            minithumbnail: chat.photo?.minithumbnail,
            placeholder: TelegramAvatarPlaceholder(
                peerID: peerID,
                accentColorID: chat.accentColorId,
                upgradedGiftColors: chat.upgradedGiftColors,
                letters: firstLetter.map { [$0] } ?? [],
                isDeleted: false,
            ),
            client: client,
        )
    }

    private func configureViews() {
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.spacing = 2
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold))
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.isAccessibilityElement = false
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.numberOfLines = 1
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.isAccessibilityElement = false
        labels.addArrangedSubview(titleLabel)
        labels.addArrangedSubview(subtitleLabel)
        contentView.addSubview(labels)

        selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(selectionIndicator)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
            avatarView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 48),
            avatarView.heightAnchor.constraint(equalToConstant: 48),
            labels.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: selectionIndicator.leadingAnchor, constant: -10),
            selectionIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            selectionIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectionIndicator.widthAnchor.constraint(equalToConstant: 22),
            selectionIndicator.heightAnchor.constraint(equalToConstant: 22),
        ])
    }
}

// MARK: - ForwardDestinationToolbar

final class ForwardDestinationToolbar: UIView {
    static let contentHeight: CGFloat = 56

    var onSend: (() -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let summaryLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(selectedCount: Int, messageCount: Int, isSending: Bool) {
        if isSending {
            summaryLabel.text = "Forwarding…"
        } else if selectedCount == 0 {
            summaryLabel.text = messageCount == 1 ? "1 message" : "\(messageCount) messages"
        } else {
            let chats = selectedCount == 1 ? "1 chat" : "\(selectedCount) chats"
            let messages = messageCount == 1 ? "1 message" : "\(messageCount) messages"
            summaryLabel.text = "\(messages) · \(chats)"
        }
        sendButton.isEnabled = selectedCount > 0 && !isSending
        sendButton.alpha = 1
        spinner.isHidden = !isSending
        if isSending {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

    private func configureViews() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = .preferredFont(forTextStyle: .subheadline)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.adjustsFontForContentSizeCategory = true
        addSubview(summaryLabel)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Forward"
        configuration.image = UIImage(
            systemName: "arrow.up",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold),
        )
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 14)
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white
        sendButton.configuration = configuration
        sendButton.addTarget(self, action: #selector(sendPressed), for: .touchUpInside)
        addSubview(sendButton)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        addSubview(spinner)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
            summaryLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            summaryLabel.topAnchor.constraint(equalTo: topAnchor),
            summaryLabel.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            sendButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            sendButton.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            sendButton.heightAnchor.constraint(equalToConstant: 42),
            summaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: spinner.leadingAnchor, constant: -10),
            spinner.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10),
            spinner.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
        ])
    }

    @objc private func sendPressed() {
        onSend?()
    }
}

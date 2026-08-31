// ForwardMessagesViewController.swift

import Combine
import TDLibKitDynamic
import UIKit

// MARK: - ForwardMessagesViewController

@MainActor final class ForwardMessagesViewController: UIViewController, UITableViewDelegate,
    UISearchResultsUpdating
{
    private enum Section {
        case chats
    }

    private struct DeliveryFailure {
        let chatID: Int64
        let description: String
        let retryable: Bool
    }

    var onFinished: ((Int) -> Void)?

    private let request: MessageForwardRequest
    private let client: TDLibClient
    private let accountID: UUID
    private let seedChats: [Chat]
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let actionToolbar = ForwardDestinationToolbar()
    private let searchController = UISearchController(searchResultsController: nil)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var actionToolbarHeightConstraint: NSLayoutConstraint!
    private var dataSource: UITableViewDiffableDataSource<Section, Int64>!
    private var chatsByID = [Int64: Chat]()
    private var eligibilityByChatID = [Int64: MessageForwardDestinationEligibility]()
    private var visibleChatIDs = [Int64]()
    private var selectedChatIDs = Set<Int64>()
    private var preparedForward: PreparedMessageForward?
    private var mode = MessageForwardMode.forward
    private var queryGeneration = UInt64.zero
    private var queryTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var accountCancellable: AnyCancellable?
    private var isSending = false

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
        configureToolbar()
        observeAccount()
        for chat in seedChats {
            chatsByID[chat.id] = chat
        }
        prepareMessages()
        loadChats(query: "")
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        actionToolbarHeightConstraint?.constant =
            ForwardDestinationToolbar.contentHeight + view.safeAreaInsets.bottom
    }

    func updateSearchResults(for searchController: UISearchController) {
        loadChats(query: searchController.searchBar.text ?? "")
    }

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isSending,
              preparedForward != nil,
              let chatID = dataSource.itemIdentifier(for: indexPath),
              eligibilityByChatID[chatID]?.isAllowed == true
        else { return }
        if selectedChatIDs.contains(chatID) {
            selectedChatIDs.remove(chatID)
        } else {
            selectedChatIDs.insert(chatID)
        }
        reconfigure(chatIDs: [chatID])
        updateToolbar()
    }

    private func configureNavigation() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelPressed),
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Options",
            image: UIImage(systemName: "ellipsis.circle"),
            primaryAction: nil,
            menu: UIMenu(children: []),
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "Search Chats"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = 62
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0)
        tableView.register(ForwardDestinationCell.self, forCellReuseIdentifier: ForwardDestinationCell.reuseID)
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
                selected: selectedChatIDs.contains(chatID),
                enabled: eligibility?.isAllowed == true,
                client: client,
            )
            return cell
        }
    }

    private func configureToolbar() {
        actionToolbar.translatesAutoresizingMaskIntoConstraints = false
        actionToolbar.onSend = { [weak self] in
            self?.sendSelected()
        }
        view.addSubview(actionToolbar)
        actionToolbarHeightConstraint = actionToolbar.heightAnchor.constraint(
            equalToConstant: ForwardDestinationToolbar.contentHeight + view.safeAreaInsets.bottom,
        )
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: actionToolbar.topAnchor),
            actionToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            actionToolbarHeightConstraint,
        ])
        updateToolbar()
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
                rebuildEligibility()
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
        queryTask = Task { [weak self] in
            guard let self else { return }
            if !query.isEmpty {
                try? await Task<Never, Never>.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            var ids = seedChatIDs(matching: query)
            if query.isEmpty {
                if let recent = try? await client.searchChats(limit: 50, query: "", typeFilter: nil) {
                    ids.append(contentsOf: recent.chatIds)
                }
                if let main = try? await client.getChats(chatList: .chatListMain, limit: 100) {
                    ids.append(contentsOf: main.chatIds)
                }
                if let archive = try? await client.getChats(chatList: .chatListArchive, limit: 100) {
                    ids.append(contentsOf: archive.chatIds)
                }
                await hydrateAndApply(ids: ids, generation: generation)
            } else {
                if let offline = try? await client.searchChats(limit: 50, query: query, typeFilter: nil) {
                    ids.insert(contentsOf: offline.chatIds, at: 0)
                }
                await hydrateAndApply(ids: ids, generation: generation)
                guard !Task.isCancelled,
                      generation == queryGeneration,
                      contextIsCurrent
                else { return }
                if let server = try? await client.searchChatsOnServer(
                    limit: 50,
                    query: query,
                    typeFilter: nil,
                ) {
                    ids.append(contentsOf: server.chatIds)
                    await hydrateAndApply(ids: ids, generation: generation)
                }
            }
        }
    }

    private func hydrateAndApply(
        ids: [Int64],
        generation: UInt64,
    ) async {
        let uniqueIDs = deduplicated(ids)
        for chatID in uniqueIDs where chatsByID[chatID] == nil {
            guard !Task.isCancelled else { return }
            if let chat = try? await client.getChat(chatId: chatID) {
                chatsByID[chatID] = chat
            }
        }
        guard !Task.isCancelled,
              generation == queryGeneration,
              contextIsCurrent
        else { return }
        let hydratedIDs = uniqueIDs.filter { chatsByID[$0] != nil }
        apply(chatIDs: prioritizeSavedMessages(hydratedIDs))
    }

    private func apply(chatIDs: [Int64]) {
        visibleChatIDs = chatIDs
        rebuildEligibility()
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.chats])
        snapshot.appendItems(chatIDs)
        dataSource.apply(snapshot, animatingDifferences: true)
        updateBackgroundView()
    }

    private func rebuildEligibility() {
        guard let preparedForward else { return }
        var updated = [Int64: MessageForwardDestinationEligibility]()
        for chatID in visibleChatIDs {
            guard let chat = chatsByID[chatID] else { continue }
            updated[chatID] = MessageForwardingService.localEligibility(
                of: chat,
                for: preparedForward,
            )
        }
        eligibilityByChatID.merge(updated, uniquingKeysWith: { _, new in new })
        let invalidSelection = selectedChatIDs.filter { updated[$0]?.isAllowed == false }
        selectedChatIDs.subtract(invalidSelection)
        reconfigure(chatIDs: visibleChatIDs)
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
        navigationItem.rightBarButtonItem?.menu = UIMenu(title: "Forward Options", children: actions)
        navigationItem.rightBarButtonItem?.isEnabled = actions.count > 1 && !isSending
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
              !selectedChatIDs.isEmpty,
              contextIsCurrent
        else { return }
        isSending = true
        isModalInPresentation = true
        searchController.searchBar.isUserInteractionEnabled = false
        navigationItem.leftBarButtonItem?.isEnabled = false
        configureOptionsMenu()
        updateToolbar()
        let destinations = selectedChatIDs.sorted()
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            var failures = [DeliveryFailure]()
            var completedCount = 0
            for chatID in destinations {
                guard !Task.isCancelled else { break }
                guard contextIsCurrent else {
                    failures.append(DeliveryFailure(
                        chatID: chatID,
                        description: MessageForwardingError.accountChanged.localizedDescription,
                        retryable: true,
                    ))
                    continue
                }
                do {
                    _ = try await MessageForwardingService.send(
                        preparedForward,
                        to: chatID,
                        mode: mode,
                        client: client,
                        accountID: accountID,
                    )
                    completedCount += 1
                    selectedChatIDs.remove(chatID)
                } catch is DecodingError {
                    selectedChatIDs.remove(chatID)
                    failures.append(DeliveryFailure(
                        chatID: chatID,
                        description: "TDLib returned an ambiguous partial result.",
                        retryable: false,
                    ))
                } catch let error as MessageForwardingError {
                    let retryable: Bool
                    if case .partialDelivery = error {
                        retryable = false
                        selectedChatIDs.remove(chatID)
                    } else {
                        retryable = true
                    }
                    failures.append(DeliveryFailure(
                        chatID: chatID,
                        description: error.localizedDescription,
                        retryable: retryable,
                    ))
                } catch {
                    failures.append(DeliveryFailure(
                        chatID: chatID,
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
        searchController.searchBar.isUserInteractionEnabled = true
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
            let title = chatsByID[failure.chatID]?.title ?? "Chat"
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
            selectedCount: selectedChatIDs.count,
            messageCount: request.messageIDs.count,
            isSending: isSending,
        )
    }

    private func updateBackgroundView() {
        if preparedForward == nil {
            activityIndicator.startAnimating()
            tableView.backgroundView = activityIndicator
        } else if visibleChatIDs.isEmpty {
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

    @objc private func cancelPressed() {
        guard !isSending else { return }
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
        client _: TDLibClient,
    ) {
        titleLabel.text = chat.title
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = enabled ? .secondaryLabel : .systemRed
        selectionIndicator.setSelected(selected)
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
        )
    }

    private func configureViews() {
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.spacing = 2
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.isAccessibilityElement = false
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.numberOfLines = 1
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.isAccessibilityElement = false
        labels.addArrangedSubview(titleLabel)
        labels.addArrangedSubview(subtitleLabel)
        contentView.addSubview(labels)

        selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(selectionIndicator)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 44),
            avatarView.heightAnchor.constraint(equalToConstant: 44),
            labels.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: selectionIndicator.leadingAnchor, constant: -10),
            selectionIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            selectionIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectionIndicator.widthAnchor.constraint(equalToConstant: 28),
            selectionIndicator.heightAnchor.constraint(equalToConstant: 28),
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
        sendButton.alpha = sendButton.isEnabled ? 1 : 0.35
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
        sendButton.setTitle("Forward", for: .normal)
        sendButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
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
            sendButton.topAnchor.constraint(equalTo: topAnchor),
            sendButton.heightAnchor.constraint(equalToConstant: Self.contentHeight),
            summaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: spinner.leadingAnchor, constant: -10),
            spinner.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10),
            spinner.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
        ])
    }

    @objc private func sendPressed() {
        onSend?()
    }
}

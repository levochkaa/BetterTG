// ChatFolderInviteLinks.swift

import TDLibKit
import UIKit

// MARK: - ChatFolderInviteLinkPreviewViewController

/// Telegram's ChatFolderLinkPreviewScreen for an `addlist` link and for a shared folder's new chats: the chats to
/// join with checkmarks, the ones already joined kept and tinted, and Add Folder or Join Chats. Requests run on the
/// active client and stop once the screen's scope is not current.
final class ChatFolderInviteLinkPreviewViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    struct Content {
        enum Action {
            /// `addChatFolderByInviteLink`: adds the link's folder, or the chosen chats to the user's copy of it.
            case addByLink(String)
            /// `processChatFolderNewChats`: joins chats the owner added to a shared folder the user has.
            case addNewChats(folderID: Int)
        }

        let folderTitle: String
        /// The user's folder for this link, or nil when the link adds a new one.
        let existingFolderID: Int?
        let chatIDs: [Int64]
        /// Chats already joined; a new folder lists them selected and tinted.
        let joinedChatIDs: Set<Int64>
        let action: Action
    }

    private struct Item {
        let id: Int64
        let title: String
        let subtitle: String?
        let isChannel: Bool
    }

    // MARK: Private

    private static let headerIdentifier = "ChatFolderInviteHeader"
    private static let cellIdentifier = "ChatFolderInviteCell"

    var onFinished: (() -> Void)?

    private let content: Content
    private let authority = ChatListActionAuthority()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let actionButton = UIButton(configuration: .filled())
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var items = [Item]()
    private var selectedIDs: Set<Int64>
    private var isJoining = false

    /// Telegram's allChatsAdded: the user's folder already has every chat of the link.
    private var allChatsAdded: Bool { content.existingFolderID != nil && content.chatIDs.isEmpty }
    private var joiningCount: Int { selectedIDs.subtracting(content.joinedChatIDs).count }

    init(content: Content) {
        self.content = content
        self.selectedIDs = Set(content.chatIDs)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = content.existingFolderID == nil || allChatsAdded
            ? L10n.telegram("FolderLinkPreview.TitleAddFolder")
            : L10n.telegramPlural("FolderLinkPreview.TitleAddChats", count: content.chatIDs.count)
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"), style: .plain, target: self, action: #selector(cancel),
        )

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ChatFolderLeaveHeaderView.self, forHeaderFooterViewReuseIdentifier: Self.headerIdentifier)
        tableView.tableHeaderView = descriptionView()
        view.addSubview(tableView)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.configuration?.cornerStyle = .large
        actionButton.configuration?.baseBackgroundColor = .systemBlue
        actionButton.configuration?.baseForegroundColor = .white
        actionButton.configuration?.imagePlacement = .trailing
        actionButton.configuration?.imagePadding = 8
        actionButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 17, weight: .semibold)
            return attributes
        }
        actionButton.addTarget(self, action: #selector(performAction), for: .touchUpInside)
        view.addSubview(actionButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -12),
            actionButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
        updateActionButton()
        loadItems()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView, tableView.bounds.width > 0 else { return }
        let height = header.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        .height
        guard header.frame.width != tableView.bounds.width || header.frame.height != height else { return }
        header.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: height)
        tableView.tableHeaderView = header
    }

    /// OpenResolvedUrl's `.chatFolder`: the link is checked before anything shows; one TDLib rejects has expired.
    static func present(inviteLink: String, from presenter: UIViewController) {
        let authority = ChatListActionAuthority()
        let scope = authority.scope(owner: presenter)
        let client = authority.client
        Task { @MainActor [weak presenter] in
            do {
                let info = try await scope.perform {
                    try await client.send(TDNativeRequests.checkChatFolderInviteLink(inviteLink: inviteLink))
                }
                guard let presenter else { return }
                let folder = info.chatFolderInfo
                let existingID: Int? = folder.id == 0 ? nil : folder.id
                let content = Content(
                    folderTitle: folder.name.text.text,
                    existingFolderID: existingID,
                    chatIDs: existingID == nil ? info.missingChatIds + info.addedChatIds : info.missingChatIds,
                    joinedChatIDs: existingID == nil ? Set(info.addedChatIds) : [],
                    action: .addByLink(inviteLink),
                )
                presenter.chatListTopPresenter.present(
                    TelegramNavigationController(
                        rootViewController: ChatFolderInviteLinkPreviewViewController(content: content),
                    ),
                    animated: true,
                )
            } catch {
                guard scope.isCurrent, let presenter else { return }
                let alert = UIAlertController(
                    title: nil,
                    message: L10n.telegram("Chat.ErrorFolderLinkExpired"),
                    preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
                presenter.chatListTopPresenter.present(alert, animated: true)
            }
        }
    }

    func numberOfSections(in _: UITableView) -> Int { allChatsAdded ? 0 : 1 }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: Self.cellIdentifier)
        let item = items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        configureCheckmark(cell, for: item)
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection _: Int) -> UIView? {
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: Self.headerIdentifier)
            as? ChatFolderLeaveHeaderView
        configure(header)
        return header
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isJoining else { return }
        let item = items[indexPath.row]
        // A chat the user is in stays: Telegram says so instead of deselecting it.
        if content.joinedChatIDs.contains(item.id) {
            TelegramUndoToast.show(
                text: L10n.telegram(item.isChannel
                    ? "FolderLinkPreview.ToastAlreadyMemberChannel"
                    : "FolderLinkPreview.ToastAlreadyMemberGroup"),
                in: view,
                bottomInset: 74,
                undo: nil,
            )
            return
        }
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
        if let cell = tableView.cellForRow(at: indexPath) { configureCheckmark(cell, for: item) }
        selectionDidChange()
    }

    private func configureCheckmark(_ cell: UITableViewCell, for item: Item) {
        cell.accessoryType = selectedIDs.contains(item.id) ? .checkmark : .none
        cell.tintColor = content.joinedChatIDs.contains(item.id) ? .systemGray : nil
    }

    private func configure(_ header: ChatFolderLeaveHeaderView?) {
        header?.configure(
            title: L10n.telegramPlural("FolderLinkPreview.ChatSectionJoinHeader", count: content.chatIDs.count),
            actionTitle: items.count > 1
                ? ChatFolderLeaveChatsViewController.selectAllTitle(allSelected: selectedIDs.count == items.count)
                : nil,
        ) { [weak self] in
            self?.toggleAllSelection()
        }
    }

    /// Telegram selects every chat, or else keeps only the ones already joined.
    private func toggleAllSelection() {
        guard !isJoining else { return }
        selectedIDs =
            if selectedIDs.count != items.count {
                Set(items.map(\.id))
            } else {
                content.joinedChatIDs
            }
        for cell in tableView.visibleCells {
            guard let indexPath = tableView.indexPath(for: cell) else { continue }
            configureCheckmark(cell, for: items[indexPath.row])
        }
        selectionDidChange()
    }

    private func selectionDidChange() {
        configure(tableView.headerView(forSection: 0) as? ChatFolderLeaveHeaderView)
        updateActionButton()
    }

    /// Telegram's action button: Add Folder, Join Chats with the count to join as its badge, Do Not Join Any Chats,
    /// or OK when the folder already has every chat.
    private func updateActionButton() {
        let joining = joiningCount
        let key =
            if allChatsAdded {
                "Common.OK"
            } else if content.existingFolderID == nil {
                "FolderLinkPreview.ButtonAddFolder"
            } else if joining == 0 {
                "FolderLinkPreview.ButtonDoNotJoinChats"
            } else {
                "FolderLinkPreview.ButtonJoinChats"
            }
        actionButton.configuration?.title = L10n.telegram(key)
        actionButton.configuration?.image = !allChatsAdded && joining > 0
            ? ChatFolderLeaveChatsViewController.badgeImage(joining)
            : nil
        actionButton.configuration?.showsActivityIndicator = isJoining
        actionButton.isEnabled = !isJoining && (content.existingFolderID != nil || !selectedIDs.isEmpty)
    }

    private func descriptionView() -> UIView {
        let text =
            if allChatsAdded {
                L10n.telegram("FolderLinkPreview.TextAllAdded")
            } else if content.existingFolderID == nil {
                L10n.telegram("FolderLinkPreview.TextAddFolder")
            } else {
                L10n.telegram("FolderLinkPreview.TextAddChatsV2")
                    .replacingOccurrences(of: "{folder}", with: content.folderTitle)
                    .replacingOccurrences(
                        of: "{chats}",
                        with: L10n.telegramPlural("FolderLinkPreview.TextAddChatsCount", count: content.chatIDs.count),
                    )
            }
        let container = UIView()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        return container
    }

    /// The link's chats with Telegram's labels: already a member or subscriber, or the member count.
    private func loadItems() {
        let client = authority.client
        let ids = content.chatIDs
        let joinedIDs = content.joinedChatIDs
        guard !ids.isEmpty else { return }
        spinner.startAnimating()
        tableView.backgroundView = spinner
        Task { [weak self] in
            var loaded = [Item]()
            for id in ids {
                guard !Task.isCancelled, let chat = try? await client.getChat(chatId: id) else { continue }
                var isChannel = false
                var memberCount = 0
                switch chat.type {
                case .chatTypeSupergroup(let type):
                    isChannel = type.isChannel
                    memberCount = await (try? client.getSupergroup(supergroupId: type.supergroupId))?.memberCount ?? 0
                case .chatTypeBasicGroup(let type):
                    memberCount = await (try? client.getBasicGroup(basicGroupId: type.basicGroupId))?.memberCount ?? 0
                default:
                    break
                }
                let subtitle: String? =
                    if joinedIDs.contains(id) {
                        L10n.telegram(isChannel
                            ? "FolderLinkPreview.LabelPeerSubscriber"
                            : "FolderLinkPreview.LabelPeerMember")
                    } else if memberCount > 0 {
                        L10n.telegramPlural(
                            isChannel ? "FolderLinkPreview.LabelPeerSubscribers" : "FolderLinkPreview.LabelPeerMembers",
                            count: memberCount,
                        )
                    } else {
                        nil
                    }
                let title = chat.title.trimmingCharacters(in: .whitespacesAndNewlines)
                loaded.append(Item(
                    id: id,
                    title: !title.isEmpty
                        ? title
                        : L10n.betterTG(isChannel ? "Folders.UntitledChannel" : "Folders.UntitledGroup"),
                    subtitle: subtitle,
                    isChannel: isChannel,
                ))
            }
            guard let self, authority.isCurrent else { return }
            items = loaded
            // Only the chats the user saw are joined.
            selectedIDs.formIntersection(loaded.map(\.id))
            spinner.stopAnimating()
            tableView.backgroundView = nil
            tableView.reloadData()
            updateActionButton()
        }
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func performAction() {
        guard !isJoining else { return }
        if allChatsAdded {
            dismiss(animated: true)
            return
        }
        let selected = items.map(\.id).filter(selectedIDs.contains)
        let joining = joiningCount
        let action = content.action
        // An existing folder with nothing chosen keeps the link's chats out, as Telegram's guard does.
        if case .addByLink = action, content.existingFolderID != nil, selected.isEmpty {
            dismiss(animated: true)
            return
        }
        let scope = authority.scope(owner: self)
        let client = authority.client
        isJoining = true
        updateActionButton()
        Task { [weak self] in
            do {
                try await scope.perform {
                    _ =
                        switch action {
                        case .addByLink(let link):
                            try await client.send(TDNativeRequests.addChatFolderByInviteLink(
                                inviteLink: link,
                                chatIds: selected,
                            ))
                        case .addNewChats(let folderID):
                            // No chosen chats still marks the new chats as seen, as Telegram's hideChatFolderUpdates.
                            try await client.send(TDNativeRequests.processChatFolderNewChats(
                                chatFolderId: folderID,
                                addedChatIds: selected,
                            ))
                        }
                }
                guard let self else { return }
                finish(joining: joining)
            } catch {
                guard let self, scope.isCurrent else { return }
                isJoining = false
                updateActionButton()
                let alert = UIAlertController(
                    title: nil,
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                    preferredStyle: .alert,
                )
                alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    /// Telegram's toasts: Folder Added, with the chats also joined, or Folder Updated with the chats joined.
    private func finish(joining: Int) {
        let folder = content.folderTitle
        let text: String? =
            if content.existingFolderID == nil {
                L10n.telegram("FolderLinkPreview.ToastFolderAddedTitleV2").replacingOccurrences(
                    of: "{folder}",
                    with: folder,
                )
                    + (joining > 0
                        ? "\n" + L10n.telegramPlural("FolderLinkPreview.ToastFolderAddedText", count: joining)
                        : "")
            } else if joining > 0 {
                L10n.telegram("FolderLinkPreview.ToastChatsAddedTitleV2").replacingOccurrences(
                    of: "{folder}",
                    with: folder,
                )
                    + "\n" + L10n.telegramPlural("FolderLinkPreview.ToastChatsAddedText", count: joining)
            } else {
                nil
            }
        let host = presentingViewController?.view
        let onFinished = onFinished
        dismiss(animated: true) {
            onFinished?()
            if let text, let host { TelegramUndoToast.show(text: text, in: host, bottomInset: 8, undo: nil) }
        }
    }
}

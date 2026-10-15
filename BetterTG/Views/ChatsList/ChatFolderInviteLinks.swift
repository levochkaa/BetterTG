// ChatFolderInviteLinks.swift

import Combine
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

    /// Called after the request succeeds, with the chats added to the folder.
    var onFinished: (([Int64]) -> Void)?

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
                finish(joining: joining, added: selected)
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
    private func finish(joining: Int, added: [Int64]) {
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
            onFinished?(added)
            if let text, let host { TelegramUndoToast.show(text: text, in: host, bottomInset: 8, undo: nil) }
        }
    }
}

// MARK: - ChatFolderInviteLinkActions

/// Copy and Share for a folder invite link, as in Telegram's link menus and buttons.
@MainActor enum ChatFolderInviteLinkActions {
    static func copy(_ link: String, in controller: UIViewController) {
        UIPasteboard.setPlainText(link)
        TelegramUndoToast.show(
            text: L10n.telegram("InviteLink.InviteLinkCopiedText"),
            in: controller.navigationController?.view ?? controller.view,
            bottomInset: 8,
            undo: nil,
        )
    }

    static func share(_ link: String, from controller: UIViewController, sourceView: UIView?) {
        guard let url = URL(string: link) else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = sourceView ?? controller.view
        controller.present(activity, animated: true)
    }

    /// A link as Telegram lists it: its name, or else the link without its scheme.
    static func title(of link: TDNativeChatFolderInviteLink) -> String {
        link.name.isEmpty ? link.inviteLink.replacingOccurrences(of: "https://", with: "") : link.name
    }
}

// MARK: - ChatFolderInviteLinkViewController

/// Telegram's FolderInviteLinkListController for one link: the folder's chats with the shareable ones checked, the
/// link with Copy and Share, and Name Link, Copy and Revoke in the link's menu. Done saves the name and chats with
/// `editChatFolderInviteLink`; Back with unsaved changes asks to apply or discard them.
final class ChatFolderInviteLinkViewController: UITableViewController, TelegramNavigationAttemptHandling {
    private enum Section {
        case link
        case chats
    }

    private enum LinkRow: CaseIterable {
        case link
        case copy
        case share
    }

    private struct Item {
        let id: Int64
        let title: String
        let subtitle: String
        /// Telegram's explanation for a chat the link can't share; nil for a shareable one.
        let unavailableText: String?
    }

    // MARK: Private

    private static let headerIdentifier = "ChatFolderInviteLinkHeader"
    private static let cellIdentifier = "ChatFolderInviteLinkCell"

    /// The saved link, or nil once it is revoked.
    var onChange: ((TDNativeChatFolderInviteLink?) -> Void)?

    private let session: FolderFlowSession
    private let client: TDLibClient
    private let folderID: Int
    private let folderTitle: String
    private let folderChatIDs: [Int64]
    private let shareableChatIDs: Set<Int64>
    private let descriptionLabel = UILabel()
    private var link: TDNativeChatFolderInviteLink
    private var name: String
    private var selectedIDs: Set<Int64>
    private var items = [Item]()
    private var isSaving = false
    private var didShowNewChatNotice = false
    private var sessionObservation: AnyCancellable?

    private var hasChanges: Bool { name != link.name || selectedIDs != Set(link.chatIds) }
    /// The link section shows only when the folder has a chat the user may share.
    private var sections: [Section] { shareableChatIDs.isEmpty ? [.chats] : [.link, .chats] }

    private var descriptionText: String {
        if shareableChatIDs.isEmpty { return L10n.telegram("FolderLinkScreen.TitleDescriptionUnavailable") }
        if selectedIDs.isEmpty {
            return L10n.telegram("FolderLinkScreen.TitleDescriptionDeselectedV2")
                .replacingOccurrences(of: "{folder}", with: folderTitle)
        }
        return L10n.telegram("FolderLinkScreen.TitleDescriptionSelectedV2")
            .replacingOccurrences(of: "{folder}", with: folderTitle)
            .replacingOccurrences(
                of: "{chats}",
                with: L10n.telegramPlural("FolderLinkScreen.TitleDescriptionSelectedCount", count: selectedIDs.count),
            )
    }

    init(
        session: FolderFlowSession,
        client: TDLibClient,
        folderID: Int,
        folderTitle: String,
        folderChatIDs: [Int64],
        shareableChatIDs: Set<Int64>,
        link: TDNativeChatFolderInviteLink,
    ) {
        self.session = session
        self.client = client
        self.folderID = folderID
        self.folderTitle = folderTitle
        self.folderChatIDs = folderChatIDs
        self.shareableChatIDs = shareableChatIDs
        self.link = link
        self.name = link.name
        self.selectedIDs = Set(link.chatIds)
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .prominent, target: self, action: #selector(saveLink),
        )
        tableView.register(ChatFolderLeaveHeaderView.self, forHeaderFooterViewReuseIdentifier: Self.headerIdentifier)
        tableView.tableHeaderView = descriptionView()
        sessionObservation = session.bind(self) { [weak self] in self?.updateChrome() }
        updateChrome()
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

    override func numberOfSections(in _: UITableView) -> Int { sections.count }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .link: LinkRow.allCases.count
        case .chats: items.count
        }
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section] == .link ? L10n.telegram("FolderLinkScreen.LinkSectionHeader") : nil
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard sections[section] == .chats else { return nil }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: Self.headerIdentifier)
            as? ChatFolderLeaveHeaderView
        configure(header)
        return header
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: Self.cellIdentifier)
        cell.imageView?.image = nil
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.detailTextLabel?.text = nil
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.textLabel?.textColor = .label
        switch sections[indexPath.section] {
        case .link:
            switch LinkRow.allCases[indexPath.row] {
            case .link:
                cell.textLabel?.text = link.inviteLink.replacingOccurrences(of: "https://", with: "")
                cell.accessoryView = UIImageView(image: UIImage(systemName: "ellipsis.circle"))
            case .copy:
                cell.textLabel?.text = L10n.telegram("FolderLinkScreen.LinkActionCopy")
                cell.textLabel?.textColor = .systemBlue
                cell.imageView?.image = UIImage(systemName: "doc.on.doc")
            case .share:
                cell.textLabel?.text = L10n.telegram("FolderLinkScreen.LinkActionShare")
                cell.textLabel?.textColor = .systemBlue
                cell.imageView?.image = UIImage(systemName: "square.and.arrow.up")
            }
        case .chats:
            let item = items[indexPath.row]
            cell.textLabel?.text = item.title
            cell.detailTextLabel?.text = item.subtitle
            if item.unavailableText != nil {
                cell.textLabel?.textColor = .secondaryLabel
            } else {
                cell.accessoryType = selectedIDs.contains(item.id) ? .checkmark : .none
            }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isSaving, session.scope(owner: self).isCurrent else { return }
        switch sections[indexPath.section] {
        case .link:
            switch LinkRow.allCases[indexPath.row] {
            case .link:
                guard let cell = tableView.cellForRow(at: indexPath) else { return }
                presentLinkMenu(from: cell)
            case .copy:
                ChatFolderInviteLinkActions.copy(link.inviteLink, in: self)
            case .share:
                ChatFolderInviteLinkActions.share(
                    link.inviteLink,
                    from: self,
                    sourceView: tableView.cellForRow(at: indexPath),
                )
            }
        case .chats:
            toggle(items[indexPath.row], at: indexPath)
        }
    }

    /// FolderInviteLinkListController's labels and alerts for a chat a folder link can't share.
    private static func unavailableTexts(for chat: Chat, client: TDLibClient) async -> (label: String, alert: String) {
        let userID: Int64? =
            switch chat.type {
            case .chatTypePrivate(let type): type.userId
            case .chatTypeSecret(let type): type.userId
            case .chatTypeBasicGroup, .chatTypeSupergroup: nil
            }
        if let userID {
            let user = try? await client.getUser(userId: userID)
            let isBot =
                if let user, case .userTypeBot = user.type {
                    true
                } else { false }
            return isBot
                ? (
                    L10n.telegram("FolderLinkScreen.LabelUnavailableBot"),
                    L10n.telegram("FolderLinkScreen.AlertTextUnavailableBot"),
                )
                : (
                    L10n.telegram("FolderLinkScreen.LabelUnavailableUser"),
                    L10n.telegram("FolderLinkScreen.AlertTextUnavailableUser"),
                )
        }
        var alertKey = "FolderLinkScreen.AlertTextUnavailablePrivateGroup"
        if case .chatTypeSupergroup(let type) = chat.type {
            let group = try? await client.getSupergroup(supergroupId: type.supergroupId)
            let isPublic = group?.usernames?.activeUsernames.isEmpty == false
            alertKey =
                switch (type.isChannel, isPublic) {
                case (true, true): "FolderLinkScreen.AlertTextUnavailablePublicChannel"
                case (true, false): "FolderLinkScreen.AlertTextUnavailablePrivateChannel"
                case (false, true): "FolderLinkScreen.AlertTextUnavailablePublicGroup"
                case (false, false): "FolderLinkScreen.AlertTextUnavailablePrivateGroup"
                }
        }
        return (L10n.telegram("FolderLinkScreen.LabelUnavailableGeneric"), L10n.telegram(alertKey))
    }

    /// ChatListFilterPresetController's attemptNavigation for a link: unsaved changes are applied or discarded.
    func attemptNavigation() -> Bool {
        guard hasChanges, !isSaving else { return true }
        guard presentedViewController == nil else { return false }
        let alert = UIAlertController(
            title: L10n.telegram("FolderLinkScreen.SaveAlertTitle"),
            message: L10n.telegram("FolderLinkScreen.SaveAlertText"),
            preferredStyle: .alert,
        )
        alert
            .addAction(UIAlertAction(title: L10n.telegram("FolderLinkScreen.SaveAlertActionDiscard"), style: .default) {
                [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            })
        // A link must keep a chat, so with none chosen the user stays to choose one.
        if selectedIDs.isEmpty {
            alert.addAction(UIAlertAction(
                title: L10n.telegram("FolderLinkScreen.SaveAlertActionContinue"),
                style: .cancel,
            ))
        } else {
            let apply = UIAlertAction(title: L10n.telegram("FolderLinkScreen.SaveAlertActionApply"), style: .default) {
                [weak self] _ in
                self?.saveLink()
            }
            alert.addAction(apply)
            alert.preferredAction = apply
        }
        present(alert, animated: true)
        return false
    }

    private func toggle(_ item: Item, at indexPath: IndexPath) {
        if let unavailableText = item.unavailableText {
            let alert = UIAlertController(title: nil, message: unavailableText, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
            present(alert, animated: true)
            return
        }
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
            // Telegram tells once that people who used the link can join a chat added to it.
            if !link.chatIds.contains(item.id), !didShowNewChatNotice {
                didShowNewChatNotice = true
                TelegramUndoToast.show(
                    text: L10n.telegram("FolderLinkScreen.ToastNewChatAdded"),
                    in: navigationController?.view ?? view,
                    bottomInset: 8,
                    undo: nil,
                )
            }
        }
        tableView.cellForRow(at: indexPath)?.accessoryType = selectedIDs.contains(item.id) ? .checkmark : .none
        selectionDidChange()
    }

    private func toggleAllSelection() {
        guard !isSaving else { return }
        let shareable = items.filter { $0.unavailableText == nil }.map(\.id)
        if shareable.allSatisfy(selectedIDs.contains) {
            selectedIDs.subtract(shareable)
        } else {
            selectedIDs.formUnion(shareable)
        }
        tableView.reloadData()
        updateChrome()
    }

    private func selectionDidChange() {
        if let index = sections.firstIndex(of: .chats) {
            configure(tableView.headerView(forSection: index) as? ChatFolderLeaveHeaderView)
        }
        updateChrome()
    }

    private func configure(_ header: ChatFolderLeaveHeaderView?) {
        let title =
            if shareableChatIDs.isEmpty {
                L10n.telegram("FolderLinkScreen.ChatsSectionHeaderUnavailable")
            } else if selectedIDs.isEmpty {
                L10n.telegram("FolderLinkScreen.ChatsSectionHeader")
            } else {
                L10n.telegramPlural("FolderLinkScreen.ChatsSectionHeaderSelected", count: selectedIDs.count)
            }
        let shareable = items.filter { $0.unavailableText == nil }.map(\.id)
        let actionTitle: String? =
            if items.count > 1, !shareable.isEmpty {
                L10n.telegram(shareable.allSatisfy(selectedIDs.contains)
                    ? "FolderLinkScreen.ChatsSectionHeaderActionDeselectAll"
                    : "FolderLinkScreen.ChatsSectionHeaderActionSelectAll")
            } else {
                nil
            }
        header?.configure(title: title, actionTitle: actionTitle) { [weak self] in
            self?.toggleAllSelection()
        }
    }

    private func updateChrome() {
        title = name.isEmpty ? L10n.telegram("FolderLinkScreen.Title") : name
        navigationItem.rightBarButtonItem?.isEnabled = !isSaving && hasChanges && !selectedIDs.isEmpty
            && session.isCurrent
        descriptionLabel.text = descriptionText
        view.setNeedsLayout()
    }

    private func descriptionView() -> UIView {
        let container = UIView()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = .preferredFont(forTextStyle: .subheadline)
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        container.addSubview(descriptionLabel)
        NSLayoutConstraint.activate([
            descriptionLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            descriptionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            descriptionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            descriptionLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        return container
    }

    /// The folder's chats, the shareable ones first, each one TDLib won't share with Telegram's reason.
    private func loadItems() {
        let client = client
        let ids = folderChatIDs
        let shareable = shareableChatIDs
        Task { [weak self] in
            var shareableItems = [Item]()
            var otherItems = [Item]()
            for id in ids {
                guard !Task.isCancelled, let chat = try? await client.getChat(chatId: id) else { continue }
                let trimmed = chat.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = trimmed.isEmpty ? L10n.betterTG("Chat.FallbackChatTitle") : trimmed
                if shareable.contains(id) {
                    shareableItems.append(Item(
                        id: id,
                        title: title,
                        subtitle: L10n.telegram("FolderLinkScreen.LabelCanInvite"),
                        unavailableText: nil,
                    ))
                } else {
                    let texts = await Self.unavailableTexts(for: chat, client: client)
                    otherItems.append(Item(id: id, title: title, subtitle: texts.label, unavailableText: texts.alert))
                }
            }
            guard let self, session.isCurrent else { return }
            items = shareableItems + otherItems
            tableView.reloadData()
        }
    }

    private func presentLinkMenu(from cell: UITableViewCell) {
        presentTelegramContextMenu(sourceView: cell, actions: [
            TelegramContextMenuAction(
                title: L10n.telegram("FolderLinkScreen.ContextActionNameLink"),
                image: UIImage(systemName: "pencil"),
            ) { [weak self] in self?.presentNameEditor() },
            TelegramContextMenuAction(
                title: L10n.telegram("InviteLink.ContextCopy"),
                image: UIImage(systemName: "doc.on.doc"),
            ) { [weak self] in
                guard let self else { return }
                ChatFolderInviteLinkActions.copy(link.inviteLink, in: self)
            },
            TelegramContextMenuAction(
                title: L10n.telegram("InviteLink.ContextRevoke"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
            ) { [weak self] in self?.revokeLink() },
        ])
    }

    /// Telegram's Name This Link prompt, up to 32 characters.
    private func presentNameEditor() {
        let alert = UIAlertController(
            title: L10n.telegram("FolderLinkScreen.NameLink.Title"),
            message: nil,
            preferredStyle: .alert,
        )
        let current = name
        alert.addTextField { field in
            field.text = current
            field.autocapitalizationType = .sentences
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Done"), style: .default) { [
            weak self,
            weak alert,
        ] _ in
            guard let self, let text = alert?.textFields?.first?.text else { return }
            name = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
            updateChrome()
        })
        present(alert, animated: true)
    }

    @objc private func saveLink() {
        guard !isSaving, hasChanges, !selectedIDs.isEmpty else { return }
        let scope = session.scope(owner: self)
        guard scope.isCurrent else { return }
        let ordered = items.map(\.id).filter(selectedIDs.contains)
        let chatIDs = ordered + selectedIDs.subtracting(ordered).sorted()
        let client = client
        let folderID = folderID
        let inviteLink = link.inviteLink
        let name = name
        isSaving = true
        updateChrome()
        Task { [weak self] in
            do {
                let updated = try await scope.perform {
                    try await client.send(TDNativeRequests.editChatFolderInviteLink(
                        chatFolderId: folderID,
                        inviteLink: inviteLink,
                        name: name,
                        chatIds: chatIDs,
                    ))
                }
                guard let self else { return }
                link = updated
                isSaving = false
                onChange?(updated)
                let host = navigationController?.view
                navigationController?.popViewController(animated: true)
                if let host {
                    TelegramUndoToast.show(
                        text: L10n.telegram("FolderLinkScreen.ToastLinkUpdated"),
                        in: host,
                        bottomInset: 8,
                        undo: nil,
                    )
                }
            } catch {
                guard let self, scope.isCurrent else { return }
                isSaving = false
                updateChrome()
                presentLinkError(L10n.telegram("FolderLinkScreen.SaveUnknownError"))
            }
        }
    }

    /// Telegram revokes and deletes the link; TDLib's deleteChatFolderInviteLink does both.
    private func revokeLink() {
        let scope = session.scope(owner: self)
        guard scope.isCurrent else { return }
        let client = client
        let folderID = folderID
        let inviteLink = link.inviteLink
        Task { [weak self] in
            do {
                _ = try await scope.perform {
                    try await client.send(TDNativeRequests.deleteChatFolderInviteLink(
                        chatFolderId: folderID,
                        inviteLink: inviteLink,
                    ))
                }
                guard let self else { return }
                onChange?(nil)
                navigationController?.popViewController(animated: true)
            } catch {
                guard let self, scope.isCurrent else { return }
                presentLinkError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func presentLinkError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }
}

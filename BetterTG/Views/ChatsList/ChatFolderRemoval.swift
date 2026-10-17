// ChatFolderRemoval.swift

import TDLibKit
import UIKit

// MARK: - ChatFolderRemoval

/// Telegram's folder removal (ChatListController.askForFilterRemoval and ChatListFilterPresetListController's
/// removePreset) on TDLib. A folder shared through invite links first warns that its links stop working when it has
/// any, then offers to quit its groups and channels (ChatFolderLinkPreviewScreen with the remove subject), the chats
/// TDLib suggests leaving selected, and removes it behind Telegram's Undo toast; a shared folder without groups or
/// channels is removed at once. Any other folder keeps the plain confirmation. Every request runs on the caller's
/// client and stops once its scope is not current.
@MainActor enum ChatFolderRemoval {
    /// The Undo toast's place: the chat list above its folder picker, or the window when the list isn't showing.
    struct ToastPlacement {
        let host: UIView
        let bottomInset: CGFloat
    }

    /// Brings back a folder and the chats it was leaving once its removal finished or was undone.
    private final class Restoration {
        private var restore: (() -> Void)?

        init(_ restore: @escaping () -> Void) {
            self.restore = restore
        }

        func run() {
            restore?()
            restore = nil
        }
    }

    static func confirm(
        info: ChatFolderInfo,
        folder: ChatFolder,
        from presenter: UIViewController,
        scope: ChatListActionScope,
        client: TDLibClient,
        toastPlacement: @escaping () -> ToastPlacement?,
        remove: @escaping (_ leaveChatIDs: [Int64], _ finished: @escaping () -> Void) -> Void,
        failure: @escaping (any Swift.Error) -> Void,
    ) {
        guard scope.isCurrent, scope.source?.clientID == client.id else { return }
        guard info.isShareable else {
            let alert = UIAlertController(
                title: L10n.telegram("ChatList.RemoveFolderAction"),
                message: L10n.telegram("ChatList.RemoveFolderConfirmation"),
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
            alert.addAction(UIAlertAction(
                title: L10n.telegram("ChatList.RemoveFolderAction"),
                style: .destructive,
            ) { _ in
                guard scope.isCurrent else { return }
                remove([]) {}
            })
            presenter.chatListTopPresenter.present(alert, animated: true)
            return
        }

        let offerChatsToLeave: () -> Void = { [weak presenter] in
            Task { @MainActor [weak presenter] in
                do {
                    let (items, suggestedIDs) = try await leaveCandidates(
                        folderID: info.id, folder: folder, scope: scope, client: client,
                    )
                    guard scope.isCurrent, let presenter else { return }
                    guard !items.isEmpty else {
                        remove([]) {}
                        return
                    }
                    let controller = ChatFolderLeaveChatsViewController(
                        items: items,
                        selectedIDs: suggestedIDs.intersection(items.map(\.id)),
                        scope: scope,
                        onRemove: { leaveChatIDs in
                            removeBehindUndo(
                                info: info,
                                leaveChatIDs: leaveChatIDs,
                                clientID: client.id,
                                scope: scope,
                                placement: toastPlacement(),
                                remove: remove,
                            )
                        },
                    )
                    presenter.chatListTopPresenter.present(
                        TelegramNavigationController(rootViewController: controller),
                        animated: true,
                    )
                } catch {
                    guard scope.isCurrent else { return }
                    failure(error)
                }
            }
        }
        guard info.hasMyInviteLinks else {
            offerChatsToLeave()
            return
        }
        let alert = UIAlertController(
            title: L10n.telegram("ChatList.AlertDeleteFolderTitle"),
            message: L10n.telegram("ChatList.AlertDeleteFolderText"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Delete"), style: .destructive) { _ in
            guard scope.isCurrent else { return }
            offerChatsToLeave()
        })
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        presenter.chatListTopPresenter.present(alert, animated: true)
    }

    /// ChatFolderLinkPreviewScreen's remove subject: the folder and the chats it leaves hide at once
    /// (addHiddenChatListFilterIds, addHiddenChatIds), Telegram's removedChat toast offers Undo, and the removal runs
    /// once the toast is gone. The folder and chats come back a second after the removal finishes, as TDLib's updates
    /// have dropped them by then, or right away on Undo.
    private static func removeBehindUndo(
        info: ChatFolderInfo,
        leaveChatIDs: [Int64],
        clientID: Int32,
        scope: ChatListActionScope,
        placement: ToastPlacement?,
        remove: @escaping (_ leaveChatIDs: [Int64], _ finished: @escaping () -> Void) -> Void,
    ) {
        guard scope.isCurrent else { return }
        let rootVM = RootVM.shared
        let showChats = PendingChatRemovals.shared.hide(leaveChatIDs.map {
            PendingChatRemovals.Key(clientID: clientID, chatID: $0)
        })
        rootVM.setFolderHidden(info.id, true)
        let restoration = Restoration {
            showChats()
            rootVM.setFolderHidden(info.id, false)
        }
        let commit = DispatchWorkItem {
            guard scope.isCurrent else {
                restoration.run()
                return
            }
            remove(leaveChatIDs) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { restoration.run() }
            }
            // A removal that never reports back still returns the folder if TDLib kept it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { restoration.run() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PendingChatRemovals.delay, execute: commit)
        guard let placement else { return }
        let title = L10n.telegram("FolderLinkPreview.ToastLeftTitleV2")
            .replacingOccurrences(of: "{folder}", with: info.name.text.text)
        TelegramUndoToast.show(
            title: title,
            text: leaveChatIDs.isEmpty
                ? ""
                : L10n.telegramPlural("FolderLinkPreview.ToastLeftChatsText", count: leaveChatIDs.count)
                    .withoutTelegramMarkup,
            in: placement.host,
            bottomInset: placement.bottomInset,
        ) {
            commit.cancel()
            restoration.run()
        }
    }

    /// Telegram lists the folder's channels and supergroups among its pinned and included chats, and selects the ones
    /// the server suggests leaving; a failed suggestion request selects none, as in Telegram.
    private static func leaveCandidates(
        folderID: Int,
        folder: ChatFolder,
        scope: ChatListActionScope,
        client: TDLibClient,
    ) async throws -> ([ChatFolderLeaveChatsViewController.Item], Set<Int64>) {
        var chatIDs = [Int64]()
        for id in folder.pinnedChatIds + folder.includedChatIds where !chatIDs.contains(id) {
            chatIDs.append(id)
        }
        var items = [ChatFolderLeaveChatsViewController.Item]()
        for id in chatIDs {
            try scope.check()
            guard let chat = try? await client.getChat(chatId: id),
                  case .chatTypeSupergroup(let type) = chat.type else { continue }
            let group = try? await client.getSupergroup(supergroupId: type.supergroupId)
            let title = chat.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let memberCount = group?.memberCount ?? 0
            items.append(ChatFolderLeaveChatsViewController.Item(
                id: chat.id,
                title: !title.isEmpty
                    ? title
                    : L10n.betterTG(type.isChannel ? "Folders.UntitledChannel" : "Folders.UntitledGroup"),
                subtitle: memberCount > 0
                    ? L10n.telegramPlural(
                        type
                            .isChannel
                            ? "FolderLinkPreview.LabelPeerSubscribers"
                            : "FolderLinkPreview.LabelPeerMembers",
                        count: memberCount,
                    )
                    : nil,
            ))
        }
        try scope.check()
        guard !items.isEmpty else { return ([], []) }
        let suggested = try? await client.send(TDNativeRequests.getChatFolderChatsToLeave(chatFolderId: folderID))
        try scope.check()
        return (items, Set(suggested?.chatIds ?? []))
    }
}

// MARK: - ChatFolderLeaveChatsViewController

/// Telegram's ChatFolderLinkPreviewScreen with the remove subject: the folder's groups and channels with checkmarks,
/// and a button that removes the folder alone or together with the selected chats.
final class ChatFolderLeaveChatsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    struct Item {
        let id: Int64
        let title: String
        let subtitle: String?
    }

    // MARK: Private

    private static let headerIdentifier = "ChatFolderLeaveHeader"
    private static let cellIdentifier = "ChatFolderLeaveCell"

    private let items: [Item]
    private var selectedIDs: Set<Int64>
    private let scope: ChatListActionScope
    private let onRemove: ([Int64]) -> Void
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let actionButton = UIButton(configuration: .filled())
    private var isRemoving = false

    private var selectAllTitle: String { Self.selectAllTitle(allSelected: selectedIDs.count == items.count) }

    init(items: [Item], selectedIDs: Set<Int64>, scope: ChatListActionScope, onRemove: @escaping ([Int64]) -> Void) {
        self.items = items
        self.selectedIDs = selectedIDs
        self.scope = scope
        self.onRemove = onRemove
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("FolderLinkPreview.TitleRemove")
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
        actionButton.addTarget(self, action: #selector(removeFolder), for: .touchUpInside)
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

    /// Telegram's Select All header action: its two parts in the order of the format, a space apart.
    static func selectAllTitle(allSelected: Bool) -> String {
        let dynamicPart = L10n.telegram(allSelected
            ? "FolderLinkPreview.ListSelectionSelectAllDynamicPartDeselect"
            : "FolderLinkPreview.ListSelectionSelectAllDynamicPartSelect")
        let staticPart = L10n.telegram(allSelected
            ? "FolderLinkPreview.ListSelectionSelectAllStaticPartDeselect"
            : "FolderLinkPreview.ListSelectionSelectAllStaticPartSelect")
        let format = L10n.telegram("FolderLinkPreview.ListSelectionSelectAllFormat")
        switch (format.range(of: "{dynamic}")?.lowerBound, format.range(of: "{static}")?.lowerBound) {
        case (let dynamicIndex?, let staticIndex?):
            return dynamicIndex < staticIndex ? dynamicPart + " " + staticPart : staticPart + " " + dynamicPart
        case (.some, nil):
            return dynamicPart
        case (nil, .some):
            return staticPart
        case (nil, nil):
            return ""
        }
    }

    /// The action button's count badge, as in Telegram's preview screen.
    static func badgeImage(_ count: Int) -> UIImage {
        let text = NSAttributedString(string: count.formatted(.number), attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor.systemBlue,
        ])
        let textSize = text.size()
        let height = ceil(textSize.height) + 4
        let size = CGSize(width: max(height, ceil(textSize.width) + 12), height: height)
        return UIGraphicsImageRenderer(size: size)
            .image { _ in
                UIColor.white.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: height / 2).fill()
                text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
            }
            .withRenderingMode(.alwaysOriginal)
    }

    func numberOfSections(in _: UITableView) -> Int { 1 }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: Self.cellIdentifier)
        let item = items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = selectedIDs.contains(item.id) ? .checkmark : .none
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
        guard !isRemoving else { return }
        let id = items[indexPath.row].id
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        tableView.cellForRow(at: indexPath)?.accessoryType = selectedIDs.contains(id) ? .checkmark : .none
        selectionDidChange()
    }

    private func configure(_ header: ChatFolderLeaveHeaderView?) {
        header?.configure(
            title: L10n.telegramPlural("FolderLinkPreview.RemoveSectionSelectedHeader", count: items.count),
            actionTitle: items.count > 1 ? selectAllTitle : nil,
        ) { [weak self] in
            self?.toggleAllSelection()
        }
    }

    private func toggleAllSelection() {
        guard !isRemoving else { return }
        if selectedIDs.count != items.count {
            selectedIDs = Set(items.map(\.id))
        } else {
            selectedIDs.removeAll()
        }
        for cell in tableView.visibleCells {
            guard let indexPath = tableView.indexPath(for: cell) else { continue }
            cell.accessoryType = selectedIDs.contains(items[indexPath.row].id) ? .checkmark : .none
        }
        selectionDidChange()
    }

    private func selectionDidChange() {
        configure(tableView.headerView(forSection: 0) as? ChatFolderLeaveHeaderView)
        updateActionButton()
    }

    /// Telegram's action button: Remove Folder, or Remove Folder and Chats with the selected count as its badge.
    private func updateActionButton() {
        let count = selectedIDs.count
        actionButton.configuration?.title = L10n.telegram(count == 0
            ? "FolderLinkPreview.ButtonRemoveFolder"
            : "FolderLinkPreview.ButtonRemoveFolderAndChats")
        actionButton.configuration?.image = count == 0 ? nil : Self.badgeImage(count)
    }

    private func descriptionView() -> UIView {
        let container = UIView()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = L10n.telegram("FolderLinkPreview.TextRemoveFolder")
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

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func removeFolder() {
        guard !isRemoving else { return }
        guard scope.isCurrent else {
            dismiss(animated: true)
            return
        }
        isRemoving = true
        let leaveChatIDs = items.map(\.id).filter { selectedIDs.contains($0) }
        let onRemove = onRemove
        dismiss(animated: true) {
            onRemove(leaveChatIDs)
        }
    }
}

// MARK: - ChatFolderLeaveHeaderView

/// The list header of Telegram's folder link screens: the count of chats and its Select All action.
final class ChatFolderLeaveHeaderView: UITableViewHeaderFooterView {
    // MARK: Private

    private let titleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var action: (() -> Void)?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.numberOfLines = 0
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.addTarget(self, action: #selector(performAction), for: .touchUpInside)
        contentView.addSubview(titleLabel)
        contentView.addSubview(actionButton)
        let margins = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: margins.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            actionButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            actionButton.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    func configure(title: String, actionTitle: String?, action: @escaping () -> Void) {
        titleLabel.text = title
        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.isHidden = actionTitle == nil
        self.action = action
    }

    @objc private func performAction() {
        action?()
    }
}

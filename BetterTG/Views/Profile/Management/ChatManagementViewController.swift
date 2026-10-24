// ChatManagementViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ChatManagementViewController

/// Telegram's edit mode for a group or channel (PeerInfoProfileItems.editingItems): the photo, name and
/// description, then the management screens the account's rights reach, and Delete for the owner. A new photo is
/// set as soon as it is picked, as Telegram does; Done saves the name and description through the profile's edit
/// session. Every change happens on its own tap.
final class ChatManagementViewController: SettingsListViewController {
    private let chatID: Int64
    private let isChannel: Bool
    private let session: PeerProfileEditSession
    private let openMembers: () -> Void
    private lazy var photoHeader = ComposePhotoHeaderView(
        buttonTitle: L10n.telegram(isChannel ? "Channel.UpdatePhotoItem" : "GroupInfo.SetGroupPhoto"),
    )
    private lazy var photoPicker = ComposePhotoPicker(host: self)
    private var target: ChatManagementTarget?
    /// The linked channel or discussion group, by name.
    private var linkedChatTitle: String?
    private var chatTitle = ""
    private var chatDescription = ""
    private var savedTitle = ""
    private var savedDescription = ""
    private var fieldsLoaded = false
    private var loadTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var canChangeInfo: Bool {
        target?.rights?.canChangeInfo == true
    }

    init(
        chatID: Int64,
        isChannel: Bool,
        accountID: UUID,
        accountUserID: Int64?,
        openMembers: @escaping () -> Void,
    ) {
        self.chatID = chatID
        self.isChannel = isChannel
        self.session = .live(accountID: accountID, actorID: accountUserID)
        self.openMembers = openMembers
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        actionTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Common.Edit")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .prominent, target: self, action: #selector(donePressed),
        )
        photoHeader.onSetPhoto = { [weak self] source in self?.presentPhotoMenu(from: source) }
        photoPicker.onChange = { [weak self] image in self?.photoPicked(image) }
        session.publisher
            .sink { [weak self] _ in self?.updateDoneButton() }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Counts and rights change on the screens this one opens.
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard let target else { return [SettingsSection(rows: [ChatManagementRows.loading])] }
        var sections = [SettingsSection]()
        if canChangeInfo {
            sections.append(SettingsSection(rows: [
                SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: chatTitle,
                    placeholder: L10n.telegram(
                        isChannel ? "GroupInfo.ChannelListNamePlaceholder" : "GroupInfo.GroupNamePlaceholder",
                    ),
                    maxLength: 128,
                ) { [weak self] text in
                    self?.chatTitle = text
                    self?.updateDoneButton()
                })),
                SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: chatDescription,
                    placeholder: L10n.telegram("Channel.Edit.AboutItem"),
                    maxLength: 255,
                    isMultiline: true,
                ) { [weak self] text in
                    self?.chatDescription = text
                    self?.updateDoneButton()
                })),
            ]))
        }
        let settings = settingsRows(target)
        if !settings.isEmpty { sections.append(SettingsSection(rows: settings)) }
        if let topics = topicsSection(target) { sections.append(topics) }
        let management = managementRows(target)
        if !management.isEmpty { sections.append(SettingsSection(rows: management)) }
        if let hideMembers = hideMembersSection(target) { sections.append(hideMembers) }
        if target.isCreator {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram(isChannel ? "ChannelInfo.DeleteChannel" : "Group.DeleteGroup"),
                style: .action(destructive: true),
            ) { [weak self] in self?.confirmDeletion() }]))
        }
        return sections
    }

    func disclosure(
        _ title: String,
        symbol: String,
        value: String? = nil,
        action: @escaping () -> Void,
    ) -> SettingsRow {
        SettingsRow(title: title, detail: value, symbol: symbol, accessory: .disclosure, action: action)
    }

    func push(_ controller: UIViewController) {
        guard contextIsCurrent, navigationController?.topViewController === self else { return }
        navigationController?.pushViewController(controller, animated: true)
    }

    /// The chat's own settings: type, links and history.
    private func settingsRows(_ target: ChatManagementTarget) -> [SettingsRow] {
        var rows = [SettingsRow]()
        if target.isCreator {
            let typeKey =
                switch (isChannel, target.isPublic) {
                case (true, true): "Channel.Setup.TypePublic"
                case (true, false): "Channel.Setup.TypePrivate"
                case (false, true): "Group.Setup.TypePublic"
                case (false, false): "Group.Setup.TypePrivate"
                }
            rows.append(disclosure(
                L10n.telegram(isChannel ? "Channel.TypeSetup.Title" : "GroupInfo.GroupType"),
                symbol: "globe",
                value: L10n.telegram(typeKey),
            ) { [weak self] in self?.push(ChatTypeViewController(target: target)) })
        }
        // PeerInfoProfileItems: the owner manages links while the chat is private; other admins with the right
        // manage their own links.
        if target.isCreator ? !target.isPublic : target.rights?.canInviteUsers == true {
            rows.append(disclosure(L10n.telegram("GroupInfo.InviteLinks"), symbol: "link") { [weak self] in
                self?.push(ChatInviteLinksViewController(target: target))
            })
        }
        // PeerInfoProfileItems: a channel's Discussion for those who may change its info; a group shows the
        // channel it is linked to.
        if target.supergroupID != nil {
            let isLinked = (target.supergroupInfo?.linkedChatId ?? 0) != 0
            if isChannel, target.rights?.canChangeInfo == true {
                rows.append(disclosure(
                    L10n.telegram("Channel.DiscussionGroup"),
                    symbol: "bubble.left.and.text.bubble.right",
                    value: isLinked ? linkedChatTitle : L10n.telegram("Channel.DiscussionGroupAdd"),
                ) { [weak self] in self?.push(ChatDiscussionViewController(target: target)) })
            } else if !isChannel, isLinked, target.rights?.canChangeInfo == true {
                rows.append(disclosure(
                    L10n.telegram("Group.LinkedChannel"),
                    symbol: "megaphone",
                    value: linkedChatTitle,
                ) { [weak self] in self?.push(ChatDiscussionViewController(target: target)) })
            }
        }
        // Chat History for New Members: a private supergroup without a linked channel or topics.
        if !isChannel, let info = target.supergroupInfo, target.rights?.canRestrictMembers == true,
           !target.isPublic, info.linkedChatId == 0, !target.isForum
        {
            let title = L10n.telegram("GroupInfo.GroupHistoryShort")
            rows.append(disclosure(
                title,
                symbol: "clock.arrow.circlepath",
                value: L10n.telegram(info.isAllHistoryAvailable
                    ? "GroupInfo.GroupHistoryVisible"
                    : "GroupInfo.GroupHistoryHidden"),
            ) { [weak self] in self?.presentHistoryMenu(rowTitle: title, isVisible: info.isAllHistoryAvailable) })
        }
        return rows
    }

    /// Topics for the owner of a group without a linked channel (PeerInfo.OptionTopics).
    private func topicsSection(_ target: ChatManagementTarget) -> SettingsSection? {
        guard target.isCreator, !isChannel, let supergroup = target.supergroup,
              (target.supergroupInfo?.linkedChatId ?? 0) == 0 else { return nil }
        let supergroupID = supergroup.id
        let hasTabs = supergroup.hasForumTabs
        return SettingsSection(
            footer: L10n.telegram("PeerInfo.OptionTopicsText"),
            rows: [SettingsRow(
                title: L10n.telegram("PeerInfo.OptionTopics"),
                symbol: "bubble.left.and.bubble.right",
                accessory: .toggle(isOn: target.isForum, onChange: { [weak self] isOn in
                    self?.apply { client in
                        _ = try await client.send(TDNativeRequests.toggleSupergroupIsForum(
                            supergroupId: supergroupID, isForum: isOn, hasForumTabs: hasTabs,
                        ))
                    }
                }),
            )],
        )
    }

    /// ChannelMembersController's Hide Members for admins who may restrict, once the group is large enough.
    private func hideMembersSection(_ target: ChatManagementTarget) -> SettingsSection? {
        guard !isChannel, let supergroupID = target.supergroupID, let info = target.supergroupInfo,
              target.rights?.canRestrictMembers == true else { return nil }
        return SettingsSection(
            footer: L10n.telegram(info.hasHiddenMembers
                ? "GroupMembers.MembersHiddenOn"
                : "GroupMembers.MembersHiddenOff"),
            rows: [SettingsRow(
                title: L10n.telegram("GroupMembers.HideMembers"),
                symbol: "eye.slash",
                accessory: .toggle(isOn: info.hasHiddenMembers, onChange: { [weak self] isOn in
                    self?.apply { client in
                        _ = try await client.send(TDNativeRequests.toggleSupergroupHasHiddenMembers(
                            supergroupId: supergroupID, hasHiddenMembers: isOn,
                        ))
                    }
                }),
                isEnabled: info.canHideMembers || info.hasHiddenMembers,
            )],
        )
    }

    /// GroupPreHistorySetupController's two choices, applied on the tap.
    private func presentHistoryMenu(rowTitle: String, isVisible: Bool) {
        guard contextIsCurrent, let supergroupID = target?.supergroupID,
              let cell = cell(titled: rowTitle) else { return }
        let check = UIImage(systemName: "checkmark")
        let actions = [true, false].map { visible in
            TelegramContextMenuAction(
                title: L10n.telegram(visible ? "Group.Setup.HistoryVisible" : "Group.Setup.HistoryHidden"),
                image: visible == isVisible ? check : nil,
            ) { [weak self] in
                guard visible != isVisible else { return }
                self?.apply { client in
                    _ = try await client.send(TDNativeRequests.toggleSupergroupIsAllHistoryAvailable(
                        supergroupId: supergroupID, isAllHistoryAvailable: visible,
                    ))
                }
            }
        }
        presentTelegramContextMenu(sourceView: cell, actions: actions, presentationStyle: .menuOnly)
    }

    private func cell(titled title: String) -> UITableViewCell? {
        for (sectionIndex, section) in sections.enumerated() {
            if let row = section.rows.firstIndex(where: { $0.title == title }) {
                return tableView.cellForRow(at: IndexPath(row: row, section: sectionIndex))
            }
        }
        return nil
    }

    /// A setting changed by its switch or menu; the screen rereads the chat either way, so a refused change flips
    /// back.
    private func apply(_ request: @escaping @MainActor (TDLibClient) async throws -> Void) {
        guard contextIsCurrent, actionTask == nil else {
            reload()
            return
        }
        let client = client
        actionTask = Task { [weak self] in
            var failure: Error?
            do {
                try await request(client)
            } catch {
                failure = error
            }
            guard let self else { return }
            actionTask = nil
            guard contextIsCurrent else { return }
            if let failure { presentAlert(title: nil, message: ChatManagementRows.failureText(failure)) }
            loadTask?.cancel()
            loadTask = nil
            load()
        }
    }

    /// Who is in the chat and what they may do: members, admins, permissions, requests, removed users, the log.
    private func managementRows(_ target: ChatManagementTarget) -> [SettingsRow] {
        var rows = [SettingsRow]()
        let isAdministrator = target.rights != nil
        let memberCount = target.supergroupInfo?.memberCount ?? target.basicGroupInfo?.members.count ?? 0
        if isAdministrator || !isChannel {
            rows.append(disclosure(
                L10n.telegram(isChannel ? "Channel.Info.Subscribers" : "Group.Info.Members"),
                symbol: "person.2",
                value: memberCount > 0 ? memberCount.formatted(.number) : nil,
            ) { [weak self] in self?.openMembers() })
        }
        if !isChannel, target.rights?.canRestrictMembers == true {
            rows.append(disclosure(
                L10n.telegram("GroupInfo.Permissions"),
                symbol: "key",
                value: ChatPermissionsViewController.summary(target.chat.permissions, isForum: target.isForum),
            ) { [weak self] in self?.push(ChatPermissionsViewController(target: target)) })
        }
        if isAdministrator {
            let count = target.supergroupInfo?.administratorCount ?? 0
            rows.append(disclosure(
                L10n.telegram("GroupInfo.Administrators"),
                symbol: "star",
                value: count > 0 ? count.formatted(.number) : nil,
            ) { [weak self] in self?.push(ChatAdministratorsViewController(target: target)) })
        }
        // Shown while requests wait, to admins who may add people.
        let requestCount = target.chat.pendingJoinRequests?.totalCount ?? 0
        if requestCount > 0, target.rights?.canInviteUsers == true {
            rows.append(disclosure(
                L10n.telegram("GroupInfo.MemberRequests"),
                symbol: "person.crop.circle.badge.questionmark",
                value: requestCount.formatted(.number),
            ) { [weak self] in self?.push(ChatJoinRequestsViewController(target: target)) })
        }
        if target.supergroupID != nil, target.rights?.canRestrictMembers == true {
            let count = target.supergroupInfo?.bannedCount ?? 0
            rows.append(disclosure(
                L10n.telegram("GroupInfo.Permissions.Removed"),
                symbol: "nosign",
                value: count > 0 ? count.formatted(.number) : nil,
            ) { [weak self] in self?.push(ChatRemovedUsersViewController(target: target)) })
        }
        // The admin log exists for supergroups and channels.
        if target.supergroupID != nil, isAdministrator {
            rows
                .append(disclosure(
                    L10n.telegram("Group.Info.AdminLog"),
                    symbol: "list.bullet.rectangle",
                ) { [weak self] in
                    self?.push(ChatRecentActionsViewController(target: target))
                })
        }
        return rows
    }

    private func load() {
        guard contextIsCurrent, loadTask == nil else { return }
        let client = client
        let chatID = chatID
        loadTask = Task { [weak self] in
            let target = await ChatManagementTarget.load(chatID: chatID, client: client)
            let linkedChatID = target?.supergroupInfo?.linkedChatId ?? 0
            var linkedTitle: String?
            if linkedChatID != 0 { linkedTitle = await (try? client.getChat(chatId: linkedChatID))?.title }
            guard let self, !Task.isCancelled else { return }
            loadTask = nil
            guard contextIsCurrent, let target else { return }
            self.target = target
            linkedChatTitle = linkedTitle
            if !fieldsLoaded {
                fieldsLoaded = true
                savedTitle = target.chat.title
                chatTitle = savedTitle
                savedDescription = target.supergroupInfo?.description ?? target.basicGroupInfo?.description ?? ""
                chatDescription = savedDescription
            }
            if target.rights?.canChangeInfo == true {
                photoHeader.setCurrentPhoto(SettingsPeer(chat: target.chat), client: client, accountID: accountID)
                photoHeader.frame = CGRect(
                    x: 0, y: 0, width: tableView.bounds.width, height: ComposePhotoHeaderView.height,
                )
                tableView.tableHeaderView = photoHeader
            } else {
                tableView.tableHeaderView = nil
            }
            reload()
            updateDoneButton()
        }
    }

    private func updateDoneButton() {
        let trimmedTitle = chatTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        navigationItem.rightBarButtonItem?.isEnabled = session.state == .ready && !trimmedTitle.isEmpty
    }

    // MARK: Name and description

    /// Telegram's Done: the changed name and description, then back to the profile.
    @objc private func donePressed() {
        let title = chatTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = chatDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, contextIsCurrent else { return }
        view.endEditing(true)
        var mutations = [PeerProfileEditSession.Mutation]()
        if canChangeInfo {
            if title != savedTitle { mutations.append(.title(chatID, title)) }
            if description != savedDescription { mutations.append(.description(chatID, description)) }
        }
        guard !mutations.isEmpty else {
            navigationController?.popViewController(animated: true)
            return
        }
        session.save(mutations, owner: self, accepted: { [weak self] mutation in
            switch mutation {
            case .title(_, let value): self?.savedTitle = value
            case .description(_, let value): self?.savedDescription = value
            case .bio,
                 .memberTag,
                 .name: break
            }
        }, completion: { [weak self] result, _ in
            guard let self else { return }
            switch result {
            case .success: navigationController?.popViewController(animated: true)
            case .failure(let error): presentAlert(title: nil, message: error.localizedDescription)
            }
        })
    }

    // MARK: Photo

    private func presentPhotoMenu(from source: UIView) {
        guard canChangeInfo, actionTask == nil else { return }
        photoPicker.presentMenu(from: source, hasPhoto: target?.chat.photo != nil)
    }

    /// PeerInfoScreen's avatar edit: a picked photo is set at once; Delete Photo asks first.
    private func photoPicked(_ image: UIImage?) {
        guard let image else {
            confirm(message: nil, actionTitle: L10n.telegram("GroupInfo.SetGroupPhotoDelete")) { [weak self] in
                self?.updatePhoto(nil)
            }
            return
        }
        photoHeader.setPhoto(image)
        updatePhoto(image)
    }

    private func updatePhoto(_ image: UIImage?) {
        guard actionTask == nil, contextIsCurrent else { return }
        photoHeader.setEnabled(false)
        let client = client
        let chatID = chatID
        actionTask = Task { [weak self] in
            var succeeded = false
            succeeded =
                if let image {
                    await ComposePhotoPicker.upload(image, chatID: chatID, client: client)
                } else {
                    await (try? client.send(TDNativeRequests.setChatPhoto(chatId: chatID, photo: nil))) != nil
                }
            guard let self else { return }
            actionTask = nil
            photoHeader.setEnabled(true)
            photoHeader.setPhoto(nil)
            guard contextIsCurrent else { return }
            if !succeeded { presentChatListActionFailure() }
            load()
        }
    }

    // MARK: Delete

    /// PeerInfoScreen.openDeletePeer: the owner deletes the chat for everyone (deleteChat).
    private func confirmDeletion() {
        guard let target, target.isCreator else { return }
        let text = L10n.telegram(
            isChannel ? "PeerInfo.DeleteChannelText" : "PeerInfo.DeleteGroupText",
            target.chat.title,
        )
        confirm(
            message: text.withoutTelegramMarkup,
            actionTitle: L10n.telegram(isChannel ? "PeerInfo.DeleteChannelTitle" : "PeerInfo.DeleteGroupTitle"),
        ) { [weak self] in
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.deleteChat(chatId: target.chatID))
            } completion: {
                NavigationStorage.shared.popToRoot()
            }
        }
    }
}

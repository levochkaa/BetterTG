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
    private let openAdministrators: () -> Void
    private lazy var photoHeader = ComposePhotoHeaderView(
        buttonTitle: L10n.telegram(isChannel ? "Channel.UpdatePhotoItem" : "GroupInfo.SetGroupPhoto"),
    )
    private lazy var photoPicker = ComposePhotoPicker(host: self)
    private var target: ChatManagementTarget?
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
        openAdministrators: @escaping () -> Void,
    ) {
        self.chatID = chatID
        self.isChannel = isChannel
        self.session = .live(accountID: accountID, actorID: accountUserID)
        self.openMembers = openMembers
        self.openAdministrators = openAdministrators
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
        let management = managementRows(target)
        if !management.isEmpty { sections.append(SettingsSection(rows: management)) }
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
    private func settingsRows(_: ChatManagementTarget) -> [SettingsRow] {
        []
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
        if isAdministrator {
            let count = target.supergroupInfo?.administratorCount ?? 0
            rows.append(disclosure(
                L10n.telegram("GroupInfo.Administrators"),
                symbol: "star",
                value: count > 0 ? count.formatted(.number) : nil,
            ) { [weak self] in self?.openAdministrators() })
        }
        return rows
    }

    private func load() {
        guard contextIsCurrent, loadTask == nil else { return }
        let client = client
        let chatID = chatID
        loadTask = Task { [weak self] in
            let target = await ChatManagementTarget.load(chatID: chatID, client: client)
            guard let self else { return }
            loadTask = nil
            guard !Task.isCancelled, contextIsCurrent, let target else { return }
            self.target = target
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
            case .bio, .memberTag, .name: break
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

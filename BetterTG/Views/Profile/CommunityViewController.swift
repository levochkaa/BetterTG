// CommunityViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - CommunityViewController

/// Telegram 13's CommunityViewScreen as a BetterTG list, from what TDLib tells of a community (getCommunityFullInfo,
/// kept by updateCommunityFullInfo): its chats in CommunityViewScreen's sections — the ones the account is in, the
/// ones it can view, the ones it can only ask to join and, for the community's admins, the hidden ones — each with its
/// members or subscribers, opening its chat. Telegram's add-chat, join requests, Show as One Chat and chat menus wait
/// for TDLib to offer them.
final class CommunityViewController: SettingsListViewController {
    private enum Section: CaseIterable {
        case joined
        case visible
        case requestable
        case hidden

        var title: String {
            switch self {
            case .joined: L10n.telegram("Community.View.SectionJoined")
            case .visible: L10n.telegram("Community.View.SectionVisible")
            case .requestable: L10n.telegram("Community.View.SectionRequestable")
            case .hidden: L10n.telegram("Community.View.SectionHidden")
            }
        }
    }

    private struct Row {
        let chat: Chat
        let section: Section
        let detail: String?
    }

    private let communityID: Int64
    private var rows: [Row]?
    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?

    init(communityID: Int64) {
        self.communityID = communityID
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = TelegramChatListStore.shared.communityName(communityID, clientID: client.id)
            ?? L10n.telegram("Community.View.Title")
        let source = TDLib.shared.activeUpdateSource
        let communityID = communityID
        nc.scopedPublisher(&cancellables, for: .updateCommunityFullInfo) { [weak self] event in
            guard let self, event.source == source, event.value.communityId == communityID else { return }
            load()
        }
        nc.scopedPublisher(&cancellables, for: .updateCommunity) { [weak self] event in
            guard let self, event.source == source, event.value.community.id == communityID else { return }
            title = event.value.community.name
            updateEditButton(event.value.community)
        }
        updateEditButton(TelegramChatListStore.shared.community(communityID, clientID: client.id))
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard let rows else { return [SettingsSection(rows: [ChatManagementRows.loading])] }
        return Section.allCases.compactMap { section in
            let chats = rows.filter { $0.section == section }
            guard !chats.isEmpty else { return nil }
            return SettingsSection(header: section.title, rows: chats.map { row in
                SettingsRow(
                    title: row.chat.title,
                    detail: row.detail,
                    style: .peer(SettingsPeer(chat: row.chat)),
                ) { [weak self] in self?.open(row.chat.id) }
            })
        }
    }

    /// CommunityViewScreen's sections: a chat the account is in (or a bot it talks to) is joined; else one it can read
    /// is visible, a private one shown only to admins is hidden, and the rest can be asked to join.
    private static func row(chat: Chat, item: CommunityChat, client: TDLibClient) async -> Row {
        switch chat.type {
        case .chatTypeSupergroup(let type):
            let supergroup = try? await client.send(TDNativeRequests.getSupergroup(supergroupId: type.supergroupId))
            let isJoined =
                switch supergroup?.status {
                case .chatMemberStatusAdministrator?,
                     .chatMemberStatusCreator?,
                     .chatMemberStatusMember?: true
                case .chatMemberStatusRestricted(let restricted)?: restricted.isMember
                default: false
                }
            let isPrivate = supergroup?.usernames?.activeUsernames.isEmpty != false
            let section: Section =
                if isJoined {
                    .joined
                } else if item.canViewHistory {
                    .visible
                } else if isPrivate, item.isHidden {
                    .hidden
                } else {
                    .requestable
                }
            let count = supergroup?.memberCount ?? 0
            let detail = count > 0
                ? L10n.telegramPlural(
                    type.isChannel ? "Conversation.StatusSubscribers" : "Conversation.StatusMembers",
                    count: count,
                    formattedCount: count.formatted(.number),
                )
                : nil
            return Row(chat: chat, section: section, detail: detail)
        default:
            // A bot: joined once the account has a chat with it, as Telegram counts a bot with a preview.
            return Row(chat: chat, section: chat.lastMessage != nil ? .joined : .requestable, detail: nil)
        }
    }

    /// CommunityViewScreen's Edit for whoever may change the community.
    private func updateEditButton(_ community: Community?) {
        guard let community, CommunityEditViewController.canEdit(community) else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        navigationItem.rightBarButtonItem = .telegramEdit(primaryAction: UIAction { [weak self] _ in
            guard let self, contextIsCurrent,
                  let current = TelegramChatListStore.shared.community(communityID, clientID: client.id)
            else { return }
            let edit = CommunityEditViewController(community: current)
            edit.onDeleted = { [weak self] in
                guard let self, let navigationController,
                      let index = navigationController.viewControllers.firstIndex(of: self), index > 0
                else { return }
                navigationController.popToViewController(
                    navigationController.viewControllers[index - 1],
                    animated: true,
                )
            }
            navigationController?.pushViewController(edit, animated: true)
        })
    }

    private func load() {
        guard contextIsCurrent else { return }
        loadTask?.cancel()
        let client = client
        let communityID = communityID
        loadTask = Task { [weak self] in
            guard let info = try? await client.send(TDNativeRequests.getCommunityFullInfo(communityId: communityID))
            else { return }
            var rows = [Row]()
            for item in info.chats {
                guard !Task.isCancelled,
                      let chat = try? await client.send(TDNativeRequests.getChat(chatId: item.chatId))
                else { continue }
                await rows.append(Self.row(chat: chat, item: item, client: client))
            }
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            self.rows = rows
            reload()
        }
    }

    private func open(_ chatID: Int64) {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            guard let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client),
                  let self, contextIsCurrent
            else { return }
            NavigationStorage.shared.push(.customChat(chat))
        }
    }
}

// MARK: - ProfileCommunityView

/// PeerInfoScreenCommunityItem: the community a chat or bot belongs to on its own block under the info — its 30 pt
/// photo, its name and "Community with N chats", with a disclosure arrow — opening the community.
final class ProfileCommunityView: UIControl {
    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? .systemGray5 : .secondarySystemGroupedBackground }
    }

    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(
        systemName: "chevron.right",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold),
    ))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        clipsToBounds = true
        avatarView.isUserInteractionEnabled = false
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        chevron.tintColor = .tertiaryLabel
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 1
        labels.isUserInteractionEnabled = false
        for view in [avatarView, labels, chevron] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 58),
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 30),
            avatarView.heightAnchor.constraint(equalToConstant: 30),
            labels.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A community without a photo: its first letter on a colour picked by its identifier.
    static func placeholder(_ communityID: Int64, name: String?) -> TelegramAvatarPlaceholder {
        TelegramAvatarPlaceholder(
            peerID: communityID,
            accentColorID: Int(abs(communityID % 7)),
            upgradedGiftColors: nil,
            letters: (name?.first).map { [String($0)] } ?? [],
            isDeleted: false,
        )
    }

    func configure(community: Community?, communityID: Int64, chatCount: Int?, client: TDLibClient) {
        titleLabel.text = community?.name ?? L10n.telegram("Community.View.Title")
        subtitleLabel.text = chatCount.map {
            L10n.telegramPlural("PeerInfo.Community", count: $0, formattedCount: $0.formatted(.number))
        }
        subtitleLabel.isHidden = chatCount == nil
        avatarView.configure(
            file: community?.photo?.small,
            minithumbnail: community?.photo?.minithumbnail,
            placeholder: Self.placeholder(communityID, name: community?.name),
            client: client,
        )
    }
}

// MARK: - CommunityEditViewController

/// Telegram 13's CommunityEditScreen for a community's owner or an admin who may change it, from what TDLib offers:
/// its name (setCommunityName on Done), Who Can Add Chats — All Members or Only Admins with their notes
/// (setCommunityPermissions) — and, for the owner, Delete Community after its question (deleteCommunity). The photo,
/// chats, admins, removed users and join requests wait for TDLib.
final class CommunityEditViewController: SettingsListViewController {
    var onDeleted: (() -> Void)?

    private let community: Community
    private lazy var photoHeader = ComposePhotoHeaderView(
        buttonTitle: L10n.telegram(community.photo == nil ? "Settings.SetPhoto" : "Settings.ChangePhoto"),
    )
    private lazy var photoPicker = ComposePhotoPicker(host: self)
    private var name: String
    private var membersCanAddChats: Bool
    private var isSaving = false

    private var isOwner: Bool {
        if case .communityMemberStatusCreator = community.status {
            true
        } else {
            false
        }
    }

    init(community: Community) {
        self.community = community
        self.name = community.name
        self.membersCanAddChats = community.permissions.canEditChatList
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Common.Edit")
        navigationItem.rightBarButtonItem = UIBarButtonItem.telegramDone(target: self, action: #selector(donePressed))
        // CommunityEditScreen's avatar: Set Photo, or Change Photo with removal.
        photoHeader.onSetPhoto = { [weak self] source in
            guard let self, !isSaving else { return }
            photoPicker.presentMenu(from: source, hasPhoto: community.photo != nil)
        }
        photoPicker.onChange = { [weak self] image in self?.photoPicked(image) }
        photoHeader.setCurrentPhoto(
            SettingsPeer(
                id: community.id,
                title: community.name,
                file: community.photo?.small,
                minithumbnail: community.photo?.minithumbnail,
                placeholder: ProfileCommunityView.placeholder(community.id, name: community.name),
            ),
            client: client,
            accountID: accountID,
        )
        photoHeader.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: ComposePhotoHeaderView.height)
        tableView.tableHeaderView = photoHeader
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [
            SettingsSection(rows: [SettingsRow(title: "", style: .input(SettingsTextInput(
                text: name,
                placeholder: L10n.telegram("Community.Edit.CommunityNamePlaceholder"),
                maxLength: 128,
            ) { [weak self] text in self?.name = text }))]),
            SettingsSection(
                header: L10n.telegram("Community.Edit.WhoCanAddChats"),
                rows: [true, false].map { allMembers in
                    SettingsRow(
                        title: L10n.telegram(allMembers
                            ? "Community.Edit.PermissionAllMembers"
                            : "Community.Edit.PermissionOnlyAdmins"),
                        detail: L10n.telegram(allMembers
                            ? "Community.Edit.PermissionAllMembersInfo"
                            : "Community.Edit.PermissionOnlyAdminsInfo"),
                        style: .subtitle,
                        accessory: membersCanAddChats == allMembers ? .checkmark : .none,
                        isEnabled: !isSaving,
                    ) { [weak self] in self?.setMembersCanAddChats(allMembers) }
                },
            ),
        ]
        if isOwner {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Community.Edit.DeleteCommunity"),
                style: .action(destructive: true),
                isEnabled: !isSaving,
            ) { [weak self] in self?.confirmDelete() }]))
        }
        return sections
    }

    /// The account may edit a community it owns or administers with the right to change its info.
    static func canEdit(_ community: Community) -> Bool {
        switch community.status {
        case .communityMemberStatusCreator: true
        case .communityMemberStatusAdministrator(let administrator): administrator.rights.canChangeInfo
        default: false
        }
    }

    private func photoPicked(_ image: UIImage?) {
        guard let image else {
            confirm(message: nil, actionTitle: L10n.telegram("Settings.RemoveConfirmation")) { [weak self] in
                self?.updatePhoto(nil)
            }
            return
        }
        photoHeader.setPhoto(image)
        updatePhoto(image)
    }

    /// setCommunityPhoto with the picked photo, or none to remove it.
    private func updatePhoto(_ image: UIImage?) {
        guard !isSaving, contextIsCurrent else { return }
        isSaving = true
        photoHeader.setEnabled(false)
        let client = client
        let communityID = community.id
        Task { [weak self] in
            let succeeded =
                if let image {
                    await ComposePhotoPicker.upload(image) { photo in
                        await (try? client.send(TDNativeRequests.setCommunityPhoto(
                            communityId: communityID,
                            photo: photo,
                        ))) != nil
                    }
                } else {
                    await (try? client.send(TDNativeRequests.setCommunityPhoto(
                        communityId: communityID,
                        photo: nil,
                    ))) != nil
                }
            guard let self else { return }
            isSaving = false
            photoHeader.setEnabled(true)
            guard contextIsCurrent else { return }
            if !succeeded {
                photoHeader.setPhoto(nil)
                presentAlert(title: nil, message: L10n.telegram("Login.UnknownError"))
            }
        }
    }

    private func setMembersCanAddChats(_ value: Bool) {
        guard value != membersCanAddChats, !isSaving, contextIsCurrent else { return }
        let previous = membersCanAddChats
        membersCanAddChats = value
        reload()
        let client = client
        let communityID = community.id
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.setCommunityPermissions(
                    communityId: communityID,
                    permissions: TDNativeCommunityPermissions(canEditChatList: value),
                ))
            } catch {
                guard let self else { return }
                membersCanAddChats = previous
                reload()
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }

    @objc private func donePressed() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSaving, contextIsCurrent else { return }
        guard trimmed != community.name, !trimmed.isEmpty else {
            navigationController?.popViewController(animated: true)
            return
        }
        isSaving = true
        reload()
        let client = client
        let communityID = community.id
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.setCommunityName(communityId: communityID, name: trimmed))
                guard let self, contextIsCurrent else { return }
                navigationController?.popViewController(animated: true)
            } catch {
                guard let self else { return }
                isSaving = false
                reload()
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }

    /// confirmDeleteCommunity: Delete Community with its question, then out of the community's screens.
    private func confirmDelete() {
        confirm(
            title: L10n.telegram("Community.Edit.DeleteCommunity"),
            message: L10n.telegram("Community.Edit.DeleteConfirmationText"),
            actionTitle: L10n.telegram("Common.Delete"),
        ) { [weak self] in
            guard let self, !isSaving else { return }
            isSaving = true
            reload()
            let client = client
            let communityID = community.id
            Task { [weak self] in
                do {
                    _ = try await client.send(TDNativeRequests.deleteCommunity(communityId: communityID))
                    guard let self, contextIsCurrent else { return }
                    onDeleted?()
                } catch {
                    guard let self else { return }
                    isSaving = false
                    reload()
                    if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
                }
            }
        }
    }
}

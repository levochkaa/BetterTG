// ChatAdministratorsViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatAdministratorsViewController

/// Telegram's ChannelAdminsController: a channel's Sign Messages and Show Authors' Profiles
/// (toggleSupergroupSignMessages), the owner and admins with who promoted them, and Add Admin for those who may
/// promote. A row opens the admin's rights; the owner and admins the account can't edit stay read-only.
final class ChatAdministratorsViewController: SettingsListViewController {
    private struct Entry {
        let member: ChatManagementMember
        let promotedBy: String?
        let canBeEdited: Bool
    }

    private var target: ChatManagementTarget
    private var entries = [Entry]()
    private var isLoaded = false
    private var signMessages: Bool
    private var showMessageSender: Bool
    private var loadTask: Task<Void, Never>?
    private var signTask: Task<Void, Never>?

    private var canPromote: Bool {
        target.rights?.canPromoteMembers == true
    }

    init(target: ChatManagementTarget) {
        self.target = target
        self.signMessages = target.supergroup?.signMessages ?? false
        self.showMessageSender = target.supergroup?.showMessageSender ?? false
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        signTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Channel.Management.Title")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection]()
        if target.isChannel, target.rights?.canChangeInfo == true {
            sections.append(SettingsSection(
                footer: L10n.telegram("Channel.SignMessages.Help"),
                rows: [SettingsRow(
                    title: L10n.telegram("Channel.SignMessages"),
                    accessory: .toggle(isOn: signMessages, onChange: { [weak self] isOn in
                        self?.setSignatures(signMessages: isOn, showMessageSender: false)
                    }),
                    isEnabled: signTask == nil,
                )],
            ))
            if signMessages {
                sections.append(SettingsSection(
                    footer: L10n.telegram("Channel.ShowAuthorsFooter"),
                    rows: [SettingsRow(
                        title: L10n.telegram("Channel.ShowAuthors"),
                        accessory: .toggle(isOn: showMessageSender, onChange: { [weak self] isOn in
                            self?.setSignatures(signMessages: true, showMessageSender: isOn)
                        }),
                        isEnabled: signTask == nil,
                    )],
                ))
            }
        }
        var rows = [SettingsRow]()
        if canPromote {
            rows.append(SettingsRow(
                title: L10n.telegram("Channel.Management.AddModerator"),
                style: .action(destructive: false),
                symbol: "person.badge.plus",
            ) { [weak self] in self?.addAdministrator() })
        }
        if !isLoaded { rows.append(ChatManagementRows.loading) }
        for entry in entries {
            rows.append(SettingsRow(
                title: entry.member.peer.title,
                detail: detail(for: entry),
                style: .peer(entry.member.peer),
            ) { [weak self] in self?.open(entry) })
        }
        sections.append(SettingsSection(
            header: L10n.telegram(target.isChannel
                ? "ChannelMembers.ChannelAdminsTitle"
                : "ChannelMembers.GroupAdminsTitle"),
            footer: target.isChannel && canPromote ? L10n.telegram("Channel.Management.AddModeratorHelp") : nil,
            rows: rows,
        ))
        return sections
    }

    private func detail(for entry: Entry) -> String? {
        if case .chatMemberStatusCreator = entry.member.status {
            return ChatManagementRows.role(entry.member.status, tag: entry.member.tag)
        }
        return entry.promotedBy.map { L10n.telegram("Channel.Management.PromotedBy", $0) }
            ?? ChatManagementRows.role(entry.member.status, tag: entry.member.tag)
    }

    private func load() {
        guard contextIsCurrent, loadTask == nil else { return }
        let client = client
        let chatID = target.chatID
        let group = target.group
        loadTask = Task { [weak self] in
            let refreshed = await ChatManagementTarget.load(chatID: chatID, client: client)
            var found = [ChatMember]()
            found =
                switch group {
                case .supergroup(let id):
                    await (try? client.send(TDNativeRequests.getSupergroupMembers(
                        supergroupId: id, filter: .supergroupMembersFilterAdministrators, offset: 0, limit: 200,
                    )))?.members ?? []
                case .basic:
                    (refreshed?.basicGroupInfo?.members ?? []).filter {
                        switch $0.status {
                        case .chatMemberStatusAdministrator, .chatMemberStatusCreator: true
                        default: false
                        }
                    }
                }
            let members = await ChatManagementMember.resolve(found, client: client)
            let promoters = Dictionary(found.map { ($0.memberId, $0.inviterUserId) }, uniquingKeysWith: { a, _ in a })
            var names = [Int64: String]()
            var entries = [Entry]()
            for member in members {
                let promoterID = promoters[member.sender] ?? 0
                if promoterID != 0, names[promoterID] == nil {
                    names[promoterID] = await SettingsPeer.user(promoterID, client: client)?.title
                }
                let canBeEdited: Bool =
                    switch member.status {
                    case .chatMemberStatusAdministrator(let administrator): administrator.canBeEdited
                    default: false
                    }
                entries.append(Entry(member: member, promotedBy: names[promoterID], canBeEdited: canBeEdited))
            }
            guard let self else { return }
            loadTask = nil
            guard !Task.isCancelled, contextIsCurrent else { return }
            if let refreshed {
                target = refreshed
                signMessages = refreshed.supergroup?.signMessages ?? false
                showMessageSender = refreshed.supergroup?.showMessageSender ?? false
            }
            self.entries = entries
            isLoaded = true
            reload()
        }
    }

    /// ChannelAdminsController's toggles: Show Authors' Profiles goes off with Sign Messages.
    private func setSignatures(signMessages: Bool, showMessageSender: Bool) {
        guard let supergroupID = target.supergroupID, signTask == nil, contextIsCurrent else { return }
        let previous = (self.signMessages, self.showMessageSender)
        self.signMessages = signMessages
        self.showMessageSender = signMessages && showMessageSender
        reload()
        let client = client
        let show = self.showMessageSender
        signTask = Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.toggleSupergroupSignMessages(
                    supergroupId: supergroupID, signMessages: signMessages, showMessageSender: show,
                ))
                self?.signTask = nil
                self?.reload()
            } catch {
                guard let self else { return }
                signTask = nil
                self.signMessages = previous.0
                self.showMessageSender = previous.1
                reload()
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }

    private func open(_ entry: Entry) {
        guard contextIsCurrent else { return }
        if case .chatMemberStatusCreator = entry.member.status { return }
        guard entry.canBeEdited || target.isCreator else {
            presentAlert(title: nil, message: L10n.telegram("Channel.EditAdmin.CannotEdit"))
            return
        }
        navigationController?.pushViewController(
            ChatAdminRightsViewController(target: target, member: entry.member, isNew: false),
            animated: true,
        )
    }

    /// Add Admin: a member picked from the chat, then their rights.
    private func addAdministrator() {
        guard canPromote, contextIsCurrent else { return }
        let picker = ChatMemberPickerViewController(
            target: target,
            title: L10n.telegram("Channel.Management.AddModerator"),
        ) {
            switch $0.status {
            case .chatMemberStatusAdministrator, .chatMemberStatusBanned, .chatMemberStatusCreator,
                 .chatMemberStatusLeft:
                true
            case .chatMemberStatusMember, .chatMemberStatusRestricted:
                $0.userID == nil
            }
        }
        let target = target
        picker.onPick = { [weak picker] member in
            picker?.navigationController?.pushViewController(
                ChatAdminRightsViewController(target: target, member: member, isNew: true),
                animated: true,
            )
        }
        navigationController?.pushViewController(picker, animated: true)
    }
}

// MARK: - ChatAdminRightsViewController

/// Telegram's ChannelAdminController: an admin's rights in Telegram's order for a channel, a group or a forum, only
/// those the account holds itself, and a group admin's member tag. Save promotes (setChatMemberStatus with
/// chatMemberStatusAdministrator) and sets the tag (setChatMemberTag); Dismiss makes them a member again. A basic
/// group's admins have every right, so its screen keeps only the tag and Dismiss.
final class ChatAdminRightsViewController: SettingsListViewController {
    private let target: ChatManagementTarget
    private let member: ChatManagementMember
    private let isNew: Bool
    private let grantable: AdminRightsSet
    private var rights: AdminRightsSet
    private var tag: String
    private var isSaving = false

    /// The rights rows for this kind of chat, in ChannelAdminController's rightsOrder.
    private var items: [(title: String, key: WritableKeyPath<AdminRightsSet, Bool>)] {
        guard target.supergroupID != nil else { return [] }
        if target.isChannel {
            return [
                (L10n.telegram("Channel.EditAdmin.PermissionChangeInfo"), \.canChangeInfo),
                (L10n.telegram("Channel.EditAdmin.PermissionPostMessages"), \.canPostMessages),
                (L10n.telegram("Channel.EditAdmin.PermissionEditMessagesOfOthers"), \.canEditMessages),
                (L10n.telegram("Channel.EditAdmin.PermissionDeleteMessagesOfOthers"), \.canDeleteMessages),
                (L10n.telegram("Channel.EditAdmin.PermissionPostStories"), \.canPostStories),
                (L10n.telegram("Channel.EditAdmin.PermissionEditStoriesOfOthers"), \.canEditStories),
                (L10n.telegram("Channel.EditAdmin.PermissionDeleteStoriesOfOthers"), \.canDeleteStories),
                (L10n.telegram("Channel.EditAdmin.PermissionBanUsers"), \.canRestrictMembers),
                (L10n.telegram("Channel.EditAdmin.PermissionInviteSubscribers"), \.canInviteUsers),
                (L10n.telegram("Channel.AdminLog.CanManageDirect"), \.canManageDirectMessages),
                (L10n.telegram("Channel.AdminLog.CanManageLiveStreams"), \.canManageVideoChats),
                (L10n.telegram("Channel.EditAdmin.PermissionAddAdmins"), \.canPromoteMembers),
            ]
        }
        var items: [(String, WritableKeyPath<AdminRightsSet, Bool>)] = [
            (L10n.telegram("Group.EditAdmin.PermissionChangeInfo"), \.canChangeInfo),
            (L10n.telegram("Channel.EditAdmin.PermissionDeleteMessages"), \.canDeleteMessages),
            (L10n.telegram("Channel.EditAdmin.PermissionBanUsers"), \.canRestrictMembers),
            (
                L10n.telegram(
                    target.chat.permissions.canInviteUsers
                        ? "Channel.EditAdmin.PermissionInviteViaLink"
                        : "Channel.EditAdmin.PermissionInviteMembers",
                ),
                \.canInviteUsers,
            ),
            (L10n.telegram("Channel.EditAdmin.PermissionManageRanks"), \.canManageTags),
            (L10n.telegram("Channel.EditAdmin.PermissionPinMessages"), \.canPinMessages),
        ]
        if target.isForum {
            items.append((L10n.telegram("Channel.EditAdmin.PermissionManageTopics"), \.canManageTopics))
        }
        items += [
            (L10n.telegram("Channel.EditAdmin.PermissionPostStories"), \.canPostStories),
            (L10n.telegram("Channel.EditAdmin.PermissionEditStoriesOfOthers"), \.canEditStories),
            (L10n.telegram("Channel.EditAdmin.PermissionDeleteStoriesOfOthers"), \.canDeleteStories),
            (L10n.telegram("Channel.AdminLog.CanManageCalls"), \.canManageVideoChats),
            (L10n.telegram("Channel.AdminLog.CanBeAnonymous"), \.isAnonymous),
            (L10n.telegram("Channel.EditAdmin.PermissionAddAdmins"), \.canPromoteMembers),
        ]
        return items.map { (title: $0.0, key: $0.1) }
    }

    init(target: ChatManagementTarget, member: ChatManagementMember, isNew: Bool) {
        self.target = target
        self.member = member
        self.isNew = isNew
        self.grantable = target.rights ?? .none
        self.tag = member.tag
        if case .chatMemberStatusAdministrator(let administrator) = member.status {
            self.rights = AdminRightsSet(administrator.rights)
        } else {
            // ChannelAdminController's new admin: the account's rights without adding admins or anonymity.
            var rights = target.rights ?? .none
            rights.canPromoteMembers = false
            rights.isAnonymous = false
            self.rights = rights
        }
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram(isNew ? "Channel.Management.AddModerator" : "Channel.Moderator.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Save"), style: .prominent, target: self, action: #selector(savePressed),
        )
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection(rows: [SettingsRow(
            title: member.peer.title,
            detail: ChatManagementRows.role(member.status, tag: member.tag),
            style: .peer(member.peer),
        )])]
        let rows = items.map { item in
            SettingsRow(
                title: item.title,
                accessory: .toggle(isOn: rights[keyPath: item.key], onChange: { [weak self] isOn in
                    self?.setRight(item.key, isOn)
                }),
                isEnabled: !isSaving && grantable[keyPath: item.key],
            )
        }
        if !rows.isEmpty {
            sections.append(SettingsSection(
                header: L10n.telegram("Channel.EditAdmin.PermissionsHeader"),
                footer: L10n.telegram(
                    rights.canPromoteMembers
                        ? "Channel.EditAdmin.PermissinAddAdminOn"
                        : "Channel.EditAdmin.PermissinAddAdminOff",
                ),
                rows: rows,
            ))
        }
        if !target.isChannel {
            sections.append(SettingsSection(
                header: L10n.telegram("Group.EditAdmin.MemberTagTitle"),
                footer: L10n.telegram("Group.EditAdmin.MemberTagInfo", member.peer.title),
                rows: [SettingsRow(title: "", style: .input(SettingsTextInput(
                    text: tag,
                    placeholder: L10n.telegram("Group.EditAdmin.RankAdminPlaceholder"),
                    maxLength: 16,
                ) { [weak self] text in self?.tag = text }))],
            ))
        }
        if !isNew {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Channel.Moderator.AccessLevelRevoke"),
                style: .action(destructive: true),
            ) { [weak self] in self?.dismissAdministrator() }]))
        }
        return sections
    }

    private func setRight(_ key: WritableKeyPath<AdminRightsSet, Bool>, _ value: Bool) {
        rights[keyPath: key] = value
        if key == \AdminRightsSet.canPromoteMembers {
            reload(sections: IndexSet(integer: 1))
        }
    }

    @objc private func savePressed() {
        var granted = target.supergroupID == nil ? AdminRightsSet.all() : rights
        // TDLib requires the management right of every admin.
        granted.canManageChat = true
        let status = ChatMemberStatus.chatMemberStatusAdministrator(TDNativeChatMemberStatusAdministrator(
            canBeEdited: true,
            rights: granted.native,
        ))
        let newTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        apply(status, tag: !target.isChannel && newTag != member.tag ? newTag : nil)
    }

    private func dismissAdministrator() {
        apply(.chatMemberStatusMember(TDNativeChatMemberStatusMember(memberUntilDate: 0)), tag: nil)
    }

    private func apply(_ status: ChatMemberStatus, tag newTag: String?) {
        guard !isSaving, contextIsCurrent else { return }
        isSaving = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        let client = client
        let chatID = target.chatID
        let sender = member.sender
        let userID = member.userID
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.setChatMemberStatus(
                    chatId: chatID, memberId: sender, status: status,
                ))
                if let newTag, let userID {
                    _ = try await client.setChatMemberTag(chatId: chatID, tag: newTag, userId: userID)
                }
                guard let self, contextIsCurrent else { return }
                popToAdministrators()
            } catch {
                guard let self else { return }
                isSaving = false
                navigationItem.rightBarButtonItem?.isEnabled = true
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }

    private func popToAdministrators() {
        guard let navigationController else { return }
        if let list = navigationController.viewControllers.last(where: { $0 is ChatAdministratorsViewController }) {
            navigationController.popToViewController(list, animated: true)
        } else {
            navigationController.popViewController(animated: true)
        }
    }
}

// ChatAdministratorsViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatAdministratorsViewController

/// Telegram's ChannelAdminsController: a group's Aggressive Anti-Spam (toggleSupergroupHasAggressiveAntiSpamEnabled),
/// a channel's Sign Messages and Show Authors' Profiles (toggleSupergroupSignMessages), the owner and admins with who
/// promoted them, and Add Admin for those who may promote. A row opens the admin's rights; the owner and admins the
/// account can't edit stay read-only.
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
    private var antiSpamEnabled: Bool
    private var loadTask: Task<Void, Never>?
    private var signTask: Task<Void, Never>?
    private var antiSpamTask: Task<Void, Never>?

    private var canPromote: Bool {
        target.rights?.canPromoteMembers == true
    }

    init(target: ChatManagementTarget) {
        self.target = target
        self.signMessages = target.supergroup?.signMessages ?? false
        self.showMessageSender = target.supergroup?.showMessageSender ?? false
        self.antiSpamEnabled = target.supergroupInfo?.hasAggressiveAntiSpamEnabled ?? false
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        signTask?.cancel()
        antiSpamTask?.cancel()
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
        // channelAdminsControllerEntries: a group's admin who may delete messages sees the switch once the group is
        // big enough for it (TDLib's canToggleAggressiveAntiSpam) or while it is on.
        let canToggleAntiSpam = target.supergroupInfo?.canToggleAggressiveAntiSpam == true
        if !target.isChannel, target.rights?.canDeleteMessages == true, canToggleAntiSpam || antiSpamEnabled {
            sections.append(SettingsSection(
                footer: L10n.telegram("Group.Management.AntiSpamInfo"),
                rows: [SettingsRow(
                    title: L10n.telegram("Group.Management.AntiSpam"),
                    symbol: "checkmark.shield",
                    symbolTint: .systemGreen,
                    accessory: .toggle(isOn: antiSpamEnabled, onChange: { [weak self] isOn in
                        self?.setAntiSpam(isOn)
                    }),
                    isEnabled: antiSpamTask == nil && canToggleAntiSpam,
                )],
            ))
        }
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
                        case .chatMemberStatusAdministrator,
                             .chatMemberStatusCreator: true
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
                if antiSpamTask == nil {
                    antiSpamEnabled = refreshed.supergroupInfo?.hasAggressiveAntiSpamEnabled ?? false
                }
            }
            self.entries = entries
            isLoaded = true
            reload()
        }
    }

    /// ChannelAdminsController's updateAntiSpamEnabled: the switch moves at once and goes back if TDLib refuses.
    private func setAntiSpam(_ isOn: Bool) {
        guard let supergroupID = target.supergroupID, antiSpamTask == nil, contextIsCurrent else { return }
        let previous = antiSpamEnabled
        antiSpamEnabled = isOn
        reload()
        let client = client
        antiSpamTask = Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.toggleSupergroupHasAggressiveAntiSpamEnabled(
                    supergroupId: supergroupID, hasAggressiveAntiSpamEnabled: isOn,
                ))
                self?.antiSpamTask = nil
                self?.reload()
            } catch {
                guard let self else { return }
                antiSpamTask = nil
                antiSpamEnabled = previous
                reload()
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
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
            case .chatMemberStatusAdministrator,
                 .chatMemberStatusBanned,
                 .chatMemberStatusCreator,
                 .chatMemberStatusLeft:
                true
            case .chatMemberStatusMember,
                 .chatMemberStatusRestricted:
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
    /// ChannelAdminController with `invite` for a bot (OpenResolvedUrl's groupBotStart): titled Add Bot, with a
    /// group's Admin Rights switch and a button that adds the bot as an admin after Telegram's confirmation, or as a
    /// member.
    struct BotInvite {
        /// The rights the link or the bot asks for; the account's own rights cap them.
        let requestedRights: AdminRightsSet?
        let onAdded: @MainActor () -> Void
    }

    /// ChannelAdminController's RightsItem.Sub: the rights Telegram gathers under one switch.
    private enum RightsGroup: CaseIterable {
        case messages
        case stories

        var title: String {
            switch self {
            case .messages: L10n.telegram("Channel.EditAdmin.SectionMessages")
            case .stories: L10n.telegram("Channel.EditAdmin.SectionStories")
            }
        }

        /// messageRelatedFlags and storiesRelatedFlags; a group's Delete Messages stays a right of its own.
        func keys(isChannel: Bool) -> [WritableKeyPath<AdminRightsSet, Bool>] {
            switch self {
            case .messages: isChannel ? [\.canPostMessages, \.canEditMessages, \.canDeleteMessages] : []
            case .stories: [\.canPostStories, \.canEditStories, \.canDeleteStories]
            }
        }
    }

    private let target: ChatManagementTarget
    private let member: ChatManagementMember
    private let isNew: Bool
    private let grantable: AdminRightsSet
    private let botInvite: BotInvite?
    private var rights: AdminRightsSet
    private var tag: String
    private var isSaving = false
    /// ChannelAdminControllerState's `adminRights` for an invited bot: off adds it as a member.
    private var addsBotAsAdmin = true
    /// The admin is a person, not a bot or a deleted account, as ownership can only go to one.
    private var memberCanOwn = false
    /// ChannelAdminControllerState's expandedPermissions.
    private var expandedGroups = Set<RightsGroup>()

    /// ChannelAdminController's canTransfer: the owner of a supergroup or channel sees Transfer Ownership for a person
    /// once every right of this chat is on but anonymity (areAllAdminRightsEnabled, except canBeAnonymous).
    private var canTransferOwnership: Bool {
        guard botInvite == nil, target.isCreator, target.supergroupID != nil, memberCanOwn else { return false }
        return items.filter { $0.key != \AdminRightsSet.isAnonymous }.allSatisfy { rights[keyPath: $0.key] }
    }

    /// A group's bot that isn't an admin yet may join as a member instead (Bot.AddToChat.Add.AdminRights).
    private var offersMemberInvite: Bool {
        guard botInvite != nil, !target.isChannel else { return false }
        if case .chatMemberStatusAdministrator = member.status { return false }
        return true
    }

    private var editsRights: Bool {
        !offersMemberInvite || addsBotAsAdmin
    }

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

    init(target: ChatManagementTarget, member: ChatManagementMember, isNew: Bool, botInvite: BotInvite? = nil) {
        self.target = target
        self.member = member
        self.isNew = isNew
        // ChannelAdminController's accountUserRightsFlags: the owner grants the whole mask, anonymity included, whether
        // or not they stay anonymous themselves; an admin only the rights they hold.
        self.grantable = target.isCreator ? .all(isAnonymous: true) : target.rights ?? .none
        self.botInvite = botInvite
        self.tag = member.tag
        if let requested = botInvite?.requestedRights {
            self.rights = requested.intersection(target.rights ?? .none)
        } else if case .chatMemberStatusAdministrator(let administrator) = member.status {
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
        if botInvite != nil {
            title = L10n.telegram("Bot.AddToChat.Add.Title")
            return
        }
        title = L10n.telegram(isNew ? "Channel.Management.AddModerator" : "Channel.Moderator.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Save"), style: .prominent, target: self, action: #selector(savePressed),
        )
        loadOwnershipCandidate()
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection(rows: [SettingsRow(
            title: member.peer.title,
            detail: ChatManagementRows.role(member.status, tag: member.tag),
            style: .peer(member.peer),
        )])]
        if offersMemberInvite {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Bot.AddToChat.Add.AdminRights"),
                accessory: .toggle(isOn: addsBotAsAdmin, onChange: { [weak self] isOn in
                    guard let self else { return }
                    addsBotAsAdmin = isOn
                    reload()
                }),
                isEnabled: !isSaving,
            )]))
        }
        let rows = rightsRows()
        if !rows.isEmpty, editsRights {
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
        if canTransferOwnership {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram(target.isChannel
                    ? "Channel.EditAdmin.TransferOwnership"
                    : "Group.EditAdmin.TransferOwnership"),
                style: .action(destructive: false),
                isEnabled: !isSaving,
            ) { [weak self] in self?.transferOwnership() }]))
        }
        if !target.isChannel, editsRights {
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
        if botInvite != nil {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram(editsRights ? "Bot.AddToChat.Add.AddAsAdmin" : "Bot.AddToChat.Add.AddAsMember"),
                style: .action(destructive: false),
                isEnabled: !isSaving,
            ) { [weak self] in self?.addBotPressed() }]))
        }
        if !isNew {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Channel.Moderator.AccessLevelRevoke"),
                style: .action(destructive: true),
            ) { [weak self] in self?.dismissAdministrator() }]))
        }
        return sections
    }

    private func loadOwnershipCandidate() {
        guard target.isCreator, target.supergroupID != nil, let userID = member.userID else { return }
        let client = client
        Task { [weak self] in
            let user = try? await client.getUser(userId: userID)
            guard let self, contextIsCurrent, let user else { return }
            var canOwn = false
            if case .userTypeRegular = user.type { canOwn = true }
            #if DEBUG
                // `-ui-probe-ownership-any-admin` lets a test group's bot stand in for a person, to walk the checks.
                canOwn = canOwn || ProcessInfo.processInfo.arguments.contains("-ui-probe-ownership-any-admin")
            #endif
            if canOwn {
                memberCanOwn = true
                reload()
            }
        }
    }

    /// ChannelAdminController's rightsOrder as rows: single rights as switches, and a channel's messages rights and
    /// every chat's stories rights as an ItemListExpandableSwitchItem whose switch sets them all and whose options
    /// open from its title.
    private func rightsRows() -> [SettingsRow] {
        var rows = [SettingsRow]()
        var emitted = Set<RightsGroup>()
        let all = items
        for item in all {
            guard let group = RightsGroup.allCases
                .first(where: { $0.keys(isChannel: target.isChannel).contains(item.key) })
            else {
                rows.append(SettingsRow(
                    title: item.title,
                    accessory: .toggle(isOn: rights[keyPath: item.key], onChange: { [weak self] isOn in
                        self?.setRight(item.key, isOn)
                    }),
                    isEnabled: !isSaving && grantable[keyPath: item.key],
                ))
                continue
            }
            guard emitted.insert(group).inserted else { continue }
            let options = all.filter { group.keys(isChannel: target.isChannel).contains($0.key) }
            let selected = options.count { rights[keyPath: $0.key] }
            let isExpanded = expandedGroups.contains(group)
            let title = group.title
            rows.append(SettingsRow(
                title: title,
                style: .expandable(count: "\(selected)/\(options.count)", isExpanded: isExpanded),
                accessory: .toggle(isOn: selected == options.count, onChange: { [weak self] isOn in
                    self?.setRights(options.map(\.key), isOn)
                }),
                isEnabled: !isSaving && options.contains { grantable[keyPath: $0.key] },
            ) { [weak self] in self?.toggleExpanded(group, headTitle: title) })
            guard isExpanded else { continue }
            for option in options {
                rows.append(SettingsRow(
                    title: option.title,
                    style: .option(isSelected: rights[keyPath: option.key]),
                    isEnabled: !isSaving && grantable[keyPath: option.key],
                ) { [weak self] in
                    guard let self else { return }
                    setRights([option.key], !rights[keyPath: option.key])
                })
            }
        }
        return rows
    }

    private func toggleExpanded(_ group: RightsGroup, headTitle: String) {
        if expandedGroups.remove(group) == nil { expandedGroups.insert(group) }
        reloadAnimating(sectionWithRowTitled: headTitle)
    }

    /// toggleRight for a group or one of its options: the rights the account may grant change, the others stay.
    private func setRights(_ keys: [WritableKeyPath<AdminRightsSet, Bool>], _ value: Bool) {
        let couldTransfer = canTransferOwnership
        for key in keys where grantable[keyPath: key] {
            rights[keyPath: key] = value
        }
        if canTransferOwnership != couldTransfer {
            reload()
        } else {
            refreshRowsInPlace()
        }
    }

    private func setRight(_ key: WritableKeyPath<AdminRightsSet, Bool>, _ value: Bool) {
        let couldTransfer = canTransferOwnership
        rights[keyPath: key] = value
        if canTransferOwnership != couldTransfer {
            reload()
        } else if key == \AdminRightsSet.canPromoteMembers {
            reload(sections: IndexSet(integer: offersMemberInvite ? 2 : 1))
        }
    }

    /// ChannelParticipantFooterItem for an invited bot: Add Bot as Admin asks first, Add Bot as Member adds it.
    private func addBotPressed() {
        guard !isSaving else { return }
        guard editsRights else {
            addBotAsMember()
            return
        }
        let key = target.isChannel ? "Bot.AddToChat.Add.AdminAlertTextChannel" : "Bot.AddToChat.Add.AdminAlertTextGroup"
        confirm(
            title: L10n.telegram("Bot.AddToChat.Add.AdminAlertTitle"),
            message: L10n.telegram(key, target.chat.title).replacing("**", with: ""),
            actionTitle: L10n.telegram("Bot.AddToChat.Add.AdminAlertAdd"),
            isDestructive: false,
        ) { [weak self] in self?.savePressed() }
    }

    private func addBotAsMember() {
        guard let userID = member.userID, contextIsCurrent else { return }
        isSaving = true
        reload()
        let client = client
        let chatID = target.chatID
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.addChatMember(
                    chatId: chatID,
                    userId: userID,
                    forwardLimit: 0,
                ))
                guard let self, contextIsCurrent else { return }
                botInvite?.onAdded()
            } catch {
                guard let self else { return }
                isSaving = false
                reload()
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
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
                if let botInvite {
                    botInvite.onAdded()
                } else {
                    popToAdministrators()
                }
            } catch {
                guard let self else { return }
                isSaving = false
                navigationItem.rightBarButtonItem?.isEnabled = true
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }

    // MARK: Ownership transfer

    /// ChannelAdminController's transferOwnership: TDLib's canTransferOwnership stands in for
    /// checkOwnershipTranfserAvailability, then channelOwnershipTransferController explains a refusal or confirms.
    private func transferOwnership() {
        guard canTransferOwnership, !isSaving, contextIsCurrent else { return }
        isSaving = true
        reload()
        let client = client
        Task { [weak self] in
            let result = try? await client.canTransferOwnership()
            guard let self else { return }
            isSaving = false
            reload()
            guard contextIsCurrent else { return }
            switch result {
            case .canTransferOwnershipResultOk:
                confirmOwnershipTransfer()
            case .canTransferOwnershipResultPasswordNeeded:
                showOwnershipSecurityCheck(comeBackLater: false, offersPasswordSetup: true)
            case .canTransferOwnershipResultPasswordTooFresh,
                 .canTransferOwnershipResultSessionTooFresh:
                showOwnershipSecurityCheck(comeBackLater: true, offersPasswordSetup: false)
            case nil:
                presentAlert(title: nil, message: L10n.telegram("Login.UnknownError"))
            }
        }
    }

    /// channelOwnershipTransferController: the security requirements, with "come back later" while the password or
    /// the session is too fresh, and Enable 2-Step Verification while there is no password.
    private func showOwnershipSecurityCheck(comeBackLater: Bool, offersPasswordSetup: Bool) {
        var text = L10n.telegram("OwnershipTransfer.SecurityRequirements")
        if comeBackLater { text += L10n.telegram("OwnershipTransfer.ComeBackLater") }
        let alert = UIAlertController(
            title: L10n.telegram("OwnershipTransfer.SecurityCheck"),
            message: text.replacing("**", with: ""),
            preferredStyle: .alert,
        )
        if offersPasswordSetup {
            alert.addAction(UIAlertAction(
                title: L10n.telegram("OwnershipTransfer.SetupTwoStepAuth"),
                style: .default,
            ) { [weak self] _ in self?.openTwoStepVerification() })
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        } else {
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        }
        chatListTopPresenter.present(alert, animated: true)
    }

    private func openTwoStepVerification() {
        guard contextIsCurrent else { return }
        let service = TDLibTwoStepVerificationService(client: client)
        Task { [weak self] in
            let configuration = try? await service.configuration()
            guard let self, contextIsCurrent else { return }
            navigationController?.pushViewController(
                TwoStepVerificationViewController.entry(for: configuration, service: service),
                animated: true,
            )
        }
    }

    /// confirmChannelOwnershipTransferController: what the transfer means, Change Owner or Cancel.
    private func confirmOwnershipTransfer() {
        let key = target.isChannel
            ? "Channel.OwnershipTransfer.DescriptionInfo"
            : "Group.OwnershipTransfer.DescriptionInfo"
        let alert = UIAlertController(
            title: L10n.telegram(target.isChannel
                ? "Channel.OwnershipTransfer.Title"
                : "Group.OwnershipTransfer.Title"),
            message: L10n.telegram(key, target.chat.title, member.peer.title).replacing("**", with: ""),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(
            title: L10n.telegram("Channel.OwnershipTransfer.ChangeOwner"),
            style: .default,
        ) { [weak self] _ in self?.presentOwnershipPassword(isRetry: false) })
        let cancel = UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel)
        alert.addAction(cancel)
        alert.preferredAction = cancel
        chatListTopPresenter.present(alert, animated: true)
    }

    /// commitChannelOwnershipTransferController: the 2-Step Verification password, whose Transfer stays off while the
    /// field is empty. A wrong password asks again (Telegram shakes the field).
    private func presentOwnershipPassword(isRetry: Bool) {
        guard contextIsCurrent else { return }
        let alert = UIAlertController(
            title: L10n.telegram("Channel.OwnershipTransfer.EnterPassword"),
            message: L10n.telegram(isRetry
                ? "TwoStepAuth.EnterPasswordInvalid"
                : "Channel.OwnershipTransfer.EnterPasswordText"),
            preferredStyle: .alert,
        )
        let transfer = UIAlertAction(
            title: L10n.telegram("OwnershipTransfer.Transfer"),
            style: .default,
        ) { [weak self, weak alert] _ in
            self?.commitOwnershipTransfer(password: alert?.textFields?.first?.text ?? "")
        }
        transfer.isEnabled = false
        alert.addTextField { [weak transfer] field in
            field.isSecureTextEntry = true
            field.textContentType = .password
            field.placeholder = L10n.telegram("Channel.OwnershipTransfer.PasswordPlaceholder")
            field.addAction(UIAction { [weak field] _ in
                transfer?.isEnabled = field?.text?.isEmpty == false
            }, for: .editingChanged)
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(transfer)
        alert.preferredAction = transfer
        chatListTopPresenter.present(alert, animated: true)
    }

    /// transferChatOwnership, then the admins list with TransferCompleted; the errors as
    /// commitChannelOwnershipTransferController shows them.
    private func commitOwnershipTransfer(password: String) {
        guard let userID = member.userID, !isSaving, contextIsCurrent else { return }
        isSaving = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        reload()
        let client = client
        let chatID = target.chatID
        let completed = L10n.telegram(
            "Channel.OwnershipTransfer.TransferCompleted",
            member.peer.title,
            target.chat.title,
        )
        .replacing("**", with: "")
        Task { [weak self] in
            var failure: Error?
            do {
                _ = try await client.send(TDNativeRequests.transferChatOwnership(
                    chatId: chatID, userId: userID, password: password,
                ))
            } catch {
                failure = error
            }
            guard let self else { return }
            isSaving = false
            navigationItem.rightBarButtonItem?.isEnabled = true
            reload()
            guard contextIsCurrent else { return }
            guard let failure else {
                let list = navigationController?.viewControllers
                    .last { $0 is ChatAdministratorsViewController } as? ChatAdministratorsViewController
                popToAdministrators()
                list?.showToast(completed)
                return
            }
            showOwnershipTransferError(failure)
        }
    }

    private func showOwnershipTransferError(_ error: Error) {
        let tdError = error as? TDLibError
        let description = tdError?.message ?? ""
        switch description {
        case "PASSWORD_HASH_INVALID":
            presentOwnershipPassword(isRetry: true)
            return
        case "PASSWORD_MISSING":
            showOwnershipSecurityCheck(comeBackLater: false, offersPasswordSetup: true)
            return
        case _ where description.hasPrefix("PASSWORD_TOO_FRESH_") || description.hasPrefix("SESSION_TOO_FRESH_"):
            showOwnershipSecurityCheck(comeBackLater: true, offersPasswordSetup: false)
            return
        default:
            break
        }
        let kind = target.isChannel ? "Channel" : "Group"
        let key =
            switch description {
            case _ where tdError?.code == 429 || description.hasPrefix("FLOOD_WAIT"): "TwoStepAuth.FloodError"
            case "ADMINS_TOO_MUCH": "\(kind).OwnershipTransfer.ErrorAdminsTooMuch"
            case "CHANNELS_ADMIN_PUBLIC_TOO_MUCH": "Channel.OwnershipTransfer.ErrorPublicChannelsTooMuch"
            case "USER_BLOCKED",
                 "USER_PRIVACY_RESTRICTED": "\(kind).OwnershipTransfer.ErrorPrivacyRestricted"
            default: "Login.UnknownError"
            }
        presentAlert(title: nil, message: L10n.telegram(key))
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

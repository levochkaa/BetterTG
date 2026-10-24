// ChatPermissionsViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatPermissionsViewController

/// Telegram's ChannelPermissionsController: what every member may do (setChatPermissions, sent as each toggle
/// changes), the supergroup's slowmode (setChatSlowModeDelay) and its exceptions, the members restricted one by one
/// (getSupergroupMembers with the restricted filter). A public group keeps Pin Messages and Change Group Info for
/// admins, as Telegram's NotAvailableInPublicGroups.
final class ChatPermissionsViewController: SettingsListViewController {
    /// ChannelPermissionsController's slowmode stops.
    private static let slowModeDelays = [0, 10, 30, 60, 300, 900, 3600]

    private var target: ChatManagementTarget
    private var permissions: PermissionSet
    private var savedPermissions: PermissionSet
    private var slowModeDelay: Int
    private var exceptions = [ChatManagementMember]()
    private var exceptionsLoaded = false
    private var permissionsTask: Task<Void, Never>?
    private var slowModeTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    private var isSupergroup: Bool {
        target.supergroupID != nil
    }

    init(target: ChatManagementTarget) {
        self.target = target
        self.permissions = PermissionSet(target.chat.permissions)
        self.savedPermissions = permissions
        self.slowModeDelay = target.supergroupInfo?.slowModeDelay ?? 0
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        permissionsTask?.cancel()
        slowModeTask?.cancel()
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("GroupInfo.Permissions.Title")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadExceptions()
    }

    override func makeSections() -> [SettingsSection] {
        let lockedInPublic: Set<WritableKeyPath<PermissionSet, Bool>> = target.isPublic
            ? [\.canPinMessages, \.canChangeInfo]
            : []
        var sections = [SettingsSection(
            header: L10n.telegram("GroupInfo.Permissions.SectionTitle"),
            footer: lockedInPublic.isEmpty ? nil : L10n.telegram("GroupPermission.NotAvailableInPublicGroups"),
            rows: PermissionSet.items(isForum: target.isForum, isDefault: true).map { item in
                let isLocked = lockedInPublic.contains(item.key)
                return SettingsRow(
                    title: item.title,
                    accessory: .toggle(
                        isOn: !isLocked && permissions[keyPath: item.key],
                        onChange: { [weak self] isOn in
                            self?.setPermission(item.key, isOn)
                        },
                    ),
                    isEnabled: !isLocked,
                )
            },
        )]
        guard isSupergroup else { return sections }
        sections.append(SettingsSection(
            header: L10n.telegram("GroupInfo.Permissions.SlowmodeHeader"),
            footer: L10n.telegram("GroupInfo.Permissions.SlowmodeInfo"),
            rows: Self.slowModeDelays.map { delay in
                SettingsRow(
                    title: delay == 0
                        ? L10n.telegram("GroupInfo.Permissions.SlowmodeValue.Off")
                        : SettingsFormatting.timeInterval(seconds: delay),
                    accessory: delay == slowModeDelay ? .checkmark : .none,
                ) { [weak self] in self?.setSlowModeDelay(delay) }
            },
        ))
        var exceptionRows = [SettingsRow(
            title: L10n.telegram("GroupInfo.Permissions.AddException"),
            style: .action(destructive: false),
            symbol: "person.badge.plus",
        ) { [weak self] in self?.addException() }]
        if !exceptionsLoaded {
            exceptionRows.append(ChatManagementRows.loading)
        }
        let isForum = target.isForum
        for member in exceptions {
            var detail: String?
            if case .chatMemberStatusRestricted(let restricted) = member.status {
                detail = Self.restrictionSummary(restricted.permissions, isForum: isForum)
            }
            exceptionRows.append(SettingsRow(title: member.peer.title, detail: detail, style: .peer(member.peer)) {
                [weak self] in self?.openException(member, isNew: false)
            })
        }
        sections.append(SettingsSection(
            header: L10n.telegram("GroupInfo.Permissions.Exceptions"),
            rows: exceptionRows,
        ))
        return sections
    }

    /// The permissions on, out of the list, as Telegram's Permissions row reads "N/M".
    static func summary(_ permissions: ChatPermissions, isForum: Bool) -> String {
        let set = PermissionSet(permissions)
        let items = PermissionSet.items(isForum: isForum, isDefault: true)
        let enabled = items.count(where: { set[keyPath: $0.key] })
        return "\(enabled)/\(items.count)"
    }

    /// Telegram's compact exception text: the "no …" labels of what the member may not do.
    static func restrictionSummary(_ permissions: ChatPermissions, isForum: Bool) -> String {
        let set = PermissionSet(permissions)
        return PermissionSet.items(isForum: isForum, isDefault: false)
            .filter { !set[keyPath: $0.key] }
            .map(\.short)
            .joined(separator: ", ")
    }

    // MARK: Default permissions

    private func setPermission(_ key: WritableKeyPath<PermissionSet, Bool>, _ value: Bool) {
        permissions[keyPath: key] = value
        sendPermissions()
    }

    /// One setChatPermissions at a time; toggles made meanwhile go in the next one, as Telegram's delayed update.
    private func sendPermissions() {
        guard permissionsTask == nil, permissions != savedPermissions, contextIsCurrent else { return }
        let client = client
        let chatID = target.chatID
        let sent = permissions
        permissionsTask = Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.setChatPermissions(chatId: chatID, permissions: sent.native))
                guard let self else { return }
                permissionsTask = nil
                savedPermissions = sent
                sendPermissions()
            } catch {
                guard let self else { return }
                permissionsTask = nil
                permissions = savedPermissions
                reload()
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }

    // MARK: Slowmode

    private func setSlowModeDelay(_ delay: Int) {
        guard delay != slowModeDelay, slowModeTask == nil, contextIsCurrent else { return }
        let previous = slowModeDelay
        slowModeDelay = delay
        reload(sections: IndexSet(integer: 1))
        let client = client
        let chatID = target.chatID
        slowModeTask = Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.setChatSlowModeDelay(chatId: chatID, slowModeDelay: delay))
                self?.slowModeTask = nil
            } catch {
                guard let self else { return }
                slowModeTask = nil
                slowModeDelay = previous
                reload(sections: IndexSet(integer: 1))
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }

    // MARK: Exceptions

    private func loadExceptions() {
        guard let supergroupID = target.supergroupID, contextIsCurrent, loadTask == nil else { return }
        let client = client
        loadTask = Task { [weak self] in
            let found = await (try? client.send(TDNativeRequests.getSupergroupMembers(
                supergroupId: supergroupID,
                filter: .supergroupMembersFilterRestricted(TDNativeSupergroupMembersFilterRestricted(query: "")),
                offset: 0,
                limit: 200,
            )))?.members ?? []
            let members = await ChatManagementMember.resolve(found, client: client)
            guard let self else { return }
            loadTask = nil
            guard !Task.isCancelled, contextIsCurrent else { return }
            exceptions = members
            exceptionsLoaded = true
            reload()
        }
    }

    /// ChannelPermissionsController's Add Exception: a member, then their own restrictions.
    private func addException() {
        guard contextIsCurrent else { return }
        let picker = ChatMemberPickerViewController(
            target: target,
            title: L10n.telegram("GroupInfo.Permissions.AddException"),
        ) { member in
            switch member.status {
            case .chatMemberStatusAdministrator,
                 .chatMemberStatusBanned,
                 .chatMemberStatusCreator,
                 .chatMemberStatusLeft:
                true
            case .chatMemberStatusMember,
                 .chatMemberStatusRestricted:
                false
            }
        }
        picker.onPick = { [weak self, weak picker] member in
            guard let self, let picker else { return }
            let editor = ChatMemberRestrictionViewController(target: target, member: member, isNew: true)
            picker.navigationController?.pushViewController(editor, animated: true)
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func openException(_ member: ChatManagementMember, isNew: Bool) {
        guard contextIsCurrent else { return }
        navigationController?.pushViewController(
            ChatMemberRestrictionViewController(target: target, member: member, isNew: isNew),
            animated: true,
        )
    }
}

// MARK: - ChatMemberRestrictionViewController

/// Telegram's ChannelBannedMemberController for an exception: what this member may do, within what everyone may, and
/// for how long. Save restricts them (setChatMemberStatus with chatMemberStatusRestricted); Delete Exception makes
/// them a plain member again. Both act on their own tap only.
final class ChatMemberRestrictionViewController: SettingsListViewController {
    private let target: ChatManagementTarget
    private let member: ChatManagementMember
    private let isNew: Bool
    private let defaults: PermissionSet
    private var permissions: PermissionSet
    /// Seconds from now, or 0 for Forever.
    private var duration = 0
    private var isSaving = false

    init(target: ChatManagementTarget, member: ChatManagementMember, isNew: Bool) {
        self.target = target
        self.member = member
        self.isNew = isNew
        self.defaults = PermissionSet(target.chat.permissions)
        if case .chatMemberStatusRestricted(let restricted) = member.status {
            self.permissions = PermissionSet(restricted.permissions)
            let remaining = restricted.restrictedUntilDate - Int(Foundation.Date().timeIntervalSince1970)
            self.duration = restricted.restrictedUntilDate == 0 ? 0 : max(0, remaining)
        } else {
            self.permissions = defaults
        }
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram(isNew ? "GroupPermission.NewTitle" : "GroupPermission.Title")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Save"), style: .prominent, target: self, action: #selector(savePressed),
        )
    }

    override func makeSections() -> [SettingsSection] {
        let durationText = duration == 0
            ? L10n.telegram("MessageTimer.Forever")
            : SettingsFormatting.timeInterval(seconds: duration)
        var sections = [
            SettingsSection(rows: [SettingsRow(
                title: member.peer.title,
                detail: ChatManagementRows.role(member.status, tag: member.tag),
                style: .peer(member.peer),
            )]),
            SettingsSection(
                header: L10n.telegram("GroupPermission.SectionTitle"),
                rows: PermissionSet.items(isForum: target.isForum, isDefault: false).map { item in
                    // An option off for everyone stays off (GroupPermission.PermissionDisabledByDefault).
                    let isAllowed = defaults[keyPath: item.key]
                    return SettingsRow(
                        title: item.title,
                        accessory: .toggle(
                            isOn: isAllowed && permissions[keyPath: item.key],
                            onChange: { [weak self] isOn in self?.permissions[keyPath: item.key] = isOn },
                        ),
                        isEnabled: isAllowed && !isSaving,
                    )
                },
            ),
            SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("GroupPermission.Duration"),
                detail: durationText,
                accessory: .disclosure,
            ) { [weak self] in self?.presentDurationMenu() }]),
        ]
        if !isNew {
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("GroupPermission.Delete"),
                style: .action(destructive: true),
            ) { [weak self] in self?.deleteException() }]))
        }
        return sections
    }

    private func presentDurationMenu() {
        guard let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 2)) else { return }
        let day = 24 * 60 * 60
        let check = UIImage(systemName: "checkmark")
        let actions = ([day, 7 * day, 31 * day, 0] as [Int]).map { value in
            TelegramContextMenuAction(
                title: value == 0
                    ? L10n.telegram("MessageTimer.Forever")
                    : SettingsFormatting.timeInterval(seconds: value),
                image: value == duration ? check : nil,
            ) { [weak self] in
                self?.duration = value
                self?.reload(sections: IndexSet(integer: 2))
            }
        }
        presentTelegramContextMenu(sourceView: cell, actions: actions, presentationStyle: .menuOnly)
    }

    @objc private func savePressed() {
        let untilDate = duration == 0 ? 0 : Int(Foundation.Date().timeIntervalSince1970) + duration
        apply(.chatMemberStatusRestricted(TDNativeChatMemberStatusRestricted(
            isMember: true,
            restrictedUntilDate: untilDate,
            permissions: permissions.native,
        )))
    }

    private func deleteException() {
        apply(.chatMemberStatusMember(TDNativeChatMemberStatusMember(memberUntilDate: 0)))
    }

    private func apply(_ status: ChatMemberStatus) {
        guard !isSaving, contextIsCurrent else { return }
        isSaving = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        let client = client
        let chatID = target.chatID
        let sender = member.sender
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.setChatMemberStatus(
                    chatId: chatID, memberId: sender, status: status,
                ))
                guard let self, contextIsCurrent else { return }
                popToPermissions()
            } catch {
                guard let self else { return }
                isSaving = false
                navigationItem.rightBarButtonItem?.isEnabled = true
                if contextIsCurrent { presentAlert(title: nil, message: ChatManagementRows.failureText(error)) }
            }
        }
    }

    /// Back to the screen that listed the member, past the member picker.
    private func popToPermissions() {
        guard let navigationController else { return }
        if let list = navigationController.viewControllers.last(where: { $0 is ChatPermissionsViewController }) {
            navigationController.popToViewController(list, animated: true)
        } else {
            navigationController.popViewController(animated: true)
        }
    }
}

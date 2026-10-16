// AdminDeleteMessagesViewController.swift

import TDLibKit
import UIKit

// MARK: - AdminDeleteMessagesViewController

/// Telegram's AdminUserActionsSheet for an admin deleting other members' messages in a group: the messages are
/// deleted for everyone, with Report Spam, Delete All from the senders and Ban them (or, with "Partially restrict",
/// restrict them to the rights left on) as extra choices. Nothing happens until Proceed; then the choices run in
/// Telegram's order (applyAdminUserActionsResult). With several senders each choice covers all of them.
final class AdminDeleteMessagesViewController: SettingsListViewController {
    struct Request {
        let chatID: Int64
        let supergroupID: Int64
        /// Every message deleted for everyone.
        let messageIDs: [Int64]
        /// The senders' messages among them, which Report Spam reports.
        let spamMessageIDs: [Int64]
        /// The people and chats whose messages are deleted, without repeats.
        let senders: [MessageSender]
        let canDeleteAll: Bool
        let canBan: Bool
        /// The chat's default permissions; a partial restriction keeps only rights among these.
        let chatPermissions: ChatPermissions
    }

    /// The rights of Telegram's restriction editor (AdminUserActionConfigItem and its media rights).
    private enum Permission: CaseIterable {
        case sendMessages
        case photos
        case videos
        case stickersAndGifs
        case music
        case files
        case voiceNotes
        case videoNotes
        case links
        case polls
        case reactions
        case addMembers
        case pinMessages
        case changeInfo

        static let media: [Permission] = [
            .photos, .videos, .stickersAndGifs, .music, .files, .voiceNotes, .videoNotes, .links, .polls, .reactions,
        ]

        var titleKey: String {
            switch self {
            case .sendMessages: "Channel.BanUser.PermissionSendMessages"
            case .photos: "Channel.BanUser.PermissionSendPhoto"
            case .videos: "Channel.BanUser.PermissionSendVideo"
            case .stickersAndGifs: "Channel.BanUser.PermissionSendStickersAndGifs"
            case .music: "Channel.BanUser.PermissionSendMusic"
            case .files: "Channel.BanUser.PermissionSendFile"
            case .voiceNotes: "Channel.BanUser.PermissionSendVoiceMessage"
            case .videoNotes: "Channel.BanUser.PermissionSendVideoMessage"
            case .links: "Channel.BanUser.PermissionEmbedLinks"
            case .polls: "Channel.BanUser.PermissionSendPolls"
            case .reactions: "Channel.BanUser.PermissionSendReactions"
            case .addMembers: "Channel.BanUser.PermissionAddMembers"
            case .pinMessages: "Channel.EditAdmin.PermissionPinMessages"
            case .changeInfo: "Channel.BanUser.PermissionChangeGroupInfo"
            }
        }

        static func allowed(in permissions: ChatPermissions) -> Set<Permission> {
            var result = Set<Permission>()
            if permissions.canSendBasicMessages { result.insert(.sendMessages) }
            if permissions.canSendPhotos { result.insert(.photos) }
            if permissions.canSendVideos { result.insert(.videos) }
            if permissions.canSendOtherMessages { result.insert(.stickersAndGifs) }
            if permissions.canSendAudios { result.insert(.music) }
            if permissions.canSendDocuments { result.insert(.files) }
            if permissions.canSendVoiceNotes { result.insert(.voiceNotes) }
            if permissions.canSendVideoNotes { result.insert(.videoNotes) }
            if permissions.canAddLinkPreviews { result.insert(.links) }
            if permissions.canSendPolls { result.insert(.polls) }
            if permissions.canReactToMessages { result.insert(.reactions) }
            if permissions.canInviteUsers { result.insert(.addMembers) }
            if permissions.canPinMessages { result.insert(.pinMessages) }
            if permissions.canChangeInfo { result.insert(.changeInfo) }
            return result
        }

        /// rightFlagsFromRights: the kept rights as TDLib permissions; topics and tags follow the chat's defaults.
        static func permissions(keeping kept: Set<Permission>, chatPermissions: ChatPermissions) -> ChatPermissions {
            ChatPermissions(
                canSendBasicMessages: kept.contains(.sendMessages),
                canSendAudios: kept.contains(.music),
                canSendDocuments: kept.contains(.files),
                canSendPhotos: kept.contains(.photos),
                canSendVideos: kept.contains(.videos),
                canSendVideoNotes: kept.contains(.videoNotes),
                canSendVoiceNotes: kept.contains(.voiceNotes),
                canSendPolls: kept.contains(.polls),
                canSendOtherMessages: kept.contains(.stickersAndGifs),
                canAddLinkPreviews: kept.contains(.links),
                canReactToMessages: kept.contains(.reactions),
                canEditTag: chatPermissions.canEditTag,
                canChangeInfo: kept.contains(.changeInfo),
                canInviteUsers: kept.contains(.addMembers),
                canPinMessages: kept.contains(.pinMessages),
                canCreateTopics: chatPermissions.canCreateTopics,
            )
        }
    }

    private let request: Request
    /// The toast text Telegram shows after the actions.
    private let onFinished: (String) -> Void
    private var senderName = ""
    private var reportsSpam = false
    private var deletesAll = false
    private var bans = false
    /// Telegram's "Partially restrict this user": Ban becomes a restriction keeping the rights left on.
    private var restricts = false
    private var showsMediaPermissions = false
    /// The rights a restriction can keep; empty while unknown or when a sender can't be restricted.
    private var allowedPermissions = Set<Permission>()
    private var keptPermissions = Set<Permission>()
    /// Whether each restricted person is still in the chat, so the restriction doesn't add them back.
    private var memberships = [Int64: Bool]()
    private var isRunning = false

    private var isSingle: Bool {
        request.senders.count == 1
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(request: Request, onFinished: @escaping (String) -> Void) {
        self.request = request
        self.onFinished = onFinished
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegramPlural("Chat.AdminActionSheet.DeleteTitle", count: request.messageIDs.count)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancel),
        )
        loadSenderName()
        loadRestrictions()
    }

    override func makeSections() -> [SettingsSection] {
        var rows =
            [option(L10n.telegram("Chat.AdminActionSheet.ReportSpam"), isOn: reportsSpam) { $0.reportsSpam.toggle() }]
        if request.canDeleteAll {
            rows.append(option(
                isSingle
                    ? L10n.telegram("Chat.AdminActionSheet.DeleteAllSingle", senderName)
                    : L10n.telegram("Chat.AdminActionSheet.DeleteAllMultiple"),
                isOn: deletesAll,
            ) { $0.deletesAll.toggle() })
        }
        if request.canBan {
            let banTitle =
                if isSingle {
                    L10n.telegram(
                        restricts ? "Chat.AdminActionSheet.RestrictSingle" : "Chat.AdminActionSheet.BanSingle",
                        senderName,
                    )
                } else {
                    L10n.telegram(
                        restricts ? "Chat.AdminActionSheet.RestrictMultiple" : "Chat.AdminActionSheet.BanMultiple",
                    )
                }
            rows.append(option(banTitle, isOn: bans) { sheet in
                sheet.bans.toggle()
                if !sheet.bans { sheet.restricts = false }
            })
        }
        var sections = [SettingsSection(
            header: L10n.telegram("Chat.AdminActionSheet.RestrictSectionHeader"),
            rows: rows,
        )]
        if request.canBan, !allowedPermissions.isEmpty {
            let key =
                switch (restricts, isSingle) {
                case (true, true): "Chat.AdminActionSheet.BanFooterSingle"
                case (true, false): "Chat.AdminActionSheet.BanFooterMultiple"
                case (false, true): "Chat.AdminActionSheet.RestrictFooterSingle"
                case (false, false): "Chat.AdminActionSheet.RestrictFooterMultiple"
                }
            sections.append(SettingsSection(rows: [SettingsRow(
                title: L10n.telegram(key),
                style: .action(destructive: false),
                isEnabled: !isRunning,
            ) { [weak self] in
                guard let self else { return }
                restricts.toggle()
                if restricts { bans = true }
                reload()
            }]))
        }
        if restricts {
            sections.append(SettingsSection(
                header: L10n.telegram(isSingle
                    ? "Chat.AdminActionSheet.PermissionsSectionHeader"
                    : "Chat.AdminActionSheet.PermissionsSectionHeaderMultiple"),
                rows: permissionRows(),
            ))
        }
        sections.append(SettingsSection(rows: [SettingsRow(
            title: L10n.telegram("Chat.AdminActionSheet.ActionButton"),
            style: .action(destructive: true),
            accessory: isRunning ? .activity : .none,
            isEnabled: !isRunning,
        ) { [weak self] in self?.proceed() }]))
        return sections
    }

    static func present(_ request: Request, from presenter: UIViewController, onFinished: @escaping (String) -> Void) {
        let navigation = TelegramNavigationController(
            rootViewController: AdminDeleteMessagesViewController(request: request, onFinished: onFinished),
        )
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.chatListTopPresenter.present(navigation, animated: true)
    }

    private func option(
        _ title: String,
        isOn: Bool,
        toggle: @escaping (AdminDeleteMessagesViewController) -> Void,
    ) -> SettingsRow {
        SettingsRow(title: title, accessory: isOn ? .checkmark : .none, isEnabled: !isRunning) { [weak self] in
            guard let self else { return }
            toggle(self)
            reload()
        }
    }

    /// Send Messages, Send Media with its count and the media rights below it when opened, Add Users, Pin Messages
    /// and Change Info; rights the chat itself withholds stay off.
    private func permissionRows() -> [SettingsRow] {
        var rows = [permissionRow(.sendMessages)]
        let allowedMedia = Permission.media.filter { allowedPermissions.contains($0) }
        let keptMedia = allowedMedia.filter { keptPermissions.contains($0) }
        rows.append(SettingsRow(
            title: L10n.telegram("Channel.BanUser.PermissionSendMedia"),
            detail: allowedMedia.isEmpty ? nil : "\(keptMedia.count)/\(allowedMedia.count)",
            accessory: .toggle(isOn: !keptMedia.isEmpty, onChange: { [weak self] isOn in
                guard let self else { return }
                if isOn {
                    keptPermissions.formUnion(allowedMedia)
                } else {
                    keptPermissions.subtract(allowedMedia)
                }
                reload()
            }),
            isEnabled: !isRunning && !allowedMedia.isEmpty,
        ) { [weak self] in
            guard let self else { return }
            showsMediaPermissions.toggle()
            reload()
        })
        if showsMediaPermissions {
            for permission in allowedMedia {
                rows.append(SettingsRow(
                    title: L10n.telegram(permission.titleKey),
                    accessory: keptPermissions.contains(permission) ? .checkmark : .none,
                    isEnabled: !isRunning,
                ) { [weak self] in
                    guard let self else { return }
                    if keptPermissions.contains(permission) {
                        keptPermissions.remove(permission)
                    } else {
                        keptPermissions.insert(permission)
                    }
                    reload()
                })
            }
        }
        rows.append(contentsOf: [Permission.addMembers, .pinMessages, .changeInfo].map(permissionRow))
        return rows
    }

    private func permissionRow(_ permission: Permission) -> SettingsRow {
        SettingsRow(
            title: L10n.telegram(permission.titleKey),
            accessory: .toggle(isOn: keptPermissions.contains(permission), onChange: { [weak self] isOn in
                guard let self else { return }
                if isOn {
                    keptPermissions.insert(permission)
                } else {
                    keptPermissions.remove(permission)
                }
                reload()
            }),
            isEnabled: !isRunning && allowedPermissions.contains(permission),
        )
    }

    /// Telegram names a single sender by the short name: a person's first name or the chat's title.
    private func loadSenderName() {
        guard isSingle, let sender = request.senders.first else { return }
        let client = client
        Task { [weak self] in
            var name: String?
            switch sender {
            case .messageSenderUser(let user):
                if let found = try? await client.getUser(userId: user.userId) {
                    name = found.firstName.isEmpty ? found.lastName : found.firstName
                }
            case .messageSenderChat(let chat):
                name = try? await client.getChat(chatId: chat.chatId).title
            }
            guard let self, contextIsCurrent, let name, !name.isEmpty else { return }
            senderName = name
            reload()
        }
    }

    /// The restriction editor's starting point: the chat's default rights, narrowed to what every sender has now.
    /// Owners, admins and chats posting as themselves can't be partially restricted, so the option stays hidden.
    private func loadRestrictions() {
        guard request.canBan else { return }
        let client = client
        let request = request
        Task { [weak self] in
            let allowed = Permission.allowed(in: request.chatPermissions)
            var kept = allowed
            var memberships = [Int64: Bool]()
            for sender in request.senders {
                guard case .messageSenderUser(let user) = sender,
                      let member = try? await client.getChatMember(chatId: request.chatID, memberId: sender)
                else { return }
                switch member.status {
                case .chatMemberStatusMember:
                    memberships[user.userId] = true
                case .chatMemberStatusRestricted(let restricted):
                    memberships[user.userId] = restricted.isMember
                    kept.formIntersection(Permission.allowed(in: restricted.permissions))
                case .chatMemberStatusLeft:
                    memberships[user.userId] = false
                default:
                    return
                }
            }
            guard let self, contextIsCurrent, !allowed.isEmpty else { return }
            allowedPermissions = allowed
            keptPermissions = kept
            self.memberships = memberships
            reload()
        }
    }

    @objc private func cancel() {
        guard !isRunning else { return }
        dismiss(animated: true)
    }

    /// applyAdminUserActionsResult: delete for everyone, then delete the senders' other messages, report spam and
    /// ban or restrict, as chosen. The toast lists what happened.
    private func proceed() {
        guard !isRunning, contextIsCurrent else { return }
        isRunning = true
        reload()
        let request = request
        let reportsSpam = reportsSpam
        let deletesAll = deletesAll
        let bans = bans
        let restriction = restricts
            ? Permission.permissions(keeping: keptPermissions, chatPermissions: request.chatPermissions)
            : nil
        let memberships = memberships
        let client = client
        Task { [weak self] in
            var deleted = await (try? client.deleteMessages(
                chatId: request.chatID,
                messageIds: request.messageIDs,
                revoke: true,
            )) != nil
            if deletesAll {
                for sender in request.senders {
                    let all = try? await client.send(TDNativeRequests.deleteChatMessagesBySender(
                        chatId: request.chatID,
                        senderId: sender,
                    ))
                    deleted = deleted || all != nil
                }
            }
            var reported = false
            if reportsSpam, !request.spamMessageIDs.isEmpty {
                reported = await (try? client.send(TDNativeRequests.reportSupergroupSpam(
                    supergroupId: request.supergroupID,
                    messageIds: request.spamMessageIDs,
                ))) != nil
            }
            var bannedCount = 0
            var restrictedCount = 0
            if bans {
                for sender in request.senders {
                    if let restriction, case .messageSenderUser(let user) = sender {
                        let status = ChatMemberStatus.chatMemberStatusRestricted(.init(
                            isMember: memberships[user.userId] ?? true,
                            restrictedUntilDate: 0,
                            permissions: restriction,
                        ))
                        if await (try? client.send(TDNativeRequests.setChatMemberStatus(
                            chatId: request.chatID,
                            memberId: sender,
                            status: status,
                        ))) != nil {
                            restrictedCount += 1
                        }
                    } else if await (try? client.send(TDNativeRequests.banChatMember(
                        chatId: request.chatID,
                        memberId: sender,
                        bannedUntilDate: 0,
                        revokeMessages: false,
                    ))) != nil {
                        bannedCount += 1
                    }
                }
            }
            guard let self, contextIsCurrent else { return }
            isRunning = false
            guard deleted || reported || bannedCount > 0 || restrictedCount > 0 else {
                reload()
                presentChatListActionFailure()
                return
            }
            var lines = [String]()
            if reported {
                lines.append(L10n.telegramPlural(
                    "Chat.AdminAction.ToastReportedSpamText",
                    count: request.senders.count,
                ))
            }
            if bannedCount > 0 { lines.append(L10n.telegramPlural(
                "Chat.AdminAction.ToastBannedText",
                count: bannedCount,
            )) }
            if restrictedCount > 0 {
                lines.append(L10n.telegramPlural("Chat.AdminAction.ToastRestrictedText", count: restrictedCount))
            }
            let isMultiple = request.messageIDs.count > 1 || deletesAll
            let text =
                if lines.isEmpty {
                    L10n.telegram(isMultiple
                        ? "Chat.AdminAction.ToastMessagesDeletedTextMultiple"
                        : "Chat.AdminAction.ToastMessagesDeletedTextSingle")
                } else {
                    ([L10n.telegram(isMultiple
                            ? "Chat.AdminAction.ToastMessagesDeletedTitleMultiple"
                            : "Chat.AdminAction.ToastMessagesDeletedTitleSingle")] + lines)
                        .joined(separator: "\n")
                }
            let onFinished = onFinished
            dismiss(animated: true) { onFinished(text.withoutTelegramMarkup) }
        }
    }
}

// ChatInviteLinksViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatInviteLinkText

/// How Telegram's invite link rows read (ItemListInviteLinkItem, ItemListPermanentInviteLinkItem).
@MainActor enum ChatInviteLinkText {
    static var now: Int {
        Int(Foundation.Date().timeIntervalSince1970)
    }

    /// The link's name, or the link without its scheme.
    static func title(_ link: ChatInviteLink) -> String {
        link.name.isEmpty ? address(link.inviteLink) : link.name
    }

    static func address(_ link: String) -> String {
        link.replacingOccurrences(of: "https://", with: "")
    }

    /// The main link's line: how many people joined through it.
    static func joined(_ count: Int) -> String {
        count > 0
            ? L10n.telegramPlural("InviteLink.PeopleJoined", count: count)
            : L10n.telegram("InviteLink.PeopleJoinedNone")
    }

    /// ItemListInviteLinkItem's subtitle: who joined or can join, pending requests and approval, then revoked, the
    /// remaining uses or the expiry.
    static func status(_ link: ChatInviteLink, now: Int = ChatInviteLinkText.now) -> String {
        let isExpired = link.expirationDate != 0 && now >= link.expirationDate
        let isFull = link.memberLimit > 0 && link.memberCount >= link.memberLimit
        var text = ""
        func append(_ part: String, separator: String = " • ") {
            text = text.isEmpty ? part : text + separator + part
        }
        if link.memberCount > 0 {
            text = L10n.telegramPlural("InviteLink.PeopleJoinedShort", count: link.memberCount)
        } else if link.memberLimit > 0, !isExpired, !isFull {
            text = L10n.telegramPlural("InviteLink.PeopleCanJoin", count: link.memberLimit)
        } else if isExpired || isFull {
            text = L10n.telegram("InviteLink.PeopleJoinedShortNoneExpired")
        } else if link.pendingJoinRequestCount == 0 {
            text = L10n.telegram("InviteLink.PeopleJoinedShortNone")
        }
        if link.pendingJoinRequestCount > 0 {
            append(
                L10n.telegramPlural("MemberRequests.PeopleRequestedShort", count: link.pendingJoinRequestCount),
                separator: ", ",
            )
        }
        if link.createsJoinRequest { append(L10n.telegram("InviteLink.ApprovalRequired")) }
        if link.isRevoked {
            append(L10n.telegram("InviteLink.Revoked"))
            return text
        }
        if link.memberLimit > 0, !isExpired {
            let remaining = link.memberLimit - link.memberCount
            if remaining > 0, remaining != link.memberLimit {
                append(L10n.telegramPlural("InviteLink.PeopleRemaining", count: remaining), separator: ", ")
            } else if remaining <= 0 {
                append(L10n.telegram("InviteLink.UsageLimitReached"))
            }
        }
        if link.expirationDate != 0, !isFull {
            append(isExpired
                ? L10n.telegram("InviteLink.Expired")
                : L10n.telegram("InviteLink.ExpiresIn", timeLeft(link.expirationDate - now)))
        }
        return text
    }

    /// Telegram's scheduledTimeIntervalString from a day on, else textForTimeout's countdown.
    static func timeLeft(_ seconds: Int) -> String {
        if seconds >= 24 * 60 * 60 { return SettingsFormatting.timeInterval(seconds: seconds) }
        let minutes = seconds % 3600 / 60
        let rest = seconds % 60
        return seconds < 3600
            ? String(format: "%d:%02d", minutes, rest)
            : String(format: "%d:%02d:%02d", seconds / 3600, minutes, rest)
    }

    /// GroupInfo/ChannelInfo.InviteLink.RevokeAlert before a link stops working.
    static func confirmRevoke(
        isChannel: Bool,
        in controller: SettingsListViewController,
        perform: @escaping () -> Void,
    ) {
        controller.confirm(
            message: L10n.telegram(
                isChannel ? "ChannelInfo.InviteLink.RevokeAlert.Text" : "GroupInfo.InviteLink.RevokeAlert.Text",
            ),
            actionTitle: L10n.telegram("GroupInfo.InviteLink.RevokeLink"),
            perform: perform,
        )
    }
}

// MARK: - ChatInviteLinksViewController

/// Telegram's InviteLinkListController: the main link (the public address, or the account's primary invite link with
/// Copy, Share and Revoke), the additional links the account created, with Create a New Link, and the revoked ones
/// with Delete All. A link opens its own screen. Every change happens on its own tap.
final class ChatInviteLinksViewController: SettingsListViewController {
    private static let pageLimit = 100

    private let target: ChatManagementTarget
    private var mainLink: ChatInviteLink?
    private var links = [ChatInviteLink]()
    private var revokedLinks = [ChatInviteLink]()
    private var myUserID: Int64 = 0
    private var isLoaded = false
    private var loadTask: Task<Void, Never>?

    /// The public t.me address that stands in for the invite link (InviteLink.PublicLink).
    private var publicAddress: String? {
        target.supergroup?.usernames?.activeUsernames.first.map { "https://t.me/\($0)" }
    }

    init(target: ChatManagementTarget) {
        self.target = target
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
        title = L10n.telegram("InviteLink.Title")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    override func makeSections() -> [SettingsSection] {
        let mainAddress = publicAddress ?? mainLink?.inviteLink ?? target.inviteLink
        let mainRow =
            if let mainAddress {
                SettingsRow(
                    title: ChatInviteLinkText.address(mainAddress),
                    detail: publicAddress == nil ? ChatInviteLinkText.joined(mainLink?.memberCount ?? 0) : nil,
                    style: .subtitle,
                    symbol: "link",
                ) { [weak self] in self?.presentMainMenu(mainAddress) }
            } else {
                ChatManagementRows.loading
            }
        var sections = [SettingsSection(
            header: L10n.telegram(publicAddress == nil ? "InviteLink.InviteLink" : "InviteLink.PublicLink"),
            footer: L10n.telegram(
                target.isChannel ? "InviteLink.CreatePrivateLinkHelpChannel" : "InviteLink.CreatePrivateLinkHelp",
            ),
            rows: [mainRow],
        )]
        var linkRows = [SettingsRow(
            title: L10n.telegram("InviteLink.Create"),
            style: .action(destructive: false),
            symbol: "plus",
        ) { [weak self] in self?.createLink() }]
        if !isLoaded { linkRows.append(ChatManagementRows.loading) }
        linkRows += links.map { link in
            SettingsRow(
                title: ChatInviteLinkText.title(link),
                detail: ChatInviteLinkText.status(link),
                style: .subtitle,
                accessory: .disclosure,
                action: { [weak self] in self?.open(link) },
                swipeAction: (
                    L10n.telegram("InviteLink.ContextRevoke"),
                    { [weak self] in self?.revoke(link.inviteLink) },
                ),
            )
        }
        sections.append(SettingsSection(
            header: L10n.telegram("InviteLink.AdditionalLinks"),
            footer: L10n.telegram("InviteLink.CreateInfo"),
            rows: linkRows,
        ))
        if !revokedLinks.isEmpty {
            let deleteAll = SettingsRow(
                title: L10n.telegram("InviteLink.DeleteAllRevokedLinks"),
                style: .action(destructive: true),
                symbol: "trash",
                symbolTint: .systemRed,
            ) { [weak self] in self?.deleteAllRevoked() }
            sections.append(SettingsSection(
                header: L10n.telegram("InviteLink.RevokedLinks"),
                rows: [deleteAll] + revokedLinks.map { link in
                    SettingsRow(
                        title: ChatInviteLinkText.title(link),
                        detail: ChatInviteLinkText.status(link),
                        style: .subtitle,
                        accessory: .disclosure,
                        action: { [weak self] in self?.open(link) },
                        swipeAction: (
                            L10n.telegram("InviteLink.ContextDelete"),
                            { [weak self] in self?.deleteRevoked(link.inviteLink) },
                        ),
                    )
                },
            ))
        }
        return sections
    }

    private func load() {
        guard contextIsCurrent else { return }
        loadTask?.cancel()
        let client = client
        let chatID = target.chatID
        loadTask = Task { [weak self] in
            let userID = await (try? client.getMe())?.id ?? 0
            func links(revoked: Bool) async -> [ChatInviteLink] {
                await (try? client.send(TDNativeRequests.getChatInviteLinks(
                    chatId: chatID,
                    creatorUserId: userID,
                    isRevoked: revoked,
                    offsetDate: 0,
                    offsetInviteLink: "",
                    limit: Self.pageLimit,
                )))?.inviteLinks ?? []
            }
            let active = await links(revoked: false)
            let revoked = await links(revoked: true)
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            loadTask = nil
            myUserID = userID
            mainLink = active.first { $0.isPrimary }
            links = active.filter { !$0.isPrimary }
            revokedLinks = revoked
            isLoaded = true
            reload()
        }
    }

    /// ItemListPermanentInviteLinkItem's actions: Copy, Share and, for an invite link, Revoke, which replaces it.
    private func presentMainMenu(_ address: String) {
        guard contextIsCurrent, let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) else { return }
        var actions = [
            TelegramContextMenuAction(
                title: L10n.telegram("InviteLink.ContextCopy"),
                image: UIImage(systemName: "doc.on.doc"),
            ) { [weak self] in self?.copy(address) },
            TelegramContextMenuAction(
                title: L10n.telegram("InviteLink.ContextShare"),
                image: UIImage(systemName: "square.and.arrow.up"),
            ) { [weak self] in self?.share(address) },
        ]
        if publicAddress == nil {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("InviteLink.ContextRevoke"),
                image: UIImage(systemName: "trash"),
                isDestructive: true,
            ) { [weak self] in self?.revoke(address) })
        }
        presentTelegramContextMenu(sourceView: cell, actions: actions, presentationStyle: .menuOnly)
    }

    private func copy(_ address: String) {
        ChatFolderInviteLinkActions.copy(address, in: self)
    }

    private func share(_ address: String) {
        ChatFolderInviteLinkActions.share(
            address,
            from: self,
            sourceView: tableView.cellForRow(at: IndexPath(row: 0, section: 0)),
        )
    }

    private func open(_ link: ChatInviteLink) {
        guard contextIsCurrent else { return }
        navigationController?.pushViewController(
            ChatInviteLinkViewController(target: target, link: link),
            animated: true,
        )
    }

    private func createLink() {
        guard contextIsCurrent else { return }
        navigationController?.pushViewController(
            ChatInviteLinkEditViewController(target: target, link: nil),
            animated: true,
        )
    }

    private func revoke(_ address: String) {
        ChatInviteLinkText.confirmRevoke(isChannel: target.isChannel, in: self) { [weak self] in
            guard let self else { return }
            let chatID = target.chatID
            perform(failureText: { ChatManagementRows.failureText($0) }) { client in
                _ = try await client.send(TDNativeRequests.revokeChatInviteLink(chatId: chatID, inviteLink: address))
            } completion: { [weak self] in
                self?.showToast(L10n.telegram("InviteLink.InviteLinkRevoked"))
                self?.load()
            }
        }
    }

    private func deleteRevoked(_ address: String) {
        confirm(
            message: L10n.telegram("InviteLink.DeleteLinkAlert.Text"),
            actionTitle: L10n.telegram("InviteLink.DeleteLinkAlert.Action"),
        ) { [weak self] in
            guard let self else { return }
            let chatID = target.chatID
            perform(failureText: { ChatManagementRows.failureText($0) }) { client in
                _ = try await client.send(TDNativeRequests.deleteRevokedChatInviteLink(
                    chatId: chatID, inviteLink: address,
                ))
            } completion: { [weak self] in
                self?.load()
            }
        }
    }

    private func deleteAllRevoked() {
        confirm(
            message: L10n.telegram("InviteLink.DeleteAllRevokedLinksAlert.Text"),
            actionTitle: L10n.telegram("InviteLink.DeleteAllRevokedLinksAlert.Action"),
        ) { [weak self] in
            guard let self else { return }
            let chatID = target.chatID
            let userID = myUserID
            perform(failureText: { ChatManagementRows.failureText($0) }) { client in
                _ = try await client.send(TDNativeRequests.deleteAllRevokedChatInviteLinks(
                    chatId: chatID, creatorUserId: userID,
                ))
            } completion: { [weak self] in
                self?.load()
            }
        }
    }
}

// MARK: - ChatInviteLinkViewController

/// Telegram's InviteLinkViewController: one link with Copy and Share, its state, the people who joined through it
/// (getChatInviteLinkMembers), Edit for an additional link, and Revoke or, once revoked, Delete.
final class ChatInviteLinkViewController: SettingsListViewController {
    private struct Joined {
        let peer: SettingsPeer
        let date: Int
    }

    private let target: ChatManagementTarget
    private var link: ChatInviteLink
    private var joined = [Joined]()
    private var isLoaded = false
    private var loadTask: Task<Void, Never>?

    init(target: ChatManagementTarget, link: ChatInviteLink) {
        self.target = target
        self.link = link
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
        updateChrome()
        load()
    }

    override func makeSections() -> [SettingsSection] {
        var linkRows = [SettingsRow(
            title: ChatInviteLinkText.address(link.inviteLink),
            style: .value,
            symbol: "link",
        ) { [weak self] in self?.copy() }]
        if !link.isRevoked {
            linkRows.append(SettingsRow(
                title: L10n.telegram("InviteLink.ContextCopy"),
                style: .action(destructive: false),
            ) { [weak self] in self?.copy() })
            linkRows.append(SettingsRow(
                title: L10n.telegram("InviteLink.ContextShare"),
                style: .action(destructive: false),
            ) { [weak self] in self?.share() })
        }
        var sections = [SettingsSection(footer: ChatInviteLinkText.status(link), rows: linkRows)]
        if !isLoaded {
            sections.append(SettingsSection(rows: [ChatManagementRows.loading]))
        } else if !joined.isEmpty {
            sections.append(SettingsSection(
                header: L10n.telegramPlural("InviteLink.PeopleJoined", count: max(link.memberCount, joined.count)),
                rows: joined.map { entry in
                    SettingsRow(
                        title: entry.peer.title,
                        detail: Foundation.Date(timeIntervalSince1970: TimeInterval(entry.date))
                            .formatted(date: .abbreviated, time: .shortened),
                        style: .peer(entry.peer),
                    )
                },
            ))
        }
        let isRevoked = link.isRevoked
        sections.append(SettingsSection(rows: [SettingsRow(
            title: L10n.telegram(isRevoked ? "InviteLink.ContextDelete" : "GroupInfo.InviteLink.RevokeLink"),
            style: .action(destructive: true),
        ) { [weak self] in
            if isRevoked { self?.delete() } else { self?.revoke() }
        }]))
        return sections
    }

    private func updateChrome() {
        title = link.name.isEmpty ? L10n.telegram("InviteLink.InviteLink") : link.name
        navigationItem.rightBarButtonItem = link.isPrimary || link.isRevoked
            ? nil
            : UIBarButtonItem(
                title: L10n.telegram("Common.Edit"), style: .plain, target: self, action: #selector(editPressed),
            )
    }

    private func load() {
        guard contextIsCurrent else { return }
        loadTask?.cancel()
        let client = client
        let chatID = target.chatID
        let address = link.inviteLink
        loadTask = Task { [weak self] in
            let members = await (try? client.send(TDNativeRequests.getChatInviteLinkMembers(
                chatId: chatID,
                inviteLink: address,
                onlyWithExpiredSubscription: false,
                offsetMember: nil,
                limit: 100,
            )))?.members ?? []
            var joined = [Joined]()
            for member in members {
                guard !Task.isCancelled else { return }
                guard let peer = await SettingsPeer.user(member.userId, client: client) else { continue }
                joined.append(Joined(peer: peer, date: member.joinedChatDate))
            }
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            loadTask = nil
            self.joined = joined
            isLoaded = true
            reload()
        }
    }

    private func copy() {
        ChatFolderInviteLinkActions.copy(link.inviteLink, in: self)
    }

    private func share() {
        ChatFolderInviteLinkActions.share(
            link.inviteLink,
            from: self,
            sourceView: tableView.cellForRow(at: IndexPath(row: 0, section: 0)),
        )
    }

    @objc private func editPressed() {
        guard contextIsCurrent else { return }
        let editor = ChatInviteLinkEditViewController(target: target, link: link)
        editor.onSave = { [weak self] link in
            guard let self else { return }
            self.link = link
            updateChrome()
            reload()
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func revoke() {
        ChatInviteLinkText.confirmRevoke(isChannel: target.isChannel, in: self) { [weak self] in
            guard let self else { return }
            let chatID = target.chatID
            let address = link.inviteLink
            perform(failureText: { ChatManagementRows.failureText($0) }) { client in
                _ = try await client.send(TDNativeRequests.revokeChatInviteLink(chatId: chatID, inviteLink: address))
            } completion: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
    }

    private func delete() {
        confirm(
            message: L10n.telegram("InviteLink.DeleteLinkAlert.Text"),
            actionTitle: L10n.telegram("InviteLink.DeleteLinkAlert.Action"),
        ) { [weak self] in
            guard let self else { return }
            let chatID = target.chatID
            let address = link.inviteLink
            perform(failureText: { ChatManagementRows.failureText($0) }) { client in
                _ = try await client.send(TDNativeRequests.deleteRevokedChatInviteLink(
                    chatId: chatID, inviteLink: address,
                ))
            } completion: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
    }
}

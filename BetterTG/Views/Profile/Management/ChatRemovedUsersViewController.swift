// ChatRemovedUsersViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatRemovedUsersViewController

/// Telegram's ChannelBlacklistController: the members admins removed (getSupergroupMembers with the banned filter),
/// who can't rejoin by link, each with the admin who removed them. Remove User bans a picked member; a row's menu
/// lifts the ban (setChatMemberStatus with chatMemberStatusLeft) or, in a group, adds them back. Each acts on its tap.
final class ChatRemovedUsersViewController: SettingsListViewController {
    private struct Entry {
        let member: ChatManagementMember
        let removedBy: String?
    }

    private let target: ChatManagementTarget
    private var entries = [Entry]()
    private var isLoaded = false
    private var loadTask: Task<Void, Never>?

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
        title = L10n.telegram("GroupRemoved.Title")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection(
            footer: L10n.telegram(target.isChannel ? "ChannelRemoved.RemoveInfo" : "GroupRemoved.RemoveInfo"),
            rows: [SettingsRow(
                title: L10n.telegram("GroupRemoved.Remove"),
                style: .action(destructive: false),
                symbol: "person.badge.minus",
            ) { [weak self] in self?.removeUser() }],
        )]
        guard isLoaded else {
            sections.append(SettingsSection(rows: [ChatManagementRows.loading]))
            return sections
        }
        guard !entries.isEmpty else { return sections }
        sections.append(SettingsSection(
            header: L10n.telegram("GroupRemoved.UsersSectionTitle"),
            rows: entries.enumerated().map { index, entry in
                SettingsRow(
                    title: entry.member.peer.title,
                    detail: entry.removedBy.map { L10n.telegram("Channel.Management.RemovedBy", $0) },
                    style: .peer(entry.member.peer),
                    action: { [weak self] in self?.presentMenu(for: entry, row: index) },
                    swipeAction: (
                        L10n.telegram("GroupRemoved.DeleteUser"),
                        { [weak self] in self?.unban(entry.member) },
                    ),
                )
            },
        ))
        return sections
    }

    private func load() {
        guard let supergroupID = target.supergroupID, contextIsCurrent, loadTask == nil else { return }
        let client = client
        loadTask = Task { [weak self] in
            let found = await (try? client.send(TDNativeRequests.getSupergroupMembers(
                supergroupId: supergroupID,
                filter: .supergroupMembersFilterBanned(TDNativeSupergroupMembersFilterBanned(query: "")),
                offset: 0,
                limit: 200,
            )))?.members ?? []
            let members = await ChatManagementMember.resolve(found, client: client)
            let removedBy = Dictionary(
                found.map { ($0.memberId, $0.inviterUserId) },
                uniquingKeysWith: { first, _ in first },
            )
            var removers = [Int64: String]()
            var entries = [Entry]()
            for member in members {
                let adminID = removedBy[member.sender] ?? 0
                if adminID != 0, removers[adminID] == nil {
                    removers[adminID] = await SettingsPeer.user(adminID, client: client)?.title
                }
                entries.append(Entry(member: member, removedBy: removers[adminID]))
            }
            guard let self else { return }
            loadTask = nil
            guard !Task.isCancelled, contextIsCurrent else { return }
            self.entries = entries
            isLoaded = true
            reload()
        }
    }

    /// ChannelBlacklistController's row actions: Add To Group in a group, and Delete, which lifts the ban.
    private func presentMenu(for entry: Entry, row: Int) {
        guard contextIsCurrent, let cell = tableView.cellForRow(at: IndexPath(row: row, section: 1)) else { return }
        var actions = [TelegramContextMenuAction]()
        if !target.isChannel, entry.member.userID != nil {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("GroupRemoved.AddToGroup"),
                image: UIImage(systemName: "person.badge.plus"),
            ) { [weak self] in self?.addBack(entry.member) })
        }
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram("GroupRemoved.DeleteUser"),
            image: UIImage(systemName: "trash"),
            isDestructive: true,
        ) { [weak self] in self?.unban(entry.member) })
        presentTelegramContextMenu(sourceView: cell, actions: actions, presentationStyle: .menuOnly)
    }

    private func unban(_ member: ChatManagementMember) {
        let chatID = target.chatID
        perform(failureText: { ChatManagementRows.failureText($0) }) { client in
            _ = try await client.send(TDNativeRequests.setChatMemberStatus(
                chatId: chatID, memberId: member.sender, status: .chatMemberStatusLeft,
            ))
        } completion: { [weak self] in
            self?.load()
        }
    }

    private func addBack(_ member: ChatManagementMember) {
        guard let userID = member.userID else { return }
        let chatID = target.chatID
        perform(failureText: { ChatManagementRows.failureText($0) }) { client in
            _ = try await client.send(TDNativeRequests.addChatMember(chatId: chatID, userId: userID, forwardLimit: 0))
        } completion: { [weak self] in
            self?.load()
        }
    }

    /// Remove User: a member picked from the chat is banned (banChatMember), as Telegram removes them.
    private func removeUser() {
        guard contextIsCurrent else { return }
        let picker = ChatMemberPickerViewController(target: target, title: L10n.telegram("GroupRemoved.Remove")) {
            switch $0.status {
            case .chatMemberStatusBanned, .chatMemberStatusCreator, .chatMemberStatusLeft: true
            case .chatMemberStatusAdministrator, .chatMemberStatusMember, .chatMemberStatusRestricted: false
            }
        }
        let chatID = target.chatID
        picker.onPick = { [weak self, weak picker] member in
            guard let self, contextIsCurrent else { return }
            perform(failureText: { ChatManagementRows.failureText($0) }) { client in
                _ = try await client.send(TDNativeRequests.banChatMember(
                    chatId: chatID, memberId: member.sender, bannedUntilDate: 0, revokeMessages: false,
                ))
            } completion: { [weak picker] in
                picker?.navigationController?.popViewController(animated: true)
            }
        }
        navigationController?.pushViewController(picker, animated: true)
    }
}

// ChatDiscussionViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatDiscussionViewController

/// Telegram's ChannelDiscussionGroupSetupController. A channel with a discussion group shows it with Unlink Group; a
/// group shows its channel with Unlink Channel; a channel without one lists the groups that may host its comments
/// (getSuitableDiscussionChats), and a picked group is linked after Telegram's confirmation (setChatDiscussionGroup).
/// A basic group is upgraded first, and a group that hides its history from new members is opened to them after
/// Telegram's warning, as TDLib requires.
final class ChatDiscussionViewController: SettingsListViewController {
    private let target: ChatManagementTarget
    private var linked: SettingsPeer?
    private var candidates = [SettingsPeer]()
    private var isLoaded = false
    private var loadTask: Task<Void, Never>?

    private var linkedChatID: Int64 {
        target.supergroupInfo?.linkedChatId ?? 0
    }

    private var canEdit: Bool {
        target.rights?.canChangeInfo == true
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
        title = L10n.telegram(target.isChannel ? "Channel.DiscussionGroup" : "Group.LinkedChannel")
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard isLoaded else { return [SettingsSection(rows: [ChatManagementRows.loading])] }
        if let linked {
            var sections = [SettingsSection(
                header: L10n.telegram(
                    target.isChannel ? "Channel.CommentsGroup.HeaderSet" : "Channel.CommentsGroup.HeaderGroupSet",
                    linked.title,
                ),
                footer: L10n.telegram("Channel.DiscussionGroup.Info"),
                rows: [SettingsRow(title: linked.title, style: .peer(linked))],
            )]
            if canEdit {
                sections.append(SettingsSection(rows: [SettingsRow(
                    title: L10n.telegram(
                        target.isChannel
                            ? "Channel.DiscussionGroup.UnlinkGroup"
                            : "Channel.DiscussionGroup.UnlinkChannel",
                    ),
                    style: .action(destructive: true),
                ) { [weak self] in self?.unlink() }]))
            }
            return sections
        }
        guard target.isChannel, canEdit else { return [] }
        return [SettingsSection(
            header: L10n.telegram("Channel.CommentsGroup.Header"),
            footer: L10n.telegram("Channel.DiscussionGroup.Info"),
            rows: candidates.map { group in
                SettingsRow(title: group.title, style: .peer(group)) { [weak self] in self?.confirmLink(group) }
            },
        )]
    }

    private func load() {
        guard contextIsCurrent else { return }
        loadTask?.cancel()
        let client = client
        let linkedChatID = linkedChatID
        let lists = target.isChannel && linkedChatID == 0
        loadTask = Task { [weak self] in
            var linked: SettingsPeer?
            var candidates = [SettingsPeer]()
            if linkedChatID != 0 {
                linked = await SettingsPeer.chat(linkedChatID, client: client)
            } else if lists {
                let chatIDs = await (try? client.send(TDNativeRequests.getSuitableDiscussionChats()))?.chatIds ?? []
                for chatID in chatIDs {
                    guard !Task.isCancelled else { return }
                    if let peer = await SettingsPeer.chat(chatID, client: client) { candidates.append(peer) }
                }
            }
            guard let self, !Task.isCancelled else { return }
            loadTask = nil
            guard contextIsCurrent else { return }
            self.linked = linked
            self.candidates = candidates
            isLoaded = true
            reload()
        }
    }

    /// ChannelDiscussionGroupActionSheetItem's question before linking.
    private func confirmLink(_ group: SettingsPeer) {
        let key = target.isPublic
            ? "Channel.DiscussionGroup.PublicChannelLink"
            : "Channel.DiscussionGroup.PrivateChannelLink"
        confirm(
            message: L10n.telegram(key, group.title, target.chat.title),
            actionTitle: L10n.telegram("Channel.DiscussionGroup.LinkGroup"),
            isDestructive: false,
        ) { [weak self] in self?.prepareLink(group.id) }
    }

    /// TDLib links supergroups whose history new members can see: a basic group is upgraded, and hidden history is
    /// opened after Telegram's MakeHistoryPublic warning.
    private func prepareLink(_ groupChatID: Int64) {
        guard contextIsCurrent else { return }
        let client = client
        Task { [weak self] in
            guard let chat = try? await client.getChat(chatId: groupChatID) else { return }
            var hidesHistory = false
            if case .chatTypeSupergroup(let value) = chat.type {
                let info = try? await client.getSupergroupFullInfo(supergroupId: value.supergroupId)
                hidesHistory = info?.isAllHistoryAvailable == false
            }
            guard let self, contextIsCurrent else { return }
            guard hidesHistory else {
                link(chat)
                return
            }
            confirm(
                message: L10n.telegram("Channel.DiscussionGroup.MakeHistoryPublic"),
                actionTitle: L10n.telegram("Channel.DiscussionGroup.MakeHistoryPublicProceed"),
                isDestructive: false,
            ) { [weak self] in self?.link(chat) }
        }
    }

    private func link(_ group: Chat) {
        let channelID = target.chatID
        perform(failureText: { ChatManagementRows.failureText($0) }) { client in
            var groupChatID = group.id
            switch group.type {
            case .chatTypeBasicGroup:
                groupChatID = try await client.send(TDNativeRequests.upgradeBasicGroupChatToSupergroupChat(
                    chatId: group.id,
                ))
                .id
            case .chatTypeSupergroup(let value):
                let info = try await client.getSupergroupFullInfo(supergroupId: value.supergroupId)
                if !info.isAllHistoryAvailable {
                    _ = try await client.send(TDNativeRequests.toggleSupergroupIsAllHistoryAvailable(
                        supergroupId: value.supergroupId, isAllHistoryAvailable: true,
                    ))
                }
            case .chatTypePrivate, .chatTypeSecret:
                return
            }
            _ = try await client.send(TDNativeRequests.setChatDiscussionGroup(
                chatId: channelID, discussionChatId: groupChatID,
            ))
        } completion: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    /// Unlinking always goes through the channel.
    private func unlink() {
        let channelID = target.isChannel ? target.chatID : linkedChatID
        guard channelID != 0 else { return }
        perform(failureText: { ChatManagementRows.failureText($0) }) { client in
            _ = try await client.send(TDNativeRequests.setChatDiscussionGroup(chatId: channelID, discussionChatId: 0))
        } completion: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }
}

// BlockedUsersViewController.swift

import TDLibKit
import UIKit

// MARK: - BlockedUsersViewController

/// Telegram's BlockedPeersController: Block User..., which picks a person (contacts and private chats) and blocks them
/// at once, then the blocked people and chats, loaded in pages, with swipe to Unblock (setMessageSenderBlockList with
/// no list).
final class BlockedUsersViewController: SettingsListViewController {
    private static let pageSize = 50

    private var senders = [(sender: MessageSender, peer: SettingsPeer)]()
    private var totalCount: Int?
    private var isLoading = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("BlockedUsers.Title")
        loadMore()
    }

    override func makeSections() -> [SettingsSection] {
        var rows = senders.map { item in
            SettingsRow(
                title: item.peer.title,
                style: .peer(item.peer),
                swipeAction: (
                    title: L10n.telegram("BlockedUsers.Unblock"),
                    handler: { [weak self] in self?.unblock(item.sender) },
                ),
            )
        }
        if isLoading || totalCount == nil {
            rows.append(SettingsRow(
                title: L10n.telegram("Channel.NotificationLoading"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            ))
        } else if rows.isEmpty {
            rows.append(SettingsRow(
                title: L10n.telegram("PrivacySettings.BlockedPeersEmpty"),
                style: .status(.secondaryLabel),
            ))
        }
        let add = SettingsRow(
            title: L10n.telegram("BlockedUsers.BlockUser"),
            style: .action(destructive: false),
            symbol: "plus",
        ) { [weak self] in self?.pickUser() }
        return [SettingsSection(footer: L10n.telegram("BlockedUsers.Info"), rows: [add] + rows)]
    }

    override func tableView(_ tableView: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row >= tableView.numberOfRows(inSection: indexPath.section) - 5 else { return }
        loadMore()
    }

    /// addPeer: the person picker titled Block User; the chosen one is blocked and the list starts over.
    private func pickUser() {
        var blocked = Set<Int64>()
        for item in senders {
            if case .messageSenderUser(let user) = item.sender { blocked.insert(user.userId) }
        }
        let picker = SettingsPeerPickerViewController(excludedUserIDs: blocked, excludedChatIDs: [])
        picker.pickerTitle = L10n.telegram("BlockedUsers.SelectUserTitle")
        picker.onPickUser = { [weak self, weak picker] userID in
            guard let self else { return }
            perform { client in
                _ = try await client.send(TDNativeRequests.setMessageSenderBlockList(
                    senderId: .messageSenderUser(.init(userId: userID)), blockList: .blockListMain,
                ))
            } completion: { [weak self, weak picker] in
                picker?.dismiss(animated: true)
                guard let self else { return }
                senders = []
                totalCount = nil
                reload()
                loadMore()
            }
        }
        present(TelegramNavigationController(rootViewController: picker), animated: true)
    }

    private func loadMore() {
        guard !isLoading, contextIsCurrent, totalCount.map({ senders.count < $0 }) ?? true else { return }
        isLoading = true
        let client = client
        let offset = senders.count
        Task { [weak self] in
            let page = try? await client.send(TDNativeRequests.getBlockedMessageSenders(
                blockList: .blockListMain, offset: offset, limit: Self.pageSize,
            ))
            var loaded = [(sender: MessageSender, peer: SettingsPeer)]()
            for sender in page?.senders ?? [] {
                if let peer = await SettingsPeer.resolve(sender, client: client) {
                    loaded.append((sender: sender, peer: peer))
                }
            }
            guard let self, contextIsCurrent else { return }
            isLoading = false
            senders += loaded
            let loadedCount = senders.count
            totalCount = page.map { max($0.totalCount, loadedCount) } ?? loadedCount
            if page?.senders.isEmpty != false { totalCount = senders.count }
            reload()
        }
    }

    private func unblock(_ sender: MessageSender) {
        perform { client in
            _ = try await client.send(TDNativeRequests.setMessageSenderBlockList(senderId: sender, blockList: nil))
        } completion: { [weak self] in
            guard let self else { return }
            senders.removeAll { $0.sender == sender }
            totalCount = totalCount.map { max(0, $0 - 1) }
            reload()
        }
    }
}

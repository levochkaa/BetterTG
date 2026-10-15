// BlockedUsersViewController.swift

import TDLibKit
import UIKit

// MARK: - BlockedUsersViewController

/// Telegram's BlockedPeersController: the blocked people and chats, loaded in pages, with swipe to Unblock
/// (setMessageSenderBlockList with no list). Blocking someone new happens from their chat or profile.
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
        return [SettingsSection(footer: L10n.telegram("BlockedUsers.Info"), rows: rows)]
    }

    override func tableView(_ tableView: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row >= tableView.numberOfRows(inSection: indexPath.section) - 5 else { return }
        loadMore()
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
            totalCount = page.map { max($0.totalCount, senders.count) } ?? senders.count
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

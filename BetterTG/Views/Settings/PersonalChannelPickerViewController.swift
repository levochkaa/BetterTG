// PersonalChannelPickerViewController.swift

import TDLibKit
import UIKit

// MARK: - PersonalChannelPickerViewController

/// PeerSelectionScreen for the personal channel: "Channel" over "select your channel", Hide Channel while one is set,
/// then the account's public channels (getSuitablePersonalChats) with their subscribers. Choosing one, or Hide, hands
/// it back and returns; the current one only returns.
final class PersonalChannelPickerViewController: SettingsListViewController {
    var onSelect: (((id: Int64, title: String)?) -> Void)?

    private let currentID: Int64?
    private var channels: [(peer: SettingsPeer, subscribers: Int)]?

    init(currentID: Int64?) {
        self.currentID = currentID
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Settings.PersonalChannelSelectTitle")
        navigationItem.subtitle = L10n.telegram("Settings.PersonalChannelSelectSubtitle")
        load()
    }

    override func makeSections() -> [SettingsSection] {
        var rows = [SettingsRow]()
        if currentID != nil {
            rows.append(SettingsRow(
                title: L10n.telegram("Settings.PersonalChannelRemove"),
                style: .action(destructive: false),
                symbol: "eye.slash",
            ) { [weak self] in self?.select(nil) })
        }
        for channel in channels ?? [] {
            rows.append(SettingsRow(
                title: channel.peer.title,
                detail: channel.subscribers > 0
                    ? L10n.telegramPlural("Conversation.StatusSubscribers", count: channel.subscribers)
                    : L10n.telegram("Channel.Status"),
                style: .peer(channel.peer),
            ) { [weak self] in self?.select((channel.peer.id, channel.peer.title)) })
        }
        return rows.isEmpty ? [] : [SettingsSection(rows: rows)]
    }

    private func load() {
        let client = client
        Task { [weak self] in
            let ids = await (try? client.send(TDNativeRequests.getSuitablePersonalChats()))?.chatIds ?? []
            var loaded = [(peer: SettingsPeer, subscribers: Int)]()
            for id in ids {
                guard let chat = try? await client.getChat(chatId: id) else { continue }
                var subscribers = 0
                if case .chatTypeSupergroup(let group) = chat.type,
                   let supergroup = try? await client.getSupergroup(supergroupId: group.supergroupId)
                {
                    subscribers = supergroup.memberCount
                }
                loaded.append((SettingsPeer(chat: chat), subscribers))
            }
            guard let self, contextIsCurrent else { return }
            channels = loaded
            reload()
        }
    }

    private func select(_ channel: (id: Int64, title: String)?) {
        if channel?.id != currentID { onSelect?(channel) }
        navigationController?.popViewController(animated: true)
    }
}

// GiftTransferPickerViewController.swift

import TDLibKit
import UIKit

// MARK: - GiftTransferPickerViewController

/// makePremiumGiftController's `.starGiftTransfer` contact selection, titled Transfer: the account's contacts, and
/// while searching the people and channels TDLib finds for the query (`allowChannelsInSearch`). A tap hands the
/// person or channel back; the caller asks to confirm.
final class GiftTransferPickerViewController: SettingsListViewController, UISearchResultsUpdating {
    struct Recipient {
        let peer: SettingsPeer
        let sender: MessageSender
        let isChannel: Bool
    }

    var onPick: ((Recipient) -> Void)?

    private var contacts = [Recipient]()
    private var results = [Recipient]()
    private var query = ""
    private var isLoading = true
    private var searchTask: Task<Void, Never>?
    private let searchController = UISearchController(searchResultsController: nil)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Gift.Transfer.Title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.telegram("Common.Search")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        load()
    }

    override func makeSections() -> [SettingsSection] {
        if isLoading {
            return [SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Channel.NotificationLoading"),
                style: .status(.secondaryLabel),
                accessory: .activity,
            )])]
        }
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var visible = normalized.isEmpty
            ? contacts
            : contacts.filter { $0.peer.title.localizedCaseInsensitiveContains(normalized) }
        if !normalized.isEmpty {
            let shown = Set(visible.map(\.peer.id))
            visible += results.filter { !shown.contains($0.peer.id) }
        }
        return [SettingsSection(rows: visible.map { recipient in
            SettingsRow(
                title: recipient.peer.title,
                detail: recipient.isChannel ? L10n.telegram("Channel.Status") : nil,
                style: .peer(recipient.peer),
            ) { [weak self] in self?.onPick?(recipient) }
        })]
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        reload()
        search(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func load() {
        let client = client
        Task { [weak self] in
            let me = try? await client.getMe()
            let ids = await (try? client.send(TDNativeRequests.getContacts()))?.userIds ?? []
            var contacts = [Recipient]()
            for id in ids where id != me?.id {
                guard let peer = await SettingsPeer.user(id, client: client) else { continue }
                contacts.append(Recipient(peer: peer, sender: .messageSenderUser(.init(userId: id)), isChannel: false))
            }
            guard let self, contextIsCurrent else { return }
            self.contacts = contacts
            isLoading = false
            reload()
        }
    }

    /// The people (not bots) and channels among TDLib's chats for the query, the account itself left out.
    private func search(_ query: String) {
        searchTask?.cancel()
        results = []
        guard !query.isEmpty else { return }
        let client = client
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let me = try? await client.getMe()
            let ids = await (try? client.send(TDNativeRequests.searchChats(query: query, typeFilter: nil, limit: 50)))?
                .chatIds ?? []
            var found = [Recipient]()
            for id in ids {
                guard let chat = try? await client.getChat(chatId: id) else { continue }
                switch chat.type {
                case .chatTypePrivate(let info):
                    guard info.userId != me?.id, let user = try? await client.getUser(userId: info.userId),
                          case .userTypeRegular = user.type,
                          let peer = await SettingsPeer.user(info.userId, client: client) else { continue }
                    found.append(Recipient(
                        peer: peer, sender: .messageSenderUser(.init(userId: info.userId)), isChannel: false,
                    ))
                case .chatTypeSupergroup(let info) where info.isChannel:
                    found.append(Recipient(
                        peer: SettingsPeer(chat: chat), sender: .messageSenderChat(.init(chatId: chat.id)),
                        isChannel: true,
                    ))
                default:
                    continue
                }
            }
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            results = found
            reload()
        }
    }
}

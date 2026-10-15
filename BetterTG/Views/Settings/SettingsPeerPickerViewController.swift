// SettingsPeerPickerViewController.swift

import TDLibKit
import UIKit

// MARK: - SettingsPeerPickerViewController

/// The people and groups a privacy exception can name (Telegram's Add Users search): contacts, then people and
/// groups from the chat list, filtered by the search field. Several can be checked; Done hands them back.
final class SettingsPeerPickerViewController: SettingsListViewController, UISearchResultsUpdating {
    private struct Item {
        let isUser: Bool
        let peer: SettingsPeer
        let detail: String?
    }

    /// The checked user and chat identifiers.
    var onDone: (([Int64], [Int64]) -> Void)?

    private let excludedUserIDs: Set<Int64>
    private let excludedChatIDs: Set<Int64>
    private var items = [Item]()
    private var selectedUserIDs = [Int64]()
    private var selectedChatIDs = [Int64]()
    private var query = ""
    private var isLoading = true
    private let searchController = UISearchController(searchResultsController: nil)

    init(excludedUserIDs: Set<Int64>, excludedChatIDs: Set<Int64>) {
        self.excludedUserIDs = excludedUserIDs
        self.excludedChatIDs = excludedChatIDs
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("PrivacySettings.SearchUsersTitle")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"), style: .plain, target: self, action: #selector(cancelPressed),
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Done"), style: .prominent, target: self, action: #selector(donePressed),
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.telegram("PrivacySettings.SearchUsersPlaceholder")
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
        let visible = normalized.isEmpty
            ? items
            : items.filter { $0.peer.title.localizedCaseInsensitiveContains(normalized) }
        return [SettingsSection(rows: visible.map { item in
            let selected = item.isUser
                ? selectedUserIDs.contains(item.peer.id)
                : selectedChatIDs.contains(item.peer.id)
            return SettingsRow(
                title: item.peer.title,
                detail: item.detail,
                style: .peer(item.peer),
                accessory: selected ? .checkmark : .none,
            ) { [weak self] in self?.toggle(item) }
        })]
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        reload()
    }

    private func load() {
        let client = client
        let excludedUserIDs = excludedUserIDs
        let excludedChatIDs = excludedChatIDs
        let mainChats = RootVM.shared
            .folders
            .first { folder in
                if case .main = folder.type { true } else { false }
            }?.chats ?? []
        Task { [weak self] in
            var items = [Item]()
            var seenUsers = Set<Int64>()
            let me = try? await client.getMe()
            let contacts = await (try? client.send(TDNativeRequests.getContacts()))?.userIds ?? []
            for id in contacts where id != me?.id && !excludedUserIDs.contains(id) {
                guard seenUsers.insert(id).inserted, let peer = await SettingsPeer.user(id, client: client) else {
                    continue
                }
                items.append(Item(isUser: true, peer: peer, detail: nil))
            }
            for chat in mainChats {
                switch chat.type {
                case .user(let user):
                    guard !chat.isSavedMessages, !excludedUserIDs.contains(user.id),
                          seenUsers.insert(user.id).inserted,
                          let peer = await SettingsPeer.user(user.id, client: client) else { continue }
                    items.append(Item(isUser: true, peer: peer, detail: nil))
                case .group:
                    guard !excludedChatIDs.contains(chat.id) else { continue }
                    items.append(Item(
                        isUser: false,
                        peer: SettingsPeer(chat: chat.chat),
                        detail: L10n.telegram("Group.Status"),
                    ))
                case .supergroup(let group):
                    guard !group.isChannel, !excludedChatIDs.contains(chat.id) else { continue }
                    items.append(Item(
                        isUser: false,
                        peer: SettingsPeer(chat: chat.chat),
                        detail: L10n.telegram("Group.Status"),
                    ))
                case .bot:
                    continue
                }
            }
            guard let self, contextIsCurrent else { return }
            self.items = items
            isLoading = false
            reload()
        }
    }

    private func toggle(_ item: Item) {
        let id = item.peer.id
        if item.isUser {
            if let index = selectedUserIDs.firstIndex(of: id) {
                selectedUserIDs.remove(at: index)
            } else {
                selectedUserIDs.append(id)
            }
        } else {
            if let index = selectedChatIDs.firstIndex(of: id) {
                selectedChatIDs.remove(at: index)
            } else {
                selectedChatIDs.append(id)
            }
        }
        navigationItem.rightBarButtonItem?.isEnabled = !selectedUserIDs.isEmpty || !selectedChatIDs.isEmpty
        reload()
    }

    @objc private func cancelPressed() {
        dismiss(animated: true)
    }

    @objc private func donePressed() {
        let users = selectedUserIDs
        let chats = selectedChatIDs
        let onDone = onDone
        dismiss(animated: true) { onDone?(users, chats) }
    }
}

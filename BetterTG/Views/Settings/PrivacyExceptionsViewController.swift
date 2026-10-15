// PrivacyExceptionsViewController.swift

import TDLibKit
import UIKit

// MARK: - PrivacyExceptionsViewController

/// Telegram's SelectivePrivacySettingsPeersController: the people and groups of one exception list, Add Users or
/// Groups, and swipe to remove. Every change goes back to the rule editor, which saves it.
final class PrivacyExceptionsViewController: SettingsListViewController {
    var onChange: (([Int64], [Int64]) -> Void)?

    private var userIDs: [Int64]
    private var chatIDs: [Int64]
    private var users = [Int64: SettingsPeer]()
    private var chats = [Int64: SettingsPeer]()

    init(title: String, userIDs: [Int64], chatIDs: [Int64]) {
        self.userIDs = userIDs
        self.chatIDs = chatIDs
        super.init()
        self.title = title
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        resolvePeers()
    }

    override func makeSections() -> [SettingsSection] {
        var rows = [SettingsRow(
            title: L10n.telegram("Privacy.AddNewPeer"),
            style: .action(destructive: false),
            symbol: "plus.circle.fill",
        ) { [weak self] in self?.presentPicker() }]
        for id in userIDs {
            guard let peer = users[id] else { continue }
            rows.append(SettingsRow(
                title: peer.title,
                style: .peer(peer),
                swipeAction: (
                    title: L10n.telegram("Common.Delete"),
                    handler: { [weak self] in self?.remove(userID: id, chatID: nil) },
                ),
            ))
        }
        for id in chatIDs {
            guard let peer = chats[id] else { continue }
            rows.append(SettingsRow(
                title: peer.title,
                detail: L10n.telegram("Group.Status"),
                style: .peer(peer),
                swipeAction: (
                    title: L10n.telegram("Common.Delete"),
                    handler: { [weak self] in self?.remove(userID: nil, chatID: id) },
                ),
            ))
        }
        let count = userIDs.count + chatIDs.count
        return [SettingsSection(
            header: count == 0 ? nil : L10n.telegramPlural("Privacy.ExceptionsCount", count: count),
            rows: rows,
        )]
    }

    private func resolvePeers() {
        let client = client
        let userIDs = userIDs.filter { users[$0] == nil }
        let chatIDs = chatIDs.filter { chats[$0] == nil }
        Task { [weak self] in
            var resolvedUsers = [Int64: SettingsPeer]()
            var resolvedChats = [Int64: SettingsPeer]()
            for id in userIDs {
                resolvedUsers[id] = await SettingsPeer.user(id, client: client)
            }
            for id in chatIDs {
                resolvedChats[id] = await SettingsPeer.chat(id, client: client)
            }
            guard let self, contextIsCurrent else { return }
            users.merge(resolvedUsers) { _, latest in latest }
            chats.merge(resolvedChats) { _, latest in latest }
            reload()
        }
    }

    private func presentPicker() {
        guard contextIsCurrent, presentedViewController == nil else { return }
        let picker = SettingsPeerPickerViewController(excludedUserIDs: Set(userIDs), excludedChatIDs: Set(chatIDs))
        picker.onDone = { [weak self] pickedUsers, pickedChats in
            guard let self else { return }
            userIDs += pickedUsers
            chatIDs += pickedChats
            notify()
            resolvePeers()
        }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    private func remove(userID: Int64?, chatID: Int64?) {
        if let userID { userIDs.removeAll { $0 == userID } }
        if let chatID { chatIDs.removeAll { $0 == chatID } }
        notify()
        reload()
    }

    private func notify() {
        onChange?(userIDs, chatIDs)
    }
}

// BotPeerRequestViewController.swift

import TDLibKit
import UIKit

// MARK: - BotPeerRequestViewController

/// Telegram's openRequestedPeerSelection for a reply keyboard's users or chat request button: the user's contacts and
/// chats that TDLib accepts for the button (its own check with `only_check`), searchable. A person is shared on tap,
/// or several with Done up to the button's limit (shareUsersWithBot); a group or channel after Telegram's confirmation
/// (shareChatWithBot).
final class BotPeerRequestViewController: SettingsListViewController, UISearchResultsUpdating {
    enum Request {
        case users(TDNativeKeyboardButtonTypeRequestUsers)
        case chat(TDNativeKeyboardButtonTypeRequestChat)
    }

    private struct Candidate {
        let id: Int64
        let peer: SettingsPeer
        let detail: String?
    }

    private let request: Request
    private let source: TDNativeKeyboardButtonSource
    private let botName: String
    private let onShared: () -> Void
    private let searchController = UISearchController(searchResultsController: nil)
    private var candidates = [Candidate]()
    private var selectedIDs = [Int64]()
    private var query = ""
    private var isLoading = true
    private var isSending = false

    private var buttonID: Int {
        switch request {
        case .users(let users): users.id
        case .chat(let chat): chat.id
        }
    }

    private var maximumQuantity: Int {
        if case .users(let users) = request { return max(1, users.maxQuantity) }
        return 1
    }

    /// RequestPeer's empty states, without the list of requirements.
    private var emptyText: String {
        switch request {
        case .users(let users) where users.restrictUserIsBot && users.userIsBot:
            L10n.telegram("RequestPeer.BotsAllEmpty")
        case .users:
            L10n.telegram("RequestPeer.UsersAllEmpty")
        case .chat(let chat):
            L10n.telegram(chat.chatIsChannel ? "RequestPeer.ChannelsAllEmpty" : "RequestPeer.GroupsAllEmpty")
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private init(
        request: Request,
        source: TDNativeKeyboardButtonSource,
        botName: String,
        onShared: @escaping () -> Void,
    ) {
        self.request = request
        self.source = source
        self.botName = botName
        self.onShared = onShared
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title =
            switch request {
            case .users(let users) where users.maxQuantity > 1: L10n.telegram("RequestPeer.SelectUsers")
            case .users(let users) where users.restrictUserIsBot && users.userIsBot:
                L10n.telegram("RequestPeer.ChooseBotTitle")
            case .users: L10n.telegram("RequestPeer.ChooseUserTitle")
            case .chat(let chat): L10n.telegram(chat.chatIsChannel
                    ? "RequestPeer.ChooseChannelTitle"
                    : "RequestPeer.ChooseGroupTitle")
            }
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"), style: .plain, target: self, action: #selector(cancelPressed),
        )
        if maximumQuantity > 1 {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: L10n.telegram("Common.Done"), style: .prominent, target: self, action: #selector(donePressed),
            )
            navigationItem.rightBarButtonItem?.isEnabled = false
        }
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.telegram("RequestPeer.SelectUsers.SearchPlaceholder")
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
        guard !candidates.isEmpty else {
            return [SettingsSection(rows: [SettingsRow(title: emptyText, style: .status(.secondaryLabel))])]
        }
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = normalized.isEmpty
            ? candidates
            : candidates.filter { $0.peer.title.localizedCaseInsensitiveContains(normalized) }
        return [SettingsSection(rows: visible.map { candidate in
            SettingsRow(
                title: candidate.peer.title,
                detail: candidate.detail,
                style: .peer(candidate.peer),
                accessory: selectedIDs.contains(candidate.id) ? .checkmark : .none,
                isEnabled: !isSending,
            ) { [weak self] in self?.select(candidate) }
        })]
    }

    static func present(
        _ request: Request,
        source: TDNativeKeyboardButtonSource,
        botName: String,
        from presenter: UIViewController,
        onShared: @escaping () -> Void,
    ) {
        let navigation = TelegramNavigationController(rootViewController: BotPeerRequestViewController(
            request: request,
            source: source,
            botName: botName,
            onShared: onShared,
        ))
        navigation.modalPresentationStyle = .pageSheet
        presenter.chatListTopPresenter.present(navigation, animated: true)
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        reload()
    }

    /// Contacts and chats from the main list of the requested kind, kept when TDLib accepts them for the button.
    private func load() {
        let client = client
        let request = request
        let source = source
        let buttonID = buttonID
        let mainChats = RootVM.shared
            .folders
            .first { folder in
                if case .main = folder.type { true } else { false }
            }?.chats ?? []
        Task { [weak self] in
            var found = [Candidate]()
            switch request {
            case .users:
                var seen = Set<Int64>()
                let me = try? await client.getMe()
                let contacts = await (try? client.send(TDNativeRequests.getContacts()))?.userIds ?? []
                let chatUsers = mainChats.compactMap { chat -> Int64? in
                    guard !chat.isSavedMessages else { return nil }
                    switch chat.type {
                    case .bot(let user),
                         .user(let user): return user.id
                    case .group,
                         .supergroup: return nil
                    }
                }
                for id in contacts + chatUsers where id != me?.id && seen.insert(id).inserted {
                    guard await (try? client.send(TDNativeRequests.shareUsersWithBot(
                        source: source, buttonId: buttonID, sharedUserIds: [id], onlyCheck: true,
                    ))) != nil, let user = try? await client.getUser(userId: id),
                                    let peer = await SettingsPeer.user(id, client: client) else { continue }
                    found.append(Candidate(
                        id: id,
                        peer: peer,
                        detail: user.usernames?.activeUsernames.first.map { "@" + $0 },
                    ))
                }
            case .chat(let chat):
                for item in mainChats {
                    let isChannel: Bool
                    switch item.type {
                    case .group: isChannel = false
                    case .supergroup(let group): isChannel = group.isChannel
                    case .bot,
                         .user: continue
                    }
                    guard isChannel == chat.chatIsChannel,
                          await (try? client.send(TDNativeRequests.shareChatWithBot(
                              source: source, buttonId: buttonID, sharedChatId: item.id, onlyCheck: true,
                          ))) != nil else { continue }
                    found.append(Candidate(
                        id: item.id,
                        peer: SettingsPeer(chat: item.chat),
                        detail: L10n.telegram(isChannel ? "Channel.Status" : "Group.Status"),
                    ))
                }
            }
            guard let self, contextIsCurrent else { return }
            candidates = found
            isLoading = false
            reload()
        }
    }

    private func select(_ candidate: Candidate) {
        guard !isSending else { return }
        switch request {
        case .users where maximumQuantity > 1:
            if let index = selectedIDs.firstIndex(of: candidate.id) {
                selectedIDs.remove(at: index)
            } else if selectedIDs.count >= maximumQuantity {
                showToast(L10n.telegramPlural("RequestPeer.ReachedMaximum", count: maximumQuantity))
                return
            } else {
                selectedIDs.append(candidate.id)
            }
            navigationItem.rightBarButtonItem?.isEnabled = !selectedIDs.isEmpty
            reload()
        case .users:
            share([candidate.id])
        case .chat(let chat):
            confirm(candidate, chat: chat)
        }
    }

    /// openRequestedPeerSelection's confirmation: the chat goes to the bot, which may join it or become its admin.
    private func confirm(_ candidate: Candidate, chat: TDNativeKeyboardButtonTypeRequestChat) {
        let message: String? =
            if chat.botAdministratorRights != nil {
                L10n.telegram("RequestPeer.SelectionConfirmationInviteAdminText", botName, candidate.peer.title)
            } else if chat.botIsMember {
                L10n.telegram("RequestPeer.SelectionConfirmationInviteText", botName, candidate.peer.title)
            } else {
                nil
            }
        confirm(
            title: L10n.telegram("RequestPeer.SelectionConfirmationTitle", candidate.peer.title, botName),
            message: message,
            actionTitle: L10n.telegram("RequestPeer.SelectionConfirmationSend"),
            isDestructive: false,
        ) { [weak self] in self?.share([candidate.id]) }
    }

    private func share(_ ids: [Int64]) {
        guard !isSending, !ids.isEmpty, contextIsCurrent else { return }
        isSending = true
        reload()
        let request = request
        let source = source
        let buttonID = buttonID
        perform(failureText: { [weak self] _ in
            self?.isSending = false
            self?.reload()
            return nil
        }, { client in
            _ =
                switch request {
                case .users:
                    try await client.send(TDNativeRequests.shareUsersWithBot(
                        source: source, buttonId: buttonID, sharedUserIds: ids, onlyCheck: false,
                    ))
                case .chat:
                    try await client.send(TDNativeRequests.shareChatWithBot(
                        source: source, buttonId: buttonID, sharedChatId: ids[0], onlyCheck: false,
                    ))
                }
        }, completion: { [weak self] in
            guard let self else { return }
            let onShared = onShared
            dismiss(animated: true) { onShared() }
        })
    }

    @objc private func cancelPressed() {
        dismiss(animated: true)
    }

    @objc private func donePressed() {
        share(selectedIDs)
    }
}

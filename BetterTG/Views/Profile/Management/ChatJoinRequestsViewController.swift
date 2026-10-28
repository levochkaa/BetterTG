// ChatJoinRequestsViewController.swift

import TDLibKit
import UIKit

// MARK: - ChatJoinRequestsViewController

/// Telegram's InviteRequestsController: the people who asked to join through links that need approval
/// (getChatJoinRequests), with a search. A request's menu or swipe adds the person (processChatJoinRequest with
/// approve) or dismisses the request, each on its own tap.
final class ChatJoinRequestsViewController: SettingsListViewController, UISearchResultsUpdating {
    private struct Request {
        let userID: Int64
        let peer: SettingsPeer
        let date: Int
        let bio: String
    }

    private static let searchDelay = Duration.milliseconds(250)
    private static let pageLimit = 200

    private let target: ChatManagementTarget
    private let searchController = UISearchController(searchResultsController: nil)
    private var requests = [Request]()
    private var totalCount = 0
    private var query = ""
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
        title = L10n.telegram("MemberRequests.Title")
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.telegram("MemberRequests.SearchPlaceholder")
        load()
    }

    override func makeSections() -> [SettingsSection] {
        guard isLoaded else { return [SettingsSection(rows: [ChatManagementRows.loading])] }
        guard !requests.isEmpty else {
            if !query.isEmpty {
                return [SettingsSection(rows: [SettingsRow(
                    title: L10n.telegram("Contacts.Search.NoResults"),
                    style: .status(.secondaryLabel),
                )])]
            }
            return [SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("MemberRequests.NoRequests"),
                detail: L10n.telegram(
                    target.isChannel
                        ? "MemberRequests.NoRequestsDescriptionChannel"
                        : "MemberRequests.NoRequestsDescriptionGroup",
                ),
                style: .subtitle,
            )])]
        }
        return [SettingsSection(
            header: L10n.telegramPlural("MemberRequests.PeopleRequested", count: max(totalCount, requests.count)),
            footer: query.isEmpty
                ? L10n.telegram(
                    target.isChannel ? "MemberRequests.DescriptionChannel" : "MemberRequests.DescriptionGroup",
                )
                .withoutTelegramLinks
                : nil,
            rows: requests.enumerated().map { index, request in
                SettingsRow(
                    title: request.peer.title,
                    detail: request.bio.isEmpty ? SettingsFormatting.activityDate(request.date) : request.bio,
                    style: .peer(request.peer),
                    action: { [weak self] in self?.presentMenu(for: request, row: index) },
                    swipeAction: (
                        L10n.telegram("MemberRequests.Dismiss"),
                        { [weak self] in self?.process(request, approve: false) },
                    ),
                )
            },
        )]
    }

    func updateSearchResults(for searchController: UISearchController) {
        let text = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != query else { return }
        query = text
        load()
    }

    private func load() {
        guard contextIsCurrent else { return }
        loadTask?.cancel()
        let client = client
        let chatID = target.chatID
        let query = query
        loadTask = Task { [weak self] in
            if !query.isEmpty { try? await Task.sleep(for: Self.searchDelay) }
            guard !Task.isCancelled else { return }
            let result = try? await client.send(TDNativeRequests.getChatJoinRequests(
                chatId: chatID, inviteLink: "", query: query, offsetRequest: nil, limit: Self.pageLimit,
            ))
            var requests = [Request]()
            for request in result?.requests ?? [] {
                guard !Task.isCancelled else { return }
                guard let peer = await SettingsPeer.user(request.userId, client: client) else { continue }
                requests.append(Request(userID: request.userId, peer: peer, date: request.date, bio: request.bio))
            }
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            loadTask = nil
            self.requests = requests
            totalCount = result?.totalCount ?? requests.count
            isLoaded = true
            reload()
        }
    }

    /// The request's actions: Add to Group or Channel, and Dismiss.
    private func presentMenu(for request: Request, row: Int) {
        guard contextIsCurrent, let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) else { return }
        presentTelegramContextMenu(sourceView: cell, actions: [
            TelegramContextMenuAction(
                title: L10n.telegram(target.isChannel ? "MemberRequests.AddToChannel" : "MemberRequests.AddToGroup"),
                image: UIImage(systemName: "person.badge.plus"),
            ) { [weak self] in self?.process(request, approve: true) },
            TelegramContextMenuAction(
                title: L10n.telegram("MemberRequests.Dismiss"),
                image: UIImage(systemName: "xmark.circle"),
                isDestructive: true,
            ) { [weak self] in self?.process(request, approve: false) },
        ], presentationStyle: .menuOnly)
    }

    private func process(_ request: Request, approve: Bool) {
        let chatID = target.chatID
        let isChannel = target.isChannel
        perform(failureText: { ChatManagementRows.failureText($0) }) { client in
            _ = try await client.send(TDNativeRequests.processChatJoinRequest(
                chatId: chatID, userId: request.userID, approve: approve,
            ))
        } completion: { [weak self] in
            guard let self else { return }
            requests.removeAll { $0.userID == request.userID }
            totalCount = max(0, totalCount - 1)
            reload()
            if approve {
                showToast(L10n.telegram(
                    isChannel ? "MemberRequests.UserAddedToChannel" : "MemberRequests.UserAddedToGroup",
                    request.peer.title,
                ))
            }
        }
    }
}

// MARK: TelegramNavigationSearchProvider

/// The field shows in the Telegram bar's glass, under the title, as the chat list's does; set on the navigation item,
/// iOS 26 would put a separate search toolbar at the bottom.
extension ChatJoinRequestsViewController: TelegramNavigationSearchProvider {
    var telegramNavigationSearch: UISearchController { searchController }
}

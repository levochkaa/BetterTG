// ForwardDestinationListViewController.swift

import TDLibKit
import UIKit

// MARK: - ForwardDestinationListViewController

@MainActor final class ForwardDestinationListViewController: UIViewController, UITableViewDelegate {
    private enum Section { case chats }

    let folder: CustomFolder
    var onSelect: ((Chat, Bool) -> Void)?
    var onScroll: ((CGFloat) -> Void)?

    private let client: TDLibClient
    private let accountID: UUID
    private let seedChats: [Chat]
    private let preparedForward: PreparedMessageForward?
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var dataSource: UITableViewDiffableDataSource<Section, Int64>!
    private var chatsByID = [Int64: Chat]()
    private var forumChatIDs = Set<Int64>()
    private var checkedSupergroupChatIDs = Set<Int64>()
    private var forumLookupFailedChatIDs = Set<Int64>()
    private var unavailablePrivateChatIDs = Set<Int64>()
    private var eligibilityByChatID = [Int64: MessageForwardDestinationEligibility]()
    private var visibleChatIDs = [Int64]()
    private var folderChatLimit = 100
    private var hasMoreFolderChats = true
    private var isLoadingChats = false
    private var queryGeneration = UInt64.zero
    private var queryTask: Task<Void, Never>?
    private var query = ""

    var searchOffset: CGFloat { max(0, tableView.contentOffset.y + tableView.adjustedContentInset.top) }

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    init(
        folder: CustomFolder,
        prepared: PreparedMessageForward,
        client: TDLibClient,
        accountID: UUID,
        seedChats: [Chat],
    ) {
        self.folder = folder
        self.preparedForward = prepared
        self.client = client
        self.accountID = accountID
        self.seedChats = seedChats
        super.init(nibName: nil, bundle: nil)
        for chat in seedChats {
            chatsByID[chat.id] = chat
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }
    deinit { queryTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 68, bottom: 0, right: 0)
        tableView.register(ForwardDestinationCell.self, forCellReuseIdentifier: ForwardDestinationCell.reuseID)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        dataSource = UITableViewDiffableDataSource<
            Section,
            Int64,
        >(tableView: tableView) { [weak self] table, index, id in
            guard let self, let chat = chatsByID[id],
                  let cell = table
                      .dequeueReusableCell(
                          withIdentifier: ForwardDestinationCell.reuseID,
                          for: index,
                      ) as? ForwardDestinationCell else { return UITableViewCell() }
            cell.configure(chat: chat, enabled: true, client: client)
            return cell
        }
        loadChats(query: query)
    }

    func updateQuery(_ value: String) {
        guard value != query else { return }
        query = value
        if isViewLoaded { loadChats(query: value) }
    }

    func scrollToTop() { tableView.setContentOffset(.zero, animated: true) }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isDragging || scrollView.isDecelerating { onScroll?(searchOffset) }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard contextIsCurrent, let id = dataSource.itemIdentifier(for: indexPath), let chat = chatsByID[id],
              eligibilityByChatID[id]?.isAllowed == true else { return }
        onSelect?(chat, forumChatIDs.contains(id))
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard !isLoadingChats, hasMoreFolderChats, query.isEmpty,
              indexPath.row >= dataSource.snapshot().numberOfItems - 10 else { return }
        folderChatLimit += 100
        loadChats(query: "")
    }

    private func loadChats(query rawQuery: String) {
        queryGeneration &+= 1
        let generation = queryGeneration
        queryTask?.cancel()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let chatList = folder.chatList
        isLoadingChats = true
        updateBackgroundView()
        queryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == queryGeneration {
                    isLoadingChats = false
                    updateBackgroundView()
                    if !Task.isCancelled, contextIsCurrent, query.isEmpty, hasMoreFolderChats,
                       dataSource.snapshot().numberOfItems < 10
                    {
                        folderChatLimit += 100
                        loadChats(query: "")
                    }
                }
            }
            if !query.isEmpty {
                try? await Task<Never, Never>.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            // TDLib must load a list before getChats can enumerate it (including custom folders).
            _ = try? await client.send(TDNativeRequests.loadChats(chatList: chatList, limit: 100))
            guard !Task.isCancelled, generation == queryGeneration, contextIsCurrent else { return }
            var ids = folder.chats.map(\.id)
            if let page = try? await client.getChats(chatList: chatList, limit: folderChatLimit) {
                ids = deduplicated(page.chatIds + ids)
                hasMoreFolderChats = page.chatIds.count >= folderChatLimit
            } else { hasMoreFolderChats = false }
            if !query.isEmpty {
                if let offline = try? await client.searchChats(limit: 100, query: query, typeFilter: nil) {
                    ids = offline.chatIds
                } else { ids = seedChatIDs(matching: query) }
                if let server = try? await client.searchChatsOnServer(limit: 100, query: query, typeFilter: nil) {
                    ids.append(contentsOf: server.chatIds)
                }
            }
            await hydrateAndApply(ids: ids, generation: generation, chatList: chatList, query: query)
        }
    }

    private func hydrateAndApply(
        ids: [Int64],
        generation: UInt64,
        chatList: ChatList,
        query: String,
    ) async {
        let uniqueIDs = deduplicated(ids)
        for chatID in uniqueIDs {
            guard !Task.isCancelled else { return }
            if let chat = try? await client.getChat(chatId: chatID) {
                chatsByID[chatID] = chat
            }
            if let chat = chatsByID[chatID],
               case .chatTypeSupergroup(let type) = chat.type,
               !checkedSupergroupChatIDs.contains(chatID)
            {
                if chat.viewAsTopics {
                    forumChatIDs.insert(chatID)
                    checkedSupergroupChatIDs.insert(chatID)
                    forumLookupFailedChatIDs.remove(chatID)
                } else if let supergroup = try? await client.getSupergroup(supergroupId: type.supergroupId) {
                    checkedSupergroupChatIDs.insert(chatID)
                    forumLookupFailedChatIDs.remove(chatID)
                    if supergroup.isForum {
                        forumChatIDs.insert(chatID)
                    }
                } else {
                    forumLookupFailedChatIDs.insert(chatID)
                }
            }
        }
        guard !Task.isCancelled,
              generation == queryGeneration,
              contextIsCurrent
        else { return }
        let hydratedIDs = uniqueIDs.filter { chatID in
            guard let chat = chatsByID[chatID] else { return false }
            // All Chats search can discover a recipient; a custom folder/archive search stays in that list.
            return !query.isEmpty && chatList == .chatListMain
                || chat.positions.contains { $0.list == chatList && $0.order != 0 }
        }
        for chatID in hydratedIDs {
            guard !Task.isCancelled, generation == queryGeneration, contextIsCurrent else { return }
            guard let chat = chatsByID[chatID], case .chatTypePrivate = chat.type,
                  let preparedForward else { continue }
            let eligibility = await MessageForwardingService.eligibility(
                of: chat, topic: nil, for: preparedForward, client: client,
            )
            guard !Task.isCancelled, generation == queryGeneration, contextIsCurrent else { return }
            if eligibility.isAllowed { unavailablePrivateChatIDs.remove(chatID) }
            else { unavailablePrivateChatIDs.insert(chatID) }
        }
        apply(chatIDs: prioritizeSavedMessages(hydratedIDs))
    }

    private func apply(chatIDs: [Int64]) {
        visibleChatIDs = chatIDs
        rebuildEligibility()
    }

    private func rebuildEligibility() {
        guard let preparedForward else {
            applyEligibleSnapshot()
            return
        }
        var updated = [Int64: MessageForwardDestinationEligibility]()
        for chatID in visibleChatIDs {
            guard let chat = chatsByID[chatID] else { continue }
            updated[chatID] =
                if forumLookupFailedChatIDs.contains(chatID) || unavailablePrivateChatIDs.contains(chatID) {
                    MessageForwardDestinationEligibility(
                        isAllowed: false,
                        reason: "This destination is unavailable.",
                        forcedMode: nil,
                    )
                } else {
                    MessageForwardingService.localEligibility(
                        of: chat,
                        for: preparedForward,
                    )
                }
        }
        eligibilityByChatID.merge(updated, uniquingKeysWith: { _, new in new })
        applyEligibleSnapshot()
    }

    private func applyEligibleSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.chats])
        snapshot.appendItems(visibleChatIDs.filter { eligibilityByChatID[$0]?.isAllowed == true })
        dataSource.apply(snapshot, animatingDifferences: true)
        updateBackgroundView()
    }

    private func updateBackgroundView() {
        if preparedForward == nil || isLoadingChats && dataSource.snapshot().numberOfItems == 0 {
            activityIndicator.startAnimating()
            tableView.backgroundView = activityIndicator
        } else if dataSource.snapshot().numberOfItems == 0 {
            let label = UILabel()
            label.text = "No chats found"
            label.textAlignment = .center
            label.textColor = .secondaryLabel
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
    }

    private func seedChatIDs(matching query: String) -> [Int64] {
        seedChats.compactMap { chat in
            query.isEmpty || chat.title.localizedCaseInsensitiveContains(query) ? chat.id : nil
        }
    }

    private func deduplicated(_ chatIDs: [Int64]) -> [Int64] {
        var seen = Set<Int64>()
        return chatIDs.filter { seen.insert($0).inserted }
    }

    private func prioritizeSavedMessages(_ chatIDs: [Int64]) -> [Int64] {
        guard let accountUserID = TDLib.shared.activeAccount?.userID,
              let savedIndex = chatIDs.firstIndex(where: { chatID in
                  guard let chat = chatsByID[chatID],
                        case .chatTypePrivate(let privateChat) = chat.type
                  else { return false }
                  return privateChat.userId == accountUserID
              })
        else { return chatIDs }
        var prioritized = chatIDs
        let savedID = prioritized.remove(at: savedIndex)
        prioritized.insert(savedID, at: 0)
        return prioritized
    }
}

// MARK: - ForwardDestinationCell

private final class ForwardDestinationCell: UITableViewCell {
    static let reuseID = "ForwardDestinationCell"

    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let labels = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        isAccessibilityElement = true
        configureViews()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(
        chat: Chat,
        enabled: Bool,
        client _: TDLibClient,
    ) {
        let title: String =
            if case .chatTypePrivate(let peer) = chat.type,
            peer.userId == TDLib.shared.activeAccount?.userID {
                L10n.telegram("Conversation.SavedMessages")
            } else {
                chat.title
            }
        titleLabel.text = title
        isUserInteractionEnabled = enabled
        accessibilityLabel = title
        accessibilityTraits = [.button]
        accessoryType = .none

        let peerID =
            switch chat.type {
            case .chatTypePrivate(let privateChat):
                privateChat.userId
            case .chatTypeSecret(let secretChat):
                secretChat.userId
            case .chatTypeBasicGroup, .chatTypeSupergroup:
                chat.id
            }
        let firstLetter = chat.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0).uppercased() }
        avatarView.configure(
            file: chat.photo?.small,
            minithumbnail: chat.photo?.minithumbnail,
            placeholder: TelegramAvatarPlaceholder(
                peerID: peerID,
                accentColorID: chat.accentColorId,
                upgradedGiftColors: chat.upgradedGiftColors,
                letters: firstLetter.map { [$0] } ?? [],
                isDeleted: false,
            ),
        )
    }

    private func configureViews() {
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.spacing = 2
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold))
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.isAccessibilityElement = false
        labels.addArrangedSubview(titleLabel)
        contentView.addSubview(labels)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 7),
            avatarView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -7),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            labels.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 7),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -7),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
        ])
    }
}

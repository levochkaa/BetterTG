// ForwardDestinationListViewController.swift

import TDLibKit
import UIKit

// MARK: - ForwardDestinationListViewController

@MainActor final class ForwardDestinationListViewController: UIViewController, UITableViewDelegate {
    private enum Section { case chats }

    let folder: CustomFolder
    var onSelect: ((Chat, Bool) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    /// A tap while choosing several chats (PeerSelectionControllerNode's selection) toggles the chat instead.
    var onToggle: ((Chat) -> Void)?

    private var isSelecting = false
    private var selectedChatIDs = Set<Int64>()
    /// The selection panel's height over the folder bar.
    private var extraBottomInset = CGFloat.zero

    private let client: TDLibClient
    private let accountID: UUID
    private let seedChats: [Chat]
    private let preparedForward: PreparedMessageForward?
    /// A switch inline button's chat kinds; nil lists every chat.
    private let chatTypes: InlineTargetChatTypes?
    /// ChatListNodePeersFilter's `onlyManageable`: only groups and channels the user may add a bot to.
    private let requiresBotManagement: Bool
    /// Private chats with bots, told apart from users only when the kinds treat them differently.
    private var botChatIDs = Set<Int64>()
    private var checkedBotChatIDs = Set<Int64>()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var dataSource: UITableViewDiffableDataSource<Section, Int64>!
    private var chatsByID = [Int64: Chat]()
    private var forumChatIDs = Set<Int64>()
    /// The user's own standing per destination; Telegram's send check needs it besides the default permissions. A
    /// failed lookup leaves no entry, so the chat stays hidden and the next hydration retries it.
    private var standingByChatID = [Int64: MessageForwardDestinationStanding]()
    private var unavailablePrivateChatIDs = Set<Int64>()
    /// The account's own chat, listed first in All Chats even when it isn't in the loaded page, is archived or
    /// hasn't been created yet (Telegram's `savedMessagesPeer` for writable peer selection).
    private var savedMessagesChatID: Int64?
    private var eligibilityByChatID = [Int64: MessageForwardDestinationEligibility]()
    private var visibleChatIDs = [Int64]()
    private var folderChatLimit = 100
    private var hasMoreFolderChats = true
    private var isLoadingChats = false
    private var queryGeneration = UInt64.zero
    private var queryTask: Task<Void, Never>?
    private var query = ""
    private var searchActive = false
    private var didSetInitialOffset = false
    private var didApplyFirstPage = false

    var searchOffset: CGFloat {
        // Until the first page is laid out the search field is considered hidden, as in the main list.
        guard isViewLoaded, didSetInitialOffset else { return ChatListNavigationSearchView.scrollHeight }
        return min(
            ChatListNavigationSearchView.scrollHeight,
            max(0, tableView.contentOffset.y + tableView.adjustedContentInset.top),
        )
    }

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    init(
        folder: CustomFolder,
        prepared: PreparedMessageForward,
        client: TDLibClient,
        accountID: UUID,
        seedChats: [Chat],
        chatTypes: InlineTargetChatTypes? = nil,
        requiresBotManagement: Bool = false,
    ) {
        self.folder = folder
        self.preparedForward = prepared
        self.client = client
        self.accountID = accountID
        self.seedChats = seedChats
        self.chatTypes = chatTypes
        self.requiresBotManagement = requiresBotManagement
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
        tableView.keyboardDismissMode = .interactive
        tableView.alwaysBounceVertical = true
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
            cell.setSelection(active: isSelecting, selected: selectedChatIDs.contains(id), animated: false)
            return cell
        }
        updateTableInsets()
        loadChats(query: query)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateTableInsets()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Like the main list, the search field starts hidden once the first page has its height.
        guard !didSetInitialOffset, didApplyFirstPage, tableView.bounds.height > 0,
              dataSource.snapshot().numberOfItems == 0 || tableView.contentSize.height > 0
        else { return }
        didSetInitialOffset = true
        tableView.setContentOffset(
            CGPoint(x: 0, y: -tableView.adjustedContentInset.top + ChatListNavigationSearchView.scrollHeight),
            animated: false,
        )
        onScroll?(searchOffset)
    }

    func setSearchActive(_ active: Bool, animated: Bool) {
        searchActive = active
        guard isViewLoaded else { return }
        let changes = {
            self.updateTableInsets()
            self.tableView.layoutIfNeeded()
            self.tableView.contentOffset = CGPoint(x: 0, y: -self.tableView.adjustedContentInset.top)
        }
        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
                animations: changes,
            )
        } else { changes() }
    }

    /// The chats chosen across the pages, with their checks shown while choosing several.
    func setSelection(active: Bool, selected: Set<Int64>, animated: Bool) {
        isSelecting = active
        selectedChatIDs = selected
        guard isViewLoaded else { return }
        for cell in tableView.visibleCells {
            guard let cell = cell as? ForwardDestinationCell, let indexPath = tableView.indexPath(for: cell),
                  let id = dataSource.itemIdentifier(for: indexPath) else { continue }
            cell.setSelection(active: active, selected: selected.contains(id), animated: animated)
        }
    }

    func setExtraBottomInset(_ inset: CGFloat) {
        extraBottomInset = inset
        if isViewLoaded { updateTableInsets() }
    }

    func updateQuery(_ value: String) {
        guard value != query else { return }
        query = value
        if isViewLoaded { loadChats(query: value) }
    }

    func scrollToTop() {
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView, didSetInitialOffset else { return }
        onScroll?(searchOffset)
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity _: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>,
    ) {
        guard scrollView === tableView, !searchActive else { return }
        let top = -scrollView.adjustedContentInset.top
        let distance = targetContentOffset.pointee.y - top
        let searchHeight = ChatListNavigationSearchView.scrollHeight
        guard distance > 0, distance < searchHeight else { return }
        targetContentOffset.pointee.y = top + (distance < searchHeight * 0.5 ? 0 : searchHeight)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard contextIsCurrent, let id = dataSource.itemIdentifier(for: indexPath), let chat = chatsByID[id],
              eligibilityByChatID[id]?.isAllowed == true, allowsType(of: id) else { return }
        if isSelecting {
            onToggle?(chat)
            return
        }
        onSelect?(chat, forumChatIDs.contains(id))
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard !isLoadingChats, hasMoreFolderChats, query.isEmpty,
              indexPath.row >= dataSource.snapshot().numberOfItems - 10 else { return }
        folderChatLimit += 100
        loadChats(query: "")
    }

    private func updateTableInsets() {
        let previousTop = tableView.contentInset.top
        let headerHeight = searchActive
            ? ChatListNavigationSearchView.scrollHeight
            : TelegramListNavigationBar.expandedContentHeight
        let insets = UIEdgeInsets(
            top: view.safeAreaInsets.top + headerHeight,
            left: 0,
            bottom: view.safeAreaInsets.bottom + 58 + extraBottomInset,
            right: 0,
        )
        guard tableView.contentInset != insets else { return }
        let offset = tableView.contentOffset
        tableView.contentInset = insets
        tableView.verticalScrollIndicatorInsets = insets
        if didSetInitialOffset {
            tableView.contentOffset = CGPoint(x: offset.x, y: offset.y + previousTop - insets.top)
        }
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
            if query.isEmpty, chatList == .chatListMain,
               let accountUserID = TDLib.shared.activeAccount?.userID,
               let saved = try? await client.createPrivateChat(force: false, userId: accountUserID)
            {
                guard !Task.isCancelled, generation == queryGeneration, contextIsCurrent else { return }
                savedMessagesChatID = saved.id
                ids.insert(saved.id, at: 0)
            }
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
            if let chat = chatsByID[chatID], standingByChatID[chatID] == nil,
               let standing = try? await MessageForwardingService.standing(
                   of: chat,
                   client: client,
               )
            {
                standingByChatID[chatID] = standing
                if chat.viewAsTopics || standing.isForum {
                    forumChatIDs.insert(chatID)
                }
            }
            if let chatTypes, chatTypes.users != chatTypes.bots, let chat = chatsByID[chatID],
               case .chatTypePrivate(let privateChat) = chat.type, !checkedBotChatIDs.contains(chatID),
               let user = try? await client.getUser(userId: privateChat.userId)
            {
                checkedBotChatIDs.insert(chatID)
                if case .userTypeBot = user.type { botChatIDs.insert(chatID) }
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
                || chatList == .chatListMain && chatID == savedMessagesChatID
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
            let standing = standingByChatID[chatID]
            updated[chatID] =
                if let standing, !unavailablePrivateChatIDs.contains(chatID) {
                    MessageForwardingService.localEligibility(
                        of: chat,
                        standing: standing,
                        for: preparedForward,
                    )
                } else {
                    MessageForwardDestinationEligibility(
                        isAllowed: false,
                        reason: L10n.betterTG("Forward.DestinationUnavailable"),
                        forcedMode: nil,
                    )
                }
        }
        eligibilityByChatID.merge(updated, uniquingKeysWith: { _, new in new })
        applyEligibleSnapshot()
    }

    private func applyEligibleSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Int64>()
        snapshot.appendSections([.chats])
        snapshot.appendItems(visibleChatIDs.filter { eligibilityByChatID[$0]?.isAllowed == true && allowsType(of: $0) })
        let firstPage = !didApplyFirstPage
        dataSource.apply(snapshot, animatingDifferences: !firstPage) { [weak self] in
            guard let self, firstPage else { return }
            didApplyFirstPage = true
            view.setNeedsLayout()
        }
        updateBackgroundView()
    }

    /// PeerSelectionController's `requestPeerType` for a switch inline button: users, bots, groups or channels.
    private func allowsType(of chatID: Int64) -> Bool {
        if requiresBotManagement, !canAddBot(to: chatID) { return false }
        guard let chatTypes, let chat = chatsByID[chatID] else { return true }
        switch chat.type {
        case .chatTypePrivate:
            return botChatIDs.contains(chatID) ? chatTypes.bots : chatTypes.users
        case .chatTypeBasicGroup:
            return chatTypes.groups
        case .chatTypeSupergroup(let supergroup):
            return supergroup.isChannel ? chatTypes.channels : chatTypes.groups
        case .chatTypeSecret:
            return false
        }
    }

    /// ChatListNode's `onlyManageable`: a basic group's owner or admin, a supergroup where the user may invite
    /// members, or a channel where they may add admins.
    private func canAddBot(to chatID: Int64) -> Bool {
        guard let chat = chatsByID[chatID], case .group(let group) = standingByChatID[chatID] else { return false }
        switch (chat.type, group.status) {
        case (_, .chatMemberStatusCreator):
            return true
        case (.chatTypeBasicGroup, .chatMemberStatusAdministrator):
            return true
        case (.chatTypeSupergroup(let supergroup), .chatMemberStatusAdministrator(let administrator)):
            return supergroup.isChannel ? administrator.rights.canPromoteMembers : administrator.rights.canInviteUsers
        case (.chatTypeSupergroup(let supergroup), .chatMemberStatusMember):
            return !supergroup.isChannel && chat.permissions.canInviteUsers
        case (.chatTypeSupergroup(let supergroup), .chatMemberStatusRestricted(let restricted)):
            return !supergroup.isChannel && restricted.permissions.canInviteUsers
        default:
            return false
        }
    }

    private func updateBackgroundView() {
        if preparedForward == nil || isLoadingChats && dataSource.snapshot().numberOfItems == 0 {
            activityIndicator.startAnimating()
            tableView.backgroundView = activityIndicator
        } else if dataSource.snapshot().numberOfItems == 0 {
            let label = UILabel()
            label.text = L10n.betterTG("Forward.NoChatsFound")
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
    /// ChatListItem's selection check, before the avatar while choosing several chats.
    private let checkView = ForwardSelectionCheckView()
    private var avatarLeading: NSLayoutConstraint?

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

    func setSelection(active: Bool, selected: Bool, animated: Bool) {
        checkView.setSelected(selected, animated: animated)
        accessibilityTraits = active ? (selected ? [.button, .selected] : [.button]) : [.button]
        let leading: CGFloat = active ? 54 : 16
        guard avatarLeading?.constant != leading || checkView.alpha != (active ? 1 : 0) else { return }
        avatarLeading?.constant = leading
        let changes = {
            self.checkView.alpha = active ? 1 : 0
            self.contentView.layoutIfNeeded()
        }
        if animated { UIView.animate(withDuration: 0.2, animations: changes) } else { changes() }
    }

    func configure(
        chat: Chat,
        enabled: Bool,
        client: TDLibClient,
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
            case .chatTypeBasicGroup,
                 .chatTypeSupergroup:
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
            client: client,
        )
    }

    private func configureViews() {
        checkView.translatesAutoresizingMaskIntoConstraints = false
        checkView.alpha = 0
        contentView.addSubview(checkView)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)
        let avatarLeading = avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        self.avatarLeading = avatarLeading

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
            avatarLeading,
            checkView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            checkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 22),
            checkView.heightAnchor.constraint(equalToConstant: 22),
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

// MARK: - ForwardSelectionCheckView

/// CheckNode in the chat list's selection: a grey ring, or the accent circle with a white check once chosen.
final class ForwardSelectionCheckView: UIView {
    private let ring = CAShapeLayer()
    private let fill = CAShapeLayer()
    private let check = CAShapeLayer()

    private var isChosen = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        ring.fillColor = UIColor.clear.cgColor
        ring.lineWidth = 1.5
        check.fillColor = UIColor.clear.cgColor
        check.strokeColor = UIColor.white.cgColor
        check.lineWidth = 1.8
        check.lineCap = .round
        check.lineJoin = .round
        for shape in [ring, fill, check] {
            layer.addSublayer(shape)
        }
        setSelected(false, animated: false)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.updateColors() }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let circle = UIBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75)).cgPath
        ring.path = circle
        fill.path = UIBezierPath(ovalIn: bounds).cgPath
        let path = UIBezierPath()
        path.move(to: CGPoint(x: bounds.width * 0.28, y: bounds.height * 0.52))
        path.addLine(to: CGPoint(x: bounds.width * 0.44, y: bounds.height * 0.67))
        path.addLine(to: CGPoint(x: bounds.width * 0.73, y: bounds.height * 0.36))
        check.path = path.cgPath
        updateColors()
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        let changed = isChosen != selected
        isChosen = selected
        updateColors()
        fill.opacity = selected ? 1 : 0
        check.opacity = selected ? 1 : 0
        guard animated, changed, selected else { return }
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.6
        pop.toValue = 1
        pop.damping = 12
        pop.duration = pop.settlingDuration
        layer.add(pop, forKey: "pop")
    }

    private func updateColors() {
        ring.strokeColor = UIColor.tertiaryLabel.resolvedColor(with: traitCollection).cgColor
        fill.fillColor = UIColor.systemBlue.resolvedColor(with: traitCollection).cgColor
    }
}

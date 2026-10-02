// PeerProfileControlsViewControllers.swift

import Combine
import TDLibKitDynamic
import UIKit

// MARK: - PeerProfileMembersViewController

@MainActor final class PeerProfileMembersViewController: UITableViewController, ClientRestorableNavigationEntry {
    enum Source {
        case administrators(chatID: Int64, group: Group)
        case basicGroup(chatID: Int64, id: Int64)
        case supergroup(chatID: Int64, id: Int64)

        enum Group: Equatable { case basic(Int64), supergroup(Int64) }

        var chatID: Int64 {
            switch self {
            case .administrators(let chatID, _), .basicGroup(let chatID, _), .supergroup(let chatID, _):
                chatID
            }
        }

        var group: Group {
            switch self {
            case .administrators(_, let group): group
            case .basicGroup(_, let id): .basic(id)
            case .supergroup(_, let id): .supergroup(id)
            }
        }
    }

    private struct Row {
        let accessibilityLabel: String
        let role: String
        let title: String
    }

    private struct Seed {
        let id: MemberID
        let role: String
    }

    private typealias MemberID = PeerProfileMemberID
    private typealias TableAnchor = PeerProfileMemberAnchor

    private enum Section {
        case members
    }

    private let accountID: UUID
    private let accountUserID: Int64?
    private let client: TDLibClient
    private let source: Source
    private var identity: PeerProfileRestorationIdentity
    private let parentBinding = PeerProfileMembersParentBinding()
    private var retired = false
    private var retentionDenied = false
    private var revalidation = PeerProfileMembersRevalidation()
    private var retainedHeights = [MemberID: CGFloat]()
    private var loadError: String?
    private var checkedAvailability = false
    private var quarantinedForClientChange = false
    private var basicMembersRevision = PeerProfileMembersRevision<[ChatMember]>()
    private var memberAvailabilityRevision = PeerProfileMembersRevision<Bool>()
    private var basicGroupRevision = PeerProfileMembersRevision<BasicGroup>()
    private var supergroupRevision = PeerProfileMembersRevision<Supergroup>()
    private var permissionsRevision = PeerProfileMembersRevision<ChatPermissions>()
    private var rows = [MemberID: Row]()
    private var seeds = [MemberID: Seed]()
    private var orderedIDs = [MemberID]()
    private var pendingResolutionIDs = [MemberID]()
    private var rawOffset = 0
    private var totalCount = 0
    private var hasMore = true
    private var loadTask: Task<Void, Never>?
    private var resolutionTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var tagPreparationTask: Task<Void, Never>?
    private var loadGeneration = UInt64.zero
    private var pendingAnchor: TableAnchor?
    private var snapshotApplyInProgress = false
    private var snapshotApplyPending = false
    private var cancellables = Set<AnyCancellable>()
    private var dataSource: UITableViewDiffableDataSource<Section, MemberID>!
    #if DEBUG
    private var isRestorationProbe = false
    #endif

    var navigationClientSource: TdUpdateSource? { identity.origin }

    private var contextIsCurrent: Bool {
        !retired && !identity.revoked && TDLib.shared.activeAccountID == accountID
            && TDLib.shared.activeClient.id == client.id && TDLib.shared.activeAccount?.userID == accountUserID
    }

    private var readOwnerIsCurrent: Bool {
        contextIsCurrent && identity.readySource == identity.origin && chatListActionOwnerIsAttached
            && navigationController?.viewControllers.contains(where: { $0 === self }) == true
    }

    private var isQuiescent: Bool {
        tagPreparationTask == nil && presentedViewController == nil && !isPresentingTelegramContextMenu
            && !tableView.isTracking && !tableView.isDragging && !tableView.isDecelerating
    }

    private var listNoun: String {
        switch source {
        case .administrators: "administrators"
        case .basicGroup, .supergroup: "members"
        }
    }

    init(
        accountID: UUID,
        accountUserID: Int64?,
        client: TDLibClient,
        source: Source,
        title: String,
        restoration: PeerProfileMembersRestorationState? = nil,
    ) {
        self.accountID = accountID
        self.accountUserID = accountUserID
        self.client = client
        self.source = source
        self.identity = .init(origin: .init(accountID: accountID, clientID: client.id), actorID: accountUserID)
        if let restoration, restoration.source.accountID == accountID,
           restoration.actorID == accountUserID, restoration.chatID == source.chatID
        {
            self.orderedIDs = restoration.ids
            self.retainedHeights = restoration.heights
            self.rawOffset = restoration.rawOffset
            self.totalCount = restoration.total
            self.hasMore = restoration.hasMore
            self.pendingAnchor = restoration.anchor
            revalidation.begin(ids: restoration.ids, rawOffset: restoration.rawOffset)
        }
        super.init(style: .plain)
        self.title =
            switch source {
            case .administrators: "Administrators"
            case .basicGroup, .supergroup: "Members"
            }
        navigationItem.backButtonTitle = title
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    deinit {
        loadTask?.cancel()
        resolutionTask?.cancel()
        reloadTask?.cancel()
        tagPreparationTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 58
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "member")
        configureDataSource()
        #if DEBUG
        if isRestorationProbe { applySnapshot()
        return
        }
        #endif
        TDLib.shared
            .activeClientChanges
            .sink { [weak self] source in
                guard let self else { return }
                identity.observe(source: source, actorID: TDLib.shared.activeAccount?.userID)
                if !contextIsCurrent { invalidateForContextChange() }
                retryClientRestoration()
            }
            .store(in: &cancellables)
        TDLib.shared
            .readyClientChanges
            .sink { [weak self] source in
                guard let self else { return }
                identity.readySource = source
                if source != identity.origin { invalidateForContextChange() }
                else { resumeLoadingIfNeeded() }
                retryClientRestoration()
            }
            .store(in: &cancellables)
        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            guard let self else { return }
            identity.observe(source: TDLib.shared.activeUpdateSource, actorID: TDLib.shared.activeAccount?.userID)
            if !contextIsCurrent { invalidateForContextChange() }
        }
        nc.scopedPublisher(&cancellables, for: .updateChatMember) { [weak self] event in
            guard let self, contextIsCurrent, event.source == identity.origin,
                  event.value.chatId == source.chatID else { return }
            scheduleReload()
        }
        nc.scopedPublisher(&cancellables, for: .updateBasicGroupFullInfo) { [weak self] event in
            guard let self,
                  contextIsCurrent, event.source == identity.origin,
                  case .basic(let groupID) = source.group,
                  event.value.basicGroupId == groupID,
                  basicMembersRevision.observe(event.value.basicGroupFullInfo.members)
            else { return }
            scheduleReload()
        }
        nc.scopedPublisher(&cancellables, for: .updateSupergroupFullInfo) { [weak self] event in
            guard let self,
                  contextIsCurrent, event.source == identity.origin,
                  case .supergroup(let groupID) = source.group,
                  event.value.supergroupId == groupID
            else { return }
            if case .supergroup = source, !event.value.supergroupFullInfo.canGetMembers {
                leaveUnavailableList()
                return
            }
            if memberAvailabilityRevision.observe(event.value.supergroupFullInfo.canGetMembers) { scheduleReload() }
        }
        nc.scopedPublisher(&cancellables, for: .updateBasicGroup) { [weak self] event in
            guard let self, contextIsCurrent, event.source == identity.origin,
                  source.group == .basic(event.value.basicGroup.id),
                  basicGroupRevision.observe(event.value.basicGroup) else { return }
            scheduleReload()
        }
        nc.scopedPublisher(&cancellables, for: .updateSupergroup) { [weak self] event in
            guard let self, contextIsCurrent, event.source == identity.origin,
                  source.group == .supergroup(event.value.supergroup.id),
                  supergroupRevision.observe(event.value.supergroup) else { return }
            scheduleReload()
        }
        nc.scopedPublisher(&cancellables, for: .updateChatPermissions) { [weak self] event in
            guard let self, contextIsCurrent, event.source == identity.origin,
                  event.value.chatId == source.chatID,
                  permissionsRevision.observe(event.value.permissions) else { return }
            scheduleReload()
        }
        applySnapshot()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restorePendingAnchor()
        resumeLoadingIfNeeded()
        retryClientRestoration()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        restorePendingAnchor()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil { retireReads() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController?.viewControllers.contains(where: { $0 === self }) != true { retireReads() }
    }

    override func scrollViewWillBeginDragging(_: UIScrollView) { pendingAnchor = nil }
    override func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { resumeLoadingIfNeeded()
            retryClientRestoration()
        }
    }

    override func scrollViewDidEndDecelerating(_: UIScrollView) { resumeLoadingIfNeeded()
        retryClientRestoration()
    }

    override func tableView(
        _: UITableView,
        willDisplay _: UITableViewCell,
        forRowAt indexPath: IndexPath,
    ) {
        if revalidation.active { resumeLoadingIfNeeded()
            return
        }
        guard indexPath.row >= max(0, orderedIDs.count - 10) else { return }
        loadMore()
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard tagPreparationTask == nil,
              contextIsCurrent,
              let accountUserID,
              let memberID = dataSource.itemIdentifier(for: indexPath),
              case .user(let targetUserID) = memberID,
              let title = rows[memberID]?.title
        else { return }
        tableView.isUserInteractionEnabled = false
        tagPreparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let authority = try await PeerProfileMemberTagAuthority.resolve(
                    accountID: accountID,
                    accountUserID: accountUserID,
                    chatID: source.chatID,
                    targetUserID: targetUserID,
                    client: client,
                )
                guard !Task.isCancelled, contextIsCurrent else { return }
                tagPreparationTask = nil
                tableView.isUserInteractionEnabled = true
                let editor = PeerProfileMemberTagViewController(
                    accountID: accountID,
                    accountUserID: accountUserID,
                    chatID: source.chatID,
                    client: client,
                    initialAuthority: authority,
                    targetTitle: title,
                    targetUserID: targetUserID,
                )
                editor.onSaved = { [weak self] in
                    self?.scheduleReload()
                }
                navigationController?.pushViewController(editor, animated: true)
            } catch is CancellationError {
                tagPreparationTask = nil
                tableView.isUserInteractionEnabled = true
            } catch {
                guard contextIsCurrent else { return }
                tagPreparationTask = nil
                tableView.isUserInteractionEnabled = true
                presentTagError(error)
            }
        }
    }

    override func tableView(_: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let id = dataSource.itemIdentifier(for: indexPath), rows[id] == nil,
              let height = retainedHeights[id] else { return UITableView.automaticDimension }
        return height
    }

    private static func seed(for member: ChatMember) -> Seed {
        Seed(id: MemberID(member.memberId), role: role(for: member))
    }

    private static func role(for member: ChatMember) -> String {
        switch member.status {
        case .chatMemberStatusCreator:
            member.tag.isEmpty ? "Owner" : "Owner · \(member.tag)"
        case .chatMemberStatusAdministrator:
            member.tag.isEmpty ? "Administrator" : "Administrator · \(member.tag)"
        case .chatMemberStatusBanned:
            "Banned"
        case .chatMemberStatusLeft:
            "Left"
        case .chatMemberStatusMember:
            member.tag.isEmpty ? "Member" : member.tag
        case .chatMemberStatusRestricted(let restricted):
            restricted.isMember ? "Restricted member" : "Restricted"
        }
    }

    private static func userStatus(_ status: UserStatus) -> String {
        switch status {
        case .userStatusOnline: "online"
        case .userStatusRecently: "recently"
        case .userStatusLastWeek: "within a week"
        case .userStatusLastMonth: "within a month"
        case .userStatusEmpty, .userStatusOffline: ""
        }
    }

    func attach(to parent: PeerProfileViewController) { parentBinding.attach(parent) }

    func canRetain(parent: PeerProfileViewController, accountID: UUID, actorID: Int64?, chatID: Int64) -> Bool {
        !retired && !retentionDenied && !identity.revoked && accountUserID != nil
            && self.accountID == accountID && accountUserID == actorID && source.chatID == chatID
            && TDLib.shared.activeAccountID == accountID && TDLib.shared.activeAccount?.userID == actorID
            && parentBinding.contains(self, parent: parent) && isQuiescent
    }

    func transferParent(from parent: PeerProfileViewController, to replacement: PeerProfileViewController) -> Bool {
        parentBinding.transfer(self, from: parent, to: replacement)
    }

    func prepareReplacementForReadyClient(_ next: TdUpdateSource) -> PreparedClientNavigationReplacement? {
        guard let parent = parentBinding.parent as? PeerProfileViewController,
              canRestore(next, parent: parent) else { return nil }
        return PreparedClientNavigationReplacement(preflight: { [weak self, weak parent] in
            guard let self, let parent else { return false }
            return canRestore(next, parent: parent)
        }, commit: { [self, weak parent] in
            guard let parent, canRestore(next, parent: parent), let actorID = accountUserID,
                  let replacement = parent.makeRestoredMembers(self, state: PeerProfileMembersRestorationState(
                      source: identity.origin, actorID: actorID, chatID: source.chatID,
                      administrators: {
                          if case .administrators = source {
                              true
                          } else {
                              false
                          }
                      }(),
                      ids: orderedIDs, heights: retainedHeights, rawOffset: rawOffset,
                      total: totalCount, hasMore: hasMore, anchor: pendingAnchor ?? captureAnchor(),
                  ), source: next) else { return nil }
            retireReads()
            return replacement
        })
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<
            Section,
            MemberID,
        >(tableView: tableView) { [weak self] tableView, indexPath, id in
            guard let self else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: "member", for: indexPath)
            var content = cell.defaultContentConfiguration()
            guard let row = rows[id] else {
                PeerProfileMemberPlaceholder.configure(cell, retrying: loadError != nil)
                return cell
            }
            content.text = row.title
            content.secondaryText = row.role
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            content.secondaryTextProperties.color = .secondaryLabel
            content.prefersSideBySideTextAndSecondaryText = false
            cell.contentConfiguration = content
            let canInspectTag = accountUserID != nil && {
                if case .user = id {
                    true
                } else {
                    false
                }
            }()
            cell.selectionStyle = canInspectTag ? .default : .none
            cell.accessoryType = canInspectTag ? .disclosureIndicator : .none
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = row.accessibilityLabel
            cell.accessibilityHint = canInspectTag ? "Shows member tag controls" : nil
            cell.accessibilityTraits = canInspectTag ? .button : .staticText
            return cell
        }
    }

    private func loadMore() {
        guard loadTask == nil, hasMore || revalidation.active, loadError == nil,
              contextIsCurrent, identity.readySource == identity.origin,
              chatListActionOwnerIsAttached, navigationController?.topViewController === self else { return }
        let generation = loadGeneration
        let pageOffset = revalidation.active ? revalidation.cursor : rawOffset
        tableView.tableFooterView = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                if !checkedAvailability, case .supergroup(_, let id) = source {
                    let info = try await client.getSupergroupFullInfo(supergroupId: id)
                    guard !Task.isCancelled, readOwnerIsCurrent, loadGeneration == generation else { return }
                    guard info.canGetMembers else { leaveUnavailableList()
                        return
                    }
                    _ = memberAvailabilityRevision.observe(info.canGetMembers)
                }
                checkedAvailability = true
                let page: [Seed]
                let pageRawCount: Int
                let nextTotalCount: Int
                let nextHasMore: Bool
                switch source {
                case .administrators(let chatID, _):
                    let result = try await client.getChatAdministrators(chatId: chatID)
                    page = result.administrators.map { administrator in
                        let role =
                            if administrator.isOwner {
                                administrator.customTitle.isEmpty ? "Owner" : "Owner · \(administrator.customTitle)"
                            } else {
                                administrator.customTitle.isEmpty
                                    ? "Administrator"
                                    : "Administrator · \(administrator.customTitle)"
                            }
                        return Seed(
                            id: .user(administrator.userId),
                            role: role,
                        )
                    }
                    pageRawCount = page.count
                    nextTotalCount = page.count
                    nextHasMore = false
                case .basicGroup(_, let id):
                    let info = try await client.getBasicGroupFullInfo(basicGroupId: id)
                    guard !Task.isCancelled, readOwnerIsCurrent, loadGeneration == generation else { return }
                    _ = basicMembersRevision.observe(info.members)
                    let members = info.members
                    page = members.map(Self.seed(for:))
                    pageRawCount = members.count
                    nextTotalCount = members.count
                    nextHasMore = false
                case .supergroup(_, let id):
                    let result = try await client.getSupergroupMembers(
                        filter: nil,
                        limit: 100,
                        offset: pageOffset,
                        supergroupId: id,
                    )
                    page = result.members.map(Self.seed(for:))
                    pageRawCount = result.members.count
                    nextTotalCount = max(result.totalCount, pageOffset + pageRawCount)
                    nextHasMore = !result.members.isEmpty && pageOffset + pageRawCount < nextTotalCount
                }
                guard !Task.isCancelled,
                      readOwnerIsCurrent,
                      loadGeneration == generation
                else { return }
                if revalidation.active {
                    preserveAnchor()
                    orderedIDs = revalidation.admit(ids: page.map(\.id), rawCount: pageRawCount, hasMore: nextHasMore)
                    if !revalidation.active {
                        rawOffset = revalidation.cursor
                        let acceptedIDs = Set(orderedIDs)
                        rows = rows.filter { acceptedIDs.contains($0.key) }
                        seeds = seeds.filter { acceptedIDs.contains($0.key) }
                    }
                } else { rawOffset += pageRawCount }
                totalCount = nextTotalCount
                hasMore = nextHasMore
                append(page)
                loadTask = nil
                updateEmptyState()
            } catch {
                guard !Task.isCancelled, readOwnerIsCurrent, loadGeneration == generation else { return }
                loadTask = nil
                loadError = error.localizedDescription
                showRetry(error.localizedDescription)
            }
        }
    }

    private func append(_ page: [Seed]) {
        var newSeeds = [Seed]()
        for seed in page {
            let id = seed.id
            if rows[id] == nil {
                if !orderedIDs.contains(id) { orderedIDs.append(id) }
                newSeeds.append(seed)
                rows[id] = fallbackRow(seed)
            } else if let row = rows[id] {
                rows[id] = Row(
                    accessibilityLabel: "\(row.title), \(seed.role)",
                    role: seed.role,
                    title: row.title,
                )
            }
            seeds[id] = seed
        }
        applySnapshot()
        enqueueResolution(newSeeds)
    }

    private func enqueueResolution(_ newSeeds: [Seed]) {
        #if DEBUG
        guard !isRestorationProbe else { return }
        #endif
        pendingResolutionIDs.append(contentsOf: newSeeds.map(\.id))
        guard resolutionTask == nil, !pendingResolutionIDs.isEmpty else { return }
        let generation = loadGeneration
        resolutionTask = Task { [weak self] in
            guard let self else { return }
            var resolvedIDs = [MemberID]()
            while !pendingResolutionIDs.isEmpty, !Task.isCancelled {
                let id = pendingResolutionIDs.removeFirst()
                guard let seed = seeds[id] else { continue }
                let row = await resolve(seed)
                guard !Task.isCancelled, readOwnerIsCurrent, loadGeneration == generation else { return }
                rows[id] = row
                resolvedIDs.append(id)
                if resolvedIDs.count == 16 {
                    applySnapshot()
                    resolvedIDs.removeAll(keepingCapacity: true)
                    await Task.yield()
                }
            }
            if !resolvedIDs.isEmpty {
                applySnapshot()
            }
            resolutionTask = nil
        }
    }

    private func resolve(_ seed: Seed) async -> Row {
        switch seed.id {
        case .user(let userID):
            guard let user = try? await client.getUser(userId: userID) else {
                return fallbackRow(seed)
            }
            let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            let title = name.isEmpty ? "User \(userID)" : name
            let status = Self.userStatus(user.status)
            let detail = status.isEmpty ? seed.role : "\(seed.role) · \(status)"
            return Row(
                accessibilityLabel: "\(title), \(detail)",
                role: detail,
                title: title,
            )
        case .chat(let chatID):
            let title = await (try? client.getChat(chatId: chatID))?.title ?? "Chat \(chatID)"
            return Row(
                accessibilityLabel: "\(title), \(seed.role)",
                role: seed.role,
                title: title,
            )
        }
    }

    private func fallbackRow(_ seed: Seed) -> Row {
        let title =
            switch seed.id {
            case .user(let userID): "User \(userID)"
            case .chat(let chatID): "Chat \(chatID)"
            }
        return Row(
            accessibilityLabel: "\(title), \(seed.role)",
            role: seed.role,
            title: title,
        )
    }

    private func applySnapshot() {
        preserveAnchor()
        snapshotApplyPending = true
        drainSnapshotApply()
    }

    private func drainSnapshotApply() {
        guard !snapshotApplyInProgress, snapshotApplyPending else { return }
        snapshotApplyPending = false
        var snapshot = NSDiffableDataSourceSnapshot<Section, MemberID>()
        snapshot.appendSections([.members])
        snapshot.appendItems(orderedIDs)
        let existingIDs = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(orderedIDs.filter(existingIDs.contains))
        snapshotApplyInProgress = true
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                snapshotApplyInProgress = false
                guard !retired else { return }
                if !snapshotApplyPending {
                    restorePendingAnchor()
                }
                drainSnapshotApply()
                resumeLoadingIfNeeded()
                retryClientRestoration()
            }
        }
    }

    private func showRetry(_ message: String) {
        let button = UIButton(type: .system)
        button.frame.size.height = 112
        button.setTitle("Couldn't load \(listNoun)\n\(message)\nTap to retry", for: .normal)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.addAction(UIAction { [weak self] _ in
            self?.loadError = nil
            self?.tableView.tableFooterView = nil
            self?.loadMore()
        }, for: .touchUpInside)
        tableView.tableFooterView = button
        tableView.backgroundView = nil
    }

    private func emptyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }

    private func updateEmptyState() {
        tableView.backgroundView = orderedIDs.isEmpty && loadTask == nil ? emptyLabel("No \(listNoun)") : nil
    }

    private func scheduleReload() {
        beginRevalidation()
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            reloadTask = nil
            resumeLoadingIfNeeded()
        }
    }

    private func invalidateForContextChange() {
        if !isQuiescent { retentionDenied = true }
        if !quarantinedForClientChange {
            quarantinedForClientChange = true
            beginRevalidation()
        }
        loadTask?.cancel()
        resolutionTask?.cancel()
        reloadTask?.cancel()
        tagPreparationTask?.cancel()
        loadTask = nil
        resolutionTask = nil
        reloadTask = nil
        tagPreparationTask = nil
        tableView.isUserInteractionEnabled = false
        navigationItem.prompt = identity.revoked ? "This account is no longer active." : "Reconnecting…"
    }

    private func presentTagError(_ error: Swift.Error) {
        guard presentedViewController == nil else { return }
        let message = (error as? LocalizedError)?.errorDescription
            ?? "This member's tag can't be edited right now."
        let alert = UIAlertController(title: "Can't Edit Tag", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func beginRevalidation() {
        preserveAnchor()
        for path in tableView.indexPathsForVisibleRows ?? [] {
            if let id = dataSource.itemIdentifier(for: path), rows[id] != nil {
                retainedHeights[id] = tableView.rectForRow(at: path).height
            }
        }
        loadGeneration &+= 1
        loadTask?.cancel()
        resolutionTask?.cancel()
        loadTask = nil
        resolutionTask = nil
        pendingResolutionIDs.removeAll()
        rows.removeAll()
        seeds.removeAll()
        tableView.visibleCells.forEach { PeerProfileMemberPlaceholder.configure($0, retrying: false) }
        revalidation.begin(ids: orderedIDs, rawOffset: rawOffset)
        checkedAvailability = false
        loadError = nil
        tableView.tableFooterView = nil
        tableView.backgroundView = nil
        applySnapshot()
    }

    private func preserveAnchor() {
        if pendingAnchor == nil, !tableView.isTracking, !tableView.isDragging, !tableView.isDecelerating {
            pendingAnchor = captureAnchor()
        }
    }

    private func resumeLoadingIfNeeded() {
        #if DEBUG
        guard !isRestorationProbe else { return }
        #endif
        guard !retired, isViewLoaded, view.window != nil, pendingAnchor == nil,
              !snapshotApplyInProgress, reloadTask == nil, loadError == nil,
              contextIsCurrent, identity.readySource == identity.origin else { return }
        tableView.isUserInteractionEnabled = true
        quarantinedForClientChange = false
        navigationItem.prompt = nil
        let visible = (tableView.indexPathsForVisibleRows ?? []).compactMap { dataSource.itemIdentifier(for: $0) }
        if revalidation.hasDemand(visibleIDs: visible) || orderedIDs.isEmpty { loadMore() }
    }

    private func leaveUnavailableList() {
        invalidateForContextChange()
        retireReads()
        guard navigationController?.topViewController === self else { return }
        navigationController?.popViewController(animated: false)
    }

    private func retireReads() {
        guard !retired else { return }
        retired = true
        loadGeneration &+= 1
        loadTask?.cancel()
        resolutionTask?.cancel()
        reloadTask?.cancel()
        tagPreparationTask?.cancel()
        loadTask = nil
        resolutionTask = nil
        reloadTask = nil
        tagPreparationTask = nil
        pendingResolutionIDs.removeAll()
        cancellables.removeAll()
    }

    private func retryClientRestoration() {
        guard !contextIsCurrent, !retired, !identity.revoked else { return }
        NavigationStorage.shared.retryClientRestoration()
    }

    private func canRestore(_ next: TdUpdateSource, parent: PeerProfileViewController) -> Bool {
        canRetain(parent: parent, accountID: accountID, actorID: accountUserID, chatID: source.chatID)
            && identity.accepts(
                next,
                current: TDLib.shared.activeUpdateSource,
                actorID: TDLib.shared.activeAccount?.userID,
            )
            && parent.canRestoreMembers(self, source: next) && transitionCoordinator == nil && !snapshotApplyInProgress
    }

    private func captureAnchor() -> TableAnchor? {
        TableAnchor.capture(tableView, id: { dataSource.itemIdentifier(for: $0) })
    }

    private func restorePendingAnchor() {
        guard !retired, isViewLoaded, view.window != nil, tableView.bounds.height > 0,
              !snapshotApplyInProgress, !tableView.isTracking, !tableView.isDragging, !tableView.isDecelerating,
              let anchor = pendingAnchor else { return }
        guard let indexPath = dataSource.indexPath(for: anchor.id) else {
            if !revalidation.active { pendingAnchor = nil }
            return
        }
        anchor.restore(tableView, path: indexPath)
        pendingAnchor = nil
    }
}

#if DEBUG
extension PeerProfileMembersViewController {
    /// Exercises the actual table, snapshot, quarantine and removal paths without
    /// installing subscriptions or issuing TDLib requests in the isolated window.
    static func verifyRestorationRendering(scene: UIWindowScene) async throws {
        let account = UUID()
        let client = TDLib.shared.activeClient
        let old = PeerProfileMembersViewController(
            accountID: account,
            accountUserID: 77,
            client: client,
            source: .basicGroup(chatID: 8, id: 9),
            title: "Probe",
        )
        old.isRestorationProbe = true
        old.orderedIDs = (1...60).map { .user(Int64($0)) }
        old.rawOffset = 60
        old.totalCount = 120
        for (index, id) in old.orderedIDs.enumerated() {
            let title = String(repeating: "Accepted member ", count: index % 3 + 1)
            old.rows[id] = Row(accessibilityLabel: "\(title), OLD ROLE", role: "OLD ROLE", title: title)
        }
        let parent = UIViewController()
        let navigation = UINavigationController()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -10000, y: 0, width: 390, height: 844)
        navigation.setViewControllers([parent, old], animated: false)
        window.rootViewController = navigation
        window.isHidden = false
        defer { window.isHidden = true
        window.rootViewController = nil
        }
        old.parentBinding.attach(parent)
        navigation.view.layoutIfNeeded()
        try await PeerProfileMembersRestorationProbe.until("initial member snapshot") {
            !old.snapshotApplyInProgress && !old.tableView.visibleCells.isEmpty
        }
        old.tableView.setContentOffset(CGPoint(x: 0, y: 1157), animated: false)
        old.tableView.layoutIfNeeded()
        guard let anchor = old.captureAnchor()
            else { throw PeerProfileMembersRestorationProbe.Failure(description: "missing member anchor") }
        old.invalidateForContextChange()
        try PeerProfileMembersRestorationProbe.require(old.tableView.visibleCells.allSatisfy {
            $0.accessibilityLabel == "Updating member…" && $0.accessibilityHint == nil && $0.accessoryType == .none
        }, "stale visible roles/actions survived quarantine")
        let heights = old.retainedHeights
        old.invalidateForContextChange()
        try PeerProfileMembersRestorationProbe.require(
            old.retainedHeights == heights,
            "repeat quarantine recaptured placeholder geometry",
        )
        try await PeerProfileMembersRestorationProbe
            .until("quarantine snapshot") { !old.snapshotApplyInProgress && !old.snapshotApplyPending }
        let state = PeerProfileMembersRestorationState(
            source: old.identity.origin,
            actorID: 77,
            chatID: 8,
            administrators: false,
            ids: old.orderedIDs,
            heights: heights,
            rawOffset: old.rawOffset,
            total: old.totalCount,
            hasMore: true,
            anchor: anchor,
        )
        let fresh = PeerProfileMembersViewController(
            accountID: account,
            accountUserID: 77,
            client: client,
            source: .basicGroup(chatID: 8, id: 9),
            title: "Probe",
            restoration: state,
        )
        fresh.isRestorationProbe = true
        fresh.parentBinding.attach(parent)
        navigation.setViewControllers([parent, fresh], animated: false)
        navigation.view.layoutIfNeeded()
        try await PeerProfileMembersRestorationProbe.until("restored member snapshot") {
            !fresh.snapshotApplyInProgress && fresh.pendingAnchor == nil && !fresh.tableView.visibleCells.isEmpty
        }
        guard let restored = fresh.captureAnchor()
            else { throw PeerProfileMembersRestorationProbe.Failure(description: "missing restored anchor") }
        try PeerProfileMembersRestorationProbe.require(
            old.retired && fresh.rows.isEmpty && fresh.rawOffset == 60
            && restored.id == anchor.id && abs(restored.offset - anchor.offset) < 0.75,
            "restored member identity/pixels/cursor or retired owner failed",
        )
        let page = Array(fresh.orderedIDs.prefix(5))
        fresh.orderedIDs = fresh.revalidation.admit(ids: page, rawCount: 5, hasMore: true)
        fresh.append(page.map { Seed(id: $0, role: "FRESH ROLE") })
        try await PeerProfileMembersRestorationProbe.until("fresh partial snapshot") { !fresh.snapshotApplyInProgress }
        try PeerProfileMembersRestorationProbe.require(
            fresh.rows.count == 5 && fresh.revalidation.cursor == 5
            && fresh.rawOffset == 60 && fresh.revalidation.quarantined.count == 55,
            "partial page restored stale authority or skipped raw cursor",
        )
        let pending = Task<Void, Never> { try? await Task.sleep(for: .seconds(5)) }
        fresh.loadTask = pending
        let generation = fresh.loadGeneration
        navigation.popViewController(animated: false)
        try PeerProfileMembersRestorationProbe.require(
            fresh.retired && pending.isCancelled && fresh.loadTask == nil
            && fresh.loadGeneration != generation && !fresh.parentBinding.contains(fresh, parent: parent),
            "actual pop kept read lifetime/parent authority",
        )
    }
}
#endif

// MARK: - PeerProfileMemberTagAuthority

private struct PeerProfileMemberTagAuthority {
    let baselineTag: String
    let editorTitle: String

    @MainActor static func resolve(
        accountID: UUID,
        accountUserID: Int64,
        chatID: Int64,
        targetUserID: Int64,
        client: TDLibClient,
    ) async throws -> Self {
        guard TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id
        else { throw PeerProfileMemberTagError.accountChanged }
        async let chatRequest = client.getChat(chatId: chatID)
        async let actorRequest = client.getChatMember(
            chatId: chatID,
            memberId: .messageSenderUser(.init(userId: accountUserID)),
        )
        async let targetRequest = client.getChatMember(
            chatId: chatID,
            memberId: .messageSenderUser(.init(userId: targetUserID)),
        )
        let (chat, actor, target) = try await (chatRequest, actorRequest, targetRequest)
        try Task.checkCancellation()
        guard TDLib.shared.activeAccountID == accountID,
              TDLib.shared.activeClient.id == client.id,
              chat.id == chatID,
              target.memberId == .messageSenderUser(.init(userId: targetUserID))
        else { throw PeerProfileMemberTagError.accountChanged }
        switch chat.type {
        case .chatTypeBasicGroup:
            break
        case .chatTypeSupergroup(let supergroup) where !supergroup.isChannel:
            break
        case .chatTypePrivate, .chatTypeSecret, .chatTypeSupergroup:
            throw PeerProfileMemberTagError.unsupportedChat
        }
        guard targetIsActive(target.status) else {
            throw PeerProfileMemberTagError.inactiveMember
        }
        if targetUserID == accountUserID {
            guard chat.permissions.canEditTag else { throw PeerProfileMemberTagError.permissionDenied }
        } else {
            let actorIsCreator: Bool
            let actorCanManageTags: Bool
            switch actor.status {
            case .chatMemberStatusCreator:
                actorIsCreator = true
                actorCanManageTags = true
            case .chatMemberStatusAdministrator(let administrator):
                actorIsCreator = false
                actorCanManageTags = administrator.rights.canManageTags
            case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember,
                 .chatMemberStatusRestricted:
                actorIsCreator = false
                actorCanManageTags = false
            }
            guard actorCanManageTags else { throw PeerProfileMemberTagError.permissionDenied }
            switch target.status {
            case .chatMemberStatusCreator:
                throw PeerProfileMemberTagError.permissionDenied
            case .chatMemberStatusAdministrator(let administrator):
                guard actorIsCreator || administrator.canBeEdited else {
                    throw PeerProfileMemberTagError.permissionDenied
                }
            case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember,
                 .chatMemberStatusRestricted:
                break
            }
        }
        let editorTitle =
            switch target.status {
            case .chatMemberStatusAdministrator, .chatMemberStatusCreator:
                "Edit Admin Title"
            case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember,
                 .chatMemberStatusRestricted:
                target.tag.isEmpty ? "Add Member Tag" : "Edit Member Tag"
            }
        return Self(baselineTag: target.tag, editorTitle: editorTitle)
    }

    private static func targetIsActive(_ status: ChatMemberStatus) -> Bool {
        switch status {
        case .chatMemberStatusAdministrator, .chatMemberStatusCreator, .chatMemberStatusMember:
            true
        case .chatMemberStatusRestricted(let restricted):
            restricted.isMember
        case .chatMemberStatusBanned, .chatMemberStatusLeft:
            false
        }
    }
}

// MARK: - PeerProfileMemberTagError

private enum PeerProfileMemberTagError: LocalizedError {
    case accountChanged
    case inactiveMember
    case invalidTag
    case permissionDenied
    case staleTag
    case unsupportedChat

    var errorDescription: String? {
        switch self {
        case .accountChanged:
            "The active Telegram account changed."
        case .inactiveMember:
            "This user is no longer an active member."
        case .invalidTag:
            "Tags can contain up to 16 characters and can't contain emoji or line breaks."
        case .permissionDenied:
            "You no longer have permission to edit this member's tag."
        case .staleTag:
            "The tag changed elsewhere. Close this editor and try again."
        case .unsupportedChat:
            "Member tags are available only in groups and supergroups, not channels."
        }
    }
}

// MARK: - PeerProfileMemberTagViewController

@MainActor private final class PeerProfileMemberTagViewController: UIViewController, UITextFieldDelegate {
    var onSaved: (() -> Void)?

    private let accountID: UUID
    private let accountUserID: Int64
    private let baselineTag: String
    private let chatID: Int64
    private let client: TDLibClient
    private let targetUserID: Int64
    private let targetTitle: String
    private let textField = UITextField()
    private let countLabel = UILabel()
    private let errorLabel = UILabel()
    private var saveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    init(
        accountID: UUID,
        accountUserID: Int64,
        chatID: Int64,
        client: TDLibClient,
        initialAuthority: PeerProfileMemberTagAuthority,
        targetTitle: String,
        targetUserID: Int64,
    ) {
        self.accountID = accountID
        self.accountUserID = accountUserID
        self.baselineTag = initialAuthority.baselineTag
        self.chatID = chatID
        self.client = client
        self.targetTitle = targetTitle
        self.targetUserID = targetUserID
        super.init(nibName: nil, bundle: nil)
        title = initialAuthority.editorTitle
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    deinit { saveTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save",
            style: .plain,
            target: self,
            action: #selector(save),
        )
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        view.addSubview(stack)
        let targetLabel = UILabel()
        targetLabel.font = .preferredFont(forTextStyle: .headline)
        targetLabel.adjustsFontForContentSizeCategory = true
        targetLabel.numberOfLines = 2
        targetLabel.text = targetTitle
        stack.addArrangedSubview(targetLabel)
        textField.borderStyle = .roundedRect
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.autocapitalizationType = .sentences
        textField.autocorrectionType = .no
        textField.clearButtonMode = .whileEditing
        textField.placeholder = "Tag"
        textField.text = baselineTag
        textField.delegate = self
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        stack.addArrangedSubview(textField)
        countLabel.font = .preferredFont(forTextStyle: .footnote)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .right
        stack.addArrangedSubview(countLabel)
        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        stack.addArrangedSubview(errorLabel)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            guard let self, !contextIsCurrent else { return }
            saveTask?.cancel()
            saveTask = nil
            view.isUserInteractionEnabled = false
            navigationItem.rightBarButtonItem?.isEnabled = false
        }
        updateValidation()
    }

    private static func isValid(_ tag: String) -> Bool {
        guard tag.count <= 16 else { return false }
        return !tag.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                || scalar.properties.isEmojiPresentation
                || scalar.value == 0x200D
                || scalar.value == 0x20E3
                || scalar.value == 0xFE0F
                || 0x1F1E6...0x1F1FF ~= scalar.value
                || scalar.properties.isEmoji && scalar.value > 0x7F
        }
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        save()
        return true
    }

    @objc private func textChanged() {
        errorLabel.isHidden = true
        updateValidation()
    }

    @objc private func save() {
        let tag = textField.text ?? ""
        guard saveTask == nil, contextIsCurrent, Self.isValid(tag) else {
            if !Self.isValid(tag) {
                showError(PeerProfileMemberTagError.invalidTag.localizedDescription)
            }
            return
        }
        if tag == baselineTag {
            _ = navigationController?.popViewController(animated: true)
            return
        }
        navigationItem.rightBarButtonItem?.isEnabled = false
        view.endEditing(true)
        errorLabel.isHidden = true
        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let authority = try await PeerProfileMemberTagAuthority.resolve(
                    accountID: accountID,
                    accountUserID: accountUserID,
                    chatID: chatID,
                    targetUserID: targetUserID,
                    client: client,
                )
                guard authority.baselineTag == baselineTag else {
                    throw PeerProfileMemberTagError.staleTag
                }
                guard !Task.isCancelled, contextIsCurrent else {
                    throw PeerProfileMemberTagError.accountChanged
                }
                _ = try await client.setChatMemberTag(
                    chatId: chatID,
                    tag: tag,
                    userId: targetUserID,
                )
                try Task.checkCancellation()
                guard contextIsCurrent else { return }
                saveTask = nil
                navigationItem.rightBarButtonItem?.isEnabled = true
                onSaved?()
                _ = navigationController?.popViewController(animated: true)
            } catch is CancellationError {
                saveTask = nil
                navigationItem.rightBarButtonItem?.isEnabled = true
            } catch {
                guard contextIsCurrent else { return }
                saveTask = nil
                navigationItem.rightBarButtonItem?.isEnabled = true
                showError(error.localizedDescription)
            }
        }
    }

    private func updateValidation() {
        let tag = textField.text ?? ""
        let count = tag.count
        let valid = Self.isValid(tag)
        countLabel.text = "\(count)/16"
        countLabel.textColor = valid ? .secondaryLabel : .systemRed
        navigationItem.rightBarButtonItem?.isEnabled = valid && saveTask == nil
        textField.accessibilityValue = "\(count) of 16 characters"
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

// MARK: - PeerProfileEditViewController

@MainActor final class PeerProfileEditViewController: UIViewController, UITextFieldDelegate, UITextViewDelegate {
    enum Mode {
        case selfProfile(userID: Int64, firstName: String, lastName: String, bio: String)
        case chat(
            chatID: Int64,
            title: String,
            description: String,
        )
    }

    private let session: PeerProfileEditSession
    private let mode: Mode
    private var persistedDetail: String
    private var persistedFirst: String
    private var persistedSecond: String
    private let stack = UIStackView()
    private let firstField = UITextField()
    private let secondField = UITextField()
    private let detailView = UITextView()
    private let errorLabel = UILabel()
    private var editRevision = UInt64.zero
    private var cancellables = Set<AnyCancellable>()

    var editAccountID: UUID { session.accountID }
    var canRetainStaleProfile: Bool { session.state != .revoked }
    #if DEBUG
        var persistedFieldsForProbe: [String] { [persistedFirst, persistedSecond, persistedDetail] }
    #endif

    convenience init(accountID: UUID, accountUserID: Int64?, mode: Mode) {
        self.init(session: .live(accountID: accountID, actorID: accountUserID), mode: mode)
    }

    init(session: PeerProfileEditSession, mode: Mode) {
        self.session = session
        self.mode = mode
        switch mode {
        case .selfProfile(_, let firstName, let lastName, let bio):
            self.persistedFirst = firstName
            self.persistedSecond = lastName
            self.persistedDetail = bio.replacingOccurrences(of: "\n", with: " ")
        case .chat(_, let title, let description):
            self.persistedFirst = title
            self.persistedSecond = ""
            self.persistedDetail = description
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Edit"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save",
            style: .plain,
            target: self,
            action: #selector(save),
        )
        configureForm()
        session.publisher
            .sink { [weak self] state in
                guard let self else { return }
                navigationItem.rightBarButtonItem?.isEnabled = state == .ready
                switch state {
                case .ready: navigationItem.prompt = nil
                case .waiting: navigationItem.prompt = "Reconnecting… Your changes are kept."
                case .saving: navigationItem.prompt = "Saving…"
                case .uncertain: navigationItem.prompt = "Result unknown. Check the profile before retrying."
                case .revoked:
                    navigationItem.prompt = "This account is no longer active."
                    view.isUserInteractionEnabled = false
                }
                #if DEBUG
                    recordEditorLayout(phase: "state")
                    DispatchQueue.main.async { [weak self] in self?.recordEditorLayout(phase: "after-state") }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.recordEditorLayout(phase: "settled-state")
                    }
                #endif
            }
            .store(in: &cancellables)
    }

    #if DEBUG
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            recordEditorLayout(phase: "layout")
        }

        private func recordEditorLayout(phase: String) {
            ClassicNavigationDiagnostics.editorLayout(self, fields: [firstField, secondField], phase: phase)
        }
    #endif

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === firstField, !secondField.isHidden {
            secondField.becomeFirstResponder()
        } else {
            detailView.becomeFirstResponder()
        }
        return true
    }

    func textViewDidChange(_: UITextView) { editingChanged() }

    private func configureForm() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        scrollView.addSubview(stack)
        for field in [firstField, secondField] {
            field.borderStyle = .roundedRect
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.clearButtonMode = .whileEditing
            field.delegate = self
            field.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
            stack.addArrangedSubview(field)
        }
        detailView.font = .preferredFont(forTextStyle: .body)
        detailView.delegate = self
        detailView.adjustsFontForContentSizeCategory = true
        detailView.backgroundColor = .secondarySystemBackground
        detailView.layer.cornerRadius = 10
        detailView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        detailView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        stack.addArrangedSubview(detailView)
        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        stack.addArrangedSubview(errorLabel)
        switch mode {
        case .selfProfile(_, let firstName, let lastName, let bio):
            firstField.placeholder = "First name"
            secondField.placeholder = "Last name"
            firstField.text = firstName
            secondField.text = lastName
            detailView.text = bio
            detailView.accessibilityLabel = "Bio"
        case .chat(_, let title, let description):
            firstField.placeholder = "Chat title"
            firstField.text = title
            secondField.isHidden = true
            detailView.text = description
            detailView.accessibilityLabel = "Description"
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
        ])
    }

    @objc private func editingChanged() { editRevision &+= 1 }
    @objc private func save() {
        guard session.state == .ready else { return }
        let first = firstField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let second = secondField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = detailView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else {
            showError(secondField.isHidden ? "Chat title is required." : "First name is required.")
            return
        }
        errorLabel.isHidden = true
        var mutations = [PeerProfileEditSession.Mutation]()
        switch mode {
        case .selfProfile(let userID, _, _, _):
            guard session.representsActor(userID) else {
                showError(PeerProfileEditError.permissionChanged.localizedDescription)
                return
            }
            if first != persistedFirst || second != persistedSecond {
                mutations.append(.name(first, second))
            }
            let normalizedBio = detail.replacingOccurrences(of: "\n", with: " ")
            if normalizedBio != persistedDetail { mutations.append(.bio(normalizedBio)) }
        case .chat(let chatID, _, _):
            if first != persistedFirst { mutations.append(.title(chatID, first)) }
            if detail != persistedDetail { mutations.append(.description(chatID, detail)) }
        }
        let revision = editRevision
        session.save(mutations, owner: self, accepted: { [weak self] mutation in
            guard let self else { return }
            switch mutation {
            case .name(let first, let last):
                persistedFirst = first
                persistedSecond = last
            case .title(_, let value): persistedFirst = value
            case .bio(let value), .description(_, let value): persistedDetail = value
            }
        }, completion: { [weak self] result, completed in
            guard let self, editRevision == revision else { return }
            switch result {
            case .success: navigationController?.popViewController(animated: true)
            case .failure(let error):
                let prefix =
                    if case .selfProfile = mode {
                        "Name was saved, but bio failed: "
                    } else {
                        "Title was saved, but description failed: "
                    }
                showError((completed > 0 ? prefix : "") + error.localizedDescription)
            }
        })
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

// MARK: - PeerProfileEditError

enum PeerProfileEditError: LocalizedError {
    case partialSuccess(String)
    case permissionChanged

    var errorDescription: String? {
        switch self {
        case .partialSuccess(let message): message
        case .permissionChanged: "Your permission to edit this profile has changed."
        }
    }
}

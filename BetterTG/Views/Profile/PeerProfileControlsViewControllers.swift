// PeerProfileControlsViewControllers.swift

import Combine
import TDLibKit
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

    /// The group fields the list depends on: who is in it and what the account may see. Other changes (title, photo,
    /// username, boosts) leave the rows alone.
    private struct GroupListSignature: Equatable {
        let memberCount: Int
        let status: ChatMemberStatus
        let isActive: Bool
        let upgradedToSupergroupID: Int64

        init(_ group: BasicGroup) {
            self.memberCount = group.memberCount
            self.status = group.status
            self.isActive = group.isActive
            self.upgradedToSupergroupID = group.upgradedToSupergroupId
        }

        init(_ group: Supergroup) {
            self.memberCount = group.memberCount
            self.status = group.status
            self.isActive = true
            self.upgradedToSupergroupID = 0
        }
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
    private let tagRetention = PeerProfileMemberTagRetention()
    private var retired = false
    private var retentionDenied = false
    private var revalidation = PeerProfileMembersRevalidation()
    private var retainedHeights = [MemberID: CGFloat]()
    private var loadError: String?
    private var loadRetryID: UUID?
    private var checkedAvailability = false
    private var quarantinedForClientChange = false
    private var basicMembersRevision = PeerProfileMembersRevision<[ChatMember]>()
    private var memberAvailabilityRevision = PeerProfileMembersRevision<Bool>()
    private var groupRevision = PeerProfileMembersRevision<GroupListSignature>()
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
    /// Name and role resolution survives a reread that keeps the rows; only a reset drops it.
    private var rowGeneration = UInt64.zero
    private var pendingAnchor: TableAnchor?
    private var snapshotApplyInProgress = false
    private var snapshotApplyPending = false
    private var cancellables = Set<AnyCancellable>()
    private var dataSource: UITableViewDiffableDataSource<Section, MemberID>!
    #if DEBUG
    private var isRestorationProbe = false
    private var probeReadDispatches = 0
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

    private var emptyListText: String {
        switch source {
        case .administrators: L10n.betterTG("Profile.NoAdmins")
        case .basicGroup, .supergroup: L10n.betterTG("Profile.NoMembers")
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
            case .administrators: L10n.telegram("GroupInfo.Administrators")
            case .basicGroup, .supergroup: L10n.telegram("Group.Info.Members")
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
                  groupRevision.observe(GroupListSignature(event.value.basicGroup)) else { return }
            scheduleReload()
        }
        nc.scopedPublisher(&cancellables, for: .updateSupergroup) { [weak self] event in
            guard let self, contextIsCurrent, event.source == identity.origin,
                  source.group == .supergroup(event.value.supergroup.id),
                  groupRevision.observe(GroupListSignature(event.value.supergroup)) else { return }
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
                    initialAuthority: authority,
                    targetTitle: title,
                    targetUserID: targetUserID,
                )
                editor.onSaved = { [weak self] in
                    guard let self, contextIsCurrent else { return }
                    scheduleReload()
                }
                tagRetention.editor = editor
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
            roleTitle(L10n.telegram("Channel.Management.LabelOwner"), tag: member.tag)
        case .chatMemberStatusAdministrator:
            roleTitle(L10n.telegram("Channel.Management.LabelAdministrator"), tag: member.tag)
        case .chatMemberStatusBanned:
            L10n.betterTG("Profile.RoleBanned")
        case .chatMemberStatusLeft:
            L10n.betterTG("Profile.RoleLeft")
        case .chatMemberStatusMember:
            member.tag.isEmpty ? L10n.telegram("GroupPermission.Member") : member.tag
        case .chatMemberStatusRestricted(let restricted):
            restricted.isMember
                ? L10n.betterTG("Profile.RoleRestrictedMember")
                : L10n.betterTG("Profile.RoleRestricted")
        }
    }

    private static func roleTitle(_ role: String, tag: String) -> String {
        tag.isEmpty ? role : "\(role) · \(tag)"
    }

    private static func userStatus(_ status: UserStatus) -> String {
        switch status {
        case .userStatusOnline: L10n.telegram("Presence.online")
        case .userStatusRecently: L10n.telegram("Watch.LastSeen.Lately")
        case .userStatusLastWeek: L10n.telegram("Watch.LastSeen.WithinAWeek")
        case .userStatusLastMonth: L10n.telegram("Watch.LastSeen.WithinAMonth")
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

    func retainsMemberTag(parent: PeerProfileViewController, accountID: UUID, actorID: Int64?, chatID: Int64) -> Bool {
        !retired && !retentionDenied && !identity.revoked && parentBinding.parent === parent
            && self.accountID == accountID && accountUserID == actorID && source.chatID == chatID
            && tagRetention.shouldRetain(
                parent: parent,
                members: self,
                accountID: accountID,
                actorID: actorID,
                chatID: chatID,
                currentAccountID: TDLib.shared.activeAccountID,
                currentActorID: TDLib.shared.activeAccount?.userID,
            )
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

    private func loadFailureText(_ message: String) -> String {
        switch source {
        case .administrators: L10n.betterTG("Profile.AdminsLoadFailed", message)
        case .basicGroup, .supergroup: L10n.betterTG("Profile.MembersLoadFailed", message)
        }
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
            cell.accessibilityHint = canInspectTag ? L10n.betterTG("Accessibility.MemberTagHint") : nil
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
            guard let self, !Task.isCancelled, readOwnerIsCurrent, loadGeneration == generation else { return }
            #if DEBUG
            if isRestorationProbe {
                probeReadDispatches += 1
                loadTask = nil
                return
            }
            #endif
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
                                Self.roleTitle(
                                    L10n.telegram("Channel.Management.LabelOwner"),
                                    tag: administrator.customTitle,
                                )
                            } else {
                                Self.roleTitle(
                                    L10n.telegram("Channel.Management.LabelAdministrator"),
                                    tag: administrator.customTitle,
                                )
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
        var resolving = [Seed]()
        for seed in page {
            let id = seed.id
            if rows[id] == nil {
                if !orderedIDs.contains(id) { orderedIDs.append(id) }
                resolving.append(seed)
                rows[id] = fallbackRow(seed)
            } else if seeds[id]?.role != seed.role {
                // A reread keeps the row on screen until its new role resolves with the member's name and status.
                resolving.append(seed)
            }
            seeds[id] = seed
        }
        applySnapshot()
        enqueueResolution(resolving)
    }

    private func enqueueResolution(_ newSeeds: [Seed]) {
        #if DEBUG
        guard !isRestorationProbe else { return }
        #endif
        pendingResolutionIDs.append(contentsOf: newSeeds.map(\.id))
        guard resolutionTask == nil, !pendingResolutionIDs.isEmpty else { return }
        let generation = rowGeneration
        resolutionTask = Task { [weak self] in
            guard let self else { return }
            var resolvedIDs = [MemberID]()
            while !pendingResolutionIDs.isEmpty, !Task.isCancelled {
                let id = pendingResolutionIDs.removeFirst()
                guard let seed = seeds[id] else { continue }
                let row = await resolve(seed)
                guard !Task.isCancelled, readOwnerIsCurrent, rowGeneration == generation else { return }
                // A reread may have dropped the member meanwhile.
                guard seeds[id] != nil else { continue }
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
            let title = name.isEmpty ? L10n.betterTG("Profile.UserFallback", String(userID)) : name
            let status = Self.userStatus(user.status)
            let detail = status.isEmpty ? seed.role : "\(seed.role) · \(status)"
            return Row(
                accessibilityLabel: "\(title), \(detail)",
                role: detail,
                title: title,
            )
        case .chat(let chatID):
            let title = await (try? client.getChat(chatId: chatID))?.title ?? L10n.betterTG(
                "Profile.ChatFallback",
                String(chatID),
            )
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
            case .user(let userID): L10n.betterTG("Profile.UserFallback", String(userID))
            case .chat(let chatID): L10n.betterTG("Profile.ChatFallback", String(chatID))
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
        let generation = loadGeneration
        let retryID = UUID()
        loadRetryID = retryID
        let action = UIAction(title: L10n.telegram("ChatImportActivity.Retry")) { [weak self] _ in
            self?.retryLoad(id: retryID, generation: generation)
        }
        let item = UIBarButtonItem(primaryAction: action)
        item.hidesSharedBackground = true
        navigationItem.rightBarButtonItem = item
        let button = UIButton(type: .system)
        button.frame.size.height = 112
        button.setTitle(loadFailureText(message), for: .normal)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.addAction(action, for: .touchUpInside)
        tableView.tableFooterView = button
        tableView.backgroundView = nil
        renderVisiblePlaceholders()
    }

    private func retryLoad(id: UUID, generation: UInt64) {
        guard loadRetryID == id, loadGeneration == generation, loadError != nil,
              readOwnerIsCurrent, navigationController?.topViewController === self else { return }
        loadError = nil
        loadRetryID = nil
        navigationItem.rightBarButtonItem = nil
        tableView.tableFooterView = nil
        renderVisiblePlaceholders()
        loadMore()
    }

    private func renderVisiblePlaceholders() {
        preserveAnchor()
        for path in tableView.indexPathsForVisibleRows ?? [] {
            guard let id = dataSource.itemIdentifier(for: path), rows[id] == nil,
                  let cell = tableView.cellForRow(at: path) else { continue }
            PeerProfileMemberPlaceholder.configure(cell, retrying: loadError != nil)
        }
        applySnapshot()
    }

    private func emptyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }

    private func updateEmptyState() {
        tableView.backgroundView = orderedIDs.isEmpty && loadTask == nil ? emptyLabel(emptyListText) : nil
    }

    private func scheduleReload() {
        beginRevalidation(clearingRows: false)
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
        navigationItem.prompt = identity.revoked
            ? L10n.betterTG("Session.AccountInactive")
            : L10n.betterTG("Session.Reconnecting")
    }

    private func presentTagError(_ error: Swift.Error) {
        guard presentedViewController == nil else { return }
        let message = (error as? LocalizedError)?.errorDescription
            ?? L10n.betterTG("Profile.TagEditUnavailable")
        let alert = UIAlertController(
            title: L10n.betterTG("Profile.CantEditTag"),
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }

    /// Rereads the list from its first page. A client change clears the rows, since their names, roles and actions
    /// belong to the old client; a group update keeps them until the reread pages replace them.
    private func beginRevalidation(clearingRows: Bool = true) {
        preserveAnchor()
        for path in tableView.indexPathsForVisibleRows ?? [] {
            if let id = dataSource.itemIdentifier(for: path), rows[id] != nil {
                retainedHeights[id] = tableView.rectForRow(at: path).height
            }
        }
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        if clearingRows {
            rowGeneration &+= 1
            resolutionTask?.cancel()
            resolutionTask = nil
            pendingResolutionIDs.removeAll()
            rows.removeAll()
            seeds.removeAll()
            tableView.visibleCells.forEach { PeerProfileMemberPlaceholder.configure($0, retrying: false) }
        }
        revalidation.begin(ids: orderedIDs, rawOffset: rawOffset)
        checkedAvailability = false
        loadError = nil
        loadRetryID = nil
        navigationItem.rightBarButtonItem = nil
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
        rowGeneration &+= 1
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
        guard let account = TDLib.shared.activeAccountID, let actorID = TDLib.shared.activeAccount?.userID else {
            throw PeerProfileMembersRestorationProbe
                .Failure(description: "member retry probe requires an active account")
        }
        let client = TDLib.shared.activeClient
        let old = PeerProfileMembersViewController(
            accountID: account,
            accountUserID: actorID,
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
            $0.accessibilityLabel == L10n.betterTG("Profile.UpdatingMember") && $0.accessibilityHint == nil && $0
                .accessoryType == .none
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
            actorID: actorID,
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
            accountUserID: actorID,
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
        fresh.identity.readySource = fresh.identity.origin
        fresh.loadError = "Probe offline"
        fresh.showRetry("Probe offline")
        guard let retry = fresh.tableView.tableFooterView as? UIButton else {
            throw PeerProfileMembersRestorationProbe.Failure(description: "missing retry control")
        }
        try PeerProfileMembersRestorationProbe.require(
            fresh.navigationItem.rightBarButtonItem?.title == L10n.telegram("ChatImportActivity.Retry")
            && fresh.navigationItem.rightBarButtonItem?.style == .plain
            && fresh.navigationItem.rightBarButtonItem?.hidesSharedBackground == true
            && fresh.tableView.visibleCells.allSatisfy {
                $0.accessibilityLabel == L10n.betterTG("Profile.MemberUnavailableRetry") && $0
                    .accessoryType == .none && $0
                    .accessibilityHint == nil
            },
            "deep failure lacked visible classic Retry or leaked stale roles",
        )
        try await PeerProfileMembersRestorationProbe.until("failed member snapshot") { !fresh.snapshotApplyInProgress }
        try PeerProfileMembersRestorationProbe.require(
            fresh.probeReadDispatches == 0 && fresh.loadError != nil,
            "failed page retried automatically",
        )
        let cover = UIViewController()
        navigation.pushViewController(cover, animated: false)
        retry.sendActions(for: .touchUpInside)
        try PeerProfileMembersRestorationProbe.require(
            fresh.loadError != nil && fresh.loadTask == nil,
            "covered owner retried",
        )
        navigation.popViewController(animated: false)
        fresh.identity.readySource = nil
        retry.sendActions(for: .touchUpInside)
        try PeerProfileMembersRestorationProbe.require(
            fresh.loadError != nil && fresh.loadTask == nil,
            "unready source retried",
        )
        fresh.identity.readySource = fresh.identity.origin
        fresh.loadGeneration &+= 1
        retry.sendActions(for: .touchUpInside)
        try PeerProfileMembersRestorationProbe.require(
            fresh.loadError != nil && fresh.loadTask == nil,
            "stale generation retried",
        )
        fresh.showRetry("Current failure")
        guard let currentRetry = fresh.tableView.tableFooterView as? UIButton else {
            throw PeerProfileMembersRestorationProbe.Failure(description: "missing current retry")
        }
        currentRetry.sendActions(for: .touchUpInside)
        try await PeerProfileMembersRestorationProbe.until("explicit retry dispatch") { fresh.probeReadDispatches == 1 }
        try PeerProfileMembersRestorationProbe.require(
            fresh.loadError == nil && fresh.navigationItem.rightBarButtonItem == nil,
            "explicit retry retained failure UI",
        )
        fresh.loadError = "Second failure"
        fresh.showRetry("Second failure")
        currentRetry.sendActions(for: .touchUpInside)
        try PeerProfileMembersRestorationProbe.require(
            fresh.loadError != nil && fresh.probeReadDispatches == 1,
            "previous retry control consumed new failure",
        )
        (fresh.tableView.tableFooterView as? UIButton)?.sendActions(for: .touchUpInside)
        guard let scheduled = fresh.loadTask else {
            throw PeerProfileMembersRestorationProbe.Failure(description: "explicit retry did not schedule a read")
        }
        fresh.beginRevalidation()
        await scheduled.value
        try PeerProfileMembersRestorationProbe.require(
            scheduled.isCancelled && fresh.probeReadDispatches == 1,
            "predispatch cancellation issued an obsolete read",
        )
        let pending = Task<Void, Never> { try? await Task.sleep(for: .seconds(5)) }
        fresh.loadTask = pending
        let generation = fresh.loadGeneration
        navigation.popViewController(animated: false)
        try PeerProfileMembersRestorationProbe.require(
            !fresh.readOwnerIsCurrent && !fresh.parentBinding.contains(fresh, parent: parent),
            "actual pop kept synchronous read/parent authority",
        )
        try await PeerProfileMembersRestorationProbe.until("popped read retirement") {
            fresh.retired && pending.isCancelled && fresh.loadTask == nil && fresh.loadGeneration != generation
        }
    }
}
#endif

// MARK: - PeerProfileMemberTagAuthority

struct PeerProfileMemberTagAuthority {
    let baselineTag: String
    let editorTitle: String

    @MainActor static func resolve(
        accountID: UUID,
        accountUserID: Int64,
        chatID: Int64,
        targetUserID: Int64,
        client: TDLibClient,
    ) async throws -> Self {
        try await PeerProfileMemberTagAuthorization.live(
            accountID: accountID,
            actorID: accountUserID,
            chatID: chatID,
            targetID: targetUserID,
            client: client,
        )
        .load()
    }

    @MainActor static func validate(
        _ snapshot: PeerProfileMemberTagAuthorization.Snapshot,
        actorID: Int64,
        targetID: Int64,
    ) throws -> Self {
        let actor = snapshot.actor, target = snapshot.target
        switch snapshot.chatType {
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
        if targetID == actorID {
            guard snapshot.permissions.canEditTag else { throw PeerProfileMemberTagError.permissionDenied }
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
                L10n.betterTG("Profile.EditAdminTitle")
            case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember,
                 .chatMemberStatusRestricted:
                target.tag.isEmpty ? L10n.telegram("GroupInfo.ActionAddRank") : L10n.betterTG("Profile.EditMemberTag")
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

enum PeerProfileMemberTagError: LocalizedError {
    case accountChanged
    case inactiveMember
    case invalidTag
    case permissionDenied
    case staleTag
    case unsupportedChat

    var errorDescription: String? {
        switch self {
        case .accountChanged:
            L10n.betterTG("Error.AccountChanged")
        case .inactiveMember:
            L10n.betterTG("Profile.TagInactiveMember")
        case .invalidTag:
            L10n.betterTG("Profile.TagInvalid")
        case .permissionDenied:
            L10n.betterTG("Profile.TagPermissionDenied")
        case .staleTag:
            L10n.betterTG("Profile.TagStale")
        case .unsupportedChat:
            L10n.betterTG("Profile.TagUnsupportedChat")
        }
    }
}

// MARK: - PeerProfileMemberTagViewController

@MainActor final class PeerProfileMemberTagViewController: UIViewController, UITextFieldDelegate {
    var onSaved: (() -> Void)?

    private let session: PeerProfileEditSession
    private var baselineTag: String
    private let chatID: Int64
    private let targetUserID: Int64
    private let targetTitle: String
    private let textField = UITextField()
    private let countLabel = UILabel()
    private let errorLabel = UILabel()
    private var editRevision = UInt64.zero
    private var cancellables = Set<AnyCancellable>()

    var canRetainStaleParents: Bool { session.state != .revoked }

    private var ownsUncoveredTop: Bool {
        guard PeerProfileEditSession.isAttached(self),
              navigationController?.topViewController === self else { return false }
        var node: UIViewController? = self
        while let current = node {
            guard current.presentedViewController == nil else { return false }
            node = current.parent
        }
        return true
    }

    convenience init(
        accountID: UUID,
        accountUserID: Int64,
        chatID: Int64,
        initialAuthority: PeerProfileMemberTagAuthority,
        targetTitle: String,
        targetUserID: Int64,
    ) {
        self.init(
            session: .live(accountID: accountID, actorID: accountUserID),
            chatID: chatID,
            initialAuthority: initialAuthority,
            targetTitle: targetTitle,
            targetUserID: targetUserID,
        )
    }

    init(
        session: PeerProfileEditSession,
        chatID: Int64,
        initialAuthority: PeerProfileMemberTagAuthority,
        targetTitle: String,
        targetUserID: Int64,
    ) {
        self.session = session
        self.baselineTag = initialAuthority.baselineTag
        self.chatID = chatID
        self.targetTitle = targetTitle
        self.targetUserID = targetUserID
        super.init(nibName: nil, bundle: nil)
        title = initialAuthority.editorTitle
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Save"),
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
        textField.placeholder = L10n.betterTG("Profile.TagPlaceholder")
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
        session.publisher
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready: navigationItem.prompt = nil
                case .waiting: navigationItem.prompt = L10n.betterTG("Session.ReconnectingKeepsChanges")
                case .saving: navigationItem.prompt = L10n.betterTG("Session.Saving")
                case .uncertain: navigationItem.prompt = L10n.betterTG("Profile.MemberResultUnknown")
                case .revoked:
                    navigationItem.prompt = L10n.betterTG("Session.AccountInactive")
                    view.isUserInteractionEnabled = false
                }
                updateValidation()
            }
            .store(in: &cancellables)
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

    func represents(accountID: UUID, actorID: Int64, chatID: Int64) -> Bool {
        session.accountID == accountID && session.representsActor(actorID) && self.chatID == chatID
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        save()
        return true
    }

    @objc private func textChanged() {
        editRevision &+= 1
        errorLabel.isHidden = true
        updateValidation()
    }

    @objc private func save() {
        guard ownsUncoveredTop else { return }
        let tag = textField.text ?? ""
        guard session.state == .ready, textField.markedTextRange == nil, Self.isValid(tag) else {
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
        let revision = editRevision
        session.save(
            [.memberTag(chatID: chatID, targetID: targetUserID, baseline: baselineTag, tag: tag)],
            owner: self,
            accepted: { [weak self] mutation in
                guard let self, case .memberTag(_, _, _, let tag) = mutation else { return }
                baselineTag = tag
                onSaved?()
            },
            completion: { [weak self] result, _ in
                guard let self, editRevision == revision, textField.text == tag,
                      textField.markedTextRange == nil, ownsUncoveredTop else { return }
                switch result {
                case .success: navigationController?.popViewController(animated: true)
                case .failure(let error): showError(error.localizedDescription)
                }
            },
        )
    }

    private func updateValidation() {
        let tag = textField.text ?? ""
        let count = tag.count
        let valid = Self.isValid(tag)
        countLabel.text = "\(count)/16"
        countLabel.textColor = valid ? .secondaryLabel : .systemRed
        navigationItem.rightBarButtonItem?.isEnabled = valid && textField.markedTextRange == nil && session
            .state == .ready
        textField.accessibilityValue = L10n.betterTG("Accessibility.TagCharacterCount", count)
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
        title = L10n.telegram("Common.Edit")
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Save"),
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
                case .waiting: navigationItem.prompt = L10n.betterTG("Session.ReconnectingKeepsChanges")
                case .saving: navigationItem.prompt = L10n.betterTG("Session.Saving")
                case .uncertain: navigationItem.prompt = L10n.betterTG("Profile.ProfileResultUnknown")
                case .revoked:
                    navigationItem.prompt = L10n.betterTG("Session.AccountInactive")
                    view.isUserInteractionEnabled = false
                }
            }
            .store(in: &cancellables)
    }

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
            firstField.placeholder = L10n.telegram("UserInfo.FirstNamePlaceholder")
            secondField.placeholder = L10n.telegram("UserInfo.LastNamePlaceholder")
            firstField.text = firstName
            secondField.text = lastName
            detailView.text = bio
            detailView.accessibilityLabel = L10n.telegram("Settings.About")
        case .chat(_, let title, let description):
            firstField.placeholder = L10n.betterTG("Profile.ChatTitlePlaceholder")
            firstField.text = title
            secondField.isHidden = true
            detailView.text = description
            detailView.accessibilityLabel = L10n.telegram("Channel.Edit.AboutItem")
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
            showError(secondField.isHidden
                ? L10n.betterTG("Profile.ChatTitleRequired")
                : L10n.betterTG("Profile.FirstNameRequired"))
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
            case .memberTag: break
            }
        }, completion: { [weak self] result, completed in
            guard let self, editRevision == revision else { return }
            switch result {
            case .success: navigationController?.popViewController(animated: true)
            case .failure(let error):
                let partialKey =
                    if case .selfProfile = mode {
                        "Profile.BioSaveFailed"
                    } else {
                        "Profile.DescriptionSaveFailed"
                    }
                showError(
                    completed > 0
                        ? L10n.betterTG(partialKey, error.localizedDescription)
                        : error.localizedDescription,
                )
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
        case .permissionChanged: L10n.betterTG("Profile.PermissionChanged")
        }
    }
}

// PeerProfileControlsViewControllers.swift

import Combine
import TDLibKitDynamic
import UIKit

// MARK: - PeerProfileMembersViewController

@MainActor final class PeerProfileMembersViewController: UITableViewController {
    enum Source {
        case administrators(chatID: Int64)
        case basicGroup(chatID: Int64, id: Int64, members: [ChatMember])
        case supergroup(chatID: Int64, id: Int64)

        var chatID: Int64 {
            switch self {
            case .administrators(let chatID), .basicGroup(let chatID, _, _), .supergroup(let chatID, _):
                chatID
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

    private struct TableAnchor {
        let id: MemberID
        let offset: CGFloat
    }

    private enum MemberID: Hashable {
        case chat(Int64)
        case user(Int64)

        init(_ sender: MessageSender) {
            self =
                switch sender {
                case .messageSenderChat(let sender):
                    .chat(sender.chatId)
                case .messageSenderUser(let sender):
                    .user(sender.userId)
                }
        }
    }

    private enum Section {
        case members
    }

    private let accountID: UUID
    private let accountUserID: Int64?
    private let client: TDLibClient
    private let source: Source
    private var basicGroupMembers: [ChatMember]
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

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    private var listNoun: String {
        switch source {
        case .administrators: "administrators"
        case .basicGroup, .supergroup: "members"
        }
    }

    init(accountID: UUID, accountUserID: Int64?, client: TDLibClient, source: Source, title: String) {
        self.accountID = accountID
        self.accountUserID = accountUserID
        self.client = client
        self.source = source
        self.basicGroupMembers =
            if case .basicGroup(_, _, let members) = source {
                members
            } else {
                []
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
        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            guard let self, !contextIsCurrent else { return }
            invalidateForContextChange()
        }
        nc.publisher(&cancellables, for: .updateChatMember) { [weak self] update in
            guard let self, contextIsCurrent, update.chatId == source.chatID else { return }
            scheduleReload()
        }
        nc.publisher(&cancellables, for: .updateBasicGroupFullInfo) { [weak self] update in
            guard let self,
                  contextIsCurrent,
                  case .basicGroup(_, let groupID, _) = source,
                  update.basicGroupId == groupID
            else { return }
            basicGroupMembers = update.basicGroupFullInfo.members
            scheduleReload()
        }
        nc.publisher(&cancellables, for: .updateSupergroupFullInfo) { [weak self] update in
            guard let self,
                  contextIsCurrent,
                  case .supergroup(_, let groupID) = source,
                  update.supergroupId == groupID
            else { return }
            guard update.supergroupFullInfo.canGetMembers else {
                _ = navigationController?.popViewController(animated: true)
                return
            }
            scheduleReload()
        }
        loadMore()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func tableView(
        _: UITableView,
        willDisplay _: UITableViewCell,
        forRowAt indexPath: IndexPath,
    ) {
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

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<
            Section,
            MemberID,
        >(tableView: tableView) { [weak self] tableView, indexPath, id in
            guard let self, let row = rows[id] else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: "member", for: indexPath)
            var content = cell.defaultContentConfiguration()
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
            return cell
        }
    }

    private func loadMore() {
        guard loadTask == nil, hasMore, contextIsCurrent else { return }
        let generation = loadGeneration
        tableView.tableFooterView = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page: [Seed]
                let pageRawCount: Int
                let nextTotalCount: Int
                let nextHasMore: Bool
                switch source {
                case .administrators(let chatID):
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
                case .basicGroup(_, let id, _):
                    let members: [ChatMember]
                    if !basicGroupMembers.isEmpty {
                        members = basicGroupMembers
                    } else {
                        let info = try await client.getBasicGroupFullInfo(basicGroupId: id)
                        members = info.members
                    }
                    page = members.map(Self.seed(for:))
                    pageRawCount = members.count
                    nextTotalCount = members.count
                    nextHasMore = false
                case .supergroup(_, let id):
                    let result = try await client.getSupergroupMembers(
                        filter: nil,
                        limit: 100,
                        offset: rawOffset,
                        supergroupId: id,
                    )
                    page = result.members.map(Self.seed(for:))
                    pageRawCount = result.members.count
                    nextTotalCount = max(result.totalCount, rawOffset + pageRawCount)
                    nextHasMore = !result.members.isEmpty && rawOffset + pageRawCount < nextTotalCount
                }
                guard !Task.isCancelled,
                      contextIsCurrent,
                      loadGeneration == generation
                else { return }
                rawOffset += pageRawCount
                totalCount = nextTotalCount
                hasMore = nextHasMore
                append(page)
                loadTask = nil
                updateEmptyState()
            } catch {
                guard contextIsCurrent, loadGeneration == generation else { return }
                loadTask = nil
                showRetry(error.localizedDescription)
            }
        }
    }

    private func append(_ page: [Seed]) {
        var newSeeds = [Seed]()
        for seed in page {
            let id = seed.id
            if rows[id] == nil {
                orderedIDs.append(id)
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
                guard contextIsCurrent, loadGeneration == generation else { return }
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
                if !snapshotApplyPending {
                    restorePendingAnchor()
                }
                drainSnapshotApply()
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
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            resetAndReload()
        }
    }

    private func invalidateForContextChange() {
        loadTask?.cancel()
        resolutionTask?.cancel()
        reloadTask?.cancel()
        tagPreparationTask?.cancel()
        loadTask = nil
        resolutionTask = nil
        reloadTask = nil
        tagPreparationTask = nil
        tableView.isUserInteractionEnabled = false
    }

    private func presentTagError(_ error: Swift.Error) {
        guard presentedViewController == nil else { return }
        let message = (error as? LocalizedError)?.errorDescription
            ?? "This member's tag can't be edited right now."
        let alert = UIAlertController(title: "Can't Edit Tag", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func resetAndReload() {
        pendingAnchor = captureAnchor()
        loadGeneration &+= 1
        loadTask?.cancel()
        resolutionTask?.cancel()
        loadTask = nil
        resolutionTask = nil
        pendingResolutionIDs.removeAll()
        rows.removeAll()
        seeds.removeAll()
        orderedIDs.removeAll()
        rawOffset = 0
        totalCount = 0
        hasMore = true
        tableView.tableFooterView = nil
        tableView.backgroundView = nil
        applySnapshot()
        loadMore()
    }

    private func captureAnchor() -> TableAnchor? {
        guard let indexPath = tableView.indexPathsForVisibleRows?.sorted().first,
              let id = dataSource.itemIdentifier(for: indexPath)
        else { return nil }
        let rowFrame = tableView.rectForRow(at: indexPath)
        return TableAnchor(id: id, offset: rowFrame.minY - tableView.contentOffset.y)
    }

    private func restorePendingAnchor() {
        guard let anchor = pendingAnchor,
              let indexPath = dataSource.indexPath(for: anchor.id)
        else { return }
        tableView.layoutIfNeeded()
        let targetY = tableView.rectForRow(at: indexPath).minY - anchor.offset
        let minimumY = -tableView.adjustedContentInset.top
        let maximumY = max(
            minimumY,
            tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom,
        )
        tableView.setContentOffset(CGPoint(x: 0, y: min(maximumY, max(minimumY, targetY))), animated: false)
        pendingAnchor = nil
    }
}

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

// PeerProfileControlsViewControllers.swift

import Combine
import TDLibKitDynamic
import UIKit

// MARK: - Shared permission

func peerProfileCanChangeInfo(status: ChatMemberStatus?) -> Bool {
    switch status {
    case .chatMemberStatusCreator:
        true
    case .chatMemberStatusAdministrator(let administrator):
        administrator.rights.canChangeInfo
    case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember,
         .chatMemberStatusRestricted, nil:
        false
    }
}

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

    init(accountID: UUID, client: TDLibClient, source: Source, title: String) {
        self.accountID = accountID
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
            cell.selectionStyle = .none
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = row.accessibilityLabel
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
        loadTask = nil
        resolutionTask = nil
        reloadTask = nil
        tableView.isUserInteractionEnabled = false
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

// MARK: - PeerProfileEditViewController

@MainActor final class PeerProfileEditViewController: UIViewController, UITextFieldDelegate {
    enum Mode {
        case selfProfile(userID: Int64, firstName: String, lastName: String, bio: String)
        case chat(
            chatID: Int64,
            title: String,
            description: String,
        )
    }

    private let accountID: UUID
    private let accountUserID: Int64?
    private let client: TDLibClient
    private let mode: Mode
    private var persistedDetail: String
    private var persistedFirst: String
    private var persistedSecond: String
    private let stack = UIStackView()
    private let firstField = UITextField()
    private let secondField = UITextField()
    private let detailView = UITextView()
    private let errorLabel = UILabel()
    private var saveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var contextIsCurrent: Bool {
        TDLib.shared.activeAccountID == accountID && TDLib.shared.activeClient.id == client.id
    }

    init(accountID: UUID, accountUserID: Int64?, client: TDLibClient, mode: Mode) {
        self.accountID = accountID
        self.accountUserID = accountUserID
        self.client = client
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

    deinit { saveTask?.cancel() }

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
        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            guard let self, !contextIsCurrent else { return }
            saveTask?.cancel()
            saveTask = nil
            view.isUserInteractionEnabled = false
            navigationItem.rightBarButtonItem?.isEnabled = false
        }
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
            stack.addArrangedSubview(field)
        }
        detailView.font = .preferredFont(forTextStyle: .body)
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

    @objc private func save() {
        guard saveTask == nil, contextIsCurrent else { return }
        let first = firstField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let second = secondField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = detailView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else {
            showError(secondField.isHidden ? "Chat title is required." : "First name is required.")
            return
        }
        navigationItem.rightBarButtonItem?.isEnabled = false
        errorLabel.isHidden = true
        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await performSave(first: first, second: second, detail: detail)
                guard contextIsCurrent else { return }
                saveTask = nil
                navigationItem.rightBarButtonItem?.isEnabled = true
                _ = navigationController?.popViewController(animated: true)
            } catch {
                guard contextIsCurrent else { return }
                saveTask = nil
                navigationItem.rightBarButtonItem?.isEnabled = true
                showError(error.localizedDescription)
            }
        }
    }

    private func performSave(first: String, second: String, detail: String) async throws -> Bool {
        switch mode {
        case .selfProfile(let userID, _, _, _):
            guard userID == accountUserID,
                  TDLib.shared.activeAccount?.userID == accountUserID,
                  contextIsCurrent
            else { throw PeerProfileEditError.permissionChanged }
            var changed = false
            if first != persistedFirst || second != persistedSecond {
                _ = try await client.setName(firstName: first, lastName: second)
                persistedFirst = first
                persistedSecond = second
                changed = true
            }
            guard TDLib.shared.activeAccount?.userID == accountUserID,
                  contextIsCurrent
            else { throw PeerProfileEditError.permissionChanged }
            let normalizedBio = detail.replacingOccurrences(of: "\n", with: " ")
            if normalizedBio != persistedDetail {
                do {
                    _ = try await client.setBio(bio: normalizedBio)
                    persistedDetail = normalizedBio
                    changed = true
                } catch where changed {
                    throw PeerProfileEditError
                        .partialSuccess("Name was saved, but bio failed: \(error.localizedDescription)")
                }
            }
            return changed
        case .chat(let chatID, _, _):
            guard let accountUserID,
                  TDLib.shared.activeAccount?.userID == accountUserID,
                  contextIsCurrent
            else { throw PeerProfileEditError.permissionChanged }
            let member = try await client.getChatMember(
                chatId: chatID,
                memberId: .messageSenderUser(.init(userId: accountUserID)),
            )
            guard TDLib.shared.activeAccount?.userID == accountUserID,
                  contextIsCurrent,
                  peerProfileCanChangeInfo(status: member.status)
            else {
                throw PeerProfileEditError.permissionChanged
            }
            var changed = false
            if first != persistedFirst {
                _ = try await client.setChatTitle(chatId: chatID, title: first)
                persistedFirst = first
                changed = true
            }
            guard TDLib.shared.activeAccount?.userID == accountUserID,
                  contextIsCurrent
            else { throw PeerProfileEditError.permissionChanged }
            if detail != persistedDetail {
                do {
                    _ = try await client.setChatDescription(chatId: chatID, description: detail)
                    persistedDetail = detail
                    changed = true
                } catch where changed {
                    throw PeerProfileEditError
                        .partialSuccess("Title was saved, but description failed: \(error.localizedDescription)")
                }
            }
            return changed
        }
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

// MARK: - PeerProfileEditError

private enum PeerProfileEditError: LocalizedError {
    case partialSuccess(String)
    case permissionChanged

    var errorDescription: String? {
        switch self {
        case .partialSuccess(let message): message
        case .permissionChanged: "Your permission to edit this profile has changed."
        }
    }
}

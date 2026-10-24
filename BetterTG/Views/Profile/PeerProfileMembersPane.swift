// PeerProfileMembersPane.swift

import Combine
import TDLibKit
import UIKit

// MARK: - PeerProfileMemberRights

/// PeerInfoData.availableActionsForMemberOfPeer: the owner reaches everyone but itself; an admin reaches members with
/// the right to restrict or promote, and the admins they promoted themselves (TDLib's canBeEdited). A basic group
/// offers only Remove.
enum PeerProfileMemberRights {
    static func management(
        actor: ChatMemberStatus,
        target: ChatMemberStatus,
        isSupergroup: Bool,
    ) -> (canPromote: Bool, canRestrict: Bool) {
        if case .chatMemberStatusCreator = target { return (false, false) }
        switch actor {
        case .chatMemberStatusCreator:
            return (isSupergroup, true)
        case .chatMemberStatusAdministrator(let actor):
            if case .chatMemberStatusAdministrator(let target) = target {
                return (
                    isSupergroup && target.canBeEdited && actor.rights.canPromoteMembers,
                    isSupergroup && target.canBeEdited,
                )
            }
            return (isSupergroup && actor.rights.canPromoteMembers, actor.rights.canRestrictMembers)
        case .chatMemberStatusBanned,
             .chatMemberStatusLeft,
             .chatMemberStatusMember,
             .chatMemberStatusRestricted:
            return (false, false)
        }
    }
}

// MARK: - PeerProfileMembersPane

/// Telegram's Members pane (PeerInfoMembersPaneNode over PeerInfoMembersContext): a group with more than five members
/// lists them under its profile, Add Member first for whoever may invite people. Up to 50 members sort by presence
/// with the account on top; a longer list keeps TDLib's recent order and pages on.
@MainActor final class PeerProfileMembersPane {
    enum Group: Equatable {
        case basic(Int64)
        case supergroup(Int64)
    }

    enum LabelStyle {
        case plain
        case accent
        case owner
        case admin
    }

    struct Row {
        let id: PeerProfileMemberID
        let member: ChatMember
        let title: String
        let status: String
        let statusIsActive: Bool
        let label: String?
        let labelStyle: LabelStyle
        let file: File?
        let minithumbnail: Minithumbnail?
        let placeholder: TelegramAvatarPlaceholder
        let presenceRank: (Int, Int)?
        let canEditOwnTag: Bool
    }

    private struct Context {
        var chatType: ChatType
        var permissions: ChatPermissions
        var actor: ChatMemberStatus
    }

    /// The Add Member row; members use their user ID (positive) or chat ID (negative).
    static let addMemberItem = Int64.min
    /// PeerInfoData's long list: more members than this get the pane.
    static let threshold = 5

    private static let pageSize = 200
    private static let presenceSortLimit = 50

    let chatID: Int64
    let group: Group
    weak var host: UIViewController?
    var onChange: (() -> Void)?

    private(set) var rows = [Int64: Row]()
    private(set) var hasMore = true
    private(set) var error: String?

    private let accountID: UUID
    private let accountUserID: Int64?
    private let client: TDLibClient
    private let source: TdUpdateSource
    private let isCurrent: () -> Bool
    private var order = [Int64]()
    private var context: Context?
    private var offset = 0
    private var loadTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var generation = UInt64.zero
    private var cancellables = Set<AnyCancellable>()

    var isLoading: Bool { loadTask != nil }

    var items: [Int64] {
        (canAddMembers ? [Self.addMemberItem] : []) + order
    }

    private var isSupergroup: Bool {
        if case .supergroup = group { return true }
        return false
    }

    /// PeerInfoMembersContext.canAddMembers: the owner and admins with the right; in a group also anyone the
    /// permissions let invite.
    private var canAddMembers: Bool {
        guard let context else { return false }
        switch context.actor {
        case .chatMemberStatusCreator:
            return true
        case .chatMemberStatusAdministrator(let administrator):
            return administrator.rights.canInviteUsers
        case .chatMemberStatusMember:
            return context.permissions.canInviteUsers
        case .chatMemberStatusRestricted(let restricted):
            return restricted.isMember && restricted.permissions.canInviteUsers && context.permissions.canInviteUsers
        case .chatMemberStatusBanned,
             .chatMemberStatusLeft:
            return false
        }
    }

    init(
        chatID: Int64,
        group: Group,
        accountID: UUID,
        accountUserID: Int64?,
        client: TDLibClient,
        isCurrent: @escaping () -> Bool,
    ) {
        self.chatID = chatID
        self.group = group
        self.accountID = accountID
        self.accountUserID = accountUserID
        self.client = client
        self.source = TdUpdateSource(accountID: accountID, clientID: client.id)
        self.isCurrent = isCurrent
        nc.scopedPublisher(&cancellables, for: .updateChatMember) { [weak self] event in
            guard let self, event.source == source, event.value.chatId == chatID else { return }
            scheduleReload()
        }
        nc.scopedPublisher(&cancellables, for: .updateBasicGroupFullInfo) { [weak self] event in
            guard let self, event.source == source, group == .basic(event.value.basicGroupId) else { return }
            scheduleReload()
        }
        nc.scopedPublisher(&cancellables, for: .updateChatPermissions) { [weak self] event in
            guard let self, event.source == source, event.value.chatId == chatID else { return }
            context?.permissions = event.value.permissions
            onChange?()
        }
    }

    deinit {
        loadTask?.cancel()
        reloadTask?.cancel()
        actionTask?.cancel()
    }

    // MARK: Reads

    private static func item(_ id: PeerProfileMemberID) -> Int64 {
        switch id {
        case .user(let userID): userID
        case .chat(let chatID): chatID
        }
    }

    private static func loadContext(chatID: Int64, group: Group, client: TDLibClient) async throws -> Context {
        let chat = try await client.getChat(chatId: chatID)
        let actor: ChatMemberStatus =
            switch group {
            case .basic(let id): try await client.getBasicGroup(basicGroupId: id).status
            case .supergroup(let id): try await client.getSupergroup(supergroupId: id).status
            }
        return Context(chatType: chat.type, permissions: chat.permissions, actor: actor)
    }

    private static func loadPage(
        group: Group,
        offset: Int,
        client: TDLibClient,
    ) async throws -> (members: [ChatMember], hasMore: Bool) {
        switch group {
        case .basic(let id):
            return try await (client.getBasicGroupFullInfo(basicGroupId: id).members, false)
        case .supergroup(let id):
            let page = try await client.getSupergroupMembers(
                filter: nil, limit: pageSize, offset: offset, supergroupId: id,
            )
            return (page.members, offset + page.members.count < page.totalCount)
        }
    }

    private static func row(
        for member: ChatMember,
        accountUserID: Int64?,
        context: Context,
        client: TDLibClient,
    ) async -> Row {
        let id = PeerProfileMemberID(member.memberId)
        let isSelf = accountUserID.map { id == .user($0) } ?? false
        var canEditOwnTag = false
        if isSelf, let accountUserID {
            canEditOwnTag = (try? PeerProfileMemberTagAuthority.check(
                chatType: context.chatType,
                permissions: context.permissions,
                actorStatus: context.actor,
                targetStatus: member.status,
                actorID: accountUserID,
                targetID: accountUserID,
            )) != nil
        }
        let (label, labelStyle) = label(for: member, canEditOwnTag: canEditOwnTag)
        switch id {
        case .user(let userID):
            guard let user = try? await client.getUser(userId: userID) else {
                return Row(
                    id: id, member: member, title: L10n.telegram("User.DeletedAccount"), status: "",
                    statusIsActive: false, label: label, labelStyle: labelStyle, file: nil, minithumbnail: nil,
                    placeholder: TelegramAvatarPlaceholder(
                        peerID: userID, accentColorID: 0, upgradedGiftColors: nil, letters: [], isDeleted: true,
                    ),
                    presenceRank: nil, canEditOwnTag: canEditOwnTag,
                )
            }
            let status: (text: String, isOnline: Bool) =
                if isSelf {
                    (L10n.telegram("Presence.online"), true)
                } else if case .userTypeBot(let bot) = user.type {
                    // ContactsPeerItem's bot status in a member list.
                    (L10n.telegram(
                        bot.canReadAllGroupMessages
                            ? "Bot.GroupStatusReadsHistory"
                            : "Bot.GroupStatusDoesNotReadHistory",
                    ), false)
                } else {
                    UserPresenceText.text(for: user.status)
                }
            return Row(
                id: id, member: member, title: ServiceMessageText.displayTitle(user), status: status.text,
                statusIsActive: status.isOnline, label: label, labelStyle: labelStyle,
                file: user.profilePhoto?.small, minithumbnail: user.profilePhoto?.minithumbnail,
                placeholder: user.telegramAvatarPlaceholder,
                presenceRank: isSelf ? (Int.max, 0) : UserPresenceText.rank(user.status),
                canEditOwnTag: canEditOwnTag,
            )
        case .chat(let chatID):
            let chat = try? await client.getChat(chatId: chatID)
            let title = chat?.title ?? L10n.betterTG("Chat.FallbackChatTitle")
            return Row(
                id: id, member: member, title: title, status: "", statusIsActive: false, label: label,
                labelStyle: labelStyle, file: chat?.photo?.small, minithumbnail: chat?.photo?.minithumbnail,
                placeholder: TelegramAvatarPlaceholder(
                    peerID: chatID,
                    accentColorID: chat?.accentColorId ?? 0,
                    upgradedGiftColors: chat?.upgradedGiftColors,
                    letters: title.telegramAvatarFirstLetter.map { [$0] } ?? [],
                    isDeleted: false,
                ),
                presenceRank: nil, canEditOwnTag: false,
            )
        }
    }

    /// PeerMembersListEntry's label: the tag, else owner or admin; owners and admins get a tinted pill, and the
    /// account's own row offers Add Tag in the accent color.
    private static func label(for member: ChatMember, canEditOwnTag: Bool) -> (String?, LabelStyle) {
        switch member.status {
        case .chatMemberStatusCreator:
            (member.tag.isEmpty ? L10n.telegram("GroupInfo.LabelOwner") : member.tag, .owner)
        case .chatMemberStatusAdministrator:
            (member.tag.isEmpty ? L10n.telegram("GroupInfo.LabelAdmin") : member.tag, .admin)
        case .chatMemberStatusBanned,
             .chatMemberStatusLeft,
             .chatMemberStatusMember,
             .chatMemberStatusRestricted:
            if !member.tag.isEmpty {
                (member.tag, .plain)
            } else if canEditOwnTag {
                (L10n.telegram("GroupInfo.AddRank"), .accent)
            } else {
                (nil, .plain)
            }
        }
    }

    func row(for item: Int64) -> Row? {
        rows[item]
    }

    /// Stops reading for a client that is no longer ready; the rows stay until the pane reads again.
    func suspend() {
        generation &+= 1
        loadTask?.cancel()
        loadTask = nil
        reloadTask?.cancel()
        reloadTask = nil
    }

    func loadMore() {
        guard loadTask == nil, hasMore, isCurrent() else { return }
        read(from: offset, replacing: false)
    }

    func retry() {
        error = nil
        loadMore()
    }

    /// A member's profile (PeerInfoScreenOpenMember); the account's own row edits its tag when it may, as Telegram's
    /// Add Tag label does. Add Member opens the contact picker.
    func open(_ item: Int64) {
        guard isCurrent() else { return }
        if item == Self.addMemberItem {
            guard canAddMembers else { return }
            host?.navigationController?.pushViewController(
                ComposeContactPickerViewController(mode: .addMembers(chatID: chatID, isBasicGroup: !isSupergroup)),
                animated: true,
            )
            return
        }
        guard let row = rows[item] else { return }
        if case .user(let userID) = row.id, userID == accountUserID {
            if row.canEditOwnTag { openTagEditor(row) }
            return
        }
        openChat(of: row.id) { [weak self] chat in
            guard let self, let navigation = host?.navigationController else { return }
            let profile = PeerProfileViewController(customChat: chat, topic: nil, client: client, accountID: accountID)
            profile.configureOpensChatItself()
            navigation.pushViewController(profile, animated: true)
        }
    }

    /// PeerInfoScreenNode.openMemberContextMenu: Send Message, the tag, Promote and Restrict in a supergroup, Remove.
    func menuActions(for item: Int64) -> [TelegramContextMenuAction] {
        guard let row = rows[item], let accountUserID, let context else { return [] }
        let isSelf = row.id == .user(accountUserID)
        var actions = [TelegramContextMenuAction]()
        if !isSelf {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("GroupInfo.ActionSend"),
                image: UIImage(systemName: "bubble.left"),
            ) { [weak self] in
                self?.openChat(of: row.id) { NavigationStorage.shared.push(.customChat($0)) }
            })
        }
        if let title = tagActionTitle(row, context: context, accountUserID: accountUserID) {
            actions.append(TelegramContextMenuAction(title: title, image: UIImage(systemName: "tag")) { [weak self] in
                self?.openTagEditor(row)
            })
        }
        guard !isSelf else { return actions }
        let rights = PeerProfileMemberRights.management(
            actor: context.actor, target: row.member.status, isSupergroup: isSupergroup,
        )
        let isAdministrator =
            if case .chatMemberStatusAdministrator = row.member.status {
                true
            } else {
                false
            }
        if rights.canPromote, case .user = row.id {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram(isAdministrator ? "GroupInfo.ActionEditAdmin" : "GroupInfo.ActionPromote"),
                image: UIImage(systemName: "star"),
            ) { [weak self] in
                self?.openManagement(row) { target, member in
                    ChatAdminRightsViewController(target: target, member: member, isNew: !isAdministrator)
                }
            })
        }
        guard rights.canRestrict else { return actions }
        if isSupergroup {
            actions.append(TelegramContextMenuAction(
                title: L10n.telegram("GroupInfo.ActionRestrict"),
                image: UIImage(systemName: "hand.raised"),
            ) { [weak self] in
                self?.openManagement(row) { target, member in
                    let isRestricted =
                        if case .chatMemberStatusRestricted = member.status {
                            true
                        } else {
                            false
                        }
                    return ChatMemberRestrictionViewController(target: target, member: member, isNew: !isRestricted)
                }
            })
        }
        actions.append(TelegramContextMenuAction(
            title: L10n.telegram("GroupInfo.ActionRemove"),
            image: UIImage(systemName: "person.badge.minus"),
            isDestructive: true,
        ) { [weak self] in self?.remove(row) })
        return actions
    }

    private func scheduleReload() {
        guard isCurrent() else { return }
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            reloadTask = nil
            suspend()
            read(from: 0, replacing: true)
        }
    }

    private func read(from pageOffset: Int, replacing: Bool) {
        let generation = generation
        let client = client
        let chatID = chatID
        let group = group
        let accountUserID = accountUserID
        let knownContext = replacing ? nil : context
        error = nil
        loadTask = Task { [weak self] in
            do {
                let context =
                    if let knownContext {
                        knownContext
                    } else {
                        try await Self.loadContext(chatID: chatID, group: group, client: client)
                    }
                let page = try await Self.loadPage(group: group, offset: pageOffset, client: client)
                var loaded = [Row]()
                for member in page.members {
                    guard !Task.isCancelled else { return }
                    await loaded.append(Self.row(
                        for: member,
                        accountUserID: accountUserID,
                        context: context,
                        client: client,
                    ))
                }
                guard let self, !Task.isCancelled, self.generation == generation, isCurrent() else { return }
                loadTask = nil
                self.context = context
                if replacing {
                    rows = [:]
                    order = []
                }
                for row in loaded {
                    let item = Self.item(row.id)
                    if rows[item] == nil { order.append(item) }
                    rows[item] = row
                }
                offset = pageOffset + page.members.count
                hasMore = page.hasMore && !page.members.isEmpty
                if order.count <= Self.presenceSortLimit { sortByPresence() }
                onChange?()
            } catch {
                guard let self, !Task.isCancelled, self.generation == generation, isCurrent() else { return }
                loadTask = nil
                self.error = L10n.betterTG("Profile.SharedMembersLoadFailed")
                onChange?()
            }
        }
    }

    /// PeerInfoMembers.membersSortedByPresence: the account first, then the latest presence, then the rest by ID.
    private func sortByPresence() {
        let accountItem = accountUserID
        order.sort { lhs, rhs in
            if lhs == accountItem { return true }
            if rhs == accountItem { return false }
            let left = rows[lhs]?.presenceRank
            let right = rows[rhs]?.presenceRank
            switch (left, right) {
            case (let left?, let right?):
                if left != right { return left > right }
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                break
            }
            return lhs < rhs
        }
    }

    private func tagActionTitle(_ row: Row, context: Context, accountUserID: Int64) -> String? {
        guard case .user(let targetID) = row.id else { return nil }
        do {
            try PeerProfileMemberTagAuthority.check(
                chatType: context.chatType,
                permissions: context.permissions,
                actorStatus: context.actor,
                targetStatus: row.member.status,
                actorID: accountUserID,
                targetID: targetID,
            )
        } catch {
            return nil
        }
        switch row.member.status {
        case .chatMemberStatusAdministrator,
             .chatMemberStatusCreator:
            return L10n.telegram("GroupInfo.ActionEditAdminRank")
        case .chatMemberStatusBanned,
             .chatMemberStatusLeft,
             .chatMemberStatusMember,
             .chatMemberStatusRestricted:
            return row.member.tag.isEmpty
                ? L10n.telegram("GroupInfo.ActionAddRank")
                : L10n.telegram("GroupInfo.ActionEditRank")
        }
    }

    private func openChat(of id: PeerProfileMemberID, open: @escaping (CustomChat) -> Void) {
        guard actionTask == nil, isCurrent() else { return }
        let client = client
        actionTask = Task { [weak self] in
            let chatID: Int64? =
                switch id {
                case .user(let userID): try? await client.createPrivateChat(force: false, userId: userID).id
                case .chat(let chatID): chatID
                }
            var chat: CustomChat?
            if let chatID, self?.isCurrent() == true {
                chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client)
            }
            guard let self else { return }
            actionTask = nil
            guard !Task.isCancelled, let chat, isCurrent() else { return }
            open(chat)
        }
    }

    private func openTagEditor(_ row: Row) {
        guard actionTask == nil, isCurrent(), let accountUserID, case .user(let targetUserID) = row.id else { return }
        let client = client
        let accountID = accountID
        let chatID = chatID
        actionTask = Task { [weak self] in
            do {
                let authority = try await PeerProfileMemberTagAuthority.resolve(
                    accountID: accountID,
                    accountUserID: accountUserID,
                    chatID: chatID,
                    targetUserID: targetUserID,
                    client: client,
                )
                guard let self else { return }
                actionTask = nil
                guard !Task.isCancelled, isCurrent() else { return }
                let editor = PeerProfileMemberTagViewController(
                    accountID: accountID,
                    accountUserID: accountUserID,
                    chatID: chatID,
                    initialAuthority: authority,
                    targetTitle: row.title,
                    targetUserID: targetUserID,
                )
                editor.onSaved = { [weak self] in self?.scheduleReload() }
                host?.navigationController?.pushViewController(editor, animated: true)
            } catch {
                guard let self else { return }
                actionTask = nil
                guard !Task.isCancelled, isCurrent() else { return }
                host?.presentChatListActionFailure()
            }
        }
    }

    /// Reads the chat as the management screens use it, then pushes the member's screen.
    private func openManagement(
        _ row: Row,
        screen: @escaping (ChatManagementTarget, ChatManagementMember) -> UIViewController,
    ) {
        guard actionTask == nil, isCurrent() else { return }
        let client = client
        let chatID = chatID
        let sender = row.id.sender
        actionTask = Task { [weak self] in
            let target = await ChatManagementTarget.load(chatID: chatID, client: client)
            let peer = await SettingsPeer.resolve(sender, client: client)
            guard let self else { return }
            actionTask = nil
            guard !Task.isCancelled, isCurrent(), let target, let peer else { return }
            let member = ChatManagementMember(
                sender: sender,
                peer: peer,
                status: row.member.status,
                tag: row.member.tag,
            )
            host?.navigationController?.pushViewController(screen(target, member), animated: true)
        }
    }

    /// PeerInfoScreen's .remove: the member leaves and, in a supergroup, joins Removed Users (banChatMember).
    private func remove(_ row: Row) {
        guard isCurrent() else { return }
        let client = client
        let chatID = chatID
        let sender = row.id.sender
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.banChatMember(
                    chatId: chatID, memberId: sender, bannedUntilDate: 0, revokeMessages: false,
                ))
                self?.scheduleReload()
            } catch {
                guard let self, isCurrent() else { return }
                host?.presentChatListActionFailure()
            }
        }
    }
}

// MARK: - SharedMemberRowCell

/// A member in the Members pane, after Telegram's ContactsPeerItem in its member list mode: the avatar, the name, the
/// presence (online in the accent color) and the role on the right.
final class SharedMemberRowCell: UICollectionViewCell {
    static let reuseIdentifier = "SharedMemberRowCell"

    private let avatarView = ProfileAvatarView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let roleLabel = UILabel()
    private let rolePill = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        iconView.tintColor = .tintColor
        contentView.addSubview(iconView)
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.spacing = 2
        contentView.addSubview(labels)
        rolePill.translatesAutoresizingMaskIntoConstraints = false
        rolePill.layer.cornerRadius = 10
        rolePill.layer.cornerCurve = .continuous
        contentView.addSubview(rolePill)
        roleLabel.translatesAutoresizingMaskIntoConstraints = false
        roleLabel.font = .systemFont(ofSize: 14)
        roleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        roleLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentView.addSubview(roleLabel)
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            iconView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            labels.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: roleLabel.leadingAnchor, constant: -12),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
            roleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            roleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            rolePill.leadingAnchor.constraint(equalTo: roleLabel.leadingAnchor, constant: -6),
            rolePill.trailingAnchor.constraint(equalTo: roleLabel.trailingAnchor, constant: 6),
            rolePill.centerYAnchor.constraint(equalTo: roleLabel.centerYAnchor),
            rolePill.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    /// PeerMembersListEntry.addMember: ItemListPeerActionItem with the add person icon in the accent color.
    func configureAddMember() {
        avatarView.isHidden = true
        iconView.isHidden = false
        iconView.image = UIImage(systemName: "person.badge.plus")
        titleLabel.text = L10n.telegram("GroupInfo.AddParticipant")
        titleLabel.textColor = .tintColor
        subtitleLabel.isHidden = true
        roleLabel.isHidden = true
        rolePill.isHidden = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = titleLabel.text
    }

    func configure(row: PeerProfileMembersPane.Row, accountID: UUID, client: TDLibClient) {
        avatarView.isHidden = false
        iconView.isHidden = true
        titleLabel.text = row.title
        titleLabel.textColor = .label
        subtitleLabel.text = row.status
        subtitleLabel.isHidden = row.status.isEmpty
        subtitleLabel.textColor = row.statusIsActive ? .tintColor : .secondaryLabel
        avatarView.configure(
            file: row.file,
            minithumbnail: row.minithumbnail,
            placeholder: row.placeholder,
            accountID: accountID,
            client: client,
        )
        roleLabel.text = row.label
        roleLabel.isHidden = row.label == nil
        let color: UIColor? =
            switch row.labelStyle {
            case .owner: UIColor(red: 0x95 / 255, green: 0x6A / 255, blue: 0xC8 / 255, alpha: 1)
            case .admin: UIColor(red: 0x49 / 255, green: 0xA3 / 255, blue: 0x55 / 255, alpha: 1)
            case .accent: .tintColor
            case .plain: nil
            }
        roleLabel.textColor = color ?? .secondaryLabel
        let hasPill = row.label != nil && (row.labelStyle == .owner || row.labelStyle == .admin)
        rolePill.isHidden = !hasPill
        rolePill.backgroundColor = color?.withAlphaComponent(0.1)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [row.title, row.label, row.status.isEmpty ? nil : row.status]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}

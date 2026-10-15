// ChatManagement.swift

import TDLibKit
import UIKit

// MARK: - ChatManagementTarget

/// The group or channel Telegram's management screens act on, read from TDLib now, and what the account may do there.
/// Telegram decides by the channel's isCreator flag and adminRights (PeerInfoProfileItems, ChannelAdminController);
/// the owner holds every right.
struct ChatManagementTarget {
    enum Group: Equatable {
        case basic(Int64)
        case supergroup(Int64)
    }

    let chat: Chat
    let group: Group
    let isChannel: Bool
    let isForum: Bool
    let status: ChatMemberStatus
    let supergroup: Supergroup?
    let supergroupInfo: SupergroupFullInfo?
    let basicGroupInfo: BasicGroupFullInfo?

    var chatID: Int64 {
        chat.id
    }

    var supergroupID: Int64? {
        if case .supergroup(let id) = group {
            id
        } else {
            nil
        }
    }

    var isCreator: Bool {
        if case .chatMemberStatusCreator = status {
            true
        } else {
            false
        }
    }

    /// The account's administrator rights; nil for a member.
    var rights: AdminRightsSet? {
        switch status {
        case .chatMemberStatusCreator(let creator): AdminRightsSet.all(isAnonymous: creator.isAnonymous)
        case .chatMemberStatusAdministrator(let administrator): AdminRightsSet(administrator.rights)
        default: nil
        }
    }

    var isPublic: Bool {
        supergroup?.usernames?.activeUsernames.isEmpty == false
    }

    var inviteLink: String? {
        supergroupInfo?.inviteLink?.inviteLink ?? basicGroupInfo?.inviteLink?.inviteLink
    }

    @MainActor static func load(chatID: Int64, client: TDLibClient) async -> ChatManagementTarget? {
        guard let chat = try? await client.getChat(chatId: chatID) else { return nil }
        switch chat.type {
        case .chatTypeBasicGroup(let value):
            guard let group = try? await client.getBasicGroup(basicGroupId: value.basicGroupId) else { return nil }
            let info = try? await client.getBasicGroupFullInfo(basicGroupId: value.basicGroupId)
            return ChatManagementTarget(
                chat: chat, group: .basic(group.id), isChannel: false, isForum: false, status: group.status,
                supergroup: nil, supergroupInfo: nil, basicGroupInfo: info,
            )
        case .chatTypeSupergroup(let value):
            guard let group = try? await client.getSupergroup(supergroupId: value.supergroupId) else { return nil }
            let info = try? await client.getSupergroupFullInfo(supergroupId: value.supergroupId)
            return ChatManagementTarget(
                chat: chat, group: .supergroup(group.id), isChannel: group.isChannel, isForum: group.isForum,
                status: group.status, supergroup: group, supergroupInfo: info, basicGroupInfo: nil,
            )
        case .chatTypePrivate, .chatTypeSecret:
            return nil
        }
    }
}

// MARK: - PermissionSet

/// A ChatPermissions value to edit, a field at a time.
struct PermissionSet: Equatable {
    var canSendBasicMessages: Bool
    var canSendAudios: Bool
    var canSendDocuments: Bool
    var canSendPhotos: Bool
    var canSendVideos: Bool
    var canSendVideoNotes: Bool
    var canSendVoiceNotes: Bool
    var canSendPolls: Bool
    var canSendOtherMessages: Bool
    var canAddLinkPreviews: Bool
    var canReactToMessages: Bool
    var canEditTag: Bool
    var canChangeInfo: Bool
    var canInviteUsers: Bool
    var canPinMessages: Bool
    var canCreateTopics: Bool

    var native: ChatPermissions {
        TDNativeChatPermissions(
            canSendBasicMessages: canSendBasicMessages,
            canSendAudios: canSendAudios,
            canSendDocuments: canSendDocuments,
            canSendPhotos: canSendPhotos,
            canSendVideos: canSendVideos,
            canSendVideoNotes: canSendVideoNotes,
            canSendVoiceNotes: canSendVoiceNotes,
            canSendPolls: canSendPolls,
            canSendOtherMessages: canSendOtherMessages,
            canAddLinkPreviews: canAddLinkPreviews,
            canReactToMessages: canReactToMessages,
            canEditTag: canEditTag,
            canChangeInfo: canChangeInfo,
            canInviteUsers: canInviteUsers,
            canPinMessages: canPinMessages,
            canCreateTopics: canCreateTopics,
        )
    }

    init(_ permissions: ChatPermissions) {
        self.canSendBasicMessages = permissions.canSendBasicMessages
        self.canSendAudios = permissions.canSendAudios
        self.canSendDocuments = permissions.canSendDocuments
        self.canSendPhotos = permissions.canSendPhotos
        self.canSendVideos = permissions.canSendVideos
        self.canSendVideoNotes = permissions.canSendVideoNotes
        self.canSendVoiceNotes = permissions.canSendVoiceNotes
        self.canSendPolls = permissions.canSendPolls
        self.canSendOtherMessages = permissions.canSendOtherMessages
        self.canAddLinkPreviews = permissions.canAddLinkPreviews
        self.canReactToMessages = permissions.canReactToMessages
        self.canEditTag = permissions.canEditTag
        self.canChangeInfo = permissions.canChangeInfo
        self.canInviteUsers = permissions.canInviteUsers
        self.canPinMessages = permissions.canPinMessages
        self.canCreateTopics = permissions.canCreateTopics
    }

    /// Telegram's allGroupPermissionList with the media expanded: the toggles, their titles and the compact
    /// "no …" labels of an exception's row. `isDefault` names the member tag permission for everyone.
    static func items(isForum: Bool, isDefault: Bool) -> [(
        title: String,
        short: String,
        key: WritableKeyPath<Self, Bool>,
    )] {
        var items: [(String, String, WritableKeyPath<Self, Bool>)] = [
            (
                L10n.telegram("Channel.BanUser.PermissionSendMessages"),
                L10n.telegram("GroupPermission.NoSendMessages"),
                \.canSendBasicMessages,
            ),
            (
                L10n.telegram("Channel.BanUser.PermissionSendPhoto"),
                L10n.telegram("GroupPermission.NoSendPhoto"),
                \.canSendPhotos,
            ),
            (
                L10n.telegram("Channel.BanUser.PermissionSendVideo"),
                L10n.telegram("GroupPermission.NoSendVideo"),
                \.canSendVideos,
            ),
            (
                L10n.telegram("Channel.BanUser.PermissionSendStickersAndGifs"),
                L10n.telegram("GroupPermission.NoSendGifs"),
                \.canSendOtherMessages,
            ),
            (
                L10n.telegram("Channel.BanUser.PermissionSendMusic"),
                L10n.telegram("GroupPermission.NoSendMusic"),
                \.canSendAudios,
            ),
            (
                L10n.telegram("Channel.BanUser.PermissionSendFile"),
                L10n.telegram("GroupPermission.NoSendFile"),
                \.canSendDocuments,
            ),
            (
                L10n.telegram("Channel.BanUser.PermissionSendVoiceMessage"),
                L10n.telegram("GroupPermission.NoSendVoiceMessage"),
                \.canSendVoiceNotes,
            ),
            (
                L10n.telegram("Channel.BanUser.PermissionSendVideoMessage"),
                L10n.telegram("GroupPermission.NoSendVideoMessage"),
                \.canSendVideoNotes,
            ),
            (
                L10n.telegram("Channel.BanUser.PermissionEmbedLinks"),
                L10n.telegram("GroupPermission.NoSendLinks"),
                \.canAddLinkPreviews,
            ),
            (
                L10n.telegram("Channel.BanUser.PermissionSendPolls"),
                L10n.telegram("GroupPermission.NoSendPolls"),
                \.canSendPolls,
            ),
            (
                L10n.telegram("Channel.BanUser.PermissionSendReactions"),
                L10n.telegram("GroupPermission.NoSendReactions"),
                \.canReactToMessages,
            ),
            (
                L10n.telegram("Channel.BanUser.PermissionAddMembers"),
                L10n.telegram("GroupPermission.NoAddMembers"),
                \.canInviteUsers,
            ),
            (
                L10n.telegram("Channel.EditAdmin.PermissionPinMessages"),
                L10n.telegram("GroupPermission.NoPinMessages"),
                \.canPinMessages,
            ),
            (
                L10n
                    .telegram(isDefault
                        ? "Channel.BanUser.PermissionEditOwnRank"
                        : "Channel.BanUser.PermissionEditRank"),
                L10n.telegram("GroupPermission.NoEditRank"),
                \.canEditTag,
            ),
        ]
        if isForum {
            items.append((
                L10n.telegram("Channel.EditAdmin.PermissionCreateTopics"),
                L10n.telegram("GroupPermission.NoManageTopics"),
                \.canCreateTopics,
            ))
        }
        items.append((
            L10n.telegram("Channel.BanUser.PermissionChangeGroupInfo"),
            L10n.telegram("GroupPermission.NoChangeInfo"),
            \.canChangeInfo,
        ))
        return items.map { (title: $0.0, short: $0.1, key: $0.2) }
    }
}

// MARK: - AdminRightsSet

/// A ChatAdministratorRights value to edit, a field at a time.
struct AdminRightsSet: Equatable {
    static var none: AdminRightsSet {
        AdminRightsSet(all: false, isAnonymous: false)
    }

    var canManageChat: Bool
    var canChangeInfo: Bool
    var canPostMessages: Bool
    var canEditMessages: Bool
    var canDeleteMessages: Bool
    var canInviteUsers: Bool
    var canRestrictMembers: Bool
    var canPinMessages: Bool
    var canManageTopics: Bool
    var canPromoteMembers: Bool
    var canManageVideoChats: Bool
    var canPostStories: Bool
    var canEditStories: Bool
    var canDeleteStories: Bool
    var canManageDirectMessages: Bool
    var canManageTags: Bool
    var canSendWelcomeMessages: Bool
    var isAnonymous: Bool

    var native: ChatAdministratorRights {
        TDNativeChatAdministratorRights(
            canManageChat: canManageChat,
            canChangeInfo: canChangeInfo,
            canPostMessages: canPostMessages,
            canEditMessages: canEditMessages,
            canDeleteMessages: canDeleteMessages,
            canInviteUsers: canInviteUsers,
            canRestrictMembers: canRestrictMembers,
            canPinMessages: canPinMessages,
            canManageTopics: canManageTopics,
            canPromoteMembers: canPromoteMembers,
            canManageVideoChats: canManageVideoChats,
            canPostStories: canPostStories,
            canEditStories: canEditStories,
            canDeleteStories: canDeleteStories,
            canManageDirectMessages: canManageDirectMessages,
            canManageTags: canManageTags,
            canSendWelcomeMessages: canSendWelcomeMessages,
            isAnonymous: isAnonymous,
        )
    }

    init(_ rights: ChatAdministratorRights) {
        self.canManageChat = rights.canManageChat
        self.canChangeInfo = rights.canChangeInfo
        self.canPostMessages = rights.canPostMessages
        self.canEditMessages = rights.canEditMessages
        self.canDeleteMessages = rights.canDeleteMessages
        self.canInviteUsers = rights.canInviteUsers
        self.canRestrictMembers = rights.canRestrictMembers
        self.canPinMessages = rights.canPinMessages
        self.canManageTopics = rights.canManageTopics
        self.canPromoteMembers = rights.canPromoteMembers
        self.canManageVideoChats = rights.canManageVideoChats
        self.canPostStories = rights.canPostStories
        self.canEditStories = rights.canEditStories
        self.canDeleteStories = rights.canDeleteStories
        self.canManageDirectMessages = rights.canManageDirectMessages
        self.canManageTags = rights.canManageTags
        self.canSendWelcomeMessages = rights.canSendWelcomeMessages
        self.isAnonymous = rights.isAnonymous
    }

    private init(all value: Bool, isAnonymous: Bool) {
        self.canManageChat = value
        self.canChangeInfo = value
        self.canPostMessages = value
        self.canEditMessages = value
        self.canDeleteMessages = value
        self.canInviteUsers = value
        self.canRestrictMembers = value
        self.canPinMessages = value
        self.canManageTopics = value
        self.canPromoteMembers = value
        self.canManageVideoChats = value
        self.canPostStories = value
        self.canEditStories = value
        self.canDeleteStories = value
        self.canManageDirectMessages = value
        self.canManageTags = value
        self.canSendWelcomeMessages = value
        self.isAnonymous = isAnonymous
    }

    static func all(isAnonymous: Bool = false) -> AdminRightsSet {
        AdminRightsSet(all: true, isAnonymous: isAnonymous)
    }
}

// MARK: - ChatManagementMember

/// A member row of the management lists: the person or chat, their status and Telegram's role label.
struct ChatManagementMember {
    let sender: MessageSender
    let peer: SettingsPeer
    let status: ChatMemberStatus
    let tag: String

    var userID: Int64? {
        if case .messageSenderUser(let user) = sender {
            user.userId
        } else {
            nil
        }
    }

    /// The members TDLib returned, with their names; members TDLib no longer knows are left out.
    @MainActor static func resolve(_ members: [ChatMember], client: TDLibClient) async -> [ChatManagementMember] {
        var result = [ChatManagementMember]()
        for member in members {
            guard !Task.isCancelled else { break }
            guard let peer = await SettingsPeer.resolve(member.memberId, client: client) else { continue }
            result.append(ChatManagementMember(
                sender: member.memberId, peer: peer, status: member.status, tag: member.tag,
            ))
        }
        return result
    }
}

extension MessageSender {
    static func user(_ userID: Int64) -> MessageSender {
        .messageSenderUser(TDNativeMessageSenderUser(userId: userID))
    }
}

// MARK: - ChatMemberPickerViewController

/// Telegram's ChannelMembersSearchController: the chat's members (recent first, or the basic group's list) with a
/// search (searchChatMembers). Tapping a member hands them back; the caller decides what follows.
final class ChatMemberPickerViewController: SettingsListViewController, UISearchResultsUpdating {
    private static let searchDelay = Duration.milliseconds(250)
    private static let pageLimit = 200

    var onPick: ((ChatManagementMember) -> Void)?

    private let target: ChatManagementTarget
    private let excludes: (ChatManagementMember) -> Bool
    private let searchController = UISearchController(searchResultsController: nil)
    private var members = [ChatManagementMember]()
    private var isLoading = true
    private var query = ""
    private var loadTask: Task<Void, Never>?

    /// `excludes` leaves out members the action doesn't apply to, such as the owner or existing admins.
    init(target: ChatManagementTarget, title: String, excludes: @escaping (ChatManagementMember) -> Bool) {
        self.target = target
        self.excludes = excludes
        super.init()
        self.title = title
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.telegram("Common.Search")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        load(query: "")
    }

    override func makeSections() -> [SettingsSection] {
        guard !members.isEmpty || !isLoading else {
            return [SettingsSection(rows: [ChatManagementRows.loading])]
        }
        guard !members.isEmpty else {
            return [SettingsSection(rows: [SettingsRow(
                title: L10n.telegram("Contacts.Search.NoResults"),
                style: .status(.secondaryLabel),
            )])]
        }
        return [SettingsSection(rows: members.map { member in
            SettingsRow(
                title: member.peer.title,
                detail: ChatManagementRows.role(member.status, tag: member.tag),
                style: .peer(member.peer),
            ) { [weak self] in self?.onPick?(member) }
        })]
    }

    func updateSearchResults(for searchController: UISearchController) {
        let text = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != query else { return }
        query = text
        load(query: text)
    }

    private func load(query: String) {
        loadTask?.cancel()
        guard contextIsCurrent else { return }
        isLoading = true
        reload()
        let client = client
        let target = target
        let excludes = excludes
        let waits = !query.isEmpty
        loadTask = Task { [weak self] in
            if waits { try? await Task.sleep(for: Self.searchDelay) }
            guard !Task.isCancelled else { return }
            let found: [ChatMember]
            switch target.group {
            case .supergroup(let id):
                let filter: TDNativeSupergroupMembersFilter = query.isEmpty
                    ? .supergroupMembersFilterRecent
                    : .supergroupMembersFilterSearch(TDNativeSupergroupMembersFilterSearch(query: query))
                found = await (try? client.send(TDNativeRequests.getSupergroupMembers(
                    supergroupId: id, filter: filter, offset: 0, limit: Self.pageLimit,
                )))?.members ?? []
            case .basic:
                found = await (try? client.send(TDNativeRequests.searchChatMembers(
                    chatId: target.chatID, query: query, limit: Self.pageLimit, filter: nil,
                )))?.members ?? []
            }
            let resolved = await ChatManagementMember.resolve(found, client: client).filter { !excludes($0) }
            guard let self, !Task.isCancelled, contextIsCurrent else { return }
            members = resolved
            isLoading = false
            reload()
        }
    }
}

// MARK: - ChatManagementRows

/// Rows and labels the management screens share.
@MainActor enum ChatManagementRows {
    static var loading: SettingsRow {
        SettingsRow(
            title: L10n.telegram("Channel.NotificationLoading"),
            style: .status(.secondaryLabel),
            accessory: .activity,
        )
    }

    /// Telegram's member list labels: Owner, Admin or the member's tag.
    static func role(_ status: ChatMemberStatus, tag: String) -> String? {
        switch status {
        case .chatMemberStatusCreator:
            tag.isEmpty ? L10n.telegram("Channel.Management.LabelOwner") : tag
        case .chatMemberStatusAdministrator:
            tag.isEmpty ? L10n.telegram("Channel.Management.LabelEditor") : tag
        default:
            tag.isEmpty ? nil : tag
        }
    }

    /// TDLib's failure, or Telegram's generic error text.
    static func failureText(_ error: Error) -> String {
        let message = (error as? TDLibError)?.message ?? ""
        if message.contains("CHAT_ADMIN_REQUIRED") || message.contains("RIGHT_FORBIDDEN") {
            return L10n.telegram("Common.ActionNotAllowedError")
        }
        if message.contains("USER_PRIVACY_RESTRICTED") {
            return L10n.telegram("Privacy.GroupsAndChannels.InviteToChannelMultipleError")
        }
        return L10n.telegram("Login.UnknownError")
    }
}

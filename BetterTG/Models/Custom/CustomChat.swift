// CustomChat.swift

import Combine
import TDLibKit

@MainActor final class CustomChat: ObservableObject {
    // MARK: Internal

    enum CustomChatType {
        case user(User)
        case supergroup(Supergroup)
        case group(BasicGroup)
        case bot(User)
    }

    @Published var chat: Chat
    @Published var type: CustomChatType
    @Published var position: ChatPosition
    @Published var unreadCount: Int
    @Published var lastMessage: Message?
    @Published var draftMessage: DraftMessage?
    /// A chat-list row kept through a same-account client renewal. Its files belong to the previous client, so the
    /// list loads none of them until the renewed client supplies the chat again.
    var isHeldThroughClientRenewal = false

    /// Read for every row on every pass over a list; `chat.id` goes through `@Published` and the native object.
    let id: Int64

    var displayTitle: String {
        if isSavedMessages { return L10n.telegram("Conversation.SavedMessages") }
        return chat.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.telegram("User.DeletedAccount")
            : chat.title
    }

    var isSavedMessages: Bool {
        guard let accountUserID = TDLib.shared.activeAccount?.userID else { return false }
        return user?.id == accountUserID
    }

    var bot: UserTypeBot? {
        guard case .bot(let user) = type, case .userTypeBot(let bot) = user.type else { return nil }
        return bot
    }

    var user: User? {
        switch type {
        case .bot(let user),
             .user(let user):
            user
        case .group,
             .supergroup:
            nil
        }
    }

    var supergroup: Supergroup? {
        if case .supergroup(let group) = type {
            return group
        }
        return nil
    }

    var group: BasicGroup? {
        if case .group(let group) = type {
            return group
        }
        return nil
    }

    var notificationSettingsScope: NotificationSettingsScope {
        switch type {
        case .bot,
             .user:
            .notificationSettingsScopePrivateChats
        case .group:
            .notificationSettingsScopeGroupChats
        case .supergroup(let group):
            group.isChannel ? .notificationSettingsScopeChannelChats : .notificationSettingsScopeGroupChats
        }
    }

    var adminRights: ChatAdministratorRights? {
        if case .chatMemberStatusAdministrator(let administrator) = supergroup?.status {
            return administrator.rights
        }
        return nil
    }

    /// Telegram's `hasPermission(.createTopics)` for a forum: the owner, admins who manage topics, and members
    /// when the group's permissions (and their own restrictions) allow creating topics.
    var canCreateForumTopics: Bool {
        guard let supergroup, supergroup.isForum, !supergroup.isChannel else { return false }
        switch supergroup.status {
        case .chatMemberStatusCreator:
            return true
        case .chatMemberStatusAdministrator(let administrator):
            return administrator.rights.canManageTopics || chat.permissions.canCreateTopics
        case .chatMemberStatusMember:
            return chat.permissions.canCreateTopics
        case .chatMemberStatusRestricted(let restricted):
            return restricted.isMember && restricted.permissions.canCreateTopics && chat.permissions.canCreateTopics
        case .chatMemberStatusBanned,
             .chatMemberStatusLeft:
            return false
        }
    }

    /// Telegram's `hasPermission(.manageTopics)`: pin, close and edit any topic.
    var canManageForumTopics: Bool {
        guard let supergroup, supergroup.isForum else { return false }
        if case .chatMemberStatusCreator = supergroup.status { return true }
        return adminRights?.canManageTopics == true
    }

    /// Telegram's `hasPermission(.deleteAllMessages)`, which a forum requires to delete a topic.
    var canDeleteAllMessages: Bool {
        guard let supergroup else { return false }
        if case .chatMemberStatusCreator = supergroup.status { return true }
        return adminRights?.canDeleteMessages == true
    }

    /// The secret chat's ID when this is an end-to-end encrypted chat with its user.
    var secretChatID: Int? {
        if case .chatTypeSecret(let secret) = chat.type { return secret.secretChatId }
        return nil
    }

    var shouldShowProfileImage: Bool {
        switch type {
        case .bot,
             .user: false
        case .group,
             .supergroup: true
        }
    }

    init(
        chat: Chat,
        position: ChatPosition,
        unreadCount: Int,
        type: CustomChatType,
        lastMessage: Message? = nil,
        draftMessage: DraftMessage? = nil,
    ) {
        self.id = chat.id
        self.chat = chat
        self.position = position
        self.unreadCount = unreadCount
        self.type = type
        self.lastMessage = lastMessage
        self.draftMessage = draftMessage
    }

    /// The group rule of `allowsSending` for callers that hold only the user's raw member status, such as the
    /// Forward picker's destinations.
    static func allowsSending(
        _ permission: KeyPath<ChatPermissions, Bool>,
        defaults: ChatPermissions,
        status: ChatMemberStatus,
        postsOnly: Bool,
        joinToSend: Bool,
        inReplyThread: Bool = false,
    ) -> Bool {
        switch status {
        case .chatMemberStatusCreator(let creator):
            creator.isMember
        case .chatMemberStatusAdministrator(let administrator):
            !postsOnly || administrator.rights.canPostMessages
        case .chatMemberStatusMember:
            !postsOnly && defaults[keyPath: permission]
        case .chatMemberStatusRestricted(let restricted):
            !postsOnly && restricted.isMember && restricted.permissions[keyPath: permission]
                && defaults[keyPath: permission]
        case .chatMemberStatusLeft:
            inReplyThread && !postsOnly && !joinToSend && defaults[keyPath: permission]
        case .chatMemberStatusBanned:
            false
        }
    }

    /// Telegram's send check (`canSendMessagesToChat`, `PeerChannel.hasBannedPermission`): the owner and admins are
    /// not bound by the chat's default restrictions, a channel or broadcast group takes posts only from its owner and
    /// admins who may post, and a restricted member is bound by both their own and the default permissions.
    /// `defaults` is the chat's current `Chat.permissions`, which TDLib leaves all false for a channel.
    /// In a reply thread, a discussion group that doesn't make users join first (`joinToSendMessages`) takes
    /// comments from users who aren't members (ChatInterfaceStateInputPanels, `.left` in `.replyThread`).
    func allowsSending(
        _ permission: KeyPath<ChatPermissions, Bool>,
        defaults: ChatPermissions,
        inReplyThread: Bool = false,
    ) -> Bool {
        let status: ChatMemberStatus
        let postsOnly: Bool
        let joinToSend: Bool
        switch type {
        case .supergroup(let group):
            status = group.status
            postsOnly = group.isChannel || group.isBroadcastGroup
            joinToSend = group.joinToSendMessages || group.isForum
        case .group(let group):
            status = group.status
            postsOnly = false
            joinToSend = true
        case .bot,
             .user:
            return defaults[keyPath: permission]
        }
        return Self.allowsSending(
            permission,
            defaults: defaults,
            status: status,
            postsOnly: postsOnly,
            joinToSend: joinToSend,
            inReplyThread: inReplyThread,
        )
    }

    func updatePrivateUser(_ user: User) {
        guard self.user?.id == user.id else { return }
        type =
            if case .userTypeBot = user.type {
                .bot(user)
            } else {
                .user(user)
            }
    }
}

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

    var id: Int64 { chat.id }

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
        case .bot(let user), .user(let user):
            user
        case .group, .supergroup:
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
        case .bot, .user:
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
        case .chatMemberStatusBanned, .chatMemberStatusLeft:
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

    var shouldShowProfileImage: Bool {
        switch type {
        case .bot, .user: false
        case .group, .supergroup: true
        }
    }

    var canPostMessages: Bool {
        guard let supergroup else { return true }
        if adminRights?.canPostMessages == true {
            return true
        }
        if case .chatMemberStatusCreator = supergroup.status {
            return true
        }
        if case .chatMemberStatusBanned = supergroup.status {
            return false
        }
        if case .chatMemberStatusLeft = supergroup.status {
            return false
        }
        return true
    }

    init(
        chat: Chat,
        position: ChatPosition,
        unreadCount: Int,
        type: CustomChatType,
        lastMessage: Message? = nil,
        draftMessage: DraftMessage? = nil,
    ) {
        self.chat = chat
        self.position = position
        self.unreadCount = unreadCount
        self.type = type
        self.lastMessage = lastMessage
        self.draftMessage = draftMessage
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

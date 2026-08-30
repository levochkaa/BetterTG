// CustomChat.swift

import Combine
import TDLibKitDynamic

@MainActor final class CustomChat: ObservableObject {
    // MARK: Internal

    enum CustomChatType: Equatable, Hashable {
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

    var id: Int64 { chat.id }

    var displayTitle: String {
        isSavedMessages ? L10n.telegram("Conversation.SavedMessages") : chat.title
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
        return supergroup.status != .chatMemberStatusLeft
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

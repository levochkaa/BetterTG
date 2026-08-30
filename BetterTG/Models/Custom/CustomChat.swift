// CustomChat.swift

import Combine
import TDLibKitDynamic

@MainActor final class CustomChat: ObservableObject {
    // MARK: Internal

    enum CustomChatType: Equatable, Hashable {
        case user(User)
        case supergroup(Supergroup)
        case group(BasicGroup)
        case bot(UserTypeBot)
    }

    @Published var chat: Chat
    let type: CustomChatType
    @Published var position: ChatPosition
    @Published var unreadCount: Int
    @Published var lastMessage: Message?
    @Published var draftMessage: DraftMessage?

    var id: Int64 { chat.id }

    var bot: UserTypeBot? {
        if case .bot(let bot) = type {
            return bot
        }
        return nil
    }

    var user: User? {
        if case .user(let user) = type {
            return user
        }
        return nil
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
}

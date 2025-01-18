// CustomChat.swift

import SwiftUI
import TDLibKit

@Observable class CustomChat {
    init(
        chat: Chat,
        position: ChatPosition,
        unreadCount: Int,
        type: CustomChatType,
        lastMessage: Message? = nil,
        draftMessage: DraftMessage? = nil
    ) {
        self.chat = chat
        self.position = position
        self.unreadCount = unreadCount
        self.type = type
        self.lastMessage = lastMessage
        self.draftMessage = draftMessage
    }
    
    var chat: Chat
    var position: ChatPosition
    var unreadCount: Int
    var lastMessage: Message?
    var draftMessage: DraftMessage?
    var type: CustomChatType
    
    var user: User? {
        switch type {
            case .user(let user): user
            default: nil
        }
    }
    
    var supergroup: Supergroup? {
        switch type {
            case .supergroup(let supergroup): supergroup
            default: nil
        }
    }
    
    var canPostMessages: Bool {
        if let supergroup {
            if case .chatMemberStatusCreator = supergroup.status {
                return true
            } else if case .chatMemberStatusAdministrator(let chatMemberStatusAdministrator) = supergroup.status {
                return chatMemberStatusAdministrator.rights.canPostMessages
            }
            return false
        }
        return true
    }
    
    enum CustomChatType: Equatable, Hashable {
        case user(User)
        case supergroup(Supergroup)
    }
}

extension CustomChat: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(chat)
        hasher.combine(position)
        hasher.combine(unreadCount)
        hasher.combine(type)
        hasher.combine(lastMessage)
        hasher.combine(draftMessage)
    }
}

extension CustomChat: Identifiable {
    var id: Int64 { chat.id }
}

extension CustomChat: Equatable {
    static func == (lhs: CustomChat, rhs: CustomChat) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}

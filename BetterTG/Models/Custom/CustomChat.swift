// CustomChat.swift

import SwiftUI
import TDLibKit

@Observable class CustomChat {
    init(
        chat: Chat,
        position: ChatPosition,
        unreadCount: Int,
        user: User,
        lastMessage: Message? = nil,
        draftMessage: DraftMessage? = nil
    ) {
        self.chat = chat
        self.position = position
        self.unreadCount = unreadCount
        self.user = user
        self.lastMessage = lastMessage
        self.draftMessage = draftMessage
    }
    
    var chat: Chat
    var position: ChatPosition
    var unreadCount: Int
    var user: User
    var lastMessage: Message?
    var draftMessage: DraftMessage?
}

extension CustomChat: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(chat)
        hasher.combine(position)
        hasher.combine(unreadCount)
        hasher.combine(user)
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

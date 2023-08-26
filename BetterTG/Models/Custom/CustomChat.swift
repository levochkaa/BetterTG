// CustomChat.swift

import Foundation
import TDLibKit

struct CustomChat: Identifiable, Equatable, Hashable {
    let id: UUID
    var chat: Chat
    var positions: [ChatPosition]
    var unreadCount: Int
    var user: User
    var lastMessage: Message?
    var draftMessage: DraftMessage?
    
    init(id: UUID = UUID(),
         chat: Chat,
         positions: [ChatPosition],
         unreadCount: Int,
         user: User,
         lastMessage: Message? = nil,
         draftMessage: DraftMessage? = nil
    ) {
        self.id = id
        self.chat = chat
        self.positions = positions
        self.unreadCount = unreadCount
        self.user = user
        self.lastMessage = lastMessage
        self.draftMessage = draftMessage
    }
}

extension CustomChat {
    static let placeholder: [CustomChat] = [
        .moc(UUID()), .moc(UUID()), .moc(UUID()), .moc(UUID()), .moc(UUID()), .moc(UUID()), .moc(UUID()), .moc(UUID()),
        .moc(UUID()), .moc(UUID()), .moc(UUID()), .moc(UUID()), .moc(UUID()), .moc(UUID()), .moc(UUID()), .moc(UUID())
    ]
}

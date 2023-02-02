// CustomChat.swift

import Foundation
import TDLibKit

struct CustomChat: Identifiable, Equatable {
    let id: UUID
    var chat: Chat
    var user: User
    var positions: [ChatPosition]
    var lastMessage: Message?
    var draftMessage: DraftMessage?
    
    init(id: UUID = UUID(),
         chat: Chat,
         user: User,
         positions: [ChatPosition],
         lastMessage: Message? = nil,
         draftMessage: DraftMessage? = nil
    ) {
        self.id = id
        self.chat = chat
        self.user = user
        self.positions = positions
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

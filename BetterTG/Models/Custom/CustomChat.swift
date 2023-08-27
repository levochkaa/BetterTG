// CustomChat.swift

import TDLibKit

struct CustomChat: Identifiable, Equatable, Hashable {
    var id: Int64 { chat.id }
    var chat: Chat
    var positions: [ChatPosition]
    var unreadCount: Int
    var user: User
    var lastMessage: Message?
    var draftMessage: DraftMessage?
}

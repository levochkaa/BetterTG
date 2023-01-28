// CustomChat.swift

import Foundation
import TDLibKit

struct CustomChat: Identifiable, Equatable {
    let id = UUID()
    var chat: Chat
    var user: User
    var positions: [ChatPosition]
    var lastMessage: Message?
    var draftMessage: DraftMessage?
}

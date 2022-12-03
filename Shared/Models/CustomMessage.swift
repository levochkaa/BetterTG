// CustomMessage.swift

import Foundation
import TDLibKit

struct CustomMessage: Identifiable, Equatable {
    var id = UUID()
    var message: Message
    var replyToMessage: Message?
    var replyUser: User?
    var showsContextMenu: Bool = false
    
    static func == (lhs: CustomMessage, rhs: CustomMessage) -> Bool {
        lhs.message.id == rhs.message.id
    }
}

// CustomMessage.swift

import Foundation
import TDLibKit

struct CustomMessage: Identifiable, Equatable {
    var id = UUID()
    var message: Message
    var senderUser: User?
    var replyToMessage: Message?
    var replyUser: User?
}

// CustomMessage.swift

import Foundation
import TDLibKit

struct CustomMessage: Identifiable {
    var id = UUID()
    var message: Message
    var replyToMessage: Message?
    var replyUser: User?
}

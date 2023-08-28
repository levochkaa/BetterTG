// CustomMessage.swift

import TDLibKit

struct CustomMessage: Identifiable, Equatable {
    var id: Int64 { message.id }
    var message: Message
    var senderUser: User?
    var replyUser: User?
    var replyToMessage: Message?
    var album = [Message]()
    var sendFailed = false
    var forwardedFrom: String?
}

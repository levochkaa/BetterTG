// CustomMessage.swift

import TDLibKit

struct CustomMessage: Identifiable, Equatable {
    let id = UUID()
    var message: Message
    var senderUser: User?
    var replyUser: User?
    var replyToMessage: Message?
    var album = [Message]()
    var sendFailed = false
    var forwardedFrom: String?
    var reactions: [CustomMessageReaction]?
}

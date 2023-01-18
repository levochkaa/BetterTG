// CustomMessage.swift

import Foundation
import TDLibKit
import Lottie

struct CustomMessage: Identifiable, Equatable {
    var id = UUID()
    var message: Message
    var senderUser: User?
    var replyUser: User?
    var replyToMessage: Message?
    var album = [Message]()
    var sendFailed = false
    var animojis = [Animoji]()
    var forwardedFrom: String?
}

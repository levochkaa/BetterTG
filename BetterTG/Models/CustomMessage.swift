// CustomMessage.swift

import Foundation
import TDLibKit
import Lottie

struct CustomMessage: Identifiable, Equatable {
    let id = UUID()
    var message: Message
    var senderUser: User?
    var replyUser: User?
    var replyToMessage: Message?
    var album = [Message]()
    var sendFailed = false
    var animojis = [Animoji]()
    var forwardedFrom: String?
}

extension CustomMessage {
    static func placeholder(
        _ b1: Bool = .random(), _ b2: Bool = .random(), _ b3: Bool = .random(),
        _ b4: Bool = .random(), _ b5: Bool = .random(), _ b6: Bool = .random(),
        _ b7: Bool = .random(), _ b8: Bool = .random(), _ b9: Bool = .random()
    ) -> [CustomMessage] {
        [.moc(b1), .moc(b2), .moc(b3), .moc(b4), .moc(b5), .moc(b6), .moc(b7), .moc(b8), .moc(b9)]
    }
}

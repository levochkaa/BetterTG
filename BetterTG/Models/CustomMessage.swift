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
    var forwardedFrom: String?
}

extension CustomMessage {
    static func placeholder(
        _ b1: Bool = .random(), _ b2: Bool = .random(), _ b3: Bool = .random(),
        _ b4: Bool = .random(), _ b5: Bool = .random(), _ b6: Bool = .random(),
        _ b7: Bool = .random(), _ b8: Bool = .random(), _ b9: Bool = .random(),
        _ b10: Bool = .random(), _ b11: Bool = .random(), _ b12: Bool = .random(),
        _ b13: Bool = .random(), _ b14: Bool = .random(), _ b15: Bool = .random(),
        _ c1: Int = .random(in: 1...5), _ c2: Int = .random(in: 1...5), _ c3: Int = .random(in: 1...5),
        _ c4: Int = .random(in: 1...5), _ c5: Int = .random(in: 1...5), _ c6: Int = .random(in: 1...5),
        _ c7: Int = .random(in: 1...5), _ c8: Int = .random(in: 1...5), _ c9: Int = .random(in: 1...5),
        _ c10: Int = .random(in: 1...5), _ c11: Int = .random(in: 1...5), _ c12: Int = .random(in: 1...5),
        _ c13: Int = .random(in: 1...5), _ c14: Int = .random(in: 1...5), _ c15: Int = .random(in: 1...5)
    ) -> [CustomMessage] {
        [.moc(b1, c1), .moc(b2, c2), .moc(b3, c3),
         .moc(b4, c4), .moc(b5, c5), .moc(b6, c6),
         .moc(b7, c7), .moc(b8, c8), .moc(b9, c9),
         .moc(b10, c10), .moc(b11, c11), .moc(b12, c12),
         .moc(b13, c13), .moc(b14, c14), .moc(b15, c15)]
    }
}

// +CustomMessage.swift

import SwiftUI
import TDLibKit

extension CustomMessage {
    static func moc(_ isOutgoing: Bool, _ count: Int) -> CustomMessage {
        CustomMessage(
            message: .moc(isOutgoing, count),
            senderUser: nil,
            replyUser: nil,
            replyToMessage: nil,
            album: [],
            sendFailed: false,
            animojis: [],
            forwardedFrom: nil
        )
    }
}

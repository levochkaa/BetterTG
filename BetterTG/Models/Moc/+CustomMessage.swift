// +CustomMessage.swift

import SwiftUI
import TDLibKit

extension CustomMessage {
    static func moc(_ isOutgoing: Bool = false) -> CustomMessage {
        CustomMessage(
            message: .moc(isOutgoing),
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

// +CustomChat.swift

import SwiftUI
import TDLibKit

extension CustomChat {
    static func moc(_ id: UUID) -> CustomChat {
        CustomChat(
            id: id,
            chat: .moc,
            positions: [],
            unreadCount: 0,
            user: .moc,
            lastMessage: .moc(.random(), 2),
            draftMessage: nil
        )
    }
}

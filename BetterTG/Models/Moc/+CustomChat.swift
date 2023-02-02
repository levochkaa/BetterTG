// CustomChat.swift

import SwiftUI
import TDLibKit

extension CustomChat {
    static func moc(_ id: UUID) -> CustomChat {
        CustomChat(
            id: UUID(),
            chat: .moc,
            user: .moc,
            positions: [],
            lastMessage: .moc,
            draftMessage: nil
        )
    }
}

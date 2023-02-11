// +MessageForwardInfo.swift

import Foundation
import TDLibKit

extension MessageForwardInfo {
    static let moc = MessageForwardInfo(
        date: 0,
        fromChatId: 0,
        fromMessageId: 0,
        origin: .messageForwardOriginUser(.init(senderUserId: 0)),
        publicServiceAnnouncementType: ""
    )
}

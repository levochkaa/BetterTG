// ReplyMessageType.swift

import Foundation
import TDLibKit

enum ReplyMessageType: Equatable {
    case reply, edit, replied(User, Message)
}

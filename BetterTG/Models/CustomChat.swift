// CustomChat.swift

import Foundation
import TDLibKit

struct CustomChat: Identifiable, Equatable {
    var id = UUID()
    var chat: Chat
    var user: User
}

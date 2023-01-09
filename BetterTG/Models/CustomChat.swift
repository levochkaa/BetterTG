// CustomChat.swift

import Foundation
import TDLibKit

struct CustomChat: Identifiable {
    var id = UUID()
    var chat: Chat
    var user: User
}

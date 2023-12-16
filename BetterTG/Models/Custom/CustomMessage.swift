// CustomMessage.swift

import SwiftUI
import TDLibKit

struct CustomMessage: Identifiable, Equatable, Hashable {
    var id = UUID()
    var message: Message
    var senderUser: User?
    var replyUser: User?
    var replyToMessage: Message?
    var album = [Message]()
    var sendFailed = false
    var forwardedFrom: String?
    var formattedText: FormattedText?
    
    var messageVoiceNote: MessageVoiceNote? {
        if case .messageVoiceNote(let messageVoiceNote) = message.content {
            return messageVoiceNote
        } else {
            return nil
        }
    }
}

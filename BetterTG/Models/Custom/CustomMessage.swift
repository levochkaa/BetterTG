// CustomMessage.swift

import SwiftUI
import TDLibKit

struct CustomMessage: Identifiable, Equatable, Hashable {
    var id: Int64 { message.id }
    var message: Message
    var senderUser: User?
    var replyUser: User?
    var replyToMessage: Message?
    var album = [Message]()
    var sendFailed = false
    var forwardedFrom: String?
    var formattedText: FormattedText?
    var properties: MessageProperties
    
    var messageVoiceNote: MessageVoiceNote? {
        if case .messageVoiceNote(let messageVoiceNote) = message.content {
            return messageVoiceNote
        }
        return nil
    }
    
    var messagePhoto: MessagePhoto? {
        if case .messagePhoto(let messagePhoto) = message.content {
            return messagePhoto
        }
        return nil
    }
}

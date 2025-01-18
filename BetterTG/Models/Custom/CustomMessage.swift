// CustomMessage.swift

import SwiftUI
import TDLibKit

@Observable class CustomMessage {
    init(
        message: Message,
        senderUser: User? = nil,
        replyUser: User? = nil,
        replyToMessage: Message? = nil,
        album: [Message] = [Message](),
        sendFailed: Bool = false,
        forwardedFrom: String? = nil,
        formattedText: FormattedText? = nil,
        properties: MessageProperties
    ) {
        self.message = message
        self.senderUser = senderUser
        self.replyUser = replyUser
        self.replyToMessage = replyToMessage
        self.album = album
        self.sendFailed = sendFailed
        self.forwardedFrom = forwardedFrom
        self.formattedText = formattedText
        self.properties = properties
    }
    
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

extension CustomMessage: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(message)
        hasher.combine(senderUser)
        hasher.combine(replyUser)
        hasher.combine(replyToMessage)
        hasher.combine(album)
        hasher.combine(sendFailed)
        hasher.combine(forwardedFrom)
        hasher.combine(formattedText)
        hasher.combine(properties)
    }
}

extension CustomMessage: Identifiable {
    var id: Int64 { message.id }
}

extension CustomMessage: Equatable {
    static func == (lhs: CustomMessage, rhs: CustomMessage) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}

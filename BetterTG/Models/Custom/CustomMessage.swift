// CustomMessage.swift

import SwiftUI
import TDLibKit

struct CustomMessage: Identifiable, Equatable {
    var id = UUID()
    var message: Message
    var senderUser: User?
    var replyUser: User?
    var replyToMessage: Message?
    var album = [Message]()
    var sendFailed = false
    var forwardedFrom: String?
    var formattedText: FormattedText?
    var formattedMessageDate: String
    var messageVoiceNote: MessageVoiceNote? {
        if case .messageVoiceNote(let messageVoiceNote) = message.content {
            return messageVoiceNote
        } else {
            return nil
        }
    }
    
    mutating func update(
        message: Message? = nil,
        senderUser: User? = nil,
        replyUser: User? = nil,
        album: [Message]? = nil,
        sendFailed: Bool? = nil,
        replyToMessage: Message? = nil,
        forwardedFrom: String? = nil,
        formattedText: FormattedText? = nil,
        formattedMessageDate: String? = nil
    ) {
        if let message { self.message = message }
        if let senderUser { self.senderUser = senderUser }
        if let replyUser { self.replyUser = replyUser }
        if let replyToMessage { self.replyToMessage = replyToMessage }
        if let album { self.album = album }
        if let sendFailed { self.sendFailed = sendFailed }
        if let forwardedFrom { self.forwardedFrom = forwardedFrom }
        if let formattedText { self.formattedText = formattedText }
        if let formattedMessageDate { self.formattedMessageDate = formattedMessageDate }
        id = UUID()
    }
    
    mutating func appendAlbum(_ message: Message) {
        album.append(message)
        id = UUID()
    }
}

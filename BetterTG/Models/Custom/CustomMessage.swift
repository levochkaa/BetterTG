// CustomMessage.swift

import Combine
import SwiftUI
import TDLibKit

// MARK: - CustomMessage

@Observable final class CustomMessage: ObservableObject {
    // MARK: Lifecycle

    init(
        message: Message,
        senderUser: User? = nil,
        replyUser: User? = nil,
        replyToMessage: Message? = nil,
        album: [Message] = [Message](),
        sendFailed: Bool = false,
        forwardedFrom: String? = nil,
        formattedText: FormattedText? = nil,
        properties: MessageProperties,
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
    
    // MARK: Internal

    @ObservationIgnored let objectWillChange = ObservableObjectPublisher()

    var message: Message { didSet { objectWillChange.send() } }
    var senderUser: User? { didSet { objectWillChange.send() } }
    var replyUser: User? { didSet { objectWillChange.send() } }
    var replyToMessage: Message? { didSet { objectWillChange.send() } }
    var album = [Message]() { didSet { objectWillChange.send() } }
    var sendFailed = false { didSet { objectWillChange.send() } }
    var forwardedFrom: String? { didSet { objectWillChange.send() } }
    var formattedText: FormattedText? { didSet { objectWillChange.send() } }
    var properties: MessageProperties { didSet { objectWillChange.send() } }
    
    var date: Foundation.Date { Date(timeIntervalSince1970: TimeInterval(message.date)) }
    
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

// MARK: Hashable

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

// MARK: Identifiable

extension CustomMessage: Identifiable {
    var id: Int64 { message.id }
}

// MARK: Equatable

extension CustomMessage: Equatable {
    static func == (lhs: CustomMessage, rhs: CustomMessage) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}

// CustomMessage.swift

import Combine
import Foundation
import TDLibKit

@MainActor final class CustomMessage: ObservableObject {
    // MARK: Lifecycle

    init(
        message: Message,
        senderUser: User? = nil,
        replyUser: User? = nil,
        replyToMessage: Message? = nil,
        album: [Message] = [],
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

    @Published var message: Message
    @Published var senderUser: User?
    @Published var replyUser: User?
    @Published var replyToMessage: Message?
    @Published var album: [Message]
    @Published var sendFailed: Bool
    @Published var forwardedFrom: String?
    @Published var formattedText: FormattedText?
    @Published var properties: MessageProperties

    var id: Int64 { message.id }
    var date: Foundation.Date {
        Foundation.Date(timeIntervalSince1970: TimeInterval(message.date))
    }
}

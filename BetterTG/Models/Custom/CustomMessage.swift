// CustomMessage.swift

import Combine
import Foundation
import TDLibKitDynamic

@MainActor final class CustomMessage: ObservableObject {
    // MARK: Internal

    @Published var message: Message
    @Published var senderUser: User?
    @Published var replyPresentation: MessageReplyPresentation?
    @Published var forwardPresentation: MessageForwardPresentation?
    @Published var album: [Message]
    @Published var sendFailed: Bool
    @Published var formattedText: FormattedText?
    @Published var properties: MessageProperties
    @Published var reactions: MessageReactions?
    @Published var unreadReactions: [UnreadReaction]
    @Published var reactionMutationInFlight = false
    @Published var isPinned: Bool

    var isReplyQuoteExpanded = false

    var id: Int64 { message.id }
    var contentPresentation: MessageContentPresentation {
        MessageContentPresentation.make(message)
    }

    var date: Foundation.Date {
        Foundation.Date(timeIntervalSince1970: TimeInterval(message.date))
    }

    init(
        message: Message,
        senderUser: User? = nil,
        replyPresentation: MessageReplyPresentation? = nil,
        forwardPresentation: MessageForwardPresentation? = nil,
        album: [Message] = [],
        sendFailed: Bool = false,
        formattedText: FormattedText? = nil,
        properties: MessageProperties,
        reactions: MessageReactions? = nil,
        unreadReactions: [UnreadReaction]? = nil,
        isPinned: Bool? = nil,
    ) {
        self.message = message
        self.senderUser = senderUser
        self.replyPresentation = replyPresentation
        self.forwardPresentation = forwardPresentation
        self.album = album
        self.sendFailed = sendFailed
        self.formattedText = formattedText
        self.properties = properties
        self.reactions = reactions ?? message.interactionInfo?.reactions
        self.unreadReactions = unreadReactions ?? message.unreadReactions
        self.isPinned = isPinned ?? message.isPinned
    }
}

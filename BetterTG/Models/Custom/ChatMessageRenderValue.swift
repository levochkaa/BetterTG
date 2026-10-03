// ChatMessageRenderValue.swift

import TDLibKitDynamic

/// Exact in-process rendering state. Unlike a history seed, this retains derived
/// delivery and in-flight flags. It grants no client, route, or action authority.
struct ChatMessageRenderValue: Equatable {
    let message: Message
    let senderUser: User?
    let replyPresentation: MessageReplyPresentation?
    let forwardPresentation: MessageForwardPresentation?
    let album: [Message]
    let sendFailed: Bool
    let formattedText: FormattedText?
    let properties: MessageProperties
    let reactions: MessageReactions?
    let unreadReactions: [UnreadReaction]
    let reactionMutationInFlight: Bool
    let isPinned: Bool
    let deliveryState: MessageDeliveryState
    let isReplyQuoteExpanded: Bool

    var displayedID: DisplayedMessageID {
        message.mediaAlbumId == 0 ? .message(message.id) : .album(message.mediaAlbumId.rawValue)
    }

    var sourceMessages: [Message] {
        album.isEmpty ? [message] : album.contains(where: { $0.id == message.id }) ? album : [message] + album
    }

    @MainActor init(_ value: CustomMessage) {
        self.message = value.message
        self.senderUser = value.senderUser
        self.replyPresentation = value.replyPresentation
        self.forwardPresentation = value.forwardPresentation
        self.album = value.album
        self.sendFailed = value.sendFailed
        self.formattedText = value.formattedText
        self.properties = value.properties
        self.reactions = value.reactions
        self.unreadReactions = value.unreadReactions
        self.reactionMutationInFlight = value.reactionMutationInFlight
        self.isPinned = value.isPinned
        self.deliveryState = value.deliveryState
        self.isReplyQuoteExpanded = value.isReplyQuoteExpanded
    }

    /// Materialize only for a renderer that needs CustomMessage. Never insert
    /// this detached copy into ChatVM or attach transport/update subscriptions.
    @MainActor func makeRenderOnlyMessage() -> CustomMessage {
        CustomMessage(renderOnly: self)
    }
}

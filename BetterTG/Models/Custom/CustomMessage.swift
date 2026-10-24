// CustomMessage.swift

import Combine
import Foundation
import TDLibKit

@MainActor final class CustomMessage: ObservableObject {
    // MARK: Internal

    @Published var message: Message {
        didSet {
            if oldValue.editDate != message.editDate || oldValue.content.constructorID != message.content
                .constructorID
            {
                richContentState.invalidateContent()
            }
        }
    }

    @Published var senderUser: User?
    /// Telegram's service wording with resolved names; nil keeps the generic service title.
    @Published var serviceText: String?
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
    @Published private(set) var deliveryState = MessageDeliveryState.none

    @Published var spoilersRevealed = false
    /// The expandable quotes opened in this message's text, by block index (ChatMessageTextBubbleContentNode's
    /// expandedBlockIds).
    @Published var expandedQuoteBlocks = Set<Int>()

    var isReplyQuoteExpanded = false {
        didSet { renderRevision &+= 1 }
    }

    /// Bumped by every published change and by quote expansion, which are all the inputs of ChatMessageRenderValue.
    /// A timeline row whose canonical object and revision are unchanged renders the same value, so a snapshot can
    /// skip building and deep-comparing it (each native TDLib field read crosses into C++).
    private(set) var renderRevision: UInt64 = 0
    let richContentState = MessageRichContentState()

    private var renderRevisionSubscription: AnyCancellable?

    var id: Int64 { message.id }
    var contentPresentation: MessageContentPresentation {
        MessageContentPresentation.make(message).replacingServiceTitle(serviceText)
    }

    var date: Foundation.Date {
        Foundation.Date(timeIntervalSince1970: TimeInterval(message.date))
    }

    /// Telegram's grouped status follows its first chronological member, not
    /// BetterTG's newest-first display representative. IDs only break date ties.
    var deliverySourceMessage: Message {
        sourceMessages.min { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date } ?? message
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
        // objectWillChange fires synchronously on the main actor inside each @Published setter.
        self.renderRevisionSubscription = objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.renderRevision &+= 1 }
        }
    }

    /// A detached rendering copy, never a live message or a restored history seed.
    convenience init(renderOnly value: ChatMessageRenderValue) {
        self.init(
            message: value.message, senderUser: value.senderUser,
            replyPresentation: value.replyPresentation, forwardPresentation: value.forwardPresentation,
            album: value.album, sendFailed: value.sendFailed, formattedText: value.formattedText,
            properties: value.properties, reactions: value.reactions, unreadReactions: value.unreadReactions,
            isPinned: value.isPinned,
        )
        // Preserve explicit nil rather than the normal initializer's raw fallback.
        self.reactions = value.reactions
        self.deliveryState = value.deliveryState
        self.reactionMutationInFlight = value.reactionMutationInFlight
        self.isReplyQuoteExpanded = value.isReplyQuoteExpanded
        self.expandedQuoteBlocks = value.expandedQuoteBlocks
        self.serviceText = value.serviceText
    }

    func updateDeliveryState(permitsFinalStatus: Bool, readOutbox: Int64?, topic: MessageTopic? = nil) {
        let source = deliverySourceMessage
        let next = MessageDeliveryState.resolve(
            source, permitsFinalStatus: permitsFinalStatus, readOutbox: readOutbox, topic: topic,
        )
        if deliveryState != next { deliveryState = next }
    }
}

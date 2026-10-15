// ChatMessageActionAuthority.swift

import TDLibKit
import UIKit

/// A rendered action owns its cell binding and payload, never a replacement row.
@MainActor final class ChatMessageActionAuthority {
    enum Intent {
        case reply, selection, quote, media
        case reaction(ReactionType)
        case metadata(MessageMetadataNavigationTarget)
        case content(MessageContentAction)
    }

    struct State {
        let isFull: Bool
        let isSelecting: Bool
        let isReadOnly: Bool
        let canAddReactions: Bool
        let isSelected: Bool
    }

    let bindingID = UUID()
    let displayedID: DisplayedMessageID

    private weak var message: CustomMessage?
    private weak var cell: MessageCell?
    private let source: TdUpdateSource?
    private let location: ChatLocation
    private let renderValue: ChatMessageRenderValue
    private let selected: Bool

    init(
        message: CustomMessage, cell: MessageCell, source: TdUpdateSource?, location: ChatLocation, selected: Bool,
        renderValue: ChatMessageRenderValue? = nil,
    ) {
        let value = renderValue ?? ChatMessageRenderValue(message)
        self.message = message
        self.cell = cell
        self.source = source
        self.location = location
        self.displayedID = value.displayedID
        self.renderValue = value
        self.selected = selected
    }

    func resolve(
        _ intent: Intent,
        current: CustomMessage?,
        source currentSource: TdUpdateSource?,
        location currentLocation: ChatLocation,
        ownerIsCurrent: Bool,
        rowIsCurrent: Bool,
        state: State,
    ) -> CustomMessage? {
        let sources = renderValue.sourceMessages
        let replyTarget = renderValue.replyPresentation?.navigationTarget
        let forwardTarget = renderValue.forwardPresentation?.navigationTarget
        guard ownerIsCurrent, rowIsCurrent, let source, source == currentSource,
              location == currentLocation, source.accountID == location.accountID,
              source.clientID == location.clientID,
              let cell, cell.actionBindingID == bindingID, cell.window != nil,
              cell.isUserInteractionEnabled, !cell.contentView.isHidden,
              let message, current === message, message.displayedID == displayedID,
              message.message == renderValue.message, message.sourceMessages == sources,
              sources.allSatisfy({ location.matches(message: $0) }),
              message.formattedText == renderValue.formattedText,
              message.replyPresentation?.navigationTarget == replyTarget,
              message.replyPresentation?.body == renderValue.replyPresentation?.body,
              message.replyPresentation?.quote == renderValue.replyPresentation?.quote,
              message.isReplyQuoteExpanded == renderValue.isReplyQuoteExpanded,
              message.forwardPresentation?.navigationTarget == forwardTarget
        else { return nil }
        if case .selection = intent {
            return state.isFull && state.isSelecting && state.isSelected == selected && !message.contentPresentation
                .isService
                && message.message.selfDestructType == nil ? message : nil
        }
        guard state.isFull, !state.isSelecting else { return nil }
        switch intent {
        case .reply:
            guard !state.isReadOnly, message.properties.canBeReplied else { return nil }
        case .reaction(let type):
            let chosen = MessageReactionStateReducer.isChosen(type, in: message.reactions)
            guard !state.isReadOnly, !type.isPaid, !message.reactionMutationInFlight,
                  !message.contentPresentation.isService, message.message.selfDestructType == nil,
                  message.message.ephemeralMessageId == 0, message.message.sendingState == nil,
                  chosen == MessageReactionStateReducer.isChosen(type, in: renderValue.reactions),
                  message.reactions?.reactions.contains(where: { $0.type == type }) == true,
                  state.canAddReactions || chosen else { return nil }
        case .metadata(let target):
            guard target == replyTarget || target == forwardTarget else { return nil }
        case .quote:
            guard message.replyPresentation?.isManualQuote == true, !message.isReplyQuoteExpanded else { return nil }
        case .content(.submitPollAnswer(let messageID, let optionIDs, let submission)):
            guard !state.isReadOnly, submission.messageID == messageID,
                  let raw = sources.first(where: { $0.id == messageID }),
                  case .messagePoll(let content) = raw.content,
                  !content.poll.isClosed, content.poll.voteRestrictionReason == nil,
                  content.poll.allowsRevoting || !content.poll.options.contains(where: \.isChosen),
                  !content.poll.options.contains(where: \.isBeingChosen),
                  optionIDs.allSatisfy({ content.poll.options.indices.contains($0) }),
                  Set(optionIDs).count == optionIDs.count,
                  content.poll.allowsMultipleAnswers || optionIDs.count <= 1 else { return nil }
        case .content(.cancelSending(let messageID)):
            guard let raw = sources.first(where: { $0.id == messageID }),
                  case .messageSendingStatePending = raw.sendingState else { return nil }
        case .content(.pressInlineKeyboardButton(let press)):
            // A button acts for a sent message of this row only.
            guard let raw = sources.first(where: { $0.id == press.messageID }), raw.sendingState == nil else {
                return nil
            }
        case .content, .media, .selection:
            break
        }
        return message
    }
}

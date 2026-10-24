// MessageReadReport.swift

import TDLibKit
import UIKit

// MARK: - MessageReadReport

/// ChatReadReportContextItem in a group: the row atop the message menu with how many saw the message
/// (`getMessageViewers`, while TDLib's canGetViewers allows it) and how many reacted, and up to three of them.
struct MessageReadReport {
    /// Telegram counts listens for a voice message and watches for a round video.
    enum Media {
        case other
        case voice
        case round

        init(_ content: MessageContent) {
            self =
                switch content {
                case .messageVoiceNote: .voice
                case .messageVideoNote: .round
                default: .other
                }
        }
    }

    let reactionCount: Int
    let media: Media
    /// The people who saw the message, nil until TDLib returns them; empty when they can't be listed.
    var viewerIDs: [Int64]?
    /// The latest people who reacted, first the latest reaction's (`recentSenderIds`).
    var recentReactors = [MessageSender]()

    /// The row's text once the viewers are known.
    var title: String? {
        guard let viewerIDs else { return nil }
        if viewerIDs.isEmpty {
            if reactionCount > 0 { return L10n.telegramPlural("Chat.ContextReactionCount", count: reactionCount) }
            return switch media {
            case .other: L10n.telegram("Conversation.ContextMenuNoViews")
            case .voice: L10n.telegram("Conversation.ContextMenuNobodyListened")
            case .round: L10n.telegram("Conversation.ContextMenuNobodyWatched")
            }
        }
        if reactionCount > 0 {
            if reactionCount >= viewerIDs.count {
                return L10n.telegramPlural("Chat.OutgoingContextReactionCount", count: reactionCount)
            }
            return L10n.telegram("Chat.OutgoingContextMixedReactionCount", "\(reactionCount)", "\(viewerIDs.count)")
        }
        let key =
            switch media {
            case .other: "Conversation.ContextMenuSeen"
            case .voice: "Conversation.ContextMenuListened"
            case .round: "Conversation.ContextMenuWatched"
            }
        return L10n.telegramPlural(key, count: viewerIDs.count)
    }

    /// Whether the row opens the list: Telegram's button takes touches once there is someone to list, and before the
    /// viewers load only for reactions.
    var isEnabled: Bool {
        reactionCount > 0 || viewerIDs?.isEmpty == false
    }

    /// The avatars at the trailing edge: the latest reactors, else the first viewers, three at most.
    var avatarSenders: [MessageSender] {
        var senders = [MessageSender]()
        for sender in recentReactors where !senders.contains(sender) {
            senders.append(sender)
            if senders.count == 3 { return senders }
        }
        guard senders.isEmpty else { return senders }
        return (viewerIDs ?? []).prefix(3).map { .messageSenderUser(MessageSenderUser(userId: $0)) }
    }

    init(reactionCount: Int, media: Media, canListViewers: Bool) {
        self.reactionCount = reactionCount
        self.media = media
        self.viewerIDs = canListViewers ? nil : []
    }

    /// The reactions TDLib lets the menu list, as Telegram's `canViewList`.
    @MainActor static func listedReactions(of message: CustomMessage) -> [MessageReaction] {
        guard let reactions = message.reactions, reactions.canGetAddedReactions else { return [] }
        return reactions.reactions
    }
}

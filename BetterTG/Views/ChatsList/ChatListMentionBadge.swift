// ChatListMentionBadge.swift

import UIKit

// MARK: - ChatListMentionBadge

/// Telegram's row badges left of the unread count (PresentationResourcesChatList: badgeBackgroundMention,
/// badgeBackgroundReactions, badgeBackgroundPollVotes): a white glyph on a filled circle, grey when inactive.
enum ChatListMentionBadge {
    enum Kind {
        case mention
        case reaction
        case pollVote
    }

    static let diameter = CGFloat(20)

    static func image(_ kind: Kind, inactive: Bool) -> UIImage? {
        let (symbol, color): (String, UIColor) =
            switch kind {
            case .mention: ("at.circle.fill", .systemBlue)
            case .reaction: ("heart.circle.fill", .systemPink)
            case .pollVote: ("list.bullet.circle.fill", .systemBlue)
            }
        let configuration = UIImage.SymbolConfiguration(pointSize: diameter, weight: .medium)
            .applying(UIImage.SymbolConfiguration(paletteColors: [.white, inactive ? .systemGray : color]))
        return UIImage(systemName: symbol, withConfiguration: configuration)
    }
}

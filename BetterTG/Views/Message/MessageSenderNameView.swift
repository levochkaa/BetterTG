// MessageSenderNameView.swift

import UIKit

// MARK: - MessageSenderName

/// The author line at the top of an incoming bubble in a group (ChatMessageBubbleItemNode's authorNameString): the
/// name in the author's name colour, and the rank at the trailing edge.
struct MessageSenderName: Equatable {
    enum Rank: Equatable {
        /// The owner's custom title, or "owner", in Telegram's purple.
        case owner(String)
        /// An administrator's custom title, or "admin", in green.
        case admin(String)
        /// A member's tag in the secondary colour.
        case member(String)
    }

    let name: String
    let color: UIColor
    let rank: Rank?
}

// MARK: - MessageSenderNameView

final class MessageSenderNameView: UIView {
    /// Telegram's name font: semibold at 14 / 17 of the text size, the rank regular and a point smaller.
    private static let nameFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
    private static let rankFont = UIFont.systemFont(ofSize: 13)

    private let nameLabel = UILabel()
    private let rankLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        nameLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: Self.nameFont)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rankLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: Self.rankFont)
        rankLabel.adjustsFontForContentSizeCategory = true
        rankLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        rankLabel.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [nameLabel, rankLabel])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ sender: MessageSenderName) {
        nameLabel.text = sender.name
        nameLabel.textColor = sender.color
        switch sender.rank {
        case .owner(let title):
            rankLabel.text = title
            rankLabel.textColor = UIColor(rgb: 0x956AC8)
        case .admin(let title):
            rankLabel.text = title
            rankLabel.textColor = UIColor(rgb: 0x49A355)
        case .member(let tag):
            rankLabel.text = tag
            rankLabel.textColor = .secondaryLabel
        case nil:
            rankLabel.text = nil
        }
        rankLabel.isHidden = rankLabel.text?.isEmpty != false
    }
}

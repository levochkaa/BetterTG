// ChatReplyCountCell.swift

import UIKit

// MARK: - ChatReplyCountCell

/// Telegram's ChatReplyCountItem: the service pill under a thread's root, "Discussion started" once replies follow
/// it and "No comments here yet..." before.
final class ChatReplyCountCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatReplyCountCell"

    private let titleLabel = UILabel()
    private let pillView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
        pillView.translatesAutoresizingMaskIntoConstraints = false
        pillView.backgroundColor = .secondarySystemBackground
        pillView.layer.cornerCurve = .continuous
        pillView.layer.cornerRadius = 11
        pillView.clipsToBounds = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        contentView.addSubview(pillView)
        pillView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            pillView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            pillView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            pillView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pillView.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
            pillView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -32),
            titleLabel.topAnchor.constraint(equalTo: pillView.topAnchor, constant: 3),
            titleLabel.bottomAnchor.constraint(equalTo: pillView.bottomAnchor, constant: -3),
            titleLabel.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -10),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func text(hasReplies: Bool) -> String {
        L10n.telegram(hasReplies ? "Conversation.DiscussionStarted" : "Conversation.DiscussionNotStarted")
    }

    func configure(text: String) {
        titleLabel.text = text
        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = .staticText
    }

    func resetUnavailableContent() {
        titleLabel.text = nil
        accessibilityLabel = nil
    }
}

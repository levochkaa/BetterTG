// ChatsListItemView.swift

import TDLibKitDynamic
import UIKit

// MARK: - ChatListCell

final class ChatListCell: UITableViewCell {
    // MARK: Internal

    static let reuseIdentifier = "ChatListCell"

    // MARK: Private

    private let cardView = UIView()
    private let pinView = UIImageView(image: UIImage(systemName: "pin"))
    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let messageRow = UIStackView()
    private let unreadLabel = TelegramUnreadBadgeLabel(
        minimumDiameter: 20,
        horizontalPadding: 10,
        usesStableChatListWidth: true,
    )

    var contextPreviewView: UIView { cardView }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .systemBackground
        selectionStyle = .none
        configureViews()
        configureConstraints()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(chat: CustomChat, isMuted: Bool) {
        pinView.isHidden = !chat.position.isPinned
        titleLabel.text = chat.displayTitle
        messageLabel.attributedText = ChatSummary.attributedText(for: chat)
        let hasUnread = chat.unreadCount > 0 || chat.chat.isMarkedAsUnread
        unreadLabel.text = chat.unreadCount > 0 ? compactNumericCountString(chat.unreadCount) : nil
        unreadLabel.backgroundColor = isMuted ? .systemGray : .systemBlue
        unreadLabel.isHidden = !hasUnread
        avatarView.configure(
            file: chat.chat.photo?.big,
            minithumbnail: chat.chat.photo?.minithumbnail,
            placeholder: chat.telegramAvatarPlaceholder,
        )
        accessibilityLabel = [
            chat.displayTitle,
            messageLabel.text,
            hasUnread ? (chat.unreadCount > 0 ? "\(chat.unreadCount) unread" : "unread") : nil,
        ]
            .compactMap(\.self)
            .joined(separator: ", ")
        accessibilityTraits = .button
    }

    private func configureViews() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 20
        cardView.clipsToBounds = true
        contentView.addSubview(cardView)

        for item in [pinView, avatarView, titleLabel, messageRow] {
            item.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview(item)
        }
        messageRow.axis = .horizontal
        messageRow.alignment = .center
        messageRow.spacing = 8
        messageRow.addArrangedSubview(messageLabel)
        messageRow.addArrangedSubview(unreadLabel)
        pinView.tintColor = UIColor(red: 0x76 / 255, green: 0x76 / 255, blue: 0x77 / 255, alpha: 1)
        pinView.contentMode = .scaleAspectFit
        pinView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.font = .preferredFont(forTextStyle: .title3)
        titleLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.lineBreakMode = .byTruncatingTail
        unreadLabel.textColor = .white
        unreadLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    }

    private func configureConstraints() {
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            pinView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            pinView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            pinView.widthAnchor.constraint(equalToConstant: 14),
            pinView.heightAnchor.constraint(equalToConstant: 14),
            avatarView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            avatarView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 60),
            avatarView.heightAnchor.constraint(equalToConstant: 60),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: pinView.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: cardView.centerYAnchor, constant: -2),
            messageRow.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageRow.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            messageRow.topAnchor.constraint(equalTo: cardView.centerYAnchor, constant: 2),
            unreadLabel.heightAnchor.constraint(equalToConstant: 20),
        ])
    }
}

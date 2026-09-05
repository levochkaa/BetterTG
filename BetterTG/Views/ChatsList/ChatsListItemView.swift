// ChatsListItemView.swift

import TDLibKit
import UIKit

// MARK: - ChatListCell

final class ChatListCell: UITableViewCell {
    // MARK: Internal

    static let reuseIdentifier = "ChatListCell"

    // MARK: Private

    private let rowView = UIView()
    private let separatorView = UIView()
    private let pinView = UIImageView(image: UIImage(systemName: "pin.fill"))
    private let muteView = UIImageView(image: UIImage(systemName: "speaker.slash.fill"))
    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let trailingStatusView = UIView()
    private var accessoryWidthConstraint: NSLayoutConstraint!
    private let dateLabel = UILabel()
    private let deliveryView = UIImageView()
    private let headerAccessoryRow = UIStackView()
    private let unreadLabel = TelegramUnreadBadgeLabel(
        minimumDiameter: 20,
        horizontalPadding: 10,
        usesStableChatListWidth: true,
    )
    private var pinned = false

    var contextPreviewView: UIView { rowView }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .systemBackground
        selectionStyle = .none
        isAccessibilityElement = true
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

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        updateBackground(highlighted: highlighted, animated: animated)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        updateBackground(highlighted: selected, animated: animated)
    }

    private static func dateText(for chat: CustomChat) -> String? {
        guard let timestamp = chat.draftMessage?.date ?? chat.lastMessage?.date else { return nil }
        let date = Foundation.Date(timeIntervalSince1970: TimeInterval(timestamp))
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day,
           (0...6).contains(days)
        {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: .now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.day().month(.twoDigits).year(.twoDigits))
    }

    private static func deliveryState(for chat: CustomChat) -> (
        image: UIImage?,
        color: UIColor,
        accessibilityText: String,
    )? {
        guard chat.draftMessage == nil,
              let message = chat.lastMessage,
              message.isOutgoing
        else { return nil }
        switch message.sendingState {
        case .messageSendingStateFailed:
            return (UIImage(systemName: "exclamationmark.circle"), .systemRed, "Failed to send")
        case .messageSendingStatePending:
            return (UIImage(systemName: "clock"), .secondaryLabel, "Sending")
        case nil:
            return message.id <= chat.chat.lastReadOutboxMessageId
                ? (TelegramDeliveryCheck.image(isRead: true), .systemBlue, "Read")
                : (TelegramDeliveryCheck.image(isRead: false), .systemBlue, "Delivered")
        }
    }

    func configure(chat: CustomChat, isMuted: Bool, client: TDLibClient) {
        pinned = chat.position.isPinned
        titleLabel.text = chat.displayTitle
        messageLabel.attributedText = ChatSummary.attributedText(for: chat)
        let hasUnread = chat.unreadCount > 0 || chat.chat.isMarkedAsUnread
        pinView.isHidden = !pinned || hasUnread
        muteView.isHidden = !isMuted || hasUnread || pinned
        unreadLabel.text = chat.unreadCount > 0 ? compactNumericCountString(chat.unreadCount) : nil
        unreadLabel.backgroundColor = isMuted ? .systemGray : .systemBlue
        unreadLabel.isHidden = !hasUnread
        dateLabel.text = Self.dateText(for: chat)
        let delivery = Self.deliveryState(for: chat)
        deliveryView.image = delivery?.image
        deliveryView.tintColor = delivery?.color
        deliveryView.isHidden = delivery == nil
        accessoryWidthConstraint.constant = hasUnread
            ? unreadLabel.intrinsicContentSize.width
            : (pinned || isMuted ? 14 : 0)
        setNeedsLayout()
        updateBackground(highlighted: isHighlighted || isSelected, animated: false)
        avatarView.configure(
            file: chat.chat.photo?.small,
            largeFile: chat.chat.photo?.big,
            minithumbnail: chat.chat.photo?.minithumbnail,
            placeholder: chat.telegramAvatarPlaceholder,
            client: client,
        )
        accessibilityLabel = [
            chat.displayTitle,
            messageLabel.text,
            dateLabel.text,
            delivery?.accessibilityText,
            pinned ? "Pinned" : nil,
            isMuted ? "Muted" : nil,
            hasUnread
                ? (chat.unreadCount > 0
                    ? L10n.telegramPlural("VoiceOver.Chat.UnreadMessages", count: chat.unreadCount)
                    : L10n.telegram("DialogList.Unread"))
                : nil,
        ]
            .compactMap(\.self)
            .joined(separator: ", ")
        accessibilityTraits = .button
    }

    private func updateBackground(highlighted: Bool, animated: Bool) {
        let color: UIColor = highlighted
            ? .tertiarySystemFill
            : (pinned ? .secondarySystemBackground : .systemBackground)
        guard animated else {
            rowView.backgroundColor = color
            return
        }
        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.rowView.backgroundColor = color
        }
    }

    private func configureViews() {
        rowView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowView)

        for item in [avatarView, titleLabel, headerAccessoryRow, messageLabel, trailingStatusView, separatorView] {
            item.translatesAutoresizingMaskIntoConstraints = false
            rowView.addSubview(item)
        }
        separatorView.backgroundColor = .separator

        headerAccessoryRow.axis = .horizontal
        headerAccessoryRow.alignment = .center
        headerAccessoryRow.spacing = 4
        headerAccessoryRow.addArrangedSubview(deliveryView)
        headerAccessoryRow.addArrangedSubview(dateLabel)

        for accessory in [muteView, pinView, unreadLabel] {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            trailingStatusView.addSubview(accessory)
        }
        // Pin and mute share the fixed trailing slot; unread always owns it when present.
        deliveryView.contentMode = .center

        for imageView in [pinView, muteView] {
            imageView.tintColor = .secondaryLabel
            imageView.contentMode = .scaleAspectFit
            imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        }
        titleLabel.textColor = .label
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .semibold),
            maximumPointSize: 19,
        )
        titleLabel.lineBreakMode = .byTruncatingTail
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15),
            maximumPointSize: 17,
        )
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dateLabel.textColor = .secondaryLabel
        dateLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13),
            maximumPointSize: 14,
        )
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        deliveryView.setContentCompressionResistancePriority(.required, for: .horizontal)
        unreadLabel.textColor = .white
        unreadLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        unreadLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        unreadLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func configureConstraints() {
        accessoryWidthConstraint = trailingStatusView.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            rowView.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rowView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            avatarView.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 10),
            avatarView.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 60),
            avatarView.heightAnchor.constraint(equalToConstant: 60),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: rowView.topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerAccessoryRow.leadingAnchor, constant: -6),
            headerAccessoryRow.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -14),
            headerAccessoryRow.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: trailingStatusView.leadingAnchor, constant: -6),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: rowView.bottomAnchor, constant: -9),
            trailingStatusView.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -14),
            trailingStatusView.centerYAnchor.constraint(equalTo: messageLabel.centerYAnchor),
            trailingStatusView.heightAnchor.constraint(equalToConstant: 20),
            accessoryWidthConstraint,
            pinView.centerXAnchor.constraint(equalTo: trailingStatusView.centerXAnchor),
            pinView.centerYAnchor.constraint(equalTo: trailingStatusView.centerYAnchor),
            pinView.widthAnchor.constraint(equalToConstant: 14),
            pinView.heightAnchor.constraint(equalToConstant: 14),
            muteView.centerXAnchor.constraint(equalTo: trailingStatusView.centerXAnchor),
            muteView.centerYAnchor.constraint(equalTo: trailingStatusView.centerYAnchor),
            muteView.widthAnchor.constraint(equalToConstant: 14),
            muteView.heightAnchor.constraint(equalToConstant: 14),
            unreadLabel.topAnchor.constraint(equalTo: trailingStatusView.topAnchor),
            unreadLabel.bottomAnchor.constraint(equalTo: trailingStatusView.bottomAnchor),
            unreadLabel.leadingAnchor.constraint(equalTo: trailingStatusView.leadingAnchor),
            unreadLabel.trailingAnchor.constraint(equalTo: trailingStatusView.trailingAnchor),
            separatorView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
        ])
    }
}

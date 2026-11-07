// PersonalChannelCardView.swift

import TDLibKit
import UIKit

// MARK: - PersonalChannelCardView

/// PeerInfoProfileItems' personal channel: CHANNEL with the subscribers on the right, then
/// PeerInfoScreenPersonalChannelItem's
/// chat list row for the channel (its photo, title, the last post's date and text) on the list's block background.
/// A tap opens the channel.
final class PersonalChannelCardView: UIView {
    var onOpen: (() -> Void)?

    private let headerLabel = UILabel()
    private let countLabel = UILabel()
    private let card = UIView()
    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let textLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        headerLabel.text = L10n.telegram("Profile.PersonalChannelSectionTitle")
        for label in [headerLabel, countLabel] {
            label.font = .preferredFont(forTextStyle: .footnote)
            label.textColor = .secondaryLabel
        }
        countLabel.textAlignment = .right
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        avatarView.isUserInteractionEnabled = false
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        dateLabel.font = .systemFont(ofSize: 14)
        dateLabel.textColor = .secondaryLabel
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        textLabel.font = .systemFont(ofSize: 15)
        textLabel.textColor = .secondaryLabel
        textLabel.numberOfLines = 2
        for subview in [headerLabel, countLabel, card] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        for subview in [avatarView, titleLabel, dateLabel, textLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: topAnchor),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            countLabel.firstBaselineAnchor.constraint(equalTo: headerLabel.firstBaselineAnchor),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: headerLabel.trailingAnchor, constant: 8),
            card.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            avatarView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            avatarView.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            avatarView.widthAnchor.constraint(equalToConstant: 56),
            avatarView.heightAnchor.constraint(equalToConstant: 56),
            avatarView.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            dateLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            dateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 6),
            dateLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            textLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            textLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            textLabel.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -10),
        ])
        avatarView.layer.cornerRadius = 28
        avatarView.clipsToBounds = true
        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        card.accessibilityTraits = .button
        card.isAccessibilityElement = true
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(chat: Chat, subscribers: Int, client: TDLibClient, accountID: UUID?) {
        countLabel.text = subscribers > 0
            ? L10n.telegramPlural("Conversation.StatusSubscribers", count: subscribers)
            : nil
        let peer = SettingsPeer(chat: chat)
        avatarView.configure(
            file: peer.file, minithumbnail: peer.minithumbnail, placeholder: peer.placeholder,
            accountID: accountID, client: client,
        )
        titleLabel.text = chat.title
        if let message = chat.lastMessage {
            let date = Date(timeIntervalSince1970: TimeInterval(message.date))
            dateLabel.text = Calendar.current.isDateInToday(date)
                ? date.formatted(date: .omitted, time: .shortened)
                : date.formatted(.dateTime.day().month(.abbreviated))
            textLabel.text = MessageTextSpoilerPresentation.summary(for: message)
        } else {
            dateLabel.text = nil
            textLabel.text = nil
        }
        card.accessibilityLabel = [chat.title, textLabel.text].compactMap(\.self).joined(separator: ", ")
    }

    @objc private func tapped() {
        onOpen?()
    }
}

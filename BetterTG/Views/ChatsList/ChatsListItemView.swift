// ChatsListItemView.swift

import TDLibKit
import UIKit

// MARK: - ChatListCell

final class ChatListCell: UITableViewCell {
    // MARK: Lifecycle

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .black
        selectionStyle = .none
        configureViews()
        configureConstraints()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    static let reuseIdentifier = "ChatListCell"

    var contextPreviewView: UIView { cardView }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(chat: CustomChat, folder _: CustomFolder) {
        pinView.isHidden = !chat.position.isPinned
        titleLabel.text = chat.chat.title
        messageLabel.attributedText = ChatSummary.attributedText(for: chat)
        unreadLabel.text = "\(chat.unreadCount)"
        unreadLabel.isHidden = chat.unreadCount == 0
        avatarView.configure(
            file: chat.chat.photo?.big,
            minithumbnail: chat.chat.photo?.minithumbnail,
            title: chat.chat.title,
            id: chat.id,
        )
        accessibilityLabel = [
            chat.chat.title,
            messageLabel.text,
            chat.unreadCount > 0
                ? "\(chat.unreadCount) unread"
                : nil,
        ]
            .compactMap(\.self)
            .joined(separator: ", ")
        accessibilityTraits = .button
    }

    // MARK: Private

    private let cardView = UIView()
    private let pinView = UIImageView(image: UIImage(systemName: "pin.fill"))
    private let avatarView = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let unreadLabel = UILabel()

    private func configureViews() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 20
        cardView.clipsToBounds = true
        contentView.addSubview(cardView)

        for item in [pinView, avatarView, titleLabel, messageLabel, unreadLabel] {
            item.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview(item)
        }
        pinView.tintColor = .white
        pinView.contentMode = .scaleAspectFit
        pinView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .title3)
        titleLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.lineBreakMode = .byTruncatingTail
        unreadLabel.backgroundColor = .systemGray
        unreadLabel.textColor = .white
        unreadLabel.textAlignment = .center
        unreadLabel.font = .preferredFont(forTextStyle: .caption1)
        unreadLabel.layer.cornerRadius = 16
        unreadLabel.clipsToBounds = true
        unreadLabel.adjustsFontSizeToFitWidth = true
    }

    private func configureConstraints() {
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            pinView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            pinView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            pinView.widthAnchor.constraint(equalToConstant: 13),
            pinView.heightAnchor.constraint(equalToConstant: 13),
            avatarView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            avatarView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 60),
            avatarView.heightAnchor.constraint(equalToConstant: 60),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: unreadLabel.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: cardView.centerYAnchor, constant: -2),
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: unreadLabel.leadingAnchor, constant: -8),
            messageLabel.topAnchor.constraint(equalTo: cardView.centerYAnchor, constant: 2),
            unreadLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            unreadLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            unreadLabel.widthAnchor.constraint(equalToConstant: 32),
            unreadLabel.heightAnchor.constraint(equalToConstant: 32),
        ])
    }
}

// MARK: - ProfileAvatarView

final class ProfileAvatarView: UIView {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .title2)
        addSubview(label)
        addSubview(imageView)
        isUserInteractionEnabled = true
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
    }

    func configure(file: File?, minithumbnail: Minithumbnail?, title: String, id: Int64) {
        prepareForReuse()
        label.text = String(title.prefix(1)).uppercased()
        backgroundColor = UIColor(userID: id)
        representedFile = file
        if let file {
            imageView.load(file: file, placeholderData: minithumbnail?.data, maximumPixelSize: 160)
        } else {
            imageView.image = minithumbnail.flatMap { UIImage(data: $0.data) }
        }
    }

    func prepareForReuse() {
        imageView.cancel()
        representedFile = nil
        imageView.image = nil
    }

    // MARK: Private

    private let imageView = TDImageLoadingView()
    private let label = UILabel()
    private var representedFile: File?

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, representedFile != nil, imageView.image != nil else { return }
        nearestViewController?.presentTelegramContextMenu(sourceView: self, actions: [
            TelegramContextMenuAction(
                title: "Save Photo",
                image: UIImage(systemName: "square.and.arrow.down"),
            ) { [weak self] in
                guard let image = self?.imageView.image else { return }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            },
        ], tracking: gesture)
    }
}

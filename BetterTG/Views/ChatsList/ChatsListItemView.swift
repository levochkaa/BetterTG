// ChatsListItemView.swift

import TDLibKit
import UIKit

// MARK: - ChatListCell

final class ChatListCell: UITableViewCell {
    // MARK: Lifecycle

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
    private let pinView = UIImageView(image: UIImage(systemName: "pin"))
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
            pinView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            pinView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            pinView.widthAnchor.constraint(equalToConstant: 14),
            pinView.heightAnchor.constraint(equalToConstant: 14),
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

final class ProfileAvatarView: TelegramContextMenuExtractableView {
    // MARK: Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        extractedContentView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .title2)
        extractedContentView.addSubview(label)
        extractedContentView.addSubview(imageView)
        isUserInteractionEnabled = true
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        longPressGesture.minimumPressDuration = 0.3
        addGestureRecognizer(longPressGesture)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: extractedContentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: extractedContentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: extractedContentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: extractedContentView.bottomAnchor),
            label.topAnchor.constraint(equalTo: extractedContentView.topAnchor),
            label.leadingAnchor.constraint(equalTo: extractedContentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: extractedContentView.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: extractedContentView.bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func layoutSubviews() {
        super.layoutSubviews()
        guard extractedContentView.superview === self else { return }
        extractedContentView.layer.cornerRadius = bounds.width / 2
    }

    func configure(file: File?, minithumbnail: Minithumbnail?, title: String, id: Int64) {
        label.text = String(title.prefix(1)).uppercased()
        extractedContentView.backgroundColor = UIColor(userID: id)
        let thumbnailData = minithumbnail?.data
        guard representedFile != file || representedMinithumbnailData != thumbnailData else { return }
        imageView.cancel()
        imageView.image = nil
        representedFile = file
        representedMinithumbnailData = thumbnailData
        if let file {
            imageView.load(file: file, placeholderData: thumbnailData, maximumPixelSize: 160)
        } else {
            imageView.image = thumbnailData.flatMap(UIImage.init(data:))
        }
    }

    func prepareForReuse() {
        imageView.cancel()
        representedFile = nil
        representedMinithumbnailData = nil
        imageView.image = nil
    }

    // MARK: Private

    private let imageView = TDImageLoadingView()
    private let label = UILabel()
    private var representedFile: File?
    private var representedMinithumbnailData: Data?

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let hostController = nearestViewController else { return }
        let chatController = hostController as? ChatViewController
        hostController.presentTelegramContextMenu(sourceView: self, actions: [
            TelegramContextMenuAction(
                title: "Open Profile",
                image: UIImage(systemName: "person.crop.circle"),
            ) {},
            TelegramContextMenuAction(
                title: "Search",
                image: UIImage(systemName: "magnifyingglass"),
            ) { [weak chatController] in
                chatController?.beginMessageSearch()
            },
            TelegramContextMenuAction(
                title: "Save Photo",
                image: UIImage(systemName: "square.and.arrow.down"),
            ) { [weak self] in
                guard let image = self?.imageView.image else { return }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            },
        ], tracking: gesture, presentationStyle: .avatar)
    }
}

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
        titleLabel.text = chat.chat.title
        messageLabel.attributedText = ChatSummary.attributedText(for: chat)
        let hasUnread = chat.unreadCount > 0 || chat.chat.isMarkedAsUnread
        unreadLabel.text = chat.unreadCount > 0 ? compactNumericCountString(chat.unreadCount) : nil
        unreadLabel.backgroundColor = isMuted ? .systemGray : .systemBlue
        unreadLabel.isHidden = !hasUnread
        avatarView.configure(
            file: chat.chat.photo?.big,
            minithumbnail: chat.chat.photo?.minithumbnail,
            title: chat.chat.title,
            id: chat.id,
        )
        accessibilityLabel = [
            chat.chat.title,
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

// MARK: - ProfileAvatarView

final class ProfileAvatarView: TelegramContextMenuExtractableView {
    // MARK: Private

    private let imageView = TDImageLoadingView()
    private let label = UILabel()
    private var representedAccountID: UUID?
    private var representedClientID: Int32?
    private var representedPeerID: Int64?
    private var representedFile: File?
    private var representedMinithumbnailData: Data?

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
        let accountID = TDLib.shared.activeAccountID
        let clientID = td.id
        let thumbnailData = minithumbnail?.data
        guard representedAccountID != accountID
            || representedClientID != clientID
            || representedPeerID != id
            || representedFile != file
            || representedMinithumbnailData != thumbnailData
        else { return }
        imageView.cancel()
        imageView.image = nil
        representedAccountID = accountID
        representedClientID = clientID
        representedPeerID = id
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
        representedAccountID = nil
        representedClientID = nil
        representedPeerID = nil
        representedFile = nil
        representedMinithumbnailData = nil
        imageView.image = nil
        label.text = nil
        extractedContentView.backgroundColor = .clear
    }

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

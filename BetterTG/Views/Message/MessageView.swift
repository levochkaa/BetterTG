// MessageView.swift

import TDLibKit
import UIKit

final class MessageCell: UICollectionViewCell {
    static let reuseIdentifier = "MessageCell"

    var contextPreviewView: UIView { bubbleContainerView }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
        configureViews()
        configureConstraints()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
        mediaView.prepareForReuse()
        forwardedLabel.isHidden = true
        replyView.isHidden = true
        textView.isHidden = true
        mediaView.isHidden = true
        timestampLabel.isHidden = true
        mediaTimestampLabel.isHidden = true
        onReplyTap = nil
        onMediaTap = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let maximumBubbleWidth = contentView.bounds.width * 0.82
        textView.setMaximumLayoutWidth(maximumBubbleWidth - 16)
    }

    private let rowStack = UIStackView()
    private let bubbleContainerView = TelegramContextMenuExtractableView()
    private var bubbleView: UIView { bubbleContainerView.extractedContentView }
    private let bubbleStack = UIStackView()
    private let avatarView = ProfileAvatarView()
    private let forwardedLabel = UILabel()
    private let replyView = ReplySnippetView()
    private let mediaView = MessageMediaView()
    private let textView = MessageTextContentView()
    private let timestampLabel = UILabel()
    private let mediaTimestampLabel = UILabel()
    private let leadingSpacer = UIView()
    private let trailingSpacer = UIView()
    private var onReplyTap: ((Int64) -> Void)?
    private var onMediaTap: (([Message], Int64) -> Void)?

    func configure(
        message: CustomMessage,
        chat: CustomChat,
        highlighted: Bool,
        onReplyTap: @escaping (Int64) -> Void,
        onMediaTap: @escaping ([Message], Int64) -> Void,
    ) {
        self.onReplyTap = onReplyTap
        self.onMediaTap = onMediaTap
        configureAlignment(outgoing: message.message.isOutgoing, showsAvatar: chat.shouldShowProfileImage)

        bubbleView.backgroundColor = highlighted ? UIColor.white.withAlphaComponent(0.45) : .secondarySystemBackground
        forwardedLabel.isHidden = message.forwardedFrom == nil
        forwardedLabel.text = message.forwardedFrom.map { "Forwarded from \($0)" }

        if let reply = message.replyToMessage {
            replyView.isHidden = false
            replyView.configure(
                title: message.replyUser?.firstName ?? "Reply",
                message: reply,
                onTap: { [weak self] in self?.onReplyTap?(reply.id) },
            )
        } else {
            replyView.isHidden = true
        }

        let hasMedia = mediaView.configure(message: message) { [weak self] messages, selection in
            self?.onMediaTap?(messages, selection)
        }
        mediaView.isHidden = !hasMedia

        let timestamp = Self.timeFormatter.string(from: message.date)
        let timestampText = message.sendFailed ? "Failed • \(timestamp)" : timestamp
        let timestampColor: UIColor = message.sendFailed ? .systemRed : .secondaryLabel
        if let formatted = message.formattedText {
            textView.isHidden = false
            let maximumBubbleWidth = contentView.bounds.width * 0.82
            textView.configure(
                formattedText: formatted,
                statusText: timestampText,
                statusColor: timestampColor,
                maximumWidth: maximumBubbleWidth - 16,
            )
        } else {
            textView.isHidden = true
        }

        timestampLabel.text = timestampText
        timestampLabel.textColor = timestampColor
        mediaTimestampLabel.text = timestampText
        mediaTimestampLabel.textColor = message.sendFailed ? .systemRed : .white
        let hasVisualMedia = hasMedia && message.hasVisualMedia
        timestampLabel.isHidden = message.formattedText != nil || hasVisualMedia
        mediaTimestampLabel.isHidden = message.formattedText != nil || !hasVisualMedia
        mediaView.bringSubviewToFront(mediaTimestampLabel)

        if let sender = message.senderUser, chat.shouldShowProfileImage, !message.message.isOutgoing {
            avatarView.isHidden = false
            avatarView.configure(
                file: sender.profilePhoto?.big,
                minithumbnail: sender.profilePhoto?.minithumbnail,
                title: sender.firstName,
                id: sender.id,
            )
        } else {
            avatarView.isHidden = true
        }

        isAccessibilityElement = true
        accessibilityLabel = [
            message.forwardedFrom.map { "Forwarded from \($0)" },
            message.formattedText?.text,
            timestampLabel.text,
        ]
        .compactMap(\.self)
        .joined(separator: ", ")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func configureViews() {
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.axis = .horizontal
        rowStack.alignment = .bottom
        rowStack.spacing = 5
        contentView.addSubview(rowStack)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 32),
            avatarView.heightAnchor.constraint(equalToConstant: 32),
        ])

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.backgroundColor = .secondarySystemBackground
        bubbleView.layer.cornerRadius = 20
        bubbleView.clipsToBounds = true
        bubbleStack.translatesAutoresizingMaskIntoConstraints = false
        bubbleStack.axis = .vertical
        bubbleStack.alignment = .fill
        bubbleStack.spacing = 2
        bubbleView.addSubview(bubbleStack)
        rowStack.addArrangedSubview(bubbleContainerView)
        rowStack.addArrangedSubview(trailingSpacer)

        forwardedLabel.textColor = .secondaryLabel
        forwardedLabel.font = .preferredFont(forTextStyle: .caption1)
        forwardedLabel.numberOfLines = 1
        replyView.isHidden = true
        mediaView.isHidden = true
        textView.isHidden = true
        timestampLabel.font = .preferredFont(forTextStyle: .caption2)
        timestampLabel.textAlignment = .right
        timestampLabel.isHidden = true

        mediaTimestampLabel.translatesAutoresizingMaskIntoConstraints = false
        mediaTimestampLabel.font = .preferredFont(forTextStyle: .caption2)
        mediaTimestampLabel.textAlignment = .center
        mediaTimestampLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        mediaTimestampLabel.layer.cornerRadius = 8
        mediaTimestampLabel.clipsToBounds = true
        mediaTimestampLabel.isHidden = true
        mediaView.addSubview(mediaTimestampLabel)
        NSLayoutConstraint.activate([
            mediaTimestampLabel.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor, constant: -6),
            mediaTimestampLabel.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: -5),
            mediaTimestampLabel.heightAnchor.constraint(equalToConstant: 17),
            mediaTimestampLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 38),
        ])

        for view in [forwardedLabel, replyView, mediaView, textView, timestampLabel] {
            bubbleStack.addArrangedSubview(view)
        }
        bubbleStack.setCustomSpacing(6, after: replyView)
    }

    private func configureConstraints() {
        let maxBubbleWidth = bubbleContainerView.widthAnchor.constraint(
            lessThanOrEqualTo: contentView.widthAnchor,
            multiplier: 0.82
        )
        maxBubbleWidth.priority = .required
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            rowStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            maxBubbleWidth,
            bubbleStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 6),
            bubbleStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
            bubbleStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
            bubbleStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -5),
        ])
    }

    private func configureAlignment(outgoing: Bool, showsAvatar: Bool) {
        rowStack.arrangedSubviews.forEach {
            rowStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if outgoing {
            rowStack.addArrangedSubview(leadingSpacer)
            rowStack.addArrangedSubview(bubbleContainerView)
            leadingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            bubbleContainerView.setContentHuggingPriority(.required, for: .horizontal)
        } else {
            if showsAvatar {
                rowStack.addArrangedSubview(avatarView)
            }
            rowStack.addArrangedSubview(bubbleContainerView)
            rowStack.addArrangedSubview(trailingSpacer)
            trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            bubbleContainerView.setContentHuggingPriority(.required, for: .horizontal)
        }
    }
}

final class ReplySnippetView: UIControl {
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        accentView.translatesAutoresizingMaskIntoConstraints = false
        accentView.backgroundColor = .white
        accentView.layer.cornerRadius = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.textColor = .white
        textLabel.font = .preferredFont(forTextStyle: .caption1)
        textLabel.textColor = .secondaryLabel
        textLabel.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(textLabel)
        addSubview(accentView)
        addSubview(stack)
        NSLayoutConstraint.activate([
            accentView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            accentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            accentView.widthAnchor.constraint(equalToConstant: 2),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.leadingAnchor.constraint(equalTo: accentView.trailingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let accentView = UIView()
    private let stack = UIStackView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private var onTap: (() -> Void)?

    func configure(title: String, message: Message, onTap: @escaping () -> Void) {
        titleLabel.text = title
        textLabel.text = ChatSummary.summary(for: message)
        self.onTap = onTap
    }

    @objc private func tapped() {
        onTap?()
    }
}

private extension CustomMessage {
    var hasVisualMedia: Bool {
        if !album.isEmpty { return true }
        return switch message.content {
        case .messageAnimation, .messagePhoto, .messageSticker, .messageVideo:
            true
        default:
            false
        }
    }
}

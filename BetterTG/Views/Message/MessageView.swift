// MessageView.swift

import TDLibKit
import UIKit

final class MessageCell: UICollectionViewCell {
    static let reuseIdentifier = "MessageCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
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
        onReplyTap = nil
        onMediaTap = nil
    }

    private let rowStack = UIStackView()
    private let bubbleView = UIView()
    private let bubbleStack = UIStackView()
    private let avatarView = ProfileAvatarView()
    private let forwardedLabel = UILabel()
    private let replyView = ReplySnippetView()
    private let mediaView = MessageMediaView()
    private let textView = MessageTextContentView()
    private let timestampLabel = UILabel()
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

        mediaView.isHidden = !mediaView.configure(message: message) { [weak self] messages, selection in
            self?.onMediaTap?(messages, selection)
        }
        if let formatted = message.formattedText {
            textView.isHidden = false
            textView.configure(formattedText: formatted)
        } else {
            textView.isHidden = true
        }

        timestampLabel.text = Self.timeFormatter.string(from: message.date)
        if message.sendFailed {
            timestampLabel.text = "Failed • \(timestampLabel.text ?? "")"
            timestampLabel.textColor = .systemRed
        } else {
            timestampLabel.textColor = .tertiaryLabel
        }

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

        forwardedLabel.textColor = .secondaryLabel
        forwardedLabel.font = .preferredFont(forTextStyle: .caption1)
        forwardedLabel.numberOfLines = 1
        replyView.isHidden = true
        mediaView.isHidden = true
        textView.isHidden = true
        timestampLabel.font = .preferredFont(forTextStyle: .caption2)
        timestampLabel.textAlignment = .right

        for view in [forwardedLabel, replyView, mediaView, textView, timestampLabel] {
            bubbleStack.addArrangedSubview(view)
        }
        bubbleStack.setCustomSpacing(6, after: replyView)
    }

    private func configureConstraints() {
        let maxBubbleWidth = bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.82)
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
            rowStack.addArrangedSubview(bubbleView)
            leadingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            bubbleView.setContentHuggingPriority(.required, for: .horizontal)
        } else {
            if showsAvatar {
                rowStack.addArrangedSubview(avatarView)
            }
            rowStack.addArrangedSubview(bubbleView)
            rowStack.addArrangedSubview(trailingSpacer)
            trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            bubbleView.setContentHuggingPriority(.required, for: .horizontal)
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

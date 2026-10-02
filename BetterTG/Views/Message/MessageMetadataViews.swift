// MessageMetadataViews.swift

import TDLibKitDynamic
import UIKit

// MARK: - ForwardHeaderView

final class ForwardHeaderView: UIControl {
    private let headlineLabel = UILabel()
    private let sourceLabel = UILabel()
    private let avatarView = MessageMetadataAvatarView()
    private var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let sourceRow = UIStackView(arrangedSubviews: [avatarView, sourceLabel])
        sourceRow.axis = .horizontal
        sourceRow.alignment = .center
        sourceRow.spacing = 4
        sourceRow.isUserInteractionEnabled = false

        let stack = UIStackView(arrangedSubviews: [headlineLabel, sourceRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 1
        stack.isUserInteractionEnabled = false
        addSubview(stack)

        headlineLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 14, weight: .regular),
        )
        headlineLabel.adjustsFontForContentSizeCategory = true
        headlineLabel.textColor = .systemBlue
        headlineLabel.numberOfLines = 2
        headlineLabel.lineBreakMode = .byTruncatingTail

        sourceLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 14, weight: .medium),
        )
        sourceLabel.adjustsFontForContentSizeCategory = true
        sourceLabel.textColor = .systemBlue
        sourceLabel.numberOfLines = 1
        sourceLabel.lineBreakMode = .byTruncatingTail

        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 16),
            avatarView.heightAnchor.constraint(equalToConstant: 16),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        presentation: MessageForwardPresentation,
        client: TDLibClient?,
        onTap: (() -> Void)?,
    ) {
        prepareForReuse()
        headlineLabel.text = presentation.headline
        sourceLabel.text = presentation.sourceTitle
        avatarView.configure(presentation.avatar, client: client)
        avatarView.isHidden = presentation.avatar == nil
        self.onTap = onTap
        isUserInteractionEnabled = onTap != nil
        isAccessibilityElement = true
        accessibilityLabel = presentation.accessibilityDescription
        accessibilityTraits = onTap == nil ? [.staticText] : [.button]
        accessibilityHint = onTap == nil ? nil : "Opens the forwarded message source"
    }

    func prepareForReuse() {
        avatarView.prepareForReuse()
        headlineLabel.text = nil
        sourceLabel.text = nil
        onTap = nil
        accessibilityLabel = nil
        accessibilityHint = nil
    }

    #if DEBUG
        func simulateTapForProbe() {
            tapped()
        }
    #endif

    @objc private func tapped() {
        onTap?()
    }
}

// MARK: - ReplySnippetView

final class ReplySnippetView: UIControl {
    private let accentView = UIView()
    private let bodyLabel = UILabel()
    private let quoteIconView = UIImageView(image: UIImage(systemName: "quote.opening"))
    private let textStack = UIStackView()
    private let thumbnailView = TDImageLoadingView()
    private let titleLabel = UILabel()
    private var onTap: ((Bool) -> Void)?
    private var canExpand = false
    private var expanded = false
    private var textLeadingConstraint: NSLayoutConstraint!
    private var thumbnailWidthConstraint: NSLayoutConstraint!

    #if DEBUG
        var debugBodyLineLimit: Int { bodyLabel.numberOfLines }

        func simulateTapForProbe() {
            tapped()
        }
    #endif

    private var bodyIsTruncated: Bool {
        guard canExpand,
              bodyLabel.bounds.width > 0,
              bodyLabel.numberOfLines > 0,
              let attributedText = bodyLabel.attributedText
        else { return false }
        let fullSize = attributedText.boundingRect(
            with: CGSize(width: bodyLabel.bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesFontLeading, .usesLineFragmentOrigin],
            context: nil,
        )
        .size
        let visibleHeight = bodyLabel.font.lineHeight * CGFloat(bodyLabel.numberOfLines)
        return fullSize.height > visibleHeight + 0.5
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        accentView.translatesAutoresizingMaskIntoConstraints = false
        accentView.backgroundColor = .systemBlue
        accentView.layer.cornerRadius = 1.5
        addSubview(accentView)

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        addSubview(thumbnailView)

        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 14, weight: .semibold),
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .systemBlue
        titleLabel.lineBreakMode = .byTruncatingTail

        bodyLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .regular),
        )
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.lineBreakMode = .byTruncatingTail

        quoteIconView.tintColor = .secondaryLabel
        quoteIconView.contentMode = .scaleAspectFit
        quoteIconView.setContentHuggingPriority(.required, for: .horizontal)
        quoteIconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        quoteIconView.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let bodyRow = UIStackView(arrangedSubviews: [bodyLabel, quoteIconView])
        bodyRow.axis = .horizontal
        bodyRow.alignment = .bottom
        bodyRow.spacing = 4
        bodyRow.isUserInteractionEnabled = false

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 1
        textStack.isUserInteractionEnabled = false
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(bodyRow)
        addSubview(textStack)

        self.thumbnailWidthConstraint = thumbnailView.widthAnchor.constraint(equalToConstant: 0)
        self.textLeadingConstraint = textStack.leadingAnchor.constraint(
            equalTo: thumbnailView.trailingAnchor,
            constant: 0,
        )
        NSLayoutConstraint.activate([
            accentView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            accentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            accentView.widthAnchor.constraint(equalToConstant: 3),
            thumbnailView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            thumbnailView.leadingAnchor.constraint(equalTo: accentView.trailingAnchor, constant: 6),
            thumbnailView.heightAnchor.constraint(equalToConstant: 36),
            thumbnailView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2),
            thumbnailWidthConstraint,
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            textLeadingConstraint,
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        presentation: MessageReplyPresentation,
        expanded: Bool,
        client: TDLibClient?,
        onTap: @escaping (Bool) -> Void,
    ) {
        prepareForReuse()
        self.expanded = expanded
        canExpand = presentation.isManualQuote && !expanded
        titleLabel.text = presentation.title
        titleLabel.numberOfLines = presentation.isManualQuote ? 2 : 1
        bodyLabel.attributedText = MessageTextSpoilerPresentation(presentation.body).attributedText()
        bodyLabel.numberOfLines = presentation.isManualQuote ? (expanded ? 50 : 5) : 1
        quoteIconView.isHidden = !presentation.isManualQuote
        if let thumbnail = presentation.thumbnail {
            thumbnailWidthConstraint.constant = 36
            textLeadingConstraint.constant = 6
            thumbnailView.isHidden = false
            thumbnailView.layer.cornerRadius = thumbnail.isRound ? 18 : 4
            thumbnailView.load(
                file: thumbnail.file,
                placeholderData: thumbnail.minithumbnailData,
                maximumPixelSize: 160,
                origin: client.flatMap { .captured(client: $0) },
            )
        } else {
            thumbnailWidthConstraint.constant = 0
            textLeadingConstraint.constant = 0
            thumbnailView.isHidden = true
        }
        self.onTap = onTap
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = presentation.accessibilityDescription
        accessibilityTraits = [.button]
        accessibilityHint = canExpand
            ? "Expands the quoted text"
            : (presentation.navigationTarget == nil || presentation.navigationTarget == .unavailable
                ? "Original message is unavailable"
                : "Opens the replied message")
        invalidateIntrinsicContentSize()
    }

    func configure(title: String, message: Message, onTap: @escaping () -> Void) {
        configure(title: title, text: ChatSummary.summary(for: message), onTap: onTap)
    }

    func configure(title: String, quote: InputTextQuote, onTap: @escaping () -> Void) {
        prepareForReuse()
        titleLabel.text = title
        titleLabel.numberOfLines = 2
        bodyLabel.attributedText = MessageTextSpoilerPresentation(quote.text).attributedText()
        bodyLabel.numberOfLines = 3
        quoteIconView.isHidden = false
        thumbnailWidthConstraint.constant = 0
        textLeadingConstraint.constant = 0
        thumbnailView.isHidden = true
        self.onTap = { _ in onTap() }
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = "\(title), quoted text, \(MessageTextSpoilerPresentation(quote.text).accessibilityText())"
        accessibilityTraits = [.button]
        accessibilityHint = "Opens the message"
        invalidateIntrinsicContentSize()
    }

    func configure(title: String, text: String, onTap: @escaping () -> Void) {
        prepareForReuse()
        titleLabel.text = title
        titleLabel.numberOfLines = 1
        bodyLabel.text = text
        bodyLabel.numberOfLines = 1
        quoteIconView.isHidden = true
        thumbnailWidthConstraint.constant = 0
        textLeadingConstraint.constant = 0
        thumbnailView.isHidden = true
        self.onTap = { _ in onTap() }
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = "\(title), \(text)"
        accessibilityTraits = [.button]
        accessibilityHint = "Opens the message"
        invalidateIntrinsicContentSize()
    }

    func prepareForReuse() {
        thumbnailView.cancel()
        thumbnailView.image = nil
        titleLabel.text = nil
        bodyLabel.attributedText = nil
        quoteIconView.isHidden = true
        thumbnailWidthConstraint.constant = 0
        textLeadingConstraint.constant = 0
        onTap = nil
        canExpand = false
        expanded = false
        accessibilityLabel = nil
        accessibilityHint = nil
    }

    @objc private func tapped() {
        layoutIfNeeded()
        onTap?(bodyIsTruncated && !expanded)
    }
}

// MARK: - MessageMetadataAvatarView

private final class MessageMetadataAvatarView: UIView {
    private let imageView = TDImageLoadingView()
    private let initialsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        backgroundColor = .systemBlue

        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        initialsLabel.font = .systemFont(ofSize: 8, weight: .semibold)
        initialsLabel.textColor = .white
        initialsLabel.textAlignment = .center
        addSubview(initialsLabel)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        addSubview(imageView)
        NSLayoutConstraint.activate([
            initialsLabel.topAnchor.constraint(equalTo: topAnchor),
            initialsLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            initialsLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            initialsLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
    }

    func configure(_ avatar: MessageMetadataAvatar?, client: TDLibClient?) {
        prepareForReuse()
        guard let avatar else { return }
        initialsLabel.text = avatar.initials
        if let file = avatar.file {
            imageView.load(
                file: file,
                placeholderData: avatar.minithumbnailData,
                maximumPixelSize: 80,
                origin: client.flatMap { .captured(client: $0) },
            )
        } else {
            imageView.loadPlaceholder(data: avatar.minithumbnailData, origin: client.flatMap { .captured(client: $0) })
        }
    }

    func prepareForReuse() {
        imageView.cancel()
        imageView.image = nil
        initialsLabel.text = nil
    }
}

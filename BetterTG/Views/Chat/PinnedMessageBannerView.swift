// PinnedMessageBannerView.swift

import TDLibKit
import UIKit

// MARK: - PinnedMessageBannerView

final class PinnedMessageBannerView: UIView {
    private struct RenderedContent: Equatable {
        let clientID: Int32?
        let chatID: Int64
        let messageID: Int64
        let preview: String
        let file: File?
        let minithumbnailData: Data?
        let isRound: Bool
        let index: Int
        let totalCount: Int
    }

    static let contentHeight = CGFloat(50)

    /// ChatPinnedMessageTitlePanelNode's context container: a long press previews the pinned list with its actions.
    var onContextMenu: ((ContextMenuPressGestureRecognizer) -> Void)? {
        didSet { contextGesture.isEnabled = onContextMenu != nil }
    }

    private let accentView = PinnedNavigationStripeView()
    private let thumbnailView = TDImageLoadingView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let textStack = UIStackView()
    private let openControl = UIControl()
    private let actionButton = UIButton(type: .system)
    private var thumbnailWidthConstraint: NSLayoutConstraint!
    private var textLeadingConstraint: NSLayoutConstraint!
    private var onOpen: (() -> Void)?
    private var onHide: (() -> Void)?

    private lazy var contextGesture = ContextMenuPressGestureRecognizer(
        target: self,
        action: #selector(contextPressed(_:)),
    )
    private var renderedContent: RenderedContent?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        accentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accentView)

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        addSubview(thumbnailView)

        titleLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13, weight: .semibold),
            maximumPointSize: 15,
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.isAccessibilityElement = false
        titleLabel.textColor = .systemBlue
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        bodyLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13, weight: .regular),
            maximumPointSize: 15,
        )
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.isAccessibilityElement = false
        bodyLabel.textColor = .label
        bodyLabel.numberOfLines = 1
        bodyLabel.lineBreakMode = .byTruncatingTail

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = textSpacing()
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(bodyLabel)
        textStack.isUserInteractionEnabled = false
        addSubview(textStack)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitDisplayScale.self]) {
            (self: Self, _) in
            self.textStack.spacing = self.textSpacing()
        }

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.accessibilityIdentifier = "pinned-message-hide"
        actionButton.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
        addSubview(actionButton)

        openControl.translatesAutoresizingMaskIntoConstraints = false
        openControl.accessibilityIdentifier = "pinned-message-open"
        openControl.addTarget(self, action: #selector(openPressed), for: .touchUpInside)
        addSubview(openControl)
        contextGesture.isEnabled = false
        addGestureRecognizer(contextGesture)

        self.thumbnailWidthConstraint = thumbnailView.widthAnchor.constraint(equalToConstant: 0)
        self.textLeadingConstraint = textStack.leadingAnchor.constraint(
            equalTo: thumbnailView.trailingAnchor,
            constant: 0,
        )
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
            accentView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 10),
            accentView.topAnchor.constraint(equalTo: topAnchor),
            accentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            accentView.widthAnchor.constraint(equalToConstant: 2),
            thumbnailView.leadingAnchor.constraint(equalTo: accentView.trailingAnchor, constant: 6),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.heightAnchor.constraint(equalToConstant: 35),
            thumbnailWidthConstraint,
            // Telegram's ChatPinnedMessageTitlePanelNode places the title at y 6 and the text at y 23 in its 50 pt
            // panel. Both labels keep their own height: a stack stretched to the panel let UIKit pick which label
            // grew, so a rebuilt banner could draw both lines 4 pt lower.
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            {
                let constraint = textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2)
                constraint.priority = .defaultHigh
                return constraint
            }(),
            textLeadingConstraint,
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -6),
            actionButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -2),
            actionButton.topAnchor.constraint(equalTo: topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: 44),
            openControl.topAnchor.constraint(equalTo: topAnchor),
            openControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            openControl.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor),
            openControl.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// ChatPinnedMessageTitlePanelNode's title: Previous Message for the older of two pins, the number for any but
    /// the newest of more.
    static func title(index: Int, totalCount: Int) -> String {
        if totalCount == 2 {
            return L10n.telegram(index == 0 ? "Conversation.PinnedPreviousMessage" : "Conversation.PinnedMessage")
        }
        if totalCount > 2, index != totalCount - 1 {
            return L10n.telegram("Conversation.PinnedMessage") + " #\(index + 1)"
        }
        return L10n.telegram("Conversation.PinnedMessage")
    }

    private static func previewText(for message: Message) -> String {
        let presentation = MessageContentPresentation.make(message)
        guard let formattedText = presentation.formattedText else {
            return ChatSummary.summary(for: message)
        }
        let spoilerRanges = formattedText.entities.compactMap { entity -> NSRange? in
            guard case .textEntityTypeSpoiler = entity.type else { return nil }
            return NSRange(location: entity.offset, length: entity.length)
        }
        guard !spoilerRanges.isEmpty else {
            return ChatSummary.summary(for: message)
        }
        let redacted = NSMutableString(string: formattedText.text)
        for range in spoilerRanges.sorted(by: { $0.location > $1.location })
            where NSMaxRange(range) <= redacted.length
        {
            redacted.replaceCharacters(in: range, with: "•••")
        }
        return redacted.length == 0 ? L10n.betterTG("Message.Spoiler") : String(redacted)
    }

    /// `index` counts from the oldest of `totalCount` pins.
    func configure(
        message: Message,
        index: Int = 0,
        totalCount: Int = 1,
        showsListButton: Bool = false,
        client: TDLibClient?,
        onOpen: @escaping () -> Void,
        onHide: @escaping () -> Void,
    ) {
        let preview = Self.previewText(for: message)
        let thumbnail = MessageReplyThumbnail.make(for: message.content)
        let content = RenderedContent(
            clientID: client?.id,
            chatID: message.chatId,
            messageID: message.id,
            preview: preview,
            file: thumbnail?.file,
            minithumbnailData: thumbnail?.minithumbnailData,
            isRound: thumbnail?.isRound ?? false,
            index: index,
            totalCount: totalCount,
        )
        if renderedContent == content {
            self.onOpen = onOpen
            self.onHide = onHide
            return
        }
        let animatesStripe = renderedContent?.totalCount == totalCount && window != nil
        prepareForReuse()
        renderedContent = content
        // ChatPinnedMessageTitlePanelNode: several pins swap the close button for the list button.
        actionButton.setImage(UIImage(systemName: showsListButton ? "list.bullet" : "xmark"), for: .normal)
        actionButton.accessibilityLabel = showsListButton
            ? L10n.telegram("Chat.PinnedListPreview.ShowAllMessages")
            : L10n.betterTG("Accessibility.HidePinnedMessage")
        titleLabel.text = Self.title(index: index, totalCount: totalCount)
        accentView.update(index: index, count: totalCount, animated: animatesStripe)
        bodyLabel.text = preview
        if let thumbnail {
            thumbnailWidthConstraint.constant = 35
            textLeadingConstraint.constant = 6
            thumbnailView.isHidden = false
            thumbnailView.layer.cornerRadius = thumbnail.isRound ? 17.5 : 2
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
        self.onOpen = onOpen
        self.onHide = onHide
        openControl.isAccessibilityElement = true
        openControl.accessibilityLabel = "\(titleLabel.text ?? ""), \(bodyLabel.text ?? "")"
        openControl.accessibilityHint = L10n.betterTG("Accessibility.OpenPinnedMessageHint")
        openControl.accessibilityTraits = [.button]
    }

    func prepareForReuse() {
        renderedContent = nil
        thumbnailView.cancel()
        thumbnailView.image = nil
        thumbnailView.isHidden = true
        thumbnailWidthConstraint.constant = 0
        textLeadingConstraint.constant = 0
        titleLabel.text = nil
        bodyLabel.text = nil
        onOpen = nil
        onHide = nil
        openControl.accessibilityLabel = nil
        openControl.accessibilityHint = nil
        actionButton.accessibilityLabel = nil
    }

    #if DEBUG
        func simulateOpenForProbe() {
            openPressed()
        }

        func simulateActionForProbe() {
            actionPressed()
        }
    #endif

    /// The gap that puts the text's top 17 pt below the title's, as Telegram does, at the current text size.
    private func textSpacing() -> CGFloat {
        let titleFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13, weight: .semibold),
            maximumPointSize: 15,
            compatibleWith: traitCollection,
        )
        let scale = max(1, traitCollection.displayScale)
        return max(0, 17 - (titleFont.lineHeight * scale).rounded(.up) / scale)
    }

    @objc private func contextPressed(_ gesture: ContextMenuPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onContextMenu?(gesture)
    }

    @objc private func openPressed() {
        onOpen?()
    }

    @objc private func actionPressed() {
        onHide?()
    }
}

// MARK: - PinnedNavigationStripeView

/// Telegram's AnimatedNavigationStripeNode: a 2 pt line of one segment per pin, the shown pin's in the accent and the
/// others at half strength, scrolled so the shown one stays in view; one pin is a single line 7 pt from the edges.
final class PinnedNavigationStripeView: UIView {
    private static let segmentSpacing = CGFloat(2)
    private static let verticalInset = CGFloat(7)
    private static let minSegmentHeight = CGFloat(8)

    private var index = 0
    private var count = 1
    private var segments = [CALayer]()

    #if DEBUG
        var probeSegmentFrames: [CGRect] {
            segments.map(\.frame)
        }
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutSegments()
        CATransaction.commit()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        layoutSegments()
    }

    func update(index: Int, count: Int, animated: Bool) {
        let count = max(1, count)
        let index = min(max(0, index), count - 1)
        guard index != self.index || count != self.count || segments.count != count else { return }
        self.index = index
        self.count = count
        while segments.count < count {
            let segment = CALayer()
            segment.cornerRadius = 1
            layer.addSublayer(segment)
            segments.append(segment)
        }
        while segments.count > count {
            segments.removeLast().removeFromSuperlayer()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.18)
        layoutSegments()
        CATransaction.commit()
    }

    /// AnimatedNavigationStripeNode.update's geometry.
    private func layoutSegments() {
        let height = bounds.height
        guard height > 0, !segments.isEmpty else { return }
        let spacing = Self.segmentSpacing
        let available = height - Self.verticalInset * 2
        let proposed = (available - spacing * CGFloat(count) + spacing) / CGFloat(count)
        let segmentHeight = max(proposed, Self.minSegmentHeight)
        let allHeight = CGFloat(count) * segmentHeight + CGFloat(max(0, count - 1)) * spacing
        var inset = Self.verticalInset
        if allHeight > available, allHeight - 2 <= available { inset -= 2 }
        let topHeight = CGFloat(index) * (segmentHeight + spacing)
        let bottomHeight = allHeight - topHeight - segmentHeight
        var offset = floor((height - segmentHeight) / 2)
        if offset - topHeight > inset { offset = topHeight + inset }
        if offset + segmentHeight + bottomHeight < height - inset {
            offset = height - inset - (segmentHeight + bottomHeight)
        }
        let accent = tintColor.resolvedColor(with: traitCollection)
        for (position, segment) in segments.enumerated() {
            segment.frame = CGRect(
                x: 0,
                y: offset + CGFloat(position - index) * (segmentHeight + spacing),
                width: 2,
                height: segmentHeight,
            )
            segment.backgroundColor = (position == index ? accent : accent.withAlphaComponent(0.5)).cgColor
        }
    }
}

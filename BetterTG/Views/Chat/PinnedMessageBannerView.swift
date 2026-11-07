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
        let inlineButtonTitle: String?
    }

    /// HeaderPanelContainerComponent: the 50 pt panel in a glass capsule 16 pt from the sides, with the bar's space
    /// under it.
    static let panelHeight = CGFloat(50)
    static let contentHeight = panelHeight + 8

    /// ChatPinnedMessageTitlePanelNode's context container: a long press previews the pinned list with its actions.
    var onContextMenu: ((ContextMenuPressGestureRecognizer) -> Void)? {
        didSet { contextGesture.isEnabled = onContextMenu != nil }
    }

    private let glassView: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let view = UIVisualEffectView(effect: effect)
        view.cornerConfiguration = .capsule()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let accentView = PinnedNavigationStripeView()
    private let thumbnailView = TDImageLoadingView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let textStack = UIStackView()
    private let openControl = UIControl()
    private let actionButton = UIButton(type: .system)
    /// ChatPinnedMessageTitlePanelNode's action button: the pin's single inline button as a 28 pt accent pill.
    private let inlineButton = UIButton(configuration: .filled())
    private var textTrailingToInlineButton: NSLayoutConstraint!
    private var thumbnailWidthConstraint: NSLayoutConstraint!
    private var textLeadingConstraint: NSLayoutConstraint!
    private var onOpen: (() -> Void)?
    private var onHide: (() -> Void)?
    private var onInlineButton: (() -> Void)?

    private lazy var contextGesture = ContextMenuPressGestureRecognizer(
        target: self,
        action: #selector(contextPressed(_:)),
    )
    private var renderedContent: RenderedContent?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        // The panel stands in interactive glass, its content inside it; no dividers, as Telegram's glass header has
        // none above its first panel.
        addSubview(glassView)
        let panel = glassView.contentView

        accentView.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(accentView)

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        panel.addSubview(thumbnailView)

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
        panel.addSubview(textStack)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitDisplayScale.self]) {
            (self: Self, _) in
            self.textStack.spacing = self.textSpacing()
        }

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.accessibilityIdentifier = "pinned-message-hide"
        actionButton.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
        panel.addSubview(actionButton)

        openControl.translatesAutoresizingMaskIntoConstraints = false
        openControl.accessibilityIdentifier = "pinned-message-open"
        openControl.addTarget(self, action: #selector(openPressed), for: .touchUpInside)
        panel.addSubview(openControl)

        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            let font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            attributes.font = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 15) } ?? font
            return attributes
        }
        inlineButton.configuration = configuration
        inlineButton.translatesAutoresizingMaskIntoConstraints = false
        inlineButton.accessibilityIdentifier = "pinned-message-inline-button"
        inlineButton.isHidden = true
        inlineButton.addTarget(self, action: #selector(inlineButtonPressed), for: .touchUpInside)
        panel.addSubview(inlineButton)
        contextGesture.isEnabled = false
        addGestureRecognizer(contextGesture)

        self.thumbnailWidthConstraint = thumbnailView.widthAnchor.constraint(equalToConstant: 0)
        self.textLeadingConstraint = textStack.leadingAnchor.constraint(
            equalTo: thumbnailView.trailingAnchor,
            constant: 0,
        )
        self.textTrailingToInlineButton = textStack.trailingAnchor.constraint(
            lessThanOrEqualTo: inlineButton.leadingAnchor,
            constant: -7,
        )
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            glassView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.heightAnchor.constraint(equalToConstant: Self.panelHeight),
            // ChatPinnedMessageTitlePanelNode's content 18 pt in from the capsule's sides.
            accentView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
            accentView.topAnchor.constraint(equalTo: panel.topAnchor),
            accentView.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            accentView.widthAnchor.constraint(equalToConstant: 2),
            thumbnailView.leadingAnchor.constraint(equalTo: accentView.trailingAnchor, constant: 6),
            thumbnailView.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            thumbnailView.heightAnchor.constraint(equalToConstant: 35),
            thumbnailWidthConstraint,
            // Telegram's ChatPinnedMessageTitlePanelNode places the title at y 6 and the text at y 23 in its 50 pt
            // panel. Both labels keep their own height: a stack stretched to the panel let UIKit pick which label
            // grew, so a rebuilt banner could draw both lines 4 pt lower.
            textStack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 6),
            {
                let constraint = textStack.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -2)
                constraint.priority = .defaultHigh
                return constraint
            }(),
            textLeadingConstraint,
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -6),
            // The close and list icons end about 21 pt from the capsule's end.
            actionButton.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -7),
            actionButton.topAnchor.constraint(equalTo: panel.topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: 44),
            openControl.topAnchor.constraint(equalTo: panel.topAnchor),
            openControl.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            openControl.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor),
            openControl.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            // The pill ends 11 pt from the capsule's end, its title at most 150 pt wide and the pill at least 40.
            inlineButton.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -11),
            inlineButton.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            inlineButton.heightAnchor.constraint(equalToConstant: 28),
            inlineButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            inlineButton.widthAnchor.constraint(lessThanOrEqualToConstant: 170),
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

    /// The pin's inline keyboard button the banner shows, when the keyboard is that one button.
    static func inlineButton(of message: Message) -> InlineKeyboardButton? {
        guard message.restrictionInfo?.restrictionReason.isEmpty != false,
              case .replyMarkupInlineKeyboard(let keyboard) = message.replyMarkup,
              keyboard.rows.count == 1, keyboard.rows[0].count == 1 else { return nil }
        return keyboard.rows[0][0]
    }

    /// ChatPinnedMessageTitlePanelNode's Stars payment: a Buy button whose title has ⭐️ shows Item List/PremiumIcon
    /// in its place, between spaces and a point up.
    private static func starsPaymentTitle(of message: Message) -> AttributedString? {
        guard let button = inlineButton(of: message), case .inlineKeyboardButtonTypeBuy = button.type,
              button.text.contains("⭐️"),
              let star = UIImage(named: "Message/PremiumStar")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        else { return nil }
        let font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        let rounded = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 15) } ?? font
        let parts = button.text.components(separatedBy: "⭐️")
        let result = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 {
                let attachment = NSTextAttachment(image: star)
                attachment.bounds = CGRect(
                    x: 0,
                    y: 1 + (rounded.capHeight - star.size.height) / 2,
                    width: star.size.width,
                    height: star.size.height,
                )
                result.append(NSAttributedString(string: " "))
                result.append(NSAttributedString(attachment: attachment))
                result.append(NSAttributedString(string: " "))
            }
            result.append(NSAttributedString(string: part))
        }
        result.addAttribute(.font, value: rounded, range: NSRange(location: 0, length: result.length))
        return AttributedString(result)
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

    /// `index` counts from the oldest of `totalCount` pins. With `onInlineButton` the pin's single inline button
    /// takes the place of the close and list buttons.
    func configure(
        message: Message,
        index: Int = 0,
        totalCount: Int = 1,
        showsListButton: Bool = false,
        client: TDLibClient?,
        onOpen: @escaping () -> Void,
        onHide: @escaping () -> Void,
        onInlineButton: (() -> Void)? = nil,
    ) {
        let inlineButtonTitle = onInlineButton == nil ? nil : Self.inlineButton(of: message)?.text
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
            inlineButtonTitle: inlineButtonTitle,
        )
        if renderedContent == content {
            self.onOpen = onOpen
            self.onHide = onHide
            self.onInlineButton = onInlineButton
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
        inlineButton.configuration?.title = inlineButtonTitle
        inlineButton.configuration?.attributedTitle = Self.starsPaymentTitle(of: message)
        inlineButton.accessibilityLabel = inlineButtonTitle
        inlineButton.isHidden = inlineButtonTitle == nil
        actionButton.isHidden = inlineButtonTitle != nil
        textTrailingToInlineButton.isActive = inlineButtonTitle != nil
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
        self.onInlineButton = onInlineButton
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
        onInlineButton = nil
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

    @objc private func inlineButtonPressed() {
        onInlineButton?()
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

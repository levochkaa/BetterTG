// MessageReactionView.swift

import Combine
import TDLibKit
import UIKit

// MARK: - MessageReactionStripView

final class MessageReactionStripView: UIView {
    private struct LayoutMetrics {
        let frames: [CGRect]
        let size: CGSize
    }

    override var intrinsicContentSize: CGSize {
        layoutMetrics(width: maximumLayoutWidth).size
    }

    /// The chips open who reacted on a long press, so the message's own press yields to them.
    private(set) var handlesLongPress = false

    private let itemSpacing = CGFloat(6)
    private let lineSpacing = CGFloat(6)
    private var buttons = [MessageReactionButton]()
    private var customEmojiTask: Task<Void, Never>?
    private var generation = UInt64.zero
    private var maximumLayoutWidth = CGFloat(260)
    private var playbackVisible = false
    private var horizontalAlignment = NSTextAlignment.left

    override init(frame: CGRect) {
        super.init(frame: frame)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let metrics = layoutMetrics(width: max(1, bounds.width))
        let frames = alignedFrames(metrics.frames, width: bounds.width)
        for (button, frame) in zip(buttons, frames) {
            button.frame = frame
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        layoutMetrics(width: resolvedWidth(size.width)).size
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority _: UILayoutPriority,
    ) -> CGSize {
        let width = horizontalFittingPriority == .required
            ? resolvedWidth(targetSize.width)
            : maximumLayoutWidth
        return layoutMetrics(width: width).size
    }

    /// The icon of the chip for `type`, where ReactionButtonsAsyncLayoutContainer's target view sits.
    func iconView(for type: ReactionType) -> UIView? {
        buttons.first { $0.representedType == type }?.iconView
    }

    @discardableResult func configure(
        reactions: MessageReactions?,
        unreadReactions: [UnreadReaction],
        client: TDLibClient,
        canAddReactions: Bool,
        mutationInFlight: Bool,
        horizontalAlignment: NSTextAlignment,
        onTap: @escaping (ReactionType) -> Void,
        onLongPress: ((ReactionType) -> Void)? = nil,
        tagLabel: ((ReactionType) -> String?)? = nil,
    ) -> Bool {
        prepareForReuse()
        let visibleReactions = MessageReactionStateReducer.visible(reactions)
        guard !visibleReactions.isEmpty else { return false }
        self.horizontalAlignment = horizontalAlignment
        handlesLongPress = onLongPress != nil
        let unreadTypes = Set(unreadReactions.map(\.type))
        var customButtons = [Int64: [MessageReactionButton]]()
        for reaction in visibleReactions {
            let button = MessageReactionButton()
            button.configure(
                reaction: reaction,
                unread: unreadTypes.contains(reaction.type),
                interactionEnabled: !mutationInFlight && (canAddReactions || reaction.isChosen),
                onTap: onTap,
                onLongPress: onLongPress,
                tag: tagLabel.map { label -> String? in label(reaction.type) },
            )
            button.setPlaybackVisible(playbackVisible)
            buttons.append(button)
            addSubview(button)
            if let customEmojiID = reaction.type.customEmojiID {
                customButtons[customEmojiID, default: []].append(button)
            }
        }
        if !customButtons.isEmpty {
            let currentGeneration = generation
            customEmojiTask = Task { [weak self] in
                let stickers = await CustomEmojiStickerRepository.shared.stickers(
                    for: Array(customButtons.keys),
                    client: client,
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.generation == currentGeneration else { return }
                    for (identifier, buttons) in customButtons {
                        guard let sticker = stickers[identifier] else { continue }
                        for button in buttons {
                            button.installCustomEmoji(sticker, client: client)
                            button.setPlaybackVisible(self.playbackVisible)
                        }
                    }
                }
            }
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        return true
    }

    func setMaximumLayoutWidth(_ width: CGFloat) {
        let width = max(1, width)
        guard abs(maximumLayoutWidth - width) > 0.5 else { return }
        maximumLayoutWidth = width
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func setPlaybackVisible(_ visible: Bool) {
        playbackVisible = visible
        for button in buttons {
            button.setPlaybackVisible(visible)
        }
    }

    func prepareForReuse() {
        generation &+= 1
        handlesLongPress = false
        customEmojiTask?.cancel()
        customEmojiTask = nil
        for button in buttons {
            button.prepareForReuse()
            button.removeFromSuperview()
        }
        buttons.removeAll()
        invalidateIntrinsicContentSize()
    }

    private func resolvedWidth(_ proposedWidth: CGFloat) -> CGFloat {
        guard proposedWidth.isFinite, proposedWidth > 0 else { return maximumLayoutWidth }
        return min(maximumLayoutWidth, proposedWidth)
    }

    private func layoutMetrics(width: CGFloat) -> LayoutMetrics {
        guard !buttons.isEmpty else {
            return LayoutMetrics(frames: [], size: .zero)
        }
        let availableWidth = max(1, width)
        var frames = [CGRect]()
        var x = CGFloat.zero
        var y = CGFloat.zero
        var maximumX = CGFloat.zero
        var lineHeight = CGFloat.zero
        for button in buttons {
            var size = button.sizeThatFits(CGSize(width: availableWidth, height: 30))
            size.width = min(availableWidth, max(44, size.width))
            size.height = 30
            if x > 0, x + size.width > availableWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            frames.append(frame)
            maximumX = max(maximumX, frame.maxX)
            lineHeight = max(lineHeight, size.height)
            x = frame.maxX + itemSpacing
        }
        return LayoutMetrics(
            frames: frames,
            size: CGSize(width: maximumX, height: y + lineHeight),
        )
    }

    private func alignedFrames(_ frames: [CGRect], width: CGFloat) -> [CGRect] {
        guard horizontalAlignment != .left else { return frames }
        var aligned = frames
        var rowStart = 0
        while rowStart < aligned.count {
            let rowY = aligned[rowStart].minY
            var rowEnd = rowStart + 1
            while rowEnd < aligned.count, abs(aligned[rowEnd].minY - rowY) < 0.5 {
                rowEnd += 1
            }
            let rowWidth = aligned[rowStart..<rowEnd].map(\.maxX).max() ?? 0
            let offset: CGFloat =
                if horizontalAlignment == .center {
                    max(0, (width - rowWidth) / 2)
                } else if horizontalAlignment == .right {
                    max(0, width - rowWidth)
                } else {
                    0
                }
            for index in rowStart..<rowEnd {
                aligned[index].origin.x += offset
            }
            rowStart = rowEnd
        }
        return aligned
    }
}

// MARK: - MessageReactionButton

private final class MessageReactionButton: UIControl {
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(
                withDuration: 0.12,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            ) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.9, y: 0.9)
                    : .identity
            }
        }
    }

    private let emojiLabel = UILabel()
    private let countLabel = UILabel()
    private let unreadDot = UIView()
    /// ReactionButtonComponent's tag: the label, nil without one; the whole value is nil for a reaction.
    private var tagTitle: String??
    private let tagMask = CALayer()
    private let tagShape = CAShapeLayer()
    private let tagHole = CAShapeLayer()
    private var emojiLeading: NSLayoutConstraint!
    private var countLeading: NSLayoutConstraint!
    private var customEmojiView: CustomEmojiInlineView?
    private var reactionType: ReactionType?
    private var onTap: ((ReactionType) -> Void)?

    private var onLongPress: ((ReactionType) -> Void)?
    private lazy var longPressRecognizer = UILongPressGestureRecognizer(
        target: self,
        action: #selector(longPressed(_:)),
    )
    private var playbackVisible = false

    var representedType: ReactionType? { reactionType }
    /// The custom emoji once it shows, else the emoji.
    var iconView: UIView {
        if let customEmojiView, customEmojiView.alpha > 0 { return customEmojiView }
        return emojiLabel
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 15
        layer.cornerCurve = .continuous
        layer.borderWidth = 1

        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        emojiLabel.font = .systemFont(ofSize: 18)
        emojiLabel.textAlignment = .center
        emojiLabel.isAccessibilityElement = false
        addSubview(emojiLabel)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        countLabel.isAccessibilityElement = false
        addSubview(countLabel)

        unreadDot.translatesAutoresizingMaskIntoConstraints = false
        unreadDot.backgroundColor = .systemBlue
        unreadDot.layer.cornerRadius = 2.5
        unreadDot.isAccessibilityElement = false
        addSubview(unreadDot)

        self.emojiLeading = emojiLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        self.countLeading = countLabel.leadingAnchor.constraint(equalTo: emojiLabel.trailingAnchor, constant: 3)
        tagHole.opacity = 0.5
        tagMask.addSublayer(tagShape)
        tagMask.addSublayer(tagHole)
        NSLayoutConstraint.activate([
            emojiLeading,
            emojiLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emojiLabel.widthAnchor.constraint(equalToConstant: 20),
            emojiLabel.heightAnchor.constraint(equalToConstant: 22),
            countLeading,
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            unreadDot.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            unreadDot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            unreadDot.widthAnchor.constraint(equalToConstant: 5),
            unreadDot.heightAnchor.constraint(equalToConstant: 5),
        ])
        // A tap recognizer rather than touchUpInside: in the chat's history the control saw the touch end inside
        // without sending its action.
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        longPressRecognizer.minimumPressDuration = 0.4
        longPressRecognizer.isEnabled = false
        addGestureRecognizer(longPressRecognizer)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_: CGSize) -> CGSize {
        let countWidth = ceil(countLabel.sizeThatFits(
            CGSize(width: 100, height: 22),
        )
        .width)
        if let tagTitle {
            // ReactionButtonComponent's tag: 20 pt for the image and 11 pt each side, one more without a label,
            // otherwise 2 pt and the label and 5 pt more.
            return CGSize(width: tagTitle == nil ? 43 : 20 + 22 + 2 + countWidth + 5, height: 30)
        }
        return CGSize(width: max(44, 8 + 20 + 3 + countWidth + 8), height: 30)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard tagTitle != nil else { return }
        tagMask.frame = bounds
        tagShape.frame = bounds
        tagHole.frame = bounds
        tagShape.path = Self.tagPath(width: bounds.width, height: bounds.height)
        // The ring at the tip shows through at half strength.
        let hole = UIBezierPath(ovalIn: CGRect(x: bounds.width - 12, y: (bounds.height - 6) / 2, width: 6, height: 6))
        let shape = UIBezierPath(cgPath: Self.tagPath(width: bounds.width, height: bounds.height))
        shape.append(hole)
        shape.usesEvenOddFillRule = true
        tagShape.path = shape.cgPath
        tagShape.fillRule = .evenOdd
        tagHole.path = hole.cgPath
    }

    /// MessageTagBackground.svg (23 × 30) stretched after its 8 pt left cap: rounded on the left, a point on the
    /// right.
    private static func tagPath(width: CGFloat, height _: CGFloat) -> CGPath {
        let dx = max(0, width - 23)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: 6))
        path.addCurve(
            to: CGPoint(x: 6, y: 0),
            controlPoint1: CGPoint(x: 0, y: 2.686),
            controlPoint2: CGPoint(x: 2.686, y: 0),
        )
        path.addLine(to: CGPoint(x: 8.155 + dx, y: 0))
        path.addCurve(
            to: CGPoint(x: 14.402 + dx, y: 3.002),
            controlPoint1: CGPoint(x: 10.585 + dx, y: 0),
            controlPoint2: CGPoint(x: 12.884 + dx, y: 1.105),
        )
        path.addLine(to: CGPoint(x: 22.001 + dx, y: 12.501))
        path.addCurve(
            to: CGPoint(x: 22.001 + dx, y: 17.499),
            controlPoint1: CGPoint(x: 23.17 + dx, y: 13.962),
            controlPoint2: CGPoint(x: 23.17 + dx, y: 16.038),
        )
        path.addLine(to: CGPoint(x: 14.402 + dx, y: 26.998))
        path.addCurve(
            to: CGPoint(x: 8.155 + dx, y: 30),
            controlPoint1: CGPoint(x: 12.884 + dx, y: 28.895),
            controlPoint2: CGPoint(x: 10.585 + dx, y: 30),
        )
        path.addLine(to: CGPoint(x: 6, y: 30))
        path.addCurve(
            to: CGPoint(x: 0, y: 24),
            controlPoint1: CGPoint(x: 2.686, y: 30),
            controlPoint2: CGPoint(x: 0, y: 27.314),
        )
        path.close()
        return path.cgPath
    }

    func configure(
        reaction: MessageReaction,
        unread: Bool,
        interactionEnabled: Bool,
        onTap: @escaping (ReactionType) -> Void,
        onLongPress: ((ReactionType) -> Void)? = nil,
        tag: String?? = nil,
    ) {
        prepareForReuse()
        reactionType = reaction.type
        self.onTap = onTap
        self.onLongPress = onLongPress
        tagTitle = tag
        longPressRecognizer.isEnabled = onLongPress != nil
        emojiLabel.text = reaction.type.standardEmoji ?? "◇"
        countLabel.text = compactNumericCountString(reaction.totalCount)
        unreadDot.isHidden = !unread
        // Saved Messages' tags: the tag shape, the image 6 pt in, and the label in place of the count.
        let isTag = tagTitle != nil
        emojiLeading.constant = isTag ? 6 : 8
        // The label starts 32 pt in (textOrigin).
        countLeading.constant = isTag ? 6 : 3
        layer.cornerRadius = isTag ? 0 : 15
        layer.borderWidth = isTag ? 0 : 1
        layer.mask = isTag ? tagMask : nil
        if let tagTitle {
            countLabel.text = tagTitle
            countLabel.isHidden = tagTitle == nil
            unreadDot.isHidden = true
            setNeedsLayout()
        } else {
            countLabel.isHidden = false
        }
        isEnabled = interactionEnabled
        alpha = interactionEnabled ? 1 : 0.72
        backgroundColor = reaction.isChosen
            ? UIColor.systemBlue.withAlphaComponent(0.16)
            : .tertiarySystemFill
        layer.borderColor = (
            reaction.isChosen
                ? UIColor.systemBlue.withAlphaComponent(0.65)
                : UIColor.separator.withAlphaComponent(0.35),
        ).cgColor
        isAccessibilityElement = true
        accessibilityIdentifier = "message-reaction-\(reaction.type.accessibilityIdentifierComponent)"
        accessibilityLabel = "\(reaction.type.accessibilityName), \(L10n.telegramPlural("Chat.ContextReactionCount", count: reaction.totalCount))"
        accessibilityValue = [
            reaction.isChosen ? L10n.telegram("VoiceOver.Chat.Selected") : nil,
            unread ? L10n.telegram("DialogList.Unread") : nil,
        ]
            .compactMap(\.self)
            .joined(separator: ", ")
        accessibilityTraits = reaction.isChosen ? [.button, .selected] : [.button]
    }

    func installCustomEmoji(_ sticker: Sticker, client: TDLibClient) {
        customEmojiView?.prepareForReuse()
        customEmojiView?.removeFromSuperview()
        let view = CustomEmojiInlineView()
        // ReactionButtonListComponent: reactions stop animating with Emoji Animations off.
        view.energySaving = EnergySavingRole(item: .loopEmoji, whenOff: .still)
        // ReactionButtonComponent's accentTint: a template reaction takes the count's colour.
        view.templateColor = countLabel.textColor
        view.repaintsAccentPacks = true
        customEmojiView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        insertSubview(view, aboveSubview: emojiLabel)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: emojiLabel.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: emojiLabel.centerYAnchor),
            view.widthAnchor.constraint(equalToConstant: 20),
            view.heightAnchor.constraint(equalToConstant: 20),
        ])
        view.configure(sticker: sticker, client: client)
        view.onFirstFrameReady = { [weak self, weak view] in
            guard let self, let view, customEmojiView === view else { return }
            emojiLabel.isHidden = true
            view.alpha = 1
        }
        view.setPlaybackVisible(playbackVisible)
    }

    func setPlaybackVisible(_ visible: Bool) {
        playbackVisible = visible
        customEmojiView?.setPlaybackVisible(visible)
    }

    func prepareForReuse() {
        customEmojiView?.prepareForReuse()
        customEmojiView?.removeFromSuperview()
        customEmojiView = nil
        emojiLabel.isHidden = false
        emojiLabel.text = nil
        countLabel.text = nil
        reactionType = nil
        onTap = nil
        onLongPress = nil
        longPressRecognizer.isEnabled = false
    }

    @objc private func tapped() {
        guard let reactionType else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
        onTap?(reactionType)
    }

    /// ChatMessageReactionsNode: a long press on a reaction lists who chose it.
    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let reactionType, let onLongPress else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onLongPress(reactionType)
    }
}

// MARK: - SavedMessagesTagsStore

/// getSavedMessagesTags and updateSavedMessagesTags for the client: the labels the account gave its Saved Messages
/// tags, which the tags show in place of a count.
@MainActor final class SavedMessagesTagsStore {
    static let shared = SavedMessagesTagsStore()

    let changes = PassthroughSubject<Void, Never>()

    private var clientID: Int32?
    private var labels = [ReactionType: String]()
    private var isLoading = false

    func receive(_ update: TDNativeUpdateSavedMessagesTags, clientID: Int32) {
        guard update.savedMessagesTopicId == 0 else { return }
        apply(update.tags.tags, clientID: clientID)
    }

    /// The tag's label, loading the labels the first time the client asks.
    func label(for type: ReactionType, client: TDLibClient) -> String? {
        if clientID != client.id, !isLoading {
            isLoading = true
            Task { [weak self] in
                let tags = try? await client.send(TDNativeRequests.getSavedMessagesTags(savedMessagesTopicId: 0))
                guard let self else { return }
                isLoading = false
                if let tags { apply(tags.tags, clientID: client.id) }
            }
        }
        guard clientID == client.id, let label = labels[type], !label.isEmpty else { return nil }
        return label
    }

    private func apply(_ tags: [TDNativeSavedMessagesTag], clientID: Int32) {
        let updated = Dictionary(tags.map { ($0.tag, $0.label) }, uniquingKeysWith: { first, _ in first })
        guard updated != labels || self.clientID != clientID else { return }
        self.clientID = clientID
        labels = updated
        changes.send()
    }
}

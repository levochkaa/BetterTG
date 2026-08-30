// MessageView.swift

import TDLibKitDynamic
import UIKit

// MARK: - TelegramSwipeToReplyRecognizer

private final class TelegramSwipeToReplyRecognizer: UIPanGestureRecognizer {
    // MARK: Internal

    var shouldBegin: (() -> Bool)?

    // MARK: Private

    private var firstLocation = CGPoint.zero
    private var validatedGesture = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        maximumNumberOfTouches = 1
        cancelsTouchesInView = true
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func reset() {
        super.reset()
        validatedGesture = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard shouldBegin?() != false, let touch = touches.first else {
            state = .failed
            return
        }
        firstLocation = touch.location(in: view)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: view)
        let translation = CGPoint(x: location.x - firstLocation.x, y: location.y - firstLocation.y)
        let horizontalDistance = abs(translation.x)
        let verticalDistance = abs(translation.y)

        if !validatedGesture {
            if translation.x > 0 {
                state = .failed
            } else if verticalDistance > 2, verticalDistance > horizontalDistance * 2 {
                state = .failed
            } else if horizontalDistance > 8, verticalDistance * 2 < horizontalDistance {
                validatedGesture = true
            }
        }

        if validatedGesture {
            super.touchesMoved(touches, with: event)
        }
    }
}

// MARK: - SwipeToReplyIndicatorView

private final class SwipeToReplyIndicatorView: UIView {
    // MARK: Private

    private let iconView = UIImageView()
    private let progressLayer = CAShapeLayer()
    private var thresholdPulseView: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 16.5
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: "arrowshape.turn.up.left.fill")
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        iconView.tintColor = .systemBlue
        iconView.contentMode = .center
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.systemBlue.cgColor
        progressLayer.lineWidth = 2
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        layer.addSublayer(progressLayer)
        update(progress: 0)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func layoutSubviews() {
        super.layoutSubviews()
        progressLayer.frame = bounds
        progressLayer.path = UIBezierPath(
            ovalIn: bounds.insetBy(dx: progressLayer.lineWidth / 2, dy: progressLayer.lineWidth / 2),
        ).cgPath
    }

    func update(progress: CGFloat) {
        let progress = min(max(progress, 0), 1)
        let foregroundProgress = min(1, progress * 1.2)
        alpha = foregroundProgress
        transform = CGAffineTransform(scaleX: 0.65 + foregroundProgress * 0.35, y: 0.65 + foregroundProgress * 0.35)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = progress
        CATransaction.commit()
    }

    func playThresholdAnimation() {
        thresholdPulseView?.layer.removeAllAnimations()
        thresholdPulseView?.removeFromSuperview()

        let pulseView = UIView(frame: bounds)
        pulseView.isUserInteractionEnabled = false
        pulseView.backgroundColor = backgroundColor
        pulseView.layer.cornerRadius = bounds.height / 2
        pulseView.layer.cornerCurve = .continuous
        pulseView.layer.borderColor = UIColor.systemBlue.cgColor
        pulseView.layer.borderWidth = 2
        pulseView.alpha = 0.9
        insertSubview(pulseView, at: 0)
        thresholdPulseView = pulseView

        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
        ) {
            pulseView.transform = CGAffineTransform(scaleX: 2.15, y: 2.15)
            pulseView.alpha = 0
        } completion: { [weak self, weak pulseView] _ in
            guard let pulseView else { return }
            if self?.thresholdPulseView === pulseView {
                self?.thresholdPulseView = nil
            }
            pulseView.removeFromSuperview()
        }
    }
}

// MARK: - MessageCell

final class MessageCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    // MARK: Internal

    static let reuseIdentifier = "MessageCell"

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let rowStack = UIStackView()
    private let bubbleContainerView = TelegramContextMenuExtractableView()
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
    private let swipeToReplyIndicator = SwipeToReplyIndicatorView()
    private var bubbleWidthConstraint: NSLayoutConstraint!
    private var bubbleContentNeedsMeasurement = true
    private var measuredCellWidth = CGFloat.zero
    private var replyTargetMessageID: Int64?
    private var onSwipeToReply: (() -> Void)?
    private var onMediaTap: (([Message], Int64) -> Void)?
    private var swipeReplyThreshold: CGFloat = 45
    private var swipeReplyFeedbackArmed = true
    private var swipeReplyFeedback: UIImpactFeedbackGenerator?
    private weak var suspendedHistoryPanGesture: UIPanGestureRecognizer?
    private lazy var swipeToReplyRecognizer = TelegramSwipeToReplyRecognizer(
        target: self,
        action: #selector(swipeToReply(_:)),
    )

    var contextPreviewView: UIView { bubbleContainerView }

    private var bubbleView: UIView { bubbleContainerView.extractedContentView }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
        configureViews()
        configureConstraints()
        configureSwipeToReply()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resumeHistoryScrolling()
        avatarView.prepareForReuse()
        mediaView.prepareForReuse()
        forwardedLabel.isHidden = true
        replyView.isHidden = true
        textView.isHidden = true
        mediaView.isHidden = true
        timestampLabel.isHidden = true
        mediaTimestampLabel.isHidden = true
        replyTargetMessageID = nil
        onSwipeToReply = nil
        onMediaTap = nil
        swipeToReplyRecognizer.isEnabled = false
        resetSwipeToReply(animated: false)
        bubbleContentNeedsMeasurement = true
    }

    override func layoutSubviews() {
        updateBubbleWidth(for: bounds.width)
        super.layoutSubviews()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            resumeHistoryScrolling()
        }
    }

    func replyMessageID(at point: CGPoint) -> Int64? {
        guard let replyTargetMessageID, !replyView.isHidden else { return nil }
        let replyFrame = replyView.convert(replyView.bounds, to: contentView).insetBy(dx: -4, dy: -4)
        return replyFrame.contains(point) ? replyTargetMessageID : nil
    }

    func configure(
        message: CustomMessage,
        chat: CustomChat,
        highlighted: Bool,
        onSwipeToReply: (() -> Void)?,
        onMediaTap: @escaping ([Message], Int64) -> Void,
    ) {
        self.onSwipeToReply = onSwipeToReply
        self.onMediaTap = onMediaTap
        swipeReplyThreshold = message.message.isOutgoing ? 60 : 45
        swipeToReplyRecognizer.isEnabled = onSwipeToReply != nil
        configureAlignment(outgoing: message.message.isOutgoing, showsAvatar: chat.shouldShowProfileImage)

        bubbleView.backgroundColor = highlighted ? .messageHighlight : .secondarySystemBackground
        forwardedLabel.isHidden = message.forwardedFrom == nil
        forwardedLabel.text = message.forwardedFrom.map { "Forwarded from \($0)" }

        if let reply = message.replyToMessage {
            replyView.isHidden = false
            replyTargetMessageID = reply.id
            replyView.configure(
                title: message.replyUser?.firstName ?? "Reply",
                message: reply,
                onTap: {},
            )
        } else {
            replyView.isHidden = true
            replyTargetMessageID = nil
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
            textView.configure(
                formattedText: formatted,
                statusText: timestampText,
                statusColor: timestampColor,
                maximumWidth: maximumTextWidth(for: bounds.width),
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
                placeholder: sender.telegramAvatarPlaceholder,
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

        bubbleContentNeedsMeasurement = true
        updateBubbleWidth(for: bounds.width)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer,
    ) -> Bool {
        guard gestureRecognizer === swipeToReplyRecognizer || otherGestureRecognizer === swipeToReplyRecognizer else {
            return false
        }
        return gestureRecognizer.view is UIScrollView || otherGestureRecognizer.view is UIScrollView
    }

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

    private func configureSwipeToReply() {
        swipeToReplyIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.insertSubview(swipeToReplyIndicator, belowSubview: rowStack)
        NSLayoutConstraint.activate([
            swipeToReplyIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            swipeToReplyIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            swipeToReplyIndicator.widthAnchor.constraint(equalToConstant: 33),
            swipeToReplyIndicator.heightAnchor.constraint(equalToConstant: 33),
        ])

        swipeToReplyRecognizer.shouldBegin = { [weak self] in
            self?.onSwipeToReply != nil
        }
        swipeToReplyRecognizer.delegate = self
        swipeToReplyRecognizer.isEnabled = false
        contentView.addGestureRecognizer(swipeToReplyRecognizer)
    }

    @objc private func swipeToReply(_ recognizer: TelegramSwipeToReplyRecognizer) {
        switch recognizer.state {
        case .began:
            suspendHistoryScrolling()
            swipeReplyFeedbackArmed = true
            let feedback = UIImpactFeedbackGenerator(style: .heavy)
            feedback.prepare()
            swipeReplyFeedback = feedback
        case .changed:
            let rawTranslation = recognizer.translation(in: contentView).x
            let distance = rubberBandedSwipeDistance(max(0, -rawTranslation), threshold: swipeReplyThreshold)
            rowStack.transform = CGAffineTransform(translationX: -distance, y: 0)
            let progress = distance / swipeReplyThreshold
            swipeToReplyIndicator.update(progress: progress)
            if progress <= 0.82, !swipeReplyFeedbackArmed {
                swipeReplyFeedbackArmed = true
                swipeReplyFeedback?.prepare()
            } else if progress >= 1, swipeReplyFeedbackArmed {
                swipeReplyFeedbackArmed = false
                swipeToReplyIndicator.playThresholdAnimation()
                swipeReplyFeedback?.impactOccurred(intensity: 0.8)
            }
        case .cancelled, .ended, .failed:
            let shouldReply = recognizer.state == .ended
                && recognizer.translation(in: contentView).x < -swipeReplyThreshold
            swipeReplyFeedback = nil
            resumeHistoryScrolling()
            resetSwipeToReply(animated: true)
            if shouldReply {
                onSwipeToReply?()
            }
        default:
            break
        }
    }

    private func rubberBandedSwipeDistance(_ distance: CGFloat, threshold: CGFloat) -> CGFloat {
        guard distance > threshold else { return distance }
        let excess = distance - threshold
        let range: CGFloat = 100
        let coefficient: CGFloat = 0.4
        return min(180, threshold + (1 - 1 / (excess * coefficient / range + 1)) * range)
    }

    private func resetSwipeToReply(animated: Bool) {
        let changes = {
            self.rowStack.transform = .identity
            self.swipeToReplyIndicator.update(progress: 0)
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes,
        )
    }

    private func suspendHistoryScrolling() {
        guard suspendedHistoryPanGesture == nil else { return }
        var ancestor = superview
        while let view = ancestor {
            if let collectionView = view as? UICollectionView {
                let panGesture = collectionView.panGestureRecognizer
                guard panGesture.isEnabled else { return }
                suspendedHistoryPanGesture = panGesture
                panGesture.isEnabled = false
                return
            }
            ancestor = view.superview
        }
    }

    private func resumeHistoryScrolling() {
        suspendedHistoryPanGesture?.isEnabled = true
        suspendedHistoryPanGesture = nil
    }

    private func configureConstraints() {
        let maxBubbleWidth = bubbleContainerView.widthAnchor.constraint(
            lessThanOrEqualTo: contentView.widthAnchor,
            multiplier: 0.82,
        )
        maxBubbleWidth.priority = .required
        bubbleWidthConstraint = bubbleContainerView.widthAnchor.constraint(equalToConstant: 16)
        bubbleWidthConstraint.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            rowStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            maxBubbleWidth,
            bubbleWidthConstraint,
            bubbleStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 6),
            bubbleStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
            bubbleStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
            bubbleStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -5),
        ])
    }

    private func configureAlignment(outgoing: Bool, showsAvatar: Bool) {
        for arrangedSubview in rowStack.arrangedSubviews {
            rowStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
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

    private func updateBubbleWidth(for cellWidth: CGFloat) {
        guard cellWidth > 0 else { return }
        guard bubbleContentNeedsMeasurement || abs(measuredCellWidth - cellWidth) > 0.5 else { return }
        let maximumBubbleWidth = floor(cellWidth * 0.82)
        let maximumContentWidth = max(1, maximumBubbleWidth - 16)
        textView.setMaximumLayoutWidth(maximumContentWidth)

        let fittingSize = CGSize(
            width: maximumContentWidth,
            height: UIView.layoutFittingCompressedSize.height,
        )
        var preferredContentWidth = CGFloat.zero
        for view in bubbleStack.arrangedSubviews where !view.isHidden {
            let width =
                if view === textView {
                    textView.intrinsicContentSize.width
                } else {
                    view.systemLayoutSizeFitting(
                        fittingSize,
                        withHorizontalFittingPriority: .fittingSizeLevel,
                        verticalFittingPriority: .fittingSizeLevel,
                    )
                    .width
                }
            preferredContentWidth = max(preferredContentWidth, width)
        }
        let preferredBubbleWidth = min(maximumBubbleWidth, ceil(preferredContentWidth) + 16)
        if abs(bubbleWidthConstraint.constant - preferredBubbleWidth) > 0.5 {
            bubbleWidthConstraint.constant = preferredBubbleWidth
        }
        measuredCellWidth = cellWidth
        bubbleContentNeedsMeasurement = false
    }

    private func maximumTextWidth(for cellWidth: CGFloat) -> CGFloat {
        guard cellWidth > 0 else { return Utils.maxMessageContentWidth }
        return max(1, floor(cellWidth * 0.82) - 16)
    }
}

// MARK: - ReplySnippetView

final class ReplySnippetView: UIControl {
    // MARK: Private

    private let accentView = UIView()
    private let stack = UIStackView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        accentView.translatesAutoresizingMaskIntoConstraints = false
        accentView.backgroundColor = .systemBlue
        accentView.layer.cornerRadius = 1.5
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 1
        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .semibold),
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .systemBlue
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        textLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .regular),
        )
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.textColor = .secondaryLabel
        textLabel.numberOfLines = 1
        textLabel.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(textLabel)
        addSubview(accentView)
        addSubview(stack)
        NSLayoutConstraint.activate([
            accentView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            accentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            accentView.widthAnchor.constraint(equalToConstant: 3),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.leadingAnchor.constraint(equalTo: accentView.trailingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

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
        if !album.isEmpty {
            return true
        }
        return switch message.content {
        case .messageAnimation, .messagePhoto, .messageSticker, .messageVideo:
            true
        default:
            false
        }
    }
}

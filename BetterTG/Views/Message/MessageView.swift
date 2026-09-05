// MessageView.swift

import Combine
import TDLibKit
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

    func reset() {
        layer.removeAllAnimations()
        progressLayer.removeAllAnimations()
        thresholdPulseView?.layer.removeAllAnimations()
        thresholdPulseView?.removeFromSuperview()
        thresholdPulseView = nil
        update(progress: 0)
    }
}

// MARK: - MessageCell

final class MessageCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    // MARK: Internal

    static let reuseIdentifier = "MessageCell"

    // MARK: Private

    private static let timelineContentTransform = CGAffineTransform(scaleX: 1, y: -1)

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    #if DEBUG
        private(set) var probeReuseCount = 0
        var probeSelectionTouchBindingID: UUID? { selectionTouchBindingID }

        var probeUnavailableResourcesAreReset: Bool {
            onSwipeToReply == nil && onMediaTap == nil && onSelectionToggle == nil && onSelfSizingHeightChange == nil
                && refreshSpoilerAccessibility == nil && spoilerSubscriptions.isEmpty && textSpoilers.states.isEmpty
                && representedGalleryMessageIDs.isEmpty && suspendedHistoryPanGesture == nil
                && !swipeToReplyRecognizer.isEnabled && !selectionActive && !selectionOutgoing && !selectionCentered
                && avatarView.isHidden && forwardView.isHidden && replyView.isHidden && textView.isHidden
                && mediaView.isHidden && structuredContentView.isHidden && reactionView.isHidden
                && timestampLabel.text == nil && mediaTimestampLabel.text == nil
                && textView.attributedText.length == 0 && bubbleView.isHidden
                && selectionControl.isHidden && selectionIndicatorView.isHidden
                && rowStack.transform == .identity && selectionTouchBindingID == nil
                && contentView.alpha == 1 && contentView.transform == Self.timelineContentTransform
        }
    #endif

    var onSelfSizingHeightChange: (() -> Void)?

    private(set) var actionBindingID: UUID?
    private(set) var timelineRowID: UUID?
    private(set) var timelineDisplayedID: DisplayedMessageID?
    #if DEBUG
        private(set) var probeMediaAction: (([Message], Int64) -> Void)?
    #endif

    private var selectionTouchBindingID: UUID?
    private let rowStack = UIStackView()
    private let bubbleContainerView = TelegramContextMenuExtractableView()
    private let bubbleStack = UIStackView()
    private let avatarView = ProfileAvatarView()
    private let forwardView = ForwardHeaderView()
    private let replyView = ReplySnippetView()
    private let mediaView = MessageMediaView()
    private let structuredContentView = MessageStructuredContentView()
    private let textView = MessageTextContentView()
    private let textSpoilers = MessageTextSpoilerStore()
    private var spoilerSubscriptions = Set<AnyCancellable>()
    private var refreshSpoilerAccessibility: (() -> Void)?
    private let reactionView = MessageReactionStripView()
    private let timestampLabel = UILabel()
    private let mediaTimestampLabel = UILabel()
    private let leadingSpacer = UIView()
    private let trailingSpacer = UIView()
    private let swipeToReplyIndicator = SwipeToReplyIndicatorView()
    private let selectionControl = UIControl()
    private let selectionIndicatorView = MessageSelectionIndicatorView()
    private var bubbleWidthConstraint: NSLayoutConstraint!
    private lazy var bubbleTopConstraint = bubbleStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 6)
    private lazy var bubbleLeadingConstraint = bubbleStack.leadingAnchor.constraint(
        equalTo: bubbleView.leadingAnchor,
        constant: 8,
    )
    private lazy var bubbleTrailingConstraint = bubbleStack.trailingAnchor.constraint(
        equalTo: bubbleView.trailingAnchor,
        constant: -8,
    )
    private lazy var bubbleBottomConstraint = bubbleStack.bottomAnchor.constraint(
        equalTo: bubbleView.bottomAnchor,
        constant: -5,
    )
    private var bubbleContentNeedsMeasurement = true
    private var measuredCellWidth = CGFloat.zero
    private var centeredSpacerConstraint: NSLayoutConstraint?
    private var swipeReplyBindingID: UUID?
    private var onSwipeToReply: (() -> Void)?
    private var onMediaTap: (([Message], Int64) -> Void)?
    private var onSelectionToggle: (() -> Void)?
    private var representedGalleryMessageIDs = Set<Int64>()
    private var mediaTransitionGeneration = UUID()
    private var swipeReplyThreshold: CGFloat = 45
    private var swipeReplyFeedbackArmed = true
    private var swipeReplyFeedback: UIImpactFeedbackGenerator?
    private weak var suspendedHistoryPanGesture: UIPanGestureRecognizer?
    private var selectionActive = false
    private var selectionOutgoing = false
    private var selectionCentered = false
    private lazy var swipeToReplyRecognizer = TelegramSwipeToReplyRecognizer(
        target: self,
        action: #selector(swipeToReply(_:)),
    )

    var contextPreviewView: UIView { bubbleContainerView }

    private var bubbleView: UIView { bubbleContainerView.extractedContentView }

    private var selectionRowTransform: CGAffineTransform {
        selectionActive && !selectionOutgoing && !selectionCentered
            ? CGAffineTransform(translationX: 42, y: 0)
            : .identity
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.transform = Self.timelineContentTransform
        configureViews()
        configureConstraints()
        configureSwipeToReply()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        #if DEBUG
            probeReuseCount += 1
        #endif
        resetUnavailableContent()
    }

    override func layoutSubviews() {
        updateBubbleWidth(for: bounds.width)
        super.layoutSubviews()
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes,
    ) -> UICollectionViewLayoutAttributes {
        let fitted = super.preferredLayoutAttributesFitting(layoutAttributes)
        if window != nil, abs(fitted.size.height - layoutAttributes.size.height) > 0.5 {
            onSelfSizingHeightChange?()
        }
        return fitted
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            selectionTouchBindingID = nil
            resumeHistoryScrolling()
        }
    }

    /// Collection layout attributes own the cell's alpha/transform. Keep deletion
    /// inside that boundary while retaining the inverted timeline's content flip.
    func setDeletionPresentation(alpha: CGFloat, transform: CGAffineTransform) {
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        contentView.alpha = alpha
        contentView.transform = Self.timelineContentTransform.concatenating(transform)
    }

    /// UIKit can reconfigure the current cell without calling prepareForReuse.
    func resetUnavailableContent() {
        actionBindingID = nil
        timelineRowID = nil
        timelineDisplayedID = nil
        selectionTouchBindingID = nil
        swipeReplyBindingID = nil
        #if DEBUG
            probeMediaAction = nil
        #endif
        layer.removeAllAnimations()
        rowStack.layer.removeAllAnimations()
        bubbleContainerView.layer.removeAllAnimations()
        bubbleContainerView.transform = .identity
        bubbleContainerView.alpha = 1
        if bubbleView.superview === bubbleContainerView {
            bubbleView.layer.removeAllAnimations()
            bubbleView.transform = .identity
            bubbleView.alpha = 1
        }
        swipeToReplyIndicator.reset()
        selectionIndicatorView.layer.removeAllAnimations()
        alpha = 1
        transform = .identity
        resetDeletionPresentation()
        contentView.isHidden = false
        isUserInteractionEnabled = true
        isAccessibilityElement = false
        accessibilityElementsHidden = false
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityHint = nil
        accessibilityIdentifier = nil
        accessibilityTraits = []
        resumeHistoryScrolling()
        avatarView.prepareForReuse()
        avatarView.isHidden = true
        mediaView.prepareForReuse()
        structuredContentView.prepareForReuse()
        textView.prepareForReuse()
        spoilerSubscriptions.removeAll()
        refreshSpoilerAccessibility = nil
        textSpoilers.reset()
        reactionView.prepareForReuse()
        forwardView.prepareForReuse()
        replyView.prepareForReuse()
        forwardView.isHidden = true
        replyView.isHidden = true
        textView.isHidden = true
        mediaView.isHidden = true
        structuredContentView.isHidden = true
        reactionView.isHidden = true
        timestampLabel.isHidden = true
        timestampLabel.text = nil
        mediaTimestampLabel.isHidden = true
        mediaTimestampLabel.text = nil
        bubbleView.backgroundColor = .clear
        // Context menus may currently own this view outside the cell hierarchy.
        // Conceal it without stealing the menu's view or return constraints.
        bubbleView.isHidden = true
        onSwipeToReply = nil
        onMediaTap = nil
        onSelectionToggle = nil
        onSelfSizingHeightChange = nil
        representedGalleryMessageIDs.removeAll()
        mediaTransitionGeneration = UUID()
        swipeToReplyRecognizer.isEnabled = false
        swipeReplyFeedback = nil
        swipeReplyFeedbackArmed = true
        selectionActive = false
        selectionOutgoing = false
        selectionCentered = false
        selectionControl.isHidden = true
        selectionIndicatorView.isHidden = true
        selectionIndicatorView.alpha = 0
        selectionIndicatorView.transform = .identity
        selectionIndicatorView.setSelected(false)
        accessibilityTraits.remove(.selected)
        accessibilityCustomActions = nil
        resetSwipeToReply(animated: false)
        bubbleContentNeedsMeasurement = true
        measuredCellWidth = 0
    }

    func setMediaPlaybackVisible(_ isVisible: Bool, allowsInlineVideoPlayback: Bool = true) {
        mediaView.setPlaybackVisible(
            isVisible,
            allowsInlineVideoPlayback: allowsInlineVideoPlayback,
        )
        structuredContentView.setPlaybackVisible(isVisible)
        textView.setCustomEmojiPlaybackVisible(isVisible)
        reactionView.setPlaybackVisible(isVisible)
    }

    func highlightQuote(_ quote: MessageQuoteHighlight) {
        textView.highlightQuote(position: quote.position, length: quote.length)
    }

    @discardableResult func restoreInlineVideoPlaybackOwner(_ owner: GalleryVideoPlaybackOwner) -> Bool {
        mediaView.restoreInlineVideoPlaybackOwner(owner)
    }

    func inlineVideoPlaybackCandidates(in coordinateSpace: UIView) -> [(Int64, CGRect)] {
        mediaView.inlineVideoPlaybackCandidates(in: coordinateSpace)
    }

    func galleryTransitionTarget(for messageID: Int64) -> MediaGalleryTransitionTarget? {
        guard representedGalleryMessageIDs.contains(messageID),
              !mediaView.isHidden,
              mediaView.window != nil
        else { return nil }
        let generation = mediaTransitionGeneration
        let contentGeneration = mediaView.transitionGeneration
        guard let sourceView = mediaView.galleryTransitionSourceView(for: messageID) else { return nil }
        return MediaGalleryTransitionTarget(
            messageID: messageID,
            sourceView: sourceView,
            snapshotFactory: { [weak self] in
                self?.mediaView.makeGalleryTransitionSnapshot(for: messageID)
            },
            validation: { [weak self, weak sourceView] in
                guard let self, let sourceView else { return false }
                return mediaTransitionGeneration == generation
                    && mediaView.transitionGeneration == contentGeneration
                    && representedGalleryMessageIDs.contains(messageID)
                    && mediaView.transitionIsCurrent(for: messageID)
                    && mediaView.galleryTransitionSourceView(for: messageID) === sourceView
            },
        )
    }

    func configure(
        message: CustomMessage,
        chat: CustomChat,
        highlighted: Bool,
        client: TDLibClient,
        spoilerSource: TdUpdateSource? = nil,
        mediaRevealSession: MediaRevealSession? = nil,
        pollInteractionStore: MessagePollInteractionStore,
        videoPlaybackOwners: [Int64: GalleryVideoPlaybackOwner] = [:],
        canAddReactions: Bool,
        selectionActive: Bool,
        selected: Bool,
        onSwipeToReply: (() -> Void)?,
        onSelectionToggle: (() -> Void)?,
        onReactionTap: @escaping (ReactionType) -> Void,
        onMetadataNavigate: @escaping (MessageMetadataNavigationTarget) -> Void,
        onReplyQuoteExpand: @escaping () -> Void,
        onContentAction: @escaping (MessageContentAction) -> Void,
        onMediaTap: @escaping ([Message], Int64) -> Void,
        actionBindingID: UUID = UUID(),
        timelineRowID: UUID? = nil,
        showsProfileImage: Bool? = nil,
    ) {
        self.timelineRowID = timelineRowID
        timelineDisplayedID = message.displayedID
        let showsProfileImage = showsProfileImage ?? chat.shouldShowProfileImage
        selectionTouchBindingID = nil
        self.actionBindingID = actionBindingID
        alpha = 1
        transform = .identity
        resetDeletionPresentation()
        bubbleView.isHidden = false
        contentView.isHidden = false
        accessibilityElementsHidden = false
        isUserInteractionEnabled = true
        self.onSwipeToReply = onSwipeToReply
        self.onMediaTap = onMediaTap
        self.onSelectionToggle = onSelectionToggle
        spoilerSubscriptions.removeAll()
        refreshSpoilerAccessibility = nil
        var captionTexts = [Int64: FormattedText]()
        for source in message.sourceMessages {
            if let text = MessageContentPresentation.make(source).formattedText { captionTexts[source.id] = text }
        }
        let textSourceID = message.sourceMessages
            .first {
                MessageContentPresentation.make($0).formattedText == message.formattedText
            }?.id ?? message.id
        if let text = message.formattedText { captionTexts[textSourceID] = text }
        textSpoilers.configure(
            source: spoilerSource?.clientID == client.id ? spoilerSource : nil,
            chatID: message.message.chatId, texts: captionTexts,
        )
        mediaTransitionGeneration = UUID()
        representedGalleryMessageIDs = message.album.isEmpty
            ? [message.id]
            : Set(message.album.map(\.id))
        swipeReplyThreshold = message.message.isOutgoing ? 60 : 45
        swipeToReplyRecognizer.isEnabled = onSwipeToReply != nil && !selectionActive
        let presentation = message.contentPresentation
        let visibleReactions = message.message.selfDestructType == nil
            && message.message.ephemeralMessageId == 0
            ? MessageReactionStateReducer.visible(message.reactions)
            : []
        configureAlignment(
            outgoing: message.message.isOutgoing,
            showsAvatar: showsProfileImage,
            centered: presentation.isService,
        )
        configureSelection(
            active: selectionActive,
            selected: selected,
            outgoing: message.message.isOutgoing,
            centered: presentation.isService,
        )

        let isVideoNoteMessage =
            if case .messageVideoNote = message.message.content {
                true
            } else {
                false
            }
        let isStandaloneVideoNote =
            if isVideoNoteMessage,
            message.forwardPresentation == nil,
            message.replyPresentation == nil,
            message.formattedText == nil {
                true
            } else {
                false
            }
        bubbleView.backgroundColor =
            if presentation.isService {
                highlighted ? UIColor.messageHighlight.withAlphaComponent(0.35) : .clear
            } else if isStandaloneVideoNote {
                highlighted ? UIColor.messageHighlight.withAlphaComponent(0.35) : .clear
            } else {
                highlighted ? .messageHighlight : .secondarySystemBackground
            }
        let usesEdgeToEdgeContent = isStandaloneVideoNote || presentation.isService
        bubbleTopConstraint.constant = usesEdgeToEdgeContent ? 0 : 6
        bubbleLeadingConstraint.constant = usesEdgeToEdgeContent ? 0 : 8
        bubbleTrailingConstraint.constant = usesEdgeToEdgeContent ? 0 : -8
        bubbleBottomConstraint.constant = usesEdgeToEdgeContent
            ? (visibleReactions.isEmpty ? 0 : -2)
            : -5
        if let forward = message.forwardPresentation {
            forwardView.isHidden = false
            forwardView.configure(
                presentation: forward,
                client: client,
                onTap: forward.navigationTarget.map { target in
                    { onMetadataNavigate(target) }
                },
            )
        } else {
            forwardView.isHidden = true
        }

        if let reply = message.replyPresentation {
            replyView.isHidden = false
            replyView.configure(
                presentation: reply,
                expanded: message.isReplyQuoteExpanded,
                client: client,
            ) { shouldExpand in
                if shouldExpand {
                    onReplyQuoteExpand()
                } else if let target = reply.navigationTarget {
                    onMetadataNavigate(target)
                }
            }
        } else {
            replyView.isHidden = true
        }

        let mediaAction: ([Message], Int64) -> Void = { [weak self] messages, selection in
            guard self?.actionBindingID == actionBindingID else { return }
            onMediaTap(messages, selection)
        }
        #if DEBUG
            probeMediaAction = mediaAction
        #endif
        let hasMedia = mediaView.configure(
            message: message,
            client: client,
            mediaRevealSession: mediaRevealSession,
            videoPlaybackOwners: videoPlaybackOwners,
            onTap: mediaAction,
        )
        mediaView.isHidden = !hasMedia

        let previewBelowText: Bool =
            if case .linkPreview(let preview) = presentation.supplement {
                !preview.showAboveText
            } else {
                false
            }
        if let textIndex = bubbleStack.arrangedSubviews.firstIndex(of: textView),
           let structuredIndex = bubbleStack.arrangedSubviews.firstIndex(of: structuredContentView),
           (structuredIndex > textIndex) != previewBelowText
        {
            bubbleStack.removeArrangedSubview(structuredContentView)
            let updatedTextIndex = bubbleStack.arrangedSubviews.firstIndex(of: textView) ?? 3
            bubbleStack.insertArrangedSubview(structuredContentView, at: updatedTextIndex + (previewBelowText ? 1 : 0))
        }
        let hasStructuredContent = structuredContentView.configure(
            presentation: presentation,
            messageID: message.id,
            chatID: message.message.chatId,
            album: message.album,
            client: client,
            pollInteractionStore: pollInteractionStore,
            richContentState: message.richContentState,
            onAction: onContentAction,
        )
        structuredContentView.isHidden = !hasStructuredContent
        let displayedFormattedText = structuredContentView.handlesAlbumCaptions ? nil : message.formattedText

        let timestamp = Self.timeFormatter.string(from: message.date)
        let delivery = message.deliveryState
        let timestampText = [timestamp, delivery.symbol].filter { !$0.isEmpty }.joined(separator: " ")
        let timestampColor: UIColor = delivery == .failed ? .systemRed : .secondaryLabel
        if let formatted = displayedFormattedText {
            textView.isHidden = false
            textView.onRevealSpoilers = { [weak message] in message?.spoilersRevealed = true }
            textView.configure(
                formattedText: formatted,
                statusText: previewBelowText ? "" : timestampText,
                statusColor: timestampColor,
                maximumWidth: maximumTextWidth(for: bounds.width),
                spoilersRevealed: message.spoilersRevealed,
            )
        } else {
            textView.prepareForReuse()
            textView.isHidden = true
        }

        let hasReactions = reactionView.configure(
            reactions: visibleReactions.isEmpty ? nil : message.reactions,
            unreadReactions: visibleReactions.isEmpty ? [] : message.unreadReactions,
            client: client,
            canAddReactions: canAddReactions,
            mutationInFlight: message.reactionMutationInFlight,
            horizontalAlignment: presentation.isService
                ? .center
                : (message.message.isOutgoing ? .right : .left),
            onTap: onReactionTap,
        )
        reactionView.isHidden = !hasReactions

        timestampLabel.text = timestampText
        timestampLabel.textColor = timestampColor
        mediaTimestampLabel.text = timestampText
        mediaTimestampLabel.textColor = delivery == .failed ? .systemRed : .white
        let hasVisualMedia = hasMedia && message.hasVisualMedia
        timestampLabel.isHidden = (displayedFormattedText != nil && !previewBelowText) || hasVisualMedia || presentation
            .isService
        mediaTimestampLabel.isHidden = displayedFormattedText != nil || !hasVisualMedia || presentation.isService
        mediaView.bringSubviewToFront(mediaTimestampLabel)

        if let sender = message.senderUser, showsProfileImage, !message.message.isOutgoing {
            avatarView.isHidden = false
            avatarView.configure(
                file: sender.profilePhoto?.small,
                largeFile: sender.profilePhoto?.big,
                minithumbnail: sender.profilePhoto?.minithumbnail,
                placeholder: sender.telegramAvatarPlaceholder,
                client: client,
            )
        } else {
            avatarView.isHidden = true
        }

        let isRichMessage =
            if case .richMessage = presentation.supplement {
                true
            } else {
                false
            }
        isAccessibilityElement = selectionActive || (!isVideoNoteMessage && !isRichMessage)
        let accessibilityContent =
            if structuredContentView.handlesAlbumCaptions {
                message.album.map { MessageContentPresentation.make($0).summary }.joined(separator: ", ")
            } else {
                displayedFormattedText
                    .map { TelegramSpoilers.accessibilityText($0, revealed: message.spoilersRevealed) }
                    ?? presentation.summary
            }
        accessibilityLabel = [
            message.forwardPresentation?.accessibilityDescription,
            message.replyPresentation?.accessibilityDescription,
        ]
        let suffix = [
            hasReactions ? reactionAccessibilityDescription(visibleReactions) : nil,
            timestamp,
            delivery.spoken,
        ]
        var metadataAccessibilityActions = [UIAccessibilityCustomAction]()
        if let formatted = displayedFormattedText, !message.spoilersRevealed,
           !TelegramSpoilers.ranges(in: formatted).isEmpty
        {
            metadataAccessibilityActions.append(UIAccessibilityCustomAction(name: "Reveal spoiler") { [weak self] _ in
                self?.textView.revealSpoilers() ?? false
            })
        }
        if let reply = message.replyPresentation {
            if reply.isManualQuote, !message.isReplyQuoteExpanded {
                metadataAccessibilityActions.append(UIAccessibilityCustomAction(name: "Expand quoted text") { _ in
                    onReplyQuoteExpand()
                    return true
                })
            }
            if let target = reply.navigationTarget {
                metadataAccessibilityActions.append(UIAccessibilityCustomAction(name: "Open replied message") { _ in
                    onMetadataNavigate(target)
                    return true
                })
            }
        }
        if let target = message.forwardPresentation?.navigationTarget {
            metadataAccessibilityActions
                .append(UIAccessibilityCustomAction(name: "Open forwarded message source") { _ in
                    onMetadataNavigate(target)
                    return true
                })
        }
        for reaction in visibleReactions
            where !message.reactionMutationInFlight && (canAddReactions || reaction.isChosen)
        {
            let actionName = reaction.isChosen
                ? "Remove \(reaction.type.accessibilityName) reaction"
                : "Add \(reaction.type.accessibilityName) reaction"
            metadataAccessibilityActions.append(UIAccessibilityCustomAction(name: actionName) { _ in
                onReactionTap(reaction.type)
                return true
            })
        }
        if selectionActive {
            metadataAccessibilityActions.append(UIAccessibilityCustomAction(
                name: selected ? "Deselect Message" : "Select Message",
            ) { [weak self] _ in
                guard self?.actionBindingID == actionBindingID else { return false }
                onSelectionToggle?()
                return true
            })
            if selected {
                accessibilityTraits.insert(.selected)
            } else {
                accessibilityTraits.remove(.selected)
            }
            accessibilityValue = selected ? "Selected" : "Not selected"
        } else {
            accessibilityTraits.remove(.selected)
            accessibilityValue = nil
        }
        refreshSpoilerAccessibility = { [weak self] in
            guard let self else { return }
            var content = accessibilityAlbum.isEmpty
                ?
                (accessibilityStates.first
                    .map { $0.presentation.accessibilityText(revealed: $0.revealed) } ?? fallbackAccessibilityContent)
                : accessibilityAlbum.map { MessageTextSpoilerPresentation.summary(
                    for: $0,
                    revealed: self.textSpoilers.states[$0.id]?.revealed == true,
                ) }
                .joined(separator: ", ")
            let concealed = message.sourceMessages.filter {
                !MediaRevealPermit.allows($0, permit: mediaRevealSession?.permit(for: $0))
            }
            if !concealed.isEmpty {
                // Captions have independent A10 grants; do not project raw media metadata through the cell.
                let captions = accessibilityStates.map { $0.presentation.accessibilityText(revealed: $0.revealed) }
                content = (concealed.map {
                    MediaRevealSession.Key(message: $0)?.isSecret == true ? "Protected media" : "Media spoiler"
                } + captions).joined(separator: ", ")
            }
            updateSpoilerAccessibility(
                content: content,
                prefix: prefix,
                suffix: suffix,
                states: accessibilityStates,
                actions: metadataAccessibilityActions,
            )
        }
        for state in accessibilityStates {
            state.changes.sink { [weak self] in self?.refreshSpoilerAccessibility?() }.store(in: &spoilerSubscriptions)
        }
        mediaRevealSession?.revisionsChanged
            .sink { [weak self] _ in
                self?.refreshSpoilerAccessibility?()
            }
            .store(in: &spoilerSubscriptions)
        refreshSpoilerAccessibility?()

        bubbleContentNeedsMeasurement = true
        updateBubbleWidth(for: bounds.width)
    }

    func updateSpoilerAccessibility(
        content: String, prefix: [String?], suffix: [String?], states: [MessageTextSpoilerState],
        actions: [UIAccessibilityCustomAction],
    ) {
        accessibilityLabel = (prefix + [content] + suffix).compactMap(\.self).joined(separator: ", ")
        var result = actions
        if states.contains(where: { !$0.revealed && !$0.presentation.ranges.isEmpty }) {
            result.append(UIAccessibilityCustomAction(name: "Reveal spoilers") { _ in
                states.reduce(false) { $1.reveal() || $0 }
            })
        }
        accessibilityCustomActions = result
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

    private func resetDeletionPresentation() {
        contentView.layer.removeAllAnimations()
        contentView.alpha = 1
        contentView.transform = Self.timelineContentTransform
    }

    private func configureViews() {
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.axis = .horizontal
        rowStack.alignment = .bottom
        rowStack.spacing = 5
        contentView.addSubview(rowStack)

        selectionControl.translatesAutoresizingMaskIntoConstraints = false
        selectionControl.isHidden = true
        selectionControl.accessibilityIdentifier = "message-selection-control"
        selectionControl.addTarget(self, action: #selector(selectionTouchBegan), for: .touchDown)
        selectionControl.addTarget(self, action: #selector(selectionPressed), for: .touchUpInside)
        selectionControl.addTarget(
            self,
            action: #selector(selectionTouchCancelled),
            for: [.touchCancel, .touchUpOutside],
        )
        contentView.addSubview(selectionControl)

        selectionIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        selectionIndicatorView.isHidden = true
        selectionIndicatorView.accessibilityIdentifier = "message-selection-indicator"
        contentView.addSubview(selectionIndicatorView)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 32),
            avatarView.heightAnchor.constraint(equalToConstant: 32),
        ])

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.backgroundColor = .secondarySystemBackground
        bubbleView.layer.cornerRadius = 16
        bubbleView.clipsToBounds = true
        bubbleStack.translatesAutoresizingMaskIntoConstraints = false
        bubbleStack.axis = .vertical
        bubbleStack.alignment = .fill
        bubbleStack.spacing = 2
        bubbleView.addSubview(bubbleStack)
        rowStack.addArrangedSubview(bubbleContainerView)
        rowStack.addArrangedSubview(trailingSpacer)

        forwardView.isHidden = true
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

        for view in [
            forwardView,
            replyView,
            mediaView,
            structuredContentView,
            textView,
            reactionView,
            timestampLabel,
        ] {
            bubbleStack.addArrangedSubview(view)
        }
        bubbleStack.setCustomSpacing(6, after: replyView)
        bubbleStack.setCustomSpacing(4, after: mediaView)
        bubbleStack.setCustomSpacing(4, after: textView)
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
            swipeReplyBindingID = actionBindingID
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
            let shouldReply = swipeReplyBindingID != nil && swipeReplyBindingID == actionBindingID
                && recognizer.state == .ended
                && recognizer.translation(in: contentView).x < -swipeReplyThreshold
            swipeReplyFeedback = nil
            swipeReplyBindingID = nil
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
            self.rowStack.transform = self.selectionRowTransform
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
            bubbleTopConstraint,
            bubbleLeadingConstraint,
            bubbleTrailingConstraint,
            bubbleBottomConstraint,
            selectionControl.topAnchor.constraint(equalTo: contentView.topAnchor),
            selectionControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            selectionControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            selectionControl.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            selectionIndicatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            selectionIndicatorView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectionIndicatorView.widthAnchor.constraint(equalToConstant: 28),
            selectionIndicatorView.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func configureSelection(
        active: Bool,
        selected: Bool,
        outgoing: Bool,
        centered: Bool,
    ) {
        let wasActive = selectionActive
        selectionActive = active
        selectionOutgoing = outgoing
        selectionCentered = centered
        selectionControl.isHidden = !active
        selectionIndicatorView.setSelected(selected)
        let targetTransform = selectionRowTransform
        guard wasActive != active, window != nil else {
            selectionIndicatorView.isHidden = !active
            selectionIndicatorView.alpha = active ? 1 : 0
            selectionIndicatorView.transform = .identity
            rowStack.transform = targetTransform
            return
        }
        selectionIndicatorView.isHidden = false
        if active {
            selectionIndicatorView.alpha = 0
            selectionIndicatorView.transform = CGAffineTransform(translationX: -20, y: 0)
        }
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
        ) {
            self.selectionIndicatorView.alpha = active ? 1 : 0
            self.selectionIndicatorView.transform = active
                ? .identity
                : CGAffineTransform(translationX: -20, y: 0)
            self.rowStack.transform = targetTransform
        } completion: { [weak self] _ in
            guard let self, selectionActive == active else { return }
            selectionIndicatorView.isHidden = !active
            if !active {
                selectionIndicatorView.transform = .identity
            }
        }
    }

    @objc private func selectionTouchBegan() {
        guard selectionTouchBindingID == nil, selectionActive, !selectionControl.isHidden,
              isUserInteractionEnabled, !contentView.isHidden, window != nil else { return }
        selectionTouchBindingID = actionBindingID
    }

    @objc private func selectionTouchCancelled() {
        selectionTouchBindingID = nil
    }

    @objc private func selectionPressed() {
        let binding = selectionTouchBindingID
        selectionTouchBindingID = nil
        guard let binding, binding == actionBindingID, selectionActive, !selectionControl.isHidden,
              isUserInteractionEnabled, !contentView.isHidden, window != nil else { return }
        onSelectionToggle?()
    }

    private func configureAlignment(outgoing: Bool, showsAvatar: Bool, centered: Bool) {
        centeredSpacerConstraint?.isActive = false
        centeredSpacerConstraint = nil
        for arrangedSubview in rowStack.arrangedSubviews {
            rowStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        if centered {
            rowStack.addArrangedSubview(leadingSpacer)
            rowStack.addArrangedSubview(bubbleContainerView)
            rowStack.addArrangedSubview(trailingSpacer)
            leadingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            bubbleContainerView.setContentHuggingPriority(.required, for: .horizontal)
            let constraint = leadingSpacer.widthAnchor.constraint(equalTo: trailingSpacer.widthAnchor)
            constraint.isActive = true
            centeredSpacerConstraint = constraint
        } else if outgoing {
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
        reactionView.setMaximumLayoutWidth(maximumContentWidth)

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

    private func reactionAccessibilityDescription(_ reactions: [MessageReaction]) -> String {
        reactions
            .map { "\($0.type.accessibilityName), \($0.totalCount)" }
            .joined(separator: ", ")
    }

    private func maximumTextWidth(for cellWidth: CGFloat) -> CGFloat {
        guard cellWidth > 0 else { return Utils.maxMessageContentWidth }
        return max(1, floor(cellWidth * 0.82) - 16)
    }
}

private extension CustomMessage {
    var hasVisualMedia: Bool {
        if !album.isEmpty {
            return album.contains { MessageContentPresentation.make($0).isVisualMedia }
        }
        return contentPresentation.isVisualMedia
    }
}

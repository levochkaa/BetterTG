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

    /// The label's font follows its attributed text, so the status keeps its own.
    private static let statusFont = UIFont.preferredFont(forTextStyle: .caption2)

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
                && inlineKeyboardView.isHidden
                && commentFooterView.isHidden
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
    /// The bubble and Telegram's inline keyboard under it (`ChatMessageActionButtonsNode`), at one width.
    private let bubbleColumn = UIStackView()
    private let inlineKeyboardView = MessageInlineKeyboardView()
    private let bubbleStack = UIStackView()
    private let highlightOverlay = UIView()
    private var messageIsHighlighted = false
    private var highlightConstraints = [NSLayoutConstraint]()
    private var bubbleInsetViews = [ObjectIdentifier: MessageBubbleInsetView]()
    private var usesFullBleedMedia = false
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
    private let mediaTimestampLabel = MessageMediaStatusLabel()
    private let commentFooterView = MessageCommentFooterView()
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
    var contextQuoteTextView: MessageTextContentView { textView }

    private var bubbleContentViews: [UIView] {
        [
            forwardView, replyView, mediaView, structuredContentView, textView, reactionView, timestampLabel,
            commentFooterView,
        ]
    }

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

    /// The text a quote selection works on: the message text, or in a file or music album the caption of the item
    /// at `point` (in the cell's coordinates), else the album's only caption, with that item's message ID.
    func contextQuoteTarget(at point: CGPoint) -> (textView: MessageTextContentView, sourceMessageID: Int64?)? {
        guard structuredContentView.handlesAlbumCaptions else { return (textView, nil) }
        let items = structuredContentView.albumCaptionItems
        if let pressed = items.first(where: { $0.view.convert($0.view.bounds, to: self).contains(point) }) {
            guard let caption = pressed.caption else { return nil }
            return (caption, pressed.messageID)
        }
        let captioned = items.filter { $0.caption != nil }
        guard captioned.count == 1, let only = captioned.first, let caption = only.caption else { return nil }
        return (caption, only.messageID)
    }

    /// The caption a quote of `messageID` is in: an album item's, or the message text.
    func contextQuoteTextView(forMessageID messageID: Int64) -> MessageTextContentView? {
        guard structuredContentView.handlesAlbumCaptions else { return textView }
        return structuredContentView.albumCaptionItems.first { $0.messageID == messageID }?.caption
    }

    /// The album item a long press at `point` (in the cell's coordinates) is on: a photo or video of a media album,
    /// or a file of a file or music album, as Telegram's per-item album menus act on that item.
    func contextAlbumItemID(at point: CGPoint) -> Int64? {
        if let id = mediaView.albumItemMessageID(at: point, in: self) { return id }
        guard structuredContentView.handlesAlbumCaptions else { return nil }
        return structuredContentView.albumCaptionItems
            .first { $0.view.convert($0.view.bounds, to: self).contains(point) }?
            .messageID
    }

    /// The checklist task a long press at `point` (in the cell's coordinates) is on; Telegram opens that task's
    /// own menu.
    func contextChecklistTaskID(at point: CGPoint) -> Int? {
        structuredContentView.checklistTaskID(at: point, in: self)
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
        setMessageHighlighted(nil)
        NSLayoutConstraint.deactivate(highlightConstraints)
        highlightConstraints = []
        highlightOverlay.removeFromSuperview()
        avatarView.prepareForReuse()
        avatarView.setHiddenIfChanged(true)
        mediaView.prepareForReuse()
        structuredContentView.prepareForReuse()
        textView.prepareForReuse()
        spoilerSubscriptions.removeAll()
        refreshSpoilerAccessibility = nil
        textSpoilers.reset()
        reactionView.prepareForReuse()
        inlineKeyboardView.prepareForReuse()
        inlineKeyboardView.isHidden = true
        commentFooterView.prepareForReuse()
        commentFooterView.isHidden = true
        forwardView.prepareForReuse()
        replyView.prepareForReuse()
        forwardView.isHidden = true
        replyView.isHidden = true
        textView.isHidden = true
        mediaView.setHiddenIfChanged(true)
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

    /// The comments bar shows a spinner while the post's thread opens.
    func setCommentsLoading(_ isLoading: Bool) {
        commentFooterView.setLoading(isLoading)
    }

    /// The chat search's query in the message text and a file album's captions, or nil to clear it.
    func setSearchHighlight(query: String?) {
        textView.setSearchHighlight(query)
        for item in structuredContentView.albumCaptionItems {
            item.caption?.setSearchHighlight(query)
        }
    }

    func setMessageHighlighted(_ messageID: Int64?, animated: Bool = false) {
        let highlighted = messageID != nil
        if let messageID {
            let target = (mediaView.isHidden ? nil : mediaView.galleryTransitionSourceView(for: messageID)) ??
                bubbleView
            if highlightOverlay.superview !== target {
                NSLayoutConstraint.deactivate(highlightConstraints)
                highlightOverlay.removeFromSuperview()
                target.addSubview(highlightOverlay)
                highlightOverlay.layer.cornerRadius = target.layer.cornerRadius
                highlightOverlay.layer.maskedCorners = target.layer.maskedCorners
                highlightConstraints = [
                    highlightOverlay.topAnchor.constraint(equalTo: target.topAnchor),
                    highlightOverlay.leadingAnchor.constraint(equalTo: target.leadingAnchor),
                    highlightOverlay.trailingAnchor.constraint(equalTo: target.trailingAnchor),
                    highlightOverlay.bottomAnchor.constraint(equalTo: target.bottomAnchor),
                ]
                NSLayoutConstraint.activate(highlightConstraints)
            }
        }
        let layer = highlightOverlay.layer
        let visibleOpacity = highlightOverlay.isHidden ? 0 : layer.presentation()?.opacity ?? layer.opacity
        layer.removeAnimation(forKey: "highlightFade")
        messageIsHighlighted = highlighted
        highlightOverlay.alpha = highlighted ? 1 : 0
        // Telegram shows the highlight at once and fades it out over 0.3 s (ChatMessageBubbleItemNode
        // updateHighlightedState). Timeline snapshots apply without UIView animations, so the fade is a layer
        // animation.
        guard !highlighted, animated, visibleOpacity > 0 else {
            highlightOverlay.isHidden = !highlighted
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, !messageIsHighlighted else { return }
            highlightOverlay.isHidden = true
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = visibleOpacity
        fade.toValue = 0
        fade.duration = 0.3
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "highlightFade")
        CATransaction.commit()
    }

    func highlightQuote(_ quote: MessageQuoteHighlight, messageID: Int64) {
        contextQuoteTextView(forMessageID: messageID)?.highlightQuote(position: quote.position, length: quote.length)
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
        highlightedMessageID: Int64?,
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
        onReactionLongPress: ((ReactionType) -> Void)? = nil,
        onMetadataNavigate: @escaping (MessageMetadataNavigationTarget) -> Void,
        onReplyQuoteExpand: @escaping () -> Void,
        onContentAction: @escaping (MessageContentAction) -> Void,
        onMediaTap: @escaping ([Message], Int64) -> Void,
        actionBindingID: UUID = UUID(),
        timelineRowID: UUID? = nil,
        showsProfileImage: Bool? = nil,
        commentsLoading: Bool = false,
    ) {
        // A reconfigure of the same message animates only its highlight change.
        let reconfiguresSameMessage = timelineDisplayedID == message.displayedID && window != nil
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
        // Service rows and Telegram's story-mention card sit centered without a bubble.
        let isCentered = presentation.isService || presentation.isStoryMention
        let visibleReactions = message.message.selfDestructType == nil
            && message.message.ephemeralMessageId == 0
            ? MessageReactionStateReducer.visible(message.reactions)
            : []
        configureAlignment(
            outgoing: message.message.isOutgoing,
            showsAvatar: showsProfileImage,
            centered: isCentered,
        )
        configureSelection(
            active: selectionActive,
            selected: selected,
            outgoing: message.message.isOutgoing,
            centered: isCentered,
        )

        let isUnframedMediaMessage =
            switch message.message.content {
            case .messageAnimation, .messageSticker, .messageVideoNote: true
            default: false
            }
        let isStandaloneUnframedMedia =
            if isUnframedMediaMessage,
            message.forwardPresentation == nil,
            message.replyPresentation == nil,
            message.formattedText == nil {
                true
            } else {
                false
            }
        usesFullBleedMedia = presentation.isVisualMedia || isStandaloneUnframedMedia
        // Telegram's hasCommentButton: posts of a channel with a discussion group end with the comments bar. Stickers
        // and round videos get a separate button there instead, and service messages none.
        let hasSeparateCommentButton =
            switch message.message.content {
            case .messageSticker, .messageVideoNote: true
            default: false
            }
        let commentSource: Message? =
            if chat.isBroadcastChannel, chat.supergroup?.hasLinkedChat == true, !presentation.isService,
            !hasSeparateCommentButton {
                message.sourceMessages
                    .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
                    .first { $0.schedulingState == nil && $0.interactionInfo?.replyInfo != nil }
            } else {
                nil
            }
        let hasBubbleText = message.formattedText != nil || message.forwardPresentation != nil || message
            .replyPresentation != nil
        // The comments bar sits on the bubble, as under Telegram's media posts.
        bubbleView.backgroundColor = isCentered
            || (commentSource == nil && (isStandaloneUnframedMedia || (usesFullBleedMedia && !hasBubbleText)))
            ? .clear
            : .secondarySystemBackground
        let usesEdgeToEdgeContent = usesFullBleedMedia || isCentered
        bubbleTopConstraint.constant = usesEdgeToEdgeContent ? 0 : 6
        bubbleLeadingConstraint.constant = usesEdgeToEdgeContent ? 0 : 8
        bubbleTrailingConstraint.constant = usesEdgeToEdgeContent ? 0 : -8
        bubbleBottomConstraint.constant = usesEdgeToEdgeContent ? 0 : -5
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
            maximumWidth: maximumBubbleWidth(for: bounds.width),
            mediaRevealSession: mediaRevealSession,
            videoPlaybackOwners: videoPlaybackOwners,
            onCancelSending: { [weak self] messageID in
                guard self?.actionBindingID == actionBindingID else { return }
                onContentAction(.cancelSending(messageID: messageID))
            },
            onTap: mediaAction,
        )
        mediaView.setHiddenIfChanged(!hasMedia)
        setMessageHighlighted(highlightedMessageID, animated: reconfiguresSameMessage)

        let previewBelowText: Bool =
            if case .linkPreview(let preview) = presentation.supplement {
                !preview.showAboveText
            } else {
                false
            }
        if let textIndex = bubbleStack.arrangedSubviews.firstIndex(of: arrangedBubbleView(for: textView)),
           let structuredIndex = bubbleStack.arrangedSubviews
               .firstIndex(of: arrangedBubbleView(for: structuredContentView)),
               (structuredIndex > textIndex) != previewBelowText
        {
            bubbleStack.removeArrangedSubview(arrangedBubbleView(for: structuredContentView))
            let updatedTextIndex = bubbleStack.arrangedSubviews.firstIndex(of: arrangedBubbleView(for: textView)) ?? 3
            bubbleStack.insertArrangedSubview(
                arrangedBubbleView(for: structuredContentView),
                at: updatedTextIndex + (previewBelowText
                    ? 1
                    : 0),
            )
        }
        let hasStructuredContent = structuredContentView.configure(
            presentation: presentation,
            messageID: message.id,
            chatID: message.message.chatId,
            album: message.album,
            client: client,
            pollInteractionStore: pollInteractionStore,
            richContentState: message.richContentState,
            textSpoilers: textSpoilers,
            onAction: onContentAction,
        )
        structuredContentView.isHidden = !hasStructuredContent
        let displayedFormattedText = structuredContentView.handlesAlbumCaptions ? nil : message.formattedText

        let timestamp = Self.timeFormatter.string(from: message.date)
        let delivery = message.deliveryState
        // Telegram reads the status of a caption from its message and that of an album from its first message.
        let statusSource = displayedFormattedText == nil
            ? message.deliverySourceMessage
            : message.sourceMessages.first { $0.id == textSourceID } ?? message.message
        let statusLine = MessageStatusLine.make(
            statusSource,
            isChannel: chat.isBroadcastChannel,
            time: timestamp,
            deliverySymbol: delivery.symbol,
        )
        let timestampColor: UIColor = delivery == .failed ? .systemRed : .secondaryLabel
        if let formatted = displayedFormattedText {
            textView.isHidden = false
            textView.onRevealSpoilers = { [weak message] in message?.spoilersRevealed = true }
            textView.configure(
                formattedText: formatted,
                client: client,
                statusText: previewBelowText ? "" : statusLine.text,
                statusColor: timestampColor,
                statusViewCount: previewBelowText ? nil : statusLine.viewCount,
                maximumWidth: maximumTextWidth(for: bounds.width),
                spoilersRevealed: message.spoilersRevealed,
                spoilerState: textSpoilers.states[textSourceID],
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
            horizontalAlignment: isCentered
                ? .center
                : (message.message.isOutgoing ? .right : .left),
            onTap: onReactionTap,
            onLongPress: message.reactions?.canGetAddedReactions == true ? onReactionLongPress : nil,
        )
        reactionView.isHidden = !hasReactions

        let keyboardRows: [[TDNativeInlineKeyboardButton]] =
            if case .replyMarkupInlineKeyboard(let keyboard) = message.message.replyMarkup {
                keyboard.rows
            } else {
                []
            }
        let keyboardMessageID = message.message.id
        let keyboardTap: (TDNativeInlineKeyboardButton, UIView) -> Void = { [weak self] button, _ in
            guard self?.actionBindingID == actionBindingID else { return }
            onContentAction(.pressInlineKeyboardButton(InlineKeyboardButtonPress(
                messageID: keyboardMessageID,
                type: button.type,
            )))
        }
        let hasKeyboard = inlineKeyboardView.configure(
            rows: keyboardRows,
            isInteractive: !selectionActive,
            onTap: keyboardTap,
        )
        inlineKeyboardView.isHidden = !hasKeyboard

        let commentTap: () -> Void = { [weak self] in
            guard self?.actionBindingID == actionBindingID, let messageID = commentSource?.id else { return }
            onContentAction(.openComments(messageID: messageID))
        }
        if let commentSource, let replyInfo = commentSource.interactionInfo?.replyInfo {
            commentFooterView.configure(
                replyInfo: replyInfo,
                isEnabled: commentSource.sendingState == nil && !selectionActive,
                isLoading: commentsLoading,
                client: client,
                onTap: commentTap,
            )
            commentFooterView.isHidden = false
        } else {
            commentFooterView.prepareForReuse()
            commentFooterView.isHidden = true
        }

        timestampLabel.attributedText = statusLine.attributedText(font: Self.statusFont, color: timestampColor)
        mediaTimestampLabel.attributedText = statusLine.attributedText(
            font: Self.statusFont,
            color: delivery == .failed ? .systemRed : .white,
        )
        let hasVisualMedia = hasMedia && message.hasVisualMedia
        timestampLabel.isHidden = (displayedFormattedText != nil && !previewBelowText) || hasVisualMedia || isCentered
        mediaTimestampLabel.isHidden = displayedFormattedText != nil || !hasVisualMedia || isCentered
        mediaView.bringSubviewToFront(mediaTimestampLabel)

        if let sender = message.senderUser, showsProfileImage, !message.message.isOutgoing {
            avatarView.setHiddenIfChanged(false)
            avatarView.configure(
                file: sender.profilePhoto?.small,
                largeFile: sender.profilePhoto?.big,
                minithumbnail: sender.profilePhoto?.minithumbnail,
                placeholder: sender.telegramAvatarPlaceholder,
                client: client,
            )
        } else {
            avatarView.setHiddenIfChanged(true)
        }

        let isVideoNoteMessage =
            if case .messageVideoNote = message.message.content {
                true
            } else {
                false
            }
        let isRichMessage =
            if case .richMessage = presentation.supplement {
                true
            } else {
                false
            }
        isAccessibilityElement = selectionActive || (!isVideoNoteMessage && !isRichMessage)
        let accessibilityStates = structuredContentView.handlesAlbumCaptions
            ? message.album.compactMap { textSpoilers.states[$0.id] }
            : [textSpoilers.states[textSourceID]].compactMap(\.self)
        let accessibilityAlbum = structuredContentView.handlesAlbumCaptions ? message.album : []
        // Service rows read their resolved wording (with names); other content keeps the spoiler-safe summary.
        let fallbackAccessibilityContent = presentation.isService
            ? presentation.summary
            : MessageTextSpoilerPresentation.summary(for: message.message)
        let prefix = [
            message.forwardPresentation?.accessibilityDescription,
            message.replyPresentation?.accessibilityDescription,
        ]
        let suffix = [
            hasReactions ? reactionAccessibilityDescription(visibleReactions) : nil,
            timestamp,
            delivery.spoken,
        ]
        var metadataAccessibilityActions = [UIAccessibilityCustomAction]()
        for (index, source) in message.sourceMessages.enumerated()
            where !MediaRevealPermit.allows(source, permit: mediaRevealSession?.permit(for: source))
        {
            if MediaRevealSession.Key(message: source)?.isSecret == false {
                metadataAccessibilityActions.append(UIAccessibilityCustomAction(
                    name: message.sourceMessages.count > 1
                        ? L10n.betterTG("Accessibility.RevealMediaSpoilerNumber", index + 1)
                        : L10n.betterTG("Accessibility.RevealMediaSpoiler"),
                ) { _ in
                    onMediaTap(message.sourceMessages, source.id)
                    return true
                })
            }
        }
        if let reply = message.replyPresentation {
            if reply.isManualQuote, !message.isReplyQuoteExpanded {
                metadataAccessibilityActions
                    .append(UIAccessibilityCustomAction(name: L10n.betterTG("Accessibility.ExpandQuote")) { _ in
                        onReplyQuoteExpand()
                        return true
                    })
            }
            if let target = reply.navigationTarget {
                metadataAccessibilityActions
                    .append(UIAccessibilityCustomAction(name: L10n.betterTG("Accessibility.OpenRepliedMessage")) { _ in
                        onMetadataNavigate(target)
                        return true
                    })
            }
        }
        if let target = message.forwardPresentation?.navigationTarget {
            metadataAccessibilityActions
                .append(UIAccessibilityCustomAction(name: L10n.betterTG("Accessibility.OpenForwardSource")) { _ in
                    onMetadataNavigate(target)
                    return true
                })
        }
        for reaction in visibleReactions
            where !message.reactionMutationInFlight && (canAddReactions || reaction.isChosen)
        {
            let actionName = reaction.isChosen
                ? L10n.betterTG("Accessibility.RemoveReaction", reaction.type.accessibilityName)
                : L10n.betterTG("Accessibility.AddReaction", reaction.type.accessibilityName)
            metadataAccessibilityActions.append(UIAccessibilityCustomAction(name: actionName) { _ in
                onReactionTap(reaction.type)
                return true
            })
        }
        // The cell reads as one element, so VoiceOver reaches the comments bar and the keyboard's buttons as actions.
        if !commentFooterView.isHidden, commentFooterView.isEnabled {
            metadataAccessibilityActions.append(UIAccessibilityCustomAction(name: commentFooterView.title) { _ in
                commentTap()
                return true
            })
        }
        if hasKeyboard, !selectionActive {
            for (index, entry) in inlineKeyboardView.buttons.enumerated() {
                let action = UIAccessibilityCustomAction(name: entry.button.text) { [weak self] _ in
                    self?.inlineKeyboardView.activate(index)
                    return true
                }
                metadataAccessibilityActions.append(action)
            }
        }
        if selectionActive {
            metadataAccessibilityActions.append(UIAccessibilityCustomAction(
                name: selected
                    ? L10n.betterTG("Accessibility.DeselectMessage")
                    : L10n.betterTG("Accessibility.SelectMessage"),
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
            accessibilityValue = selected
                ? L10n.telegram("VoiceOver.Chat.Selected")
                : L10n.betterTG("Accessibility.NotSelected")
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
                    MediaRevealSession.Key(message: $0)?.isSecret == true
                        ? L10n.betterTG("Accessibility.ProtectedMedia")
                        : L10n.betterTG("Accessibility.MediaSpoiler")
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
        updateBubbleContentInsets()

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
            result.append(UIAccessibilityCustomAction(name: L10n.betterTG("Accessibility.RevealSpoilers")) { _ in
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
        bubbleColumn.axis = .vertical
        bubbleColumn.alignment = .fill
        bubbleColumn.spacing = MessageInlineKeyboardView.spacing
        bubbleColumn.addArrangedSubview(bubbleContainerView)
        bubbleColumn.addArrangedSubview(inlineKeyboardView)
        inlineKeyboardView.isHidden = true
        rowStack.addArrangedSubview(bubbleColumn)
        rowStack.addArrangedSubview(trailingSpacer)

        forwardView.isHidden = true
        replyView.isHidden = true
        mediaView.isHidden = true
        textView.isHidden = true
        timestampLabel.font = Self.statusFont
        timestampLabel.textAlignment = .right
        timestampLabel.isHidden = true
        commentFooterView.isHidden = true

        mediaTimestampLabel.translatesAutoresizingMaskIntoConstraints = false
        mediaTimestampLabel.font = Self.statusFont
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

        for view in bubbleContentViews {
            if view === mediaView {
                bubbleStack.addArrangedSubview(view)
            } else {
                let insetView = MessageBubbleInsetView(content: view)
                bubbleInsetViews[ObjectIdentifier(view)] = insetView
                bubbleStack.addArrangedSubview(insetView)
            }
        }
        bubbleStack.setCustomSpacing(6, after: arrangedBubbleView(for: replyView))
        bubbleStack.setCustomSpacing(4, after: mediaView)
        bubbleStack.setCustomSpacing(4, after: arrangedBubbleView(for: textView))
        highlightOverlay.translatesAutoresizingMaskIntoConstraints = false
        highlightOverlay.backgroundColor = .tertiarySystemFill
        highlightOverlay.isUserInteractionEnabled = false
        highlightOverlay.accessibilityElementsHidden = true
        highlightOverlay.isHidden = true
        bubbleView.addSubview(highlightOverlay)
        highlightConstraints = [
            highlightOverlay.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            highlightOverlay.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            highlightOverlay.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
            highlightOverlay.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
        ]
        NSLayoutConstraint.activate(highlightConstraints)
    }

    private func arrangedBubbleView(for content: UIView) -> UIView {
        bubbleInsetViews[ObjectIdentifier(content)] ?? content
    }

    private func updateBubbleContentInsets() {
        for content in bubbleContentViews {
            bubbleInsetViews[ObjectIdentifier(content)]?.setHiddenIfChanged(content.isHidden)
        }
        let visibleItems = bubbleStack.arrangedSubviews.filter { !$0.isHidden }
        var mediaCorners = CACornerMask()
        if !usesFullBleedMedia || visibleItems.first === mediaView {
            mediaCorners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner])
        }
        if !usesFullBleedMedia || visibleItems.last === mediaView {
            mediaCorners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        }
        mediaView.setBubbleCorners(mediaCorners)
        // Telegram drops the bar's separator right under media.
        if let footerIndex = visibleItems.firstIndex(of: arrangedBubbleView(for: commentFooterView)) {
            commentFooterView.showsSeparator = footerIndex > 0 && visibleItems[footerIndex - 1] !== mediaView
        }
        for insetView in bubbleInsetViews.values {
            insetView.setInsets(usesFullBleedMedia
                ? UIEdgeInsets(
                    top: visibleItems.first === insetView ? 6 : 0,
                    left: 8,
                    bottom: visibleItems.last === insetView ? 5 : 0,
                    right: 8,
                )
                : .zero)
        }
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
            rowStack.addArrangedSubview(bubbleColumn)
            rowStack.addArrangedSubview(trailingSpacer)
            leadingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            bubbleColumn.setContentHuggingPriority(.required, for: .horizontal)
            let constraint = leadingSpacer.widthAnchor.constraint(equalTo: trailingSpacer.widthAnchor)
            constraint.isActive = true
            centeredSpacerConstraint = constraint
        } else if outgoing {
            rowStack.addArrangedSubview(leadingSpacer)
            rowStack.addArrangedSubview(bubbleColumn)
            leadingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            bubbleColumn.setContentHuggingPriority(.required, for: .horizontal)
        } else {
            if showsAvatar {
                rowStack.addArrangedSubview(avatarView)
            }
            rowStack.addArrangedSubview(bubbleColumn)
            rowStack.addArrangedSubview(trailingSpacer)
            trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            bubbleColumn.setContentHuggingPriority(.required, for: .horizontal)
        }
    }

    private func updateBubbleWidth(for cellWidth: CGFloat) {
        guard cellWidth > 0 else { return }
        guard bubbleContentNeedsMeasurement || abs(measuredCellWidth - cellWidth) > 0.5 else { return }
        let maximumBubbleWidth = maximumBubbleWidth(for: cellWidth)
        if !mediaView.isHidden {
            mediaView.updateMaximumWidth(maximumBubbleWidth)
        }
        let mediaWidth = usesFullBleedMedia && !mediaView.isHidden
            ? mediaView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
            : 0
        let maximumContentWidth = max(1, min(maximumBubbleWidth, mediaWidth > 0 ? mediaWidth : maximumBubbleWidth) - 16)
        textView.setMaximumLayoutWidth(maximumContentWidth)
        reactionView.setMaximumLayoutWidth(maximumContentWidth)

        let fittingSize = CGSize(
            width: maximumContentWidth,
            height: UIView.layoutFittingCompressedSize.height,
        )
        var preferredContentWidth = CGFloat.zero
        for view in bubbleContentViews where !view.isHidden {
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
        var preferredBubbleWidth = min(
            maximumBubbleWidth,
            ceil(mediaWidth > 0 ? mediaWidth : preferredContentWidth + 16),
        )
        // Telegram widens the bubble to fit the inline keyboard's rows; a media bubble keeps the media's width.
        if !inlineKeyboardView.isHidden, mediaWidth == 0 {
            preferredBubbleWidth = min(maximumBubbleWidth, max(preferredBubbleWidth, inlineKeyboardView.minimumWidth))
        }
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

    /// The widest bubble, which is also the widest media: Telegram's constrained width for media sizing.
    private func maximumBubbleWidth(for cellWidth: CGFloat) -> CGFloat {
        floor((cellWidth > 0 ? cellWidth : Utils.screen.bounds.width - 16) * 0.82)
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

// MARK: - MessageMediaStatusLabel

/// The status over media (Telegram's `ImageOutgoing` date and status), padded inside its dark capsule so a view
/// count or "edited" keeps clear of the rounded ends.
private final class MessageMediaStatusLabel: UILabel {
    private static let horizontalPadding: CGFloat = 6

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + Self.horizontalPadding * 2, height: size.height)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: Self.horizontalPadding, dy: 0))
    }
}

// MARK: - MessageBubbleInsetView

/// Only text/metadata gets padding; visual media spans the entire bubble width.
private final class MessageBubbleInsetView: UIView {
    override var isHidden: Bool {
        didSet { bottom.isActive = !isHidden }
    }

    private let leading: NSLayoutConstraint
    private let trailing: NSLayoutConstraint
    private let top: NSLayoutConstraint
    private let bottom: NSLayoutConstraint

    init(content: UIView) {
        let container = UILayoutGuide()
        self.leading = content.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        self.trailing = content.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        self.top = content.topAnchor.constraint(equalTo: container.topAnchor)
        self.bottom = content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        super.init(frame: .zero)
        addLayoutGuide(container)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            leading, trailing, top, bottom,
        ])
        self.isHidden = content.isHidden
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setInsets(_ insets: UIEdgeInsets) {
        leading.constant = insets.left
        trailing.constant = -insets.right
        top.constant = insets.top
        bottom.constant = -insets.bottom
    }
}

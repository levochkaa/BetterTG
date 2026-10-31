// ChatSponsoredMessageView.swift

import AVFoundation
import TDLibKit
import UIKit

// MARK: - ChatSponsoredMessageActions

/// What the ad's bubble asks its chat to do, as ChatControllerInteraction's `activateAdAction`, `openAdsInfo` and
/// `openNoAdsDemo` do.
struct ChatSponsoredMessageActions {
    /// The body, the button or a picture: `clickChatSponsoredMessage`, then the sponsor's link.
    var activate: (_ isMediaClick: Bool) -> Void = { _ in }
    /// The ad's video: the click as a media click, then the video full screen.
    var playVideo: (_ file: File) -> Void = { _ in }
    /// A link in the ad's text, which opens as it would in a message; the chat counts the click.
    var openLink: () -> Void = {}
    /// "what's this?": About These Ads.
    var openInfo: () -> Void = {}
    /// The close button beside the bubble: Telegram's No Ads Premium demo.
    var close: () -> Void = {}
    /// The lower half of that button, on an ad that can be reported: the ad's menu.
    var more: () -> Void = {}
}

// MARK: - ChatSponsoredMessageContentView

/// ChatMessageWebpageBubbleContentNode with an ad, ChatMessageAttachedContentNode's layout: the accent line and tint,
/// the ad's own media before the text, the "Sponsored" or "Recommended" label with "what's this?" when the ad can be
/// reported, the sponsor's title, the text and the sponsor's photo beside it, then the button in the accent colour
/// under a hairline, uppercased, with a corner arrow when it leads out of Telegram.
final class ChatSponsoredMessageContentView: UIView, UIGestureRecognizerDelegate {
    private static let fontSize = CGFloat(15)

    private let message: ChatSponsoredMessage
    private let actions: ChatSponsoredMessageActions
    private let accent: UIColor
    private let textView = MessageTextContentView()
    private let sponsorPhotoView = TDImageLoadingView()
    private let mediaView = UIView()
    private let mediaImageView = TDImageLoadingView()
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    private var playbackVisible = false
    private let badgeButton = UIButton(type: .system)
    private let actionButton = UIButton(type: .system)
    /// The label and "what's this?", and the sponsor's title: what the card's width must fit beside the text.
    private let titleRow = UIStackView()
    private var sponsorTitleLabel: UILabel?

    init(message: ChatSponsoredMessage, client: TDLibClient, actions: ChatSponsoredMessageActions) {
        self.message = message
        self.actions = actions
        self.accent = AvatarColorPalette.shared.nameColor(accentColorID: message.accentColorID)
        super.init(frame: .zero)
        layer.cornerRadius = 5
        layer.cornerCurve = .continuous
        clipsToBounds = true
        backgroundColor = accent.withAlphaComponent(0.1)

        let line = UIView()
        line.backgroundColor = accent
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        // `preferMediaBeforeText`: the ad's own media leads, full width.
        if message.media != nil {
            configureMedia(client: client)
            content.addArrangedSubview(mediaView)
            content.setCustomSpacing(6, after: mediaView)
        }

        let titleLabel = label(
            L10n.telegram(message.isRecommended ? "Message.AdRecommendedLabel" : "Message.AdSponsoredLabel"),
            weight: .semibold,
            color: accent,
            lines: 2,
        )
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleRow.addArrangedSubview(titleLabel)
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 5
        if message.canBeReported {
            configureBadge()
            titleRow.addArrangedSubview(badgeButton)
        }
        titleRow.setCustomSpacing(0, after: titleRow.arrangedSubviews.last ?? titleLabel)
        titleRow.addArrangedSubview(UIView())

        let column = UIStackView(arrangedSubviews: [titleRow])
        column.axis = .vertical
        column.spacing = 0
        if !message.title.isEmpty {
            let sponsorTitleLabel = label(message.title, weight: .semibold, color: .label, lines: 5)
            self.sponsorTitleLabel = sponsorTitleLabel
            column.addArrangedSubview(sponsorTitleLabel)
        }
        if !message.text.text.isEmpty {
            textView.linkTextAttributes = [.foregroundColor: accent]
            textView.configure(
                formattedText: message.text,
                client: client,
                statusText: "",
                statusColor: .secondaryLabel,
                maximumWidth: Utils.maxMessageContentWidth,
            )
            textView.onUnhandledTap = { [actions] in actions.activate(false) }
            // ChatController's openUrl counts a link of an ad as its click, then opens it as usual.
            textView.onOpenRichURL = { [actions] _ in
                actions.openLink()
                return false
            }
            column.setCustomSpacing(2, after: column.arrangedSubviews.last ?? titleRow)
            column.addArrangedSubview(textView)
        }

        let header = UIStackView(arrangedSubviews: [column])
        header.axis = .horizontal
        header.alignment = .top
        header.spacing = 6
        // The sponsor's photo stands in for media only when the ad has none (AdMessagesHistoryContext's `media`).
        if message.media == nil, let photo = message.sponsorPhoto,
           let size = photo.sizes.max(by: { $0.width * $0.height < $1.width * $1.height })
        {
            sponsorPhotoView.contentMode = .scaleAspectFill
            sponsorPhotoView.clipsToBounds = true
            sponsorPhotoView.layer.cornerRadius = 4
            sponsorPhotoView.layer.cornerCurve = .continuous
            sponsorPhotoView.load(
                file: size.photo,
                placeholderData: photo.minithumbnail?.data,
                maximumPixelSize: 320,
                client: client,
            )
            sponsorPhotoView.isUserInteractionEnabled = true
            sponsorPhotoView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(photoTapped)))
            NSLayoutConstraint.activate([
                sponsorPhotoView.widthAnchor.constraint(equalToConstant: 54),
                sponsorPhotoView.heightAnchor.constraint(equalToConstant: 54),
            ])
            header.addArrangedSubview(sponsorPhotoView)
        }
        content.addArrangedSubview(header)

        if !message.buttonText.isEmpty {
            let separator = UIView()
            separator.backgroundColor = accent.withAlphaComponent(0.2)
            separator.heightAnchor.constraint(equalToConstant: 1 / max(1, Utils.screen.scale)).isActive = true
            content.setCustomSpacing(7, after: header)
            content.addArrangedSubview(separator)
            configureActionButton()
            content.addArrangedSubview(actionButton)
        }

        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: topAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.widthAnchor.constraint(equalToConstant: 3),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: message.buttonText.isEmpty ? -6 : 0),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(bodyTapped))
        tap.delegate = self
        addGestureRecognizer(tap)
        accessibilityElements = [titleLabel] + column.arrangedSubviews.dropFirst()
            + (message.canBeReported ? [badgeButton] : []) + (message.buttonText.isEmpty ? [] : [actionButton])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = mediaView.bounds
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }

    private static func isImage(_ format: TDNativeThumbnailFormat) -> Bool {
        switch format {
        case .thumbnailFormatJpeg,
             .thumbnailFormatPng,
             .thumbnailFormatWebp: true
        default: false
        }
    }

    /// The text's width: the card's, less its insets and the sponsor's photo beside it.
    func setMaximumWidth(_ width: CGFloat) {
        let photo: CGFloat = sponsorPhotoView.superview == nil ? 0 : 54 + 6
        textView.setMaximumLayoutWidth(max(1, width - 17 - photo))
    }

    /// The width the card needs for its text, label and button, at most `width`.
    func preferredWidth(maximum width: CGFloat) -> CGFloat {
        guard message.media == nil else { return width }
        setMaximumWidth(width)
        let text = [
            textView.superview == nil ? 0 : textView.intrinsicContentSize.width,
            titleRow.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width,
            sponsorTitleLabel?.intrinsicContentSize.width ?? 0,
        ].max() ?? 0
        let photo: CGFloat = sponsorPhotoView.superview == nil ? 0 : 54 + 6
        let button = message.buttonText.isEmpty ? 0 : actionButton.intrinsicContentSize.width
        return min(width, ceil(max(text + photo, button)) + 17)
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        playbackVisible = isVisible
        textView.setCustomEmojiPlaybackVisible(isVisible)
        updatePlayback()
    }

    func prepareForRemoval() {
        player?.pause()
        looper?.disableLooping()
        readyObservation = nil
        playerLayer.player = nil
        player = nil
        looper = nil
        mediaImageView.cancel()
        sponsorPhotoView.cancel()
        textView.prepareForReuse()
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view, current !== self {
            if current === textView || current is UIControl || current === mediaView || current === sponsorPhotoView {
                return false
            }
            view = current.superview
        }
        return true
    }

    private func label(_ text: String, weight: UIFont.Weight, color: UIColor, lines: Int) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: Self.fontSize, weight: weight)
        label.textColor = color
        label.numberOfLines = lines
        return label
    }

    /// ChatMessageAttachedContentNode's title badge: "what's this?" in the accent colour on its 10% pill.
    private func configureBadge() {
        var configuration = UIButton.Configuration.plain()
        configuration.attributedTitle = AttributedString(
            L10n.telegram("Message.AdWhatIsThis"),
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 11)]),
        )
        configuration.baseForegroundColor = accent
        configuration.background.backgroundColor = accent.withAlphaComponent(0.1)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 1, leading: 5, bottom: 1, trailing: 5)
        badgeButton.configuration = configuration
        badgeButton.setContentHuggingPriority(.required, for: .horizontal)
        badgeButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        badgeButton.addAction(UIAction { [actions] _ in actions.openInfo() }, for: .touchUpInside)
    }

    /// ChatMessageAttachedContentButtonNode without a background: 36 pt, semibold 14 pt in the accent colour, and
    /// the link icon in its top corner for a link out of Telegram.
    private func configureActionButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.attributedTitle = AttributedString(
            message.buttonText.uppercased(),
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]),
        )
        configuration.baseForegroundColor = accent
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18)
        actionButton.configuration = configuration
        actionButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        actionButton.addAction(UIAction { [actions] _ in actions.activate(false) }, for: .touchUpInside)
        guard !message.opensInTelegram else { return }
        let icon = UIImageView(image: UIImage(
            systemName: "arrow.up.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold),
        ))
        icon.tintColor = accent
        icon.isUserInteractionEnabled = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: actionButton.topAnchor, constant: 5),
            icon.trailingAnchor.constraint(equalTo: actionButton.trailingAnchor, constant: -1),
        ])
    }

    /// ChatMessageInteractiveMediaNode with `automaticPlayback`: the picture, or the video or GIF looping silently
    /// from its downloaded file.
    private func configureMedia(client: TDLibClient) {
        mediaView.clipsToBounds = true
        mediaView.layer.cornerRadius = 4
        mediaView.layer.cornerCurve = .continuous
        mediaView.backgroundColor = .tertiarySystemFill
        mediaImageView.contentMode = .scaleAspectFill
        mediaImageView.clipsToBounds = true
        mediaImageView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.addSubview(mediaImageView)
        playerLayer.videoGravity = .resizeAspectFill
        mediaView.layer.addSublayer(playerLayer)
        NSLayoutConstraint.activate([
            mediaImageView.topAnchor.constraint(equalTo: mediaView.topAnchor),
            mediaImageView.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            mediaImageView.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            mediaImageView.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),
        ])
        let size = message.mediaSize ?? CGSize(width: 1, height: 1)
        let aspect = min(1.3, max(0.5, size.height / max(1, size.width)))
        mediaView.heightAnchor.constraint(equalTo: mediaView.widthAnchor, multiplier: aspect).isActive = true
        mediaView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(mediaTapped)))
        mediaView.isAccessibilityElement = true
        mediaView.accessibilityTraits = [.image, .button]
        switch message.media {
        case .photo(let photo):
            mediaView.accessibilityLabel = L10n.telegram("Message.Photo")
            if let file = message.mediaFile {
                mediaImageView.load(file: file, placeholderData: photo.minithumbnail?.data, client: client)
            } else {
                mediaImageView.loadPlaceholder(data: photo.minithumbnail?.data, client: client)
            }
        case .video(let video):
            mediaView.accessibilityLabel = L10n.telegram("Message.Video")
            loadThumbnail(video.thumbnail, minithumbnail: video.minithumbnail, client: client)
            installPlayer()
        case .animation(let animation):
            mediaView.accessibilityLabel = L10n.telegram("Message.Animation")
            loadThumbnail(animation.thumbnail, minithumbnail: animation.minithumbnail, client: client)
            installPlayer()
        case nil:
            break
        }
    }

    private func loadThumbnail(_ thumbnail: TDNativeThumbnail?, minithumbnail: Minithumbnail?, client: TDLibClient) {
        if let thumbnail, Self.isImage(thumbnail.format) {
            mediaImageView.load(file: thumbnail.file, placeholderData: minithumbnail?.data, client: client)
        } else {
            mediaImageView.loadPlaceholder(data: minithumbnail?.data, client: client)
        }
    }

    private func installPlayer() {
        guard let file = message.mediaFile, file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return }
        let player = AVQueuePlayer()
        player.isMuted = true
        self.player = player
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: URL(fileURLWithPath: file.local.path)))
        playerLayer.player = player
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            Task { @MainActor [weak self] in self?.mediaImageView.isHidden = ready }
        }
        updatePlayback()
    }

    /// Video and GIF autoplay as Power Saving allows, while the bubble shows.
    private func updatePlayback() {
        let feature: EnergyUsage.Item =
            if case .video = message.media {
                .autoplayVideo
            } else {
                .autoplayGif
            }
        if playbackVisible, window != nil, EnergyUsage.shared.allows(feature) {
            player?.play()
        } else {
            player?.pause()
        }
    }

    @objc private func bodyTapped() {
        actions.activate(false)
    }

    @objc private func photoTapped() {
        actions.activate(true)
    }

    /// ChatController's openMessage for an ad: a video opens full screen, any other media opens the ad's link.
    @objc private func mediaTapped() {
        if case .video = message.media, let file = message.mediaFile {
            actions.playVideo(file)
        } else {
            actions.activate(true)
        }
    }
}

// MARK: - ChatSponsoredMessageActionsView

/// ChatMessageShareButton for an ad: the close button beside the bubble's top and, when the ad can be reported,
/// the "more" button under it in the same pill.
final class ChatSponsoredMessageActionsView: UIView {
    var onClose: (() -> Void)?
    var onMore: (() -> Void)?

    private let closeButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let separator = UIView()
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 30)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 15
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]) { (self: Self, _) in
            self.updateBorder()
        }
        for (button, symbol, label) in [
            (closeButton, "xmark", L10n.telegram("Common.Close")),
            (moreButton, "ellipsis", L10n.telegram("Common.More")),
        ] {
            button.setImage(UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold),
            ), for: .normal)
            button.tintColor = .label
            button.accessibilityLabel = label
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        moreButton.addAction(UIAction { [weak self] _ in self?.onMore?() }, for: .touchUpInside)
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightConstraint,
            closeButton.topAnchor.constraint(equalTo: topAnchor),
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            moreButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            moreButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            moreButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            moreButton.heightAnchor.constraint(equalToConstant: 30),
            separator.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(1, Utils.screen.scale)),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBorder()
    }

    func configure(hasMore: Bool) {
        moreButton.isHidden = !hasMore
        separator.isHidden = !hasMore
        heightConstraint.constant = hasMore ? 60 : 30
    }

    private func updateBorder() {
        layer.borderWidth = 1 / max(1, traitCollection.displayScale)
        layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }
}

// MARK: - ChatSponsoredMessageCell

/// ChatMessageBubbleItemNode with an ad: an incoming bubble holding only the ad's attached content, without an author
/// name, date, reactions or swipe to reply, and ChatMessageShareButton's close button at its top.
final class ChatSponsoredMessageCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatSponsoredMessageCell"

    private(set) var messageID: Int64?

    private let bubbleContainer = TelegramContextMenuExtractableView()
    private let bubbleBackground = MessageBubbleBackgroundView()
    private let actionsView = ChatSponsoredMessageActionsView()
    private var card: ChatSponsoredMessageContentView?
    private var bubbleWidthConstraint: NSLayoutConstraint!
    private var measuredWidth = CGFloat.zero

    var contextPreviewView: UIView { bubbleContainer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The history is flipped; its rows turn back upright.
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
        let bubble = bubbleContainer.extractedContentView
        bubble.backgroundColor = .clear
        bubbleBackground.fillColor = .secondarySystemBackground
        bubbleBackground.configure(outgoing: false, merge: MessageBubbleMerge(), tail: true)
        bubbleBackground.translatesAutoresizingMaskIntoConstraints = false
        bubble.insertSubview(bubbleBackground, at: 0)
        bubbleContainer.onExtractionChange = { [weak self] extracted in
            self?.bubbleBackground.isExtracted = extracted
            self?.bubbleBackground.layoutIfNeeded()
        }
        bubbleContainer.translatesAutoresizingMaskIntoConstraints = false
        actionsView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleContainer)
        contentView.addSubview(actionsView)
        self.bubbleWidthConstraint = bubbleContainer.widthAnchor.constraint(equalToConstant: 280)
        // ChatMessageItemLayoutConstants: an incoming bubble 10 pt from the edge with 2⅓ pt above and below, and the
        // share button 8 pt after it, level with its top (ChatMessageBubbleItemNode with `adAttribute`).
        NSLayoutConstraint.activate([
            bubbleBackground.topAnchor.constraint(equalTo: bubble.topAnchor),
            bubbleBackground.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            bubbleBackground.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            bubbleBackground.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            bubbleContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7 / 3),
            bubbleContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7 / 3),
            bubbleContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            bubbleWidthConstraint,
            actionsView.leadingAnchor.constraint(equalTo: bubbleContainer.trailingAnchor, constant: 8),
            actionsView.topAnchor.constraint(equalTo: bubbleContainer.topAnchor, constant: 1),
            actionsView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.layer.removeAllAnimations()
        contentView.alpha = 1
    }

    override func layoutSubviews() {
        updateBubbleWidth(for: bounds.width)
        super.layoutSubviews()
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes,
    ) -> UICollectionViewLayoutAttributes {
        updateBubbleWidth(for: layoutAttributes.size.width)
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }

    func configure(message: ChatSponsoredMessage, client: TDLibClient, actions: ChatSponsoredMessageActions) {
        actionsView.onClose = actions.close
        actionsView.onMore = actions.more
        actionsView.configure(hasMore: message.canBeReported)
        guard messageID != message.id || card == nil else { return }
        messageID = message.id
        card?.prepareForRemoval()
        card?.removeFromSuperview()
        let card = ChatSponsoredMessageContentView(message: message, client: client, actions: actions)
        card.translatesAutoresizingMaskIntoConstraints = false
        let bubble = bubbleContainer.extractedContentView
        bubble.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8),
            card.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -8),
            card.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
        ])
        self.card = card
        measuredWidth = 0
        card.setPlaybackVisible(window != nil)
        accessibilityElements = [card, actionsView]
        setNeedsLayout()
    }

    func resetUnavailableContent() {
        card?.prepareForRemoval()
        card?.removeFromSuperview()
        card = nil
        messageID = nil
        actionsView.onClose = nil
        actionsView.onMore = nil
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        card?.setPlaybackVisible(isVisible)
    }

    /// ChatMessageBubbleItemNode's fade for an ad coming into view.
    func animateAppearance() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        contentView.alpha = 0
        UIView.animate(withDuration: 0.25, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.contentView.alpha = 1
        }
    }

    /// The widest bubble, as MessageCell's beside a share button: 82% of the row, less the button and its spacing.
    private func updateBubbleWidth(for cellWidth: CGFloat) {
        guard cellWidth > 0, let card, abs(measuredWidth - cellWidth) > 0.5 else { return }
        measuredWidth = cellWidth
        let maximum = min(floor(cellWidth * 0.82), floor(cellWidth - 30 - 8 - 12))
        let cardWidth = card.preferredWidth(maximum: maximum - 16)
        card.setMaximumWidth(cardWidth)
        bubbleWidthConstraint.constant = min(maximum, cardWidth + 16)
    }
}

// MARK: - ChatSponsoredVideoViewController

/// UniversalVideoGalleryItem for an ad's video: the video full screen with its sound, a tap to pause or play, and the
/// ad's button at the bottom, which closes the video and opens the ad as a click from full screen.
final class ChatSponsoredVideoViewController: UIViewController {
    override var prefersStatusBarHidden: Bool { true }

    private let player: AVPlayer
    private let playerLayer = AVPlayerLayer()
    private let buttonTitle: String
    private let onOpen: () -> Void
    private var endObserver: NSObjectProtocol?

    init(url: URL, buttonTitle: String, onOpen: @escaping () -> Void) {
        self.player = AVPlayer(url: url)
        self.buttonTitle = buttonTitle
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(togglePlayback)))
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.player.seek(to: .zero)
                self?.player.play()
            }
        }

        let close = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        close.setImage(UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold),
        ), for: .normal)
        close.tintColor = .white
        close.accessibilityLabel = L10n.telegram("Common.Close")

        let open = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            let onOpen = onOpen
            dismiss(animated: true) { onOpen() }
        })
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.attributedTitle = AttributedString(
            buttonTitle,
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]),
        )
        open.configuration = configuration
        open.isHidden = buttonTitle.isEmpty

        for subview in [close, open] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            open.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            open.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            open.heightAnchor.constraint(equalToConstant: 50),
            open.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
        ])
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        applyIPhoneDuoTopSafeArea()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        player.play()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    @objc private func togglePlayback() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }
}

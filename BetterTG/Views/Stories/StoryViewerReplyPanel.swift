// StoryViewerReplyPanel.swift

import TDLibKit
import UIKit

// MARK: - StoryReplyPanel

/// StoryItemSetContainerComponent's input panel under someone else's story: a user's story takes a private reply and
/// a group's story a comment where the account may write, beside the like button and, for a public story, the share
/// button. The account's own stories, channels and bots get none; a service account's story, an unsupported one and
/// one TDLib won't take replies to show Telegram's disabled placeholder instead of the field.
enum StoryReplyPanel {
    /// What the panel reads about the story's poster.
    enum Poster: Equatable {
        case user(isBot: Bool, isService: Bool, isSelf: Bool)
        /// A supergroup that isn't a channel, whether the account may send text there and whether it has a username.
        case group(canWrite: Bool, isPublic: Bool)
        /// A channel, and whether it has a username (Telegram's addressName).
        case channel(isPublic: Bool)
        case other
    }

    struct Configuration: Equatable {
        enum Field: Equatable {
            case input(placeholder: String)
            /// MessageInputPanelComponent's disabledPlaceholder: why the story takes no reply.
            case disabled(String)
        }

        let field: Field
        /// The reply is a comment in the group, as Story.SendReactionAsGroupMessage names it.
        let isGroup: Bool
        /// likeAction: everyone's but a service account's.
        let showsLike: Bool
        /// likeOptionsAction: holding the like button picks another reaction, on users' stories only.
        let offersLikeOptions: Bool
        /// forwardAction: a public story that may be forwarded.
        let showsForward: Bool

        var acceptsInput: Bool {
            if case .input = field { return true }
            return false
        }
    }

    /// The panel for the story, or nil where Telegram shows none.
    static func configuration(story: Story, poster: Poster) -> Configuration? {
        var isLive = false
        var isUnsupported = false
        switch story.content {
        case .storyContentLive: isLive = true
        case .storyContentUnsupported: isUnsupported = true
        case .storyContentPhoto,
             .storyContentVideo: break
        }
        // BetterTG shows a live stream as unsupported, without Telegram's live chat input.
        let showsForward = !isLive && StoryMoreMenu.isPublic(story) && story.canBeForwarded
        let unavailable = Configuration.Field.disabled(L10n.telegram("Story.FooterReplyUnavailable"))
        switch poster {
        case .user(let isBot, let isService, let isSelf):
            guard !isBot, !isSelf else { return nil }
            let replies = !isService && !isUnsupported && !isLive && story.canBeReplied
            return Configuration(
                field: replies
                    ? .input(placeholder: L10n.telegram("Story.InputPlaceholderReplyPrivately"))
                    : unavailable,
                isGroup: false,
                showsLike: !isService && !isLive,
                offersLikeOptions: !isService && !isLive,
                showsForward: showsForward,
            )
        case .group(let canWrite, _):
            // Where the account can't write, Telegram's channel footer takes the panel's place.
            guard canWrite else { return nil }
            return Configuration(
                field: isUnsupported || isLive
                    ? unavailable
                    : .input(placeholder: L10n.telegram("Story.InputPlaceholderReplyInGroup")),
                isGroup: true,
                showsLike: !isLive,
                offersLikeOptions: false,
                showsForward: showsForward,
            )
        case .channel,
             .other:
            return nil
        }
    }

    /// The poster's kind, whether it's the account itself, a bot or a service account, and for a group whether the
    /// account may send text there (Telegram's banSendText check).
    static func resolvePoster(chatID: Int64, client: TDLibClient) async -> Poster? {
        guard let chat = try? await client.send(TDNativeRequests.getChat(chatId: chatID)) else { return nil }
        switch chat.type {
        case .chatTypePrivate(let info):
            let user = try? await client.send(TDNativeRequests.getUser(userId: info.userId))
            let me = try? await client.send(TDNativeRequests.getMe())
            var isBot = false
            if case .userTypeBot = user?.type { isBot = true }
            return .user(
                isBot: isBot,
                isService: StoryMoreMenu.serviceUserIDs.contains(info.userId),
                isSelf: me?.id == info.userId,
            )
        case .chatTypeSupergroup(let info):
            let group = try? await client.send(TDNativeRequests.getSupergroup(supergroupId: info.supergroupId))
            let isPublic = group?.usernames?.activeUsernames.isEmpty == false
            if info.isChannel { return .channel(isPublic: isPublic) }
            return .group(canWrite: canWrite(status: group?.status, permissions: chat.permissions), isPublic: isPublic)
        case .chatTypeBasicGroup,
             .chatTypeSecret:
            return .other
        }
    }

    static func canWrite(status: ChatMemberStatus?, permissions: ChatPermissions) -> Bool {
        switch status {
        case .chatMemberStatusAdministrator,
             .chatMemberStatusCreator:
            true
        case .chatMemberStatusRestricted(let restricted):
            restricted.permissions.canSendBasicMessages && permissions.canSendBasicMessages
        case .chatMemberStatusBanned:
            false
        case .chatMemberStatusLeft,
             .chatMemberStatusMember,
             nil:
            permissions.canSendBasicMessages
        }
    }

    /// The text a reaction sends as a message: the emoji, or a custom emoji's fallback emoji carrying the custom one.
    static func messageText(for type: ReactionType, sticker: Sticker?) -> FormattedText? {
        if let emoji = type.standardEmoji {
            return FormattedText(entities: [], text: emoji)
        }
        guard let customEmojiID = type.customEmojiID, let sticker, !sticker.emoji.isEmpty else { return nil }
        let entity = TextEntity(
            length: (sticker.emoji as NSString).length,
            offset: 0,
            type: .textEntityTypeCustomEmoji(TextEntityTypeCustomEmoji(customEmojiId: customEmojiID)),
        )
        return FormattedText(entities: [entity], text: sticker.emoji)
    }
}

// MARK: - StoryReplyPanelView

/// MessageInputPanelComponent in its story style: a 40 pt field 14 pt below the panel's top and 6 pt above its bottom,
/// 9 pt from the leading edge, with the share and like buttons in 41 pt slots after it. While the field edits or
/// holds text, it widens to the send button's slot and the like and share buttons give way to it.
final class StoryReplyPanelView: UIView, UITextViewDelegate {
    static let fieldHeight = CGFloat(40)
    static let topInset = CGFloat(14)
    static let bottomInset = CGFloat(6)
    static let height = fieldHeight + topInset + bottomInset

    private static let sideInset = CGFloat(9)
    private static let buttonSize = CGFloat(33)
    private static let textInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    private static let maximumFieldHeight = CGFloat(122)

    var onSend: ((String) -> Void)?
    var onLike: (() -> Void)?
    /// Every state of the press held on the like button, so the reactions above it can follow the finger.
    var onLikeOptions: ((UILongPressGestureRecognizer) -> Void)?
    var onForward: (() -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    var onTextChanged: (() -> Void)?

    private(set) var configuration: StoryReplyPanel.Configuration?
    let likeButton = StoryLikeButton()

    private let fieldBackground: UIVisualEffectView = {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = false
        let view = UIVisualEffectView(effect: effect)
        view.isUserInteractionEnabled = false
        return view
    }()

    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private lazy var likeOptionsGesture = UILongPressGestureRecognizer(target: self, action: #selector(likeHeld(_:)))

    var isEditing: Bool {
        textView.isFirstResponder
    }

    var text: String {
        textView.text ?? ""
    }

    var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The field takes the send button's layout while it edits or keeps text.
    private var showsSendLayout: Bool {
        isEditing || !text.isEmpty
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(fieldBackground)

        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .white
        textView.tintColor = .white
        textView.keyboardAppearance = .dark
        textView.textContainerInset = Self.textInsets
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.delegate = self
        textView.accessibilityIdentifier = "story-reply-field"
        addSubview(textView)

        placeholderLabel.font = .systemFont(ofSize: 17)
        placeholderLabel.textColor = UIColor.white.withAlphaComponent(0.35)
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)

        let sendImage = UIImage(
            systemName: "arrow.up.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 30)
                .applying(UIImage.SymbolConfiguration(paletteColors: [.white, .systemBlue])),
        )
        sendButton.setImage(sendImage, for: .normal)
        sendButton.accessibilityLabel = L10n.telegram("MediaPicker.Send")
        sendButton.accessibilityIdentifier = "story-reply-send"
        sendButton.addAction(UIAction { [weak self] _ in self?.sendPressed() }, for: .touchUpInside)
        addSubview(sendButton)

        forwardButton.tintColor = .white
        forwardButton.setImage(
            UIImage(systemName: "paperplane", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)),
            for: .normal,
        )
        forwardButton.accessibilityLabel = L10n.telegram("Story.Context.Share")
        forwardButton.accessibilityIdentifier = "story-reply-share"
        forwardButton.addAction(UIAction { [weak self] _ in self?.onForward?() }, for: .touchUpInside)
        addSubview(forwardButton)

        likeButton.addAction(UIAction { [weak self] _ in self?.onLike?() }, for: .touchUpInside)
        likeOptionsGesture.minimumPressDuration = 0.3
        likeButton.addGestureRecognizer(likeOptionsGesture)
        addSubview(likeButton)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let fieldHeight = max(Self.fieldHeight, bounds.height - Self.topInset - Self.bottomInset)
        let field = fieldFrame(width: width, fieldHeight: fieldHeight)
        fieldBackground.frame = field
        fieldBackground.cornerConfiguration = .corners(radius: .fixed(Double(Self.fieldHeight / 2)))
        textView.frame = field
        textView.isScrollEnabled = fieldHeight >= Self.maximumFieldHeight
        let placeholderInsets = Self.textInsets
        placeholderLabel.frame = CGRect(
            x: field.minX + placeholderInsets.left,
            y: field.minY,
            width: field.width - placeholderInsets.left - placeholderInsets.right,
            height: Self.fieldHeight,
        )
        // The buttons sit on the field's last line.
        let buttonY = field.maxY - Self.fieldHeight + (Self.fieldHeight - Self.buttonSize) / 2
        let slotX = field.maxX + 4
        sendButton.frame = CGRect(x: slotX, y: buttonY, width: Self.buttonSize, height: Self.buttonSize)
        let showsForward = configuration?.showsForward == true
        forwardButton.frame = CGRect(x: slotX + 3, y: buttonY, width: Self.buttonSize, height: Self.buttonSize)
        let likeX = showsForward ? slotX + 44 : slotX + 3
        likeButton.frame = CGRect(x: likeX, y: buttonY, width: Self.buttonSize, height: Self.buttonSize)
    }

    func configure(_ configuration: StoryReplyPanel.Configuration?) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        switch configuration?.field {
        case .input(let placeholder):
            placeholderLabel.text = placeholder
            placeholderLabel.textAlignment = .natural
            textView.isEditable = true
            textView.isHidden = false
        case .disabled(let text):
            if isEditing { textView.resignFirstResponder() }
            textView.text = ""
            placeholderLabel.text = text
            placeholderLabel.textAlignment = .center
            textView.isEditable = false
            textView.isHidden = true
        case nil:
            if isEditing { textView.resignFirstResponder() }
            textView.text = ""
        }
        likeOptionsGesture.isEnabled = configuration?.offersLikeOptions == true
        updateControls()
        setNeedsLayout()
    }

    /// The like button shows the story's chosen reaction.
    func setReaction(_ reaction: ReactionType?, client: TDLibClient, loadsSticker: Bool, animated: Bool) {
        likeButton.setReaction(reaction, client: client, loadsSticker: loadsSticker, animated: animated)
    }

    func beginEditing() {
        guard configuration?.acceptsInput == true else { return }
        textView.becomeFirstResponder()
    }

    func endEditing() {
        textView.resignFirstResponder()
    }

    func clearText() {
        textView.text = ""
        textViewDidChange(textView)
    }

    #if DEBUG
        func probeSetText(_ text: String) {
            textView.text = text
            textViewDidChange(textView)
        }
    #endif

    /// The panel's height for its text: one 40 pt line, growing with the text to five lines.
    func preferredHeight(width: CGFloat) -> CGFloat {
        guard configuration?.acceptsInput == true, !text.isEmpty else { return Self.height }
        let fieldWidth = fieldFrame(width: width, fieldHeight: Self.fieldHeight).width
        let fitted = textView.sizeThatFits(CGSize(width: fieldWidth, height: .greatestFiniteMagnitude)).height
        let fieldHeight = min(Self.maximumFieldHeight, max(Self.fieldHeight, ceil(fitted)))
        return fieldHeight + Self.topInset + Self.bottomInset
    }

    // MARK: UITextViewDelegate

    func textViewDidBeginEditing(_: UITextView) {
        updateControls()
        setNeedsLayout()
        onEditingChanged?(true)
    }

    func textViewDidEndEditing(_: UITextView) {
        updateControls()
        setNeedsLayout()
        onEditingChanged?(false)
    }

    func textViewDidChange(_: UITextView) {
        updateControls()
        setNeedsLayout()
        onTextChanged?()
    }

    func textView(_: UITextView, shouldChangeTextIn _: NSRange, replacementText text: String) -> Bool {
        // Return sends, as the story field's single-line send does; a shifted return still breaks the line.
        guard text == "\n" else { return true }
        sendPressed()
        return false
    }

    /// The field's frame: up to the send button's slot while it edits; otherwise before the share and like slots,
    /// 99 pt short of the width with both, 50 pt with one, and to the edge's inset without either.
    private func fieldFrame(width: CGFloat, fieldHeight: CGFloat) -> CGRect {
        let trailing: CGFloat
        if configuration?.acceptsInput == true, showsSendLayout {
            trailing = 41
        } else {
            let showsLike = configuration?.showsLike == true
            let showsForward = configuration?.showsForward == true
            trailing =
                switch (showsLike, showsForward) {
                case (true, true): 90
                case (false, true),
                     (true, false): 41
                case (false, false): Self.sideInset
                }
        }
        return CGRect(
            x: Self.sideInset,
            y: Self.topInset,
            width: max(1, width - Self.sideInset - trailing),
            height: fieldHeight,
        )
    }

    private func updateControls() {
        let acceptsInput = configuration?.acceptsInput == true
        let sending = acceptsInput && showsSendLayout
        placeholderLabel.isHidden = acceptsInput && !text.isEmpty
        sendButton.isHidden = !sending
        sendButton.isEnabled = hasText
        sendButton.alpha = hasText ? 1 : 0.5
        forwardButton.isHidden = sending || configuration?.showsForward != true
        likeButton.isHidden = sending || configuration?.showsLike != true
    }

    private func sendPressed() {
        guard hasText else { return }
        onSend?(text)
    }

    @objc private func likeHeld(_ gesture: UILongPressGestureRecognizer) {
        onLikeOptions?(gesture)
    }
}

// MARK: - StoryLikeButton

/// MessageInputActionButtonComponent's like mode: an outlined heart, Telegram's red heart once liked, or the chosen
/// reaction's emoji; a new reaction bounces in.
final class StoryLikeButton: UIControl {
    private static let likedColor = UIColor(red: 1, green: 59 / 255, blue: 48 / 255, alpha: 1)

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    private(set) var reaction: ReactionType?

    private let heartView = UIImageView()
    private let emojiLabel = UILabel()
    private let stickerView = CustomEmojiInlineView()
    private var stickerTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        heartView.contentMode = .center
        heartView.isUserInteractionEnabled = false
        addSubview(heartView)
        emojiLabel.font = .systemFont(ofSize: 24)
        emojiLabel.textAlignment = .center
        emojiLabel.isUserInteractionEnabled = false
        addSubview(emojiLabel)
        stickerView.isUserInteractionEnabled = false
        stickerView.isHidden = true
        stickerView.onFirstFrameReady = { [weak self] in self?.stickerView.isHidden = false }
        addSubview(stickerView)
        isAccessibilityElement = true
        accessibilityIdentifier = "story-reply-like"
        accessibilityLabel = L10n.betterTG("Accessibility.StoryLike")
        show(nil, client: nil, loadsSticker: false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stickerTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        heartView.frame = bounds
        emojiLabel.frame = bounds
        stickerView.frame = bounds.insetBy(dx: 2, dy: 2)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stickerView.setPlaybackVisible(window != nil)
    }

    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        bounds.insetBy(dx: -4, dy: -6).contains(point)
    }

    /// Telegram's ❤ reaction, with or without the variation selector.
    private static func isHeart(_ emoji: String) -> Bool {
        emoji.unicodeScalars.first?.value == 0x2764
    }

    func setReaction(_ reaction: ReactionType?, client: TDLibClient, loadsSticker: Bool, animated: Bool) {
        guard reaction != self.reaction else { return }
        show(reaction, client: client, loadsSticker: loadsSticker)
        guard animated, reaction != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.45,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.transform = .identity
        }
    }

    private func show(_ reaction: ReactionType?, client: TDLibClient?, loadsSticker: Bool) {
        self.reaction = reaction
        stickerTask?.cancel()
        stickerTask = nil
        stickerView.prepareForReuse()
        stickerView.isHidden = true
        accessibilityTraits = reaction == nil ? .button : [.button, .selected]
        let isHeart = reaction == nil || reaction?.standardEmoji.map(Self.isHeart) == true
        heartView.isHidden = !isHeart
        heartView.image = UIImage(
            systemName: reaction == nil ? "heart" : "heart.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular),
        )
        heartView.tintColor = reaction == nil ? .white : Self.likedColor
        emojiLabel.isHidden = isHeart
        emojiLabel.text = isHeart ? nil : reaction?.standardEmoji
        guard !isHeart, let customEmojiID = reaction?.customEmojiID, let client, loadsSticker else { return }
        stickerTask = Task { [weak self] in
            let stickers = await CustomEmojiStickerRepository.shared.stickers(for: [customEmojiID], client: client)
            guard let self, !Task.isCancelled, self.reaction?.customEmojiID == customEmojiID,
                  let sticker = stickers[customEmojiID] else { return }
            emojiLabel.text = sticker.emoji
            stickerView.configure(sticker: sticker, client: client)
        }
    }
}

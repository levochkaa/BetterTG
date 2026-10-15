// MessageCommentFooterView.swift

import TDLibKit
import UIKit

// MARK: - MessageCommentFooterView

/// Telegram's comments bar at the bottom of a channel post (`ChatMessageCommentFooterContentNode`): the comments
/// icon or up to three recent commenters, "Leave a Comment" or "N Comments", a dot for unread comments and an arrow
/// that turns into a spinner while the thread opens.
final class MessageCommentFooterView: UIControl {
    private struct Avatar {
        let file: File?
        let minithumbnail: Minithumbnail?
        let placeholder: TelegramAvatarPlaceholder
    }

    /// The bar sits inside the bubble's 8 pt content inset; its separator reaches the bubble's edges.
    static let bubbleInset: CGFloat = 8

    private static let height: CGFloat = 38
    /// Room for the arrow after the title (Telegram's 24 pt text inset plus the bubble's).
    private static let trailingInset: CGFloat = 29
    private static let avatarSize: CGFloat = 30
    private static let avatarSpacing: CGFloat = 20
    private static let avatarBorder: CGFloat = 1.5
    private static let maximumAvatarCount = 3

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            // HighlightTrackingButtonNode: 0.4 while pressed, then back to 1 over 0.2 s.
            contentView.layer.removeAnimation(forKey: "highlight")
            contentView.alpha = isHighlighted ? 0.4 : 1
            guard !isHighlighted else { return }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.4
            fade.toValue = 1
            fade.duration = 0.2
            contentView.layer.add(fade, forKey: "highlight")
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: ceil(textOriginX + titleWidth(title) + Self.trailingInset), height: Self.height)
    }

    private(set) var title = ""

    var showsSeparator = true {
        didSet { separatorView.isHidden = !showsSeparator }
    }

    private let contentView = UIView()
    private let separatorView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let unreadDotView = UIView()
    private let arrowView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var avatarRings = [UIView]()
    private var avatarViews = [ProfileAvatarView]()
    private var shortTitle: String?
    private var onTap: (() -> Void)?
    private var repliers = [MessageSender]()
    private var repliersClientID: Int32?
    /// Slots are reserved for every recent commenter at once, so the title doesn't move when their avatars load.
    private var avatarCount = 0
    private var avatarTask: Task<Void, Never>?
    private var avatarGeneration = 0

    private var textOriginX: CGFloat {
        avatarCount == 0 ? 42 : 45 + Self.avatarSpacing * CGFloat(avatarCount - 1)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        contentView.isUserInteractionEnabled = false
        addSubview(contentView)

        separatorView.backgroundColor = .separator
        contentView.addSubview(separatorView)

        iconView.image = UIImage(
            systemName: "bubble.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular),
        )
        iconView.tintColor = .systemBlue
        contentView.addSubview(iconView)

        for _ in 0..<Self.maximumAvatarCount {
            let ring = UIView()
            ring.backgroundColor = .secondarySystemBackground
            ring.layer.cornerRadius = Self.avatarSize / 2 + Self.avatarBorder
            ring.isHidden = true
            let avatar = ProfileAvatarView()
            avatar.showsContextMenu = false
            avatar.isUserInteractionEnabled = false
            avatar.frame = CGRect(
                x: Self.avatarBorder,
                y: Self.avatarBorder,
                width: Self.avatarSize,
                height: Self.avatarSize,
            )
            ring.addSubview(avatar)
            avatarRings.append(ring)
            avatarViews.append(avatar)
        }
        // The first commenter overlaps the next.
        avatarRings.reversed().forEach(contentView.addSubview)

        titleLabel.font = .body
        titleLabel.textColor = .systemBlue
        titleLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(titleLabel)

        unreadDotView.backgroundColor = .systemBlue
        unreadDotView.layer.cornerRadius = 3
        unreadDotView.isHidden = true
        contentView.addSubview(unreadDotView)

        arrowView.image = UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold),
        )
        arrowView.tintColor = .systemBlue
        contentView.addSubview(arrowView)

        spinner.color = .systemBlue
        spinner.hidesWhenStopped = true
        contentView.addSubview(spinner)

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = bounds
        separatorView.frame = CGRect(
            x: -Self.bubbleInset,
            y: 0,
            width: bounds.width + Self.bubbleInset * 2,
            height: 1 / max(traitCollection.displayScale, 1),
        )
        let midY = bounds.height / 2
        let iconSize = iconView.image?.size ?? .zero
        iconView.frame = CGRect(
            x: 7,
            y: round(midY - iconSize.height / 2),
            width: iconSize.width,
            height: iconSize.height,
        )
        let ringSize = Self.avatarSize + Self.avatarBorder * 2
        for (index, ring) in avatarRings.enumerated() {
            ring.frame = CGRect(
                x: 5 - Self.avatarBorder + Self.avatarSpacing * CGFloat(index),
                y: round(midY - ringSize / 2),
                width: ringSize,
                height: ringSize,
            )
        }
        let arrowSize = arrowView.image?.size ?? .zero
        arrowView.frame = CGRect(
            x: bounds.width - 10 - arrowSize.width,
            y: round(midY - arrowSize.height / 2),
            width: arrowSize.width,
            height: arrowSize.height,
        )
        spinner.center = CGPoint(x: arrowView.frame.midX, y: midY)

        // Telegram switches to the short title when the full one would be truncated.
        let textX = textOriginX
        let available = max(0, bounds.width - textX - Self.trailingInset)
        let text = titleWidth(title) > available + 0.5 ? shortTitle ?? title : title
        if titleLabel.text != text { titleLabel.text = text }
        let titleSize = titleLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: bounds.height))
        titleLabel.frame = CGRect(
            x: textX,
            y: round(midY - titleSize.height / 2),
            width: min(ceil(titleSize.width), available),
            height: ceil(titleSize.height),
        )
        unreadDotView.frame = CGRect(x: titleLabel.frame.maxX + 4, y: round(midY - 3) + 1, width: 6, height: 6)
    }

    /// "Leave a Comment" with its short form, or "N Comments" (Conversation.MessageViewCommentsFormat).
    static func titles(replyCount: Int) -> (full: String, short: String?) {
        guard replyCount > 0 else {
            return (
                L10n.telegram("Conversation.MessageLeaveComment"),
                L10n.telegram("Conversation.MessageLeaveCommentShort"),
            )
        }
        // The plural form brackets its count, as in "[%@]Comments"; the format places the count itself.
        var noun = L10n.telegramPlural("Conversation.MessageViewComments", count: replyCount)
        if let start = noun.firstIndex(of: "["), let end = noun.firstIndex(of: "]"), start < end {
            noun.removeSubrange(start...end)
        } else {
            noun = noun.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789-,. "))
        }
        return (L10n.telegram("Conversation.MessageViewCommentsFormat", "\(replyCount)", noun), nil)
    }

    private static func avatar(for sender: MessageSender, client: TDLibClient) async -> Avatar? {
        switch sender {
        case .messageSenderUser(let value):
            guard let user = try? await client.getUser(userId: value.userId) else { return nil }
            return Avatar(
                file: user.profilePhoto?.small,
                minithumbnail: user.profilePhoto?.minithumbnail,
                placeholder: user.telegramAvatarPlaceholder,
            )
        case .messageSenderChat(let value):
            guard let chat = try? await client.getChat(chatId: value.chatId) else { return nil }
            return Avatar(
                file: chat.photo?.small,
                minithumbnail: chat.photo?.minithumbnail,
                placeholder: TelegramAvatarPlaceholder(
                    peerID: chat.id,
                    accentColorID: chat.accentColorId,
                    upgradedGiftColors: chat.upgradedGiftColors,
                    letters: chat.title.first.map { [String($0).uppercased()] } ?? [],
                    isDeleted: false,
                ),
            )
        }
    }

    /// `isEnabled` is false for a post that hasn't reached the server and while messages are selected.
    func configure(
        replyInfo: MessageReplyInfo,
        isEnabled: Bool,
        isLoading: Bool,
        client: TDLibClient,
        onTap: @escaping () -> Void,
    ) {
        self.onTap = onTap
        self.isEnabled = isEnabled
        isUserInteractionEnabled = isEnabled
        alpha = isEnabled ? 1 : 0.5
        let titles = Self.titles(replyCount: replyInfo.replyCount)
        if title != titles.full || shortTitle != titles.short {
            title = titles.full
            shortTitle = titles.short
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
        accessibilityLabel = title
        // Telegram marks unseen comments when the thread's last message is past the read one; TDLib reports 0 for
        // an unknown read position.
        unreadDotView.isHidden = replyInfo.lastReadInboxMessageId == 0
            || replyInfo.lastMessageId <= replyInfo.lastReadInboxMessageId
        setLoading(isLoading)
        updateRepliers(Array(replyInfo.recentReplierIds.prefix(Self.maximumAvatarCount)), client: client)
    }

    /// Telegram's `currentMessageWithLoadingReplyThread`: a spinner replaces the arrow while the thread loads.
    func setLoading(_ isLoading: Bool) {
        arrowView.isHidden = isLoading
        if isLoading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

    func prepareForReuse() {
        avatarTask?.cancel()
        avatarTask = nil
        avatarGeneration &+= 1
        repliers = []
        repliersClientID = nil
        avatarCount = 0
        resetAvatars()
        onTap = nil
        title = ""
        shortTitle = nil
        titleLabel.text = nil
        accessibilityLabel = nil
        unreadDotView.isHidden = true
        showsSeparator = true
        isHighlighted = false
        contentView.layer.removeAnimation(forKey: "highlight")
        contentView.alpha = 1
        isEnabled = true
        isUserInteractionEnabled = true
        alpha = 1
        setLoading(false)
        invalidateIntrinsicContentSize()
    }

    @objc private func tapped() {
        onTap?()
    }

    private func titleWidth(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil((text as NSString).size(withAttributes: [.font: titleLabel.font as Any]).width)
    }

    /// Telegram reads the commenters from the message's peers; TDLib's local cache answers `getUser` and `getChat`
    /// for them, and a result for a replaced list or client is dropped.
    private func updateRepliers(_ senders: [MessageSender], client: TDLibClient) {
        guard senders != repliers || repliersClientID != client.id else { return }
        avatarTask?.cancel()
        avatarGeneration &+= 1
        let generation = avatarGeneration
        repliers = senders
        repliersClientID = client.id
        resetAvatars()
        avatarCount = senders.count
        iconView.isHidden = avatarCount > 0
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        guard !senders.isEmpty else {
            avatarTask = nil
            return
        }
        avatarTask = Task { [weak self] in
            var avatars = [Avatar]()
            for sender in senders {
                guard !Task.isCancelled else { return }
                if let avatar = await Self.avatar(for: sender, client: client) { avatars.append(avatar) }
            }
            guard let self, !Task.isCancelled, avatarGeneration == generation else { return }
            avatarTask = nil
            showAvatars(avatars, client: client)
        }
    }

    private func showAvatars(_ avatars: [Avatar], client: TDLibClient) {
        for (index, avatar) in avatars.enumerated() where index < avatarViews.count {
            avatarViews[index].configure(
                file: avatar.file,
                minithumbnail: avatar.minithumbnail,
                placeholder: avatar.placeholder,
                usesPeerPhotoForSavedMessages: true,
                client: client,
            )
            avatarRings[index].isHidden = false
        }
        if avatars.count != avatarCount {
            avatarCount = avatars.count
            iconView.isHidden = avatarCount > 0
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    private func resetAvatars() {
        for (ring, avatar) in zip(avatarRings, avatarViews) {
            avatar.prepareForReuse()
            ring.isHidden = true
        }
        iconView.isHidden = false
    }
}

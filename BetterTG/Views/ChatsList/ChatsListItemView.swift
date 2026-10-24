// ChatsListItemView.swift

import Combine
import TDLibKit
import UIKit

// MARK: - ChatListCell

final class ChatListCell: UITableViewCell {
    // MARK: Internal

    static let reuseIdentifier = "ChatListCell"
    /// A card row: the 76 pt card and 4 pt above and below it.
    static let cardRowHeight = CGFloat(84)

    private static let cardHorizontalInset = CGFloat(20)
    private static let cardVerticalInset = CGFloat(4)
    /// UITableView's inset-grouped section radius, as the Settings cards have it.
    private static let cardCornerRadius = CGFloat(26)

    /// BetterTG's chat card, styled like the Settings cards: inset from the sides, rounded, on the grouped
    /// background. Plain rows (search results) keep the full-width row with a separator.
    var usesCardStyle = true {
        didSet {
            guard usesCardStyle != oldValue else { return }
            applyStyle()
        }
    }

    /// Opens the chat's stories from its avatar, zooming from the given view (ChatListItem.avatarStoryTapGesture).
    var onOpenStories: ((UIView) -> Void)? {
        didSet { updateStoryInteraction() }
    }

    // MARK: Private

    private let rowView = UIView()
    private let separatorView = UIView()
    private let pinView = UIImageView(image: UIImage(systemName: "pin.fill"))
    private let muteView = UIImageView(image: UIImage(systemName: "speaker.slash.fill"))
    private let avatarView = ProfileAvatarView()
    /// ChatListItem's PeerOnlineMarkerNode: a 14 pt dot, its 2 pt ring in the row's colour, 2 pt inside the avatar's
    /// corner.
    private let onlineMarker = ChatListOnlineMarkerView()
    /// Telegram's story ring around the avatar (ChatListItem: 2.33 pt, 1.33 pt once seen).
    private let storyRingView = StoryAvatarRingView(activeLineWidth: 2.33, inactiveLineWidth: 1.33)
    private lazy var storyTapGesture = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    /// Telegram's mention or reaction badge, left of the unread count (ChatListItem, mentionBadgeNode).
    private let mentionBadgeView = UIImageView()
    private let trailingBadges = UIStackView()
    private let trailingStatusView = UIView()
    private var accessoryWidthConstraint: NSLayoutConstraint!
    private let dateLabel = UILabel()
    private let deliveryView = UIImageView()
    private let headerAccessoryRow = UIStackView()
    private let unreadLabel = TelegramUnreadBadgeLabel(
        minimumDiameter: 20,
        horizontalPadding: 10,
        usesStableChatListWidth: true,
    )
    private var pinned = false
    /// The configuration a late sender name re-applies, if the cell still shows that chat.
    private weak var configuredChat: CustomChat?
    private var configuredMuted = false
    private var configuredArchived = false
    private var configuredClient: TDLibClient?
    private var activityCancellable: AnyCancellable?
    private var rowInsetConstraints = [NSLayoutConstraint]()
    private var plainTextConstraints = [NSLayoutConstraint]()
    private var cardTextConstraints = [NSLayoutConstraint]()

    var contextPreviewView: UIView { rowView }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .systemBackground
        selectionStyle = .none
        // Pinned rows show a reorder handle while the list reorders them.
        showsReorderControl = true
        isAccessibilityElement = true
        configureViews()
        configureConstraints()
        applyStyle()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
        onOpenStories = nil
        activityCancellable = nil
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        updateBackground(highlighted: highlighted, animated: animated)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        updateBackground(highlighted: selected, animated: animated)
    }

    /// The chat list's date: the time today, the weekday within a week, else the day.
    static func dateText(timestamp: Int) -> String {
        let date = Foundation.Date(timeIntervalSince1970: TimeInterval(timestamp))
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day,
           (0...6).contains(days)
        {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: .now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.day().month(.twoDigits).year(.twoDigits))
    }

    /// Telegram draws a secret chat's title in green after a lock (`ChatListItem`, `secretTitleColor`).
    private static func title(for chat: CustomChat, font: UIFont) -> NSAttributedString {
        guard chat.secretChatID != nil else {
            // ChatListItem's credibility icon after the title.
            return PeerCredibilityBadge.title(
                chat.displayTitle,
                badge: PeerCredibilityBadge(chat: chat),
                font: font,
                color: .label,
            )
        }
        let configuration = UIImage.SymbolConfiguration(font: font, scale: .small)
        let lock = NSTextAttachment(
            image: UIImage(systemName: "lock.fill", withConfiguration: configuration)?
                .withTintColor(.systemGreen, renderingMode: .alwaysOriginal) ?? UIImage(),
        )
        let title = NSMutableAttributedString(attachment: lock)
        title.append(NSAttributedString(
            string: " " + chat.displayTitle,
            attributes: [.foregroundColor: UIColor.systemGreen],
        ))
        return title
    }

    private static func dateText(for chat: CustomChat) -> String? {
        guard let timestamp = chat.draftMessage?.date ?? chat.lastMessage?.date else { return nil }
        return dateText(timestamp: timestamp)
    }

    /// Telegram (ChatListItem) shows an unseen mention first, then unseen reactions. The mention badge greys only in
    /// the archive, the reaction badge for a muted chat.
    private static func mentionBadgeImage(for chat: CustomChat, isMuted: Bool, isArchived: Bool) -> UIImage? {
        if chat.chat.unreadMentionCount > 0 {
            ChatListMentionBadge.image(.mention, inactive: isArchived)
        } else if chat.chat.unreadReactionCount > 0 {
            ChatListMentionBadge.image(.reaction, inactive: isMuted)
        } else {
            nil
        }
    }

    private static func deliveryState(for chat: CustomChat) -> (
        image: UIImage?,
        color: UIColor,
        accessibilityText: String,
    )? {
        guard chat.draftMessage == nil,
              let message = chat.lastMessage,
              message.isOutgoing
        else { return nil }
        switch message.sendingState {
        case .messageSendingStateFailed:
            return (UIImage(systemName: "exclamationmark.circle"), .systemRed, L10n.telegram("VoiceOver.Chat.Failed"))
        case .messageSendingStatePending:
            return (UIImage(systemName: "clock"), .secondaryLabel, L10n.telegram("VoiceOver.Chat.Sending"))
        case nil:
            return message.id <= chat.chat.lastReadOutboxMessageId
                ? (
                    TelegramDeliveryCheck.image(isRead: true),
                    .systemBlue,
                    L10n.telegram("Conversation.ChecksTooltip.Read"),
                )
                : (
                    TelegramDeliveryCheck.image(isRead: false),
                    .systemBlue,
                    L10n.telegram("Conversation.ChecksTooltip.Delivered"),
                )
        }
    }

    func configure(chat: CustomChat, isMuted: Bool, isArchived: Bool = false, client: TDLibClient) {
        // A presence change on the same chat animates the marker; a reused row snaps to its new chat.
        let sameChat = configuredChat?.id == chat.id
        configuredChat = chat
        configuredMuted = isMuted
        configuredArchived = isArchived
        configuredClient = client
        pinned = chat.position.isPinned
        titleLabel.attributedText = Self.title(for: chat, font: titleLabel.font)
        messageLabel.attributedText = activityText(for: chat, client: client) ?? summaryText(for: chat, client: client)
        let chatID = chat.id
        activityCancellable = ChatListActivities.shared
            .changes
            .filter { $0 == chatID }
            .sink { [weak self] _ in
                guard let self, let chat = configuredChat, chat.id == chatID,
                      let client = configuredClient else { return }
                messageLabel.attributedText = activityText(for: chat, client: client)
                    ?? summaryText(for: chat, client: client)
            }
        let hasUnread = chat.unreadCount > 0 || chat.chat.isMarkedAsUnread
        let mentionBadge = Self.mentionBadgeImage(for: chat, isMuted: isMuted, isArchived: isArchived)
        mentionBadgeView.image = mentionBadge
        mentionBadgeView.isHidden = mentionBadge == nil
        // Telegram shows the pin only when no badge is shown.
        pinView.isHidden = !pinned || hasUnread || mentionBadge != nil
        muteView.isHidden = !isMuted || hasUnread || pinned || mentionBadge != nil
        unreadLabel.text = chat.unreadCount > 0 ? compactNumericCountString(chat.unreadCount) : nil
        unreadLabel.backgroundColor = isMuted ? .systemGray : .systemBlue
        unreadLabel.isHidden = !hasUnread
        dateLabel.text = Self.dateText(for: chat)
        let delivery = Self.deliveryState(for: chat)
        deliveryView.image = delivery?.image
        deliveryView.tintColor = delivery?.color
        deliveryView.isHidden = delivery == nil
        let accessoryWidth = hasUnread
            ? unreadLabel.intrinsicContentSize.width
            : (pinView.isHidden && muteView.isHidden ? 0 : 14)
        accessoryWidthConstraint.constant = accessoryWidth
        trailingStatusView.isHidden = accessoryWidth == 0
        setNeedsLayout()
        updateBackground(highlighted: isHighlighted || isSelected, animated: false)
        if chat.isHeldThroughClientRenewal {
            avatarView.configureHeldThroughClientRenewal(
                file: chat.chat.photo?.small,
                minithumbnail: chat.chat.photo?.minithumbnail,
                placeholder: chat.telegramAvatarPlaceholder,
                client: client,
            )
        } else {
            avatarView.configure(
                file: chat.chat.photo?.small,
                largeFile: chat.chat.photo?.big,
                minithumbnail: chat.chat.photo?.minithumbnail,
                placeholder: chat.telegramAvatarPlaceholder,
                client: client,
            )
        }
        let showsOnline = !chat.isSavedMessages && chat.user?.showsOnlineMarker == true
        onlineMarker.setVisible(showsOnline, animated: sameChat && window != nil)
        let storyStyle = chat.activeStoryState?.ringStyle
        storyRingView.style = storyStyle
        let avatarScale = StoryAvatarRingView.avatarScale(diameter: 60, lineWidth: 2.33)
        avatarView.transform = storyStyle == nil ? .identity : CGAffineTransform(scaleX: avatarScale, y: avatarScale)
        updateStoryInteraction()
        accessibilityLabel = [
            chat.displayTitle,
            messageLabel.text,
            dateLabel.text,
            delivery?.accessibilityText,
            pinned ? L10n.betterTG("Accessibility.Pinned") : nil,
            isMuted ? L10n.betterTG("Accessibility.Muted") : nil,
            hasUnread
                ? (chat.unreadCount > 0
                    ? L10n.telegramPlural("VoiceOver.Chat.UnreadMessages", count: chat.unreadCount)
                    : L10n.telegram("DialogList.Unread"))
                : nil,
            chat.chat.unreadMentionCount > 0
                ? L10n.betterTG("Accessibility.UnreadMentions", chat.chat.unreadMentionCount)
                : nil,
            chat.chat.unreadReactionCount > 0
                ? L10n.betterTG("Accessibility.UnreadReactions", chat.chat.unreadReactionCount)
                : nil,
        ]
            .compactMap(\.self)
            .joined(separator: ", ")
        accessibilityTraits = .button
    }

    /// The avatar opens stories only while the chat has some and the list offers it; otherwise a tap selects the row.
    private func updateStoryInteraction() {
        let isAvailable = storyRingView.style != nil && onOpenStories != nil
        storyTapGesture.isEnabled = isAvailable
        accessibilityCustomActions = isAvailable
            ? [UIAccessibilityCustomAction(name: L10n.telegram("Chat.StoryMentionAction")) { [weak self] _ in
                self?.openStories() ?? false
            }]
            : nil
    }

    @objc private func avatarTapped() {
        _ = openStories()
    }

    private func openStories() -> Bool {
        guard storyRingView.style != nil, let onOpenStories else { return false }
        onOpenStories(avatarView)
        return true
    }

    /// Telegram replaces the row's message with who is typing or sending, while they do (`ChatListTypingNode`).
    private func activityText(for chat: CustomChat, client: TDLibClient) -> NSAttributedString? {
        guard let text = ChatListActivities.shared.text(for: chat, client: client), !text.isEmpty else { return nil }
        return NSAttributedString(string: text + "…", attributes: [.foregroundColor: UIColor.secondaryLabel])
    }

    private func summaryText(for chat: CustomChat, client: TDLibClient) -> NSAttributedString? {
        var missing = [Int64]()
        defer { requestUsers(missing, chat: chat, client: client) }
        let lastMessage = chat.draftMessage == nil ? chat.lastMessage : nil
        if let message = lastMessage, let service = ChatPreviewText.serviceText(
            for: message, chatTitle: chat.chat.title, isChannel: chat.supergroup?.isChannel == true,
            client: client, missing: &missing,
            onResolved: { [weak self] in self?.reconfigure(chatID: chat.id) },
        ) {
            return NSAttributedString(string: service, attributes: [.foregroundColor: UIColor.secondaryLabel])
        }
        guard let summary = ChatSummary.attributedText(for: chat) else { return nil }
        let isGroup =
            switch chat.type {
            case .group: true
            case .supergroup(let supergroup): !supergroup.isChannel
            case .bot,
                 .user: false
            }
        let author = isGroup
            ? lastMessage.flatMap { ChatPreviewText.authorPrefix(for: $0, client: client, missing: &missing) }
            : nil
        return ChatPreviewText.prefixed(author, summary)
    }

    private func requestUsers(_ ids: [Int64], chat: CustomChat, client: TDLibClient) {
        guard !ids.isEmpty else { return }
        let chatID = chat.id
        for id in Set(ids) {
            ChatListSenderNames.shared.resolve(userID: id, client: client) { [weak self] in
                self?.reconfigure(chatID: chatID)
            }
        }
    }

    /// Configures the row again once a name or a service message's wording lands, while it still shows that chat.
    private func reconfigure(chatID: Int64) {
        guard let chat = configuredChat, chat.id == chatID, let client = configuredClient else { return }
        configure(chat: chat, isMuted: configuredMuted, isArchived: configuredArchived, client: client)
    }

    private func updateBackground(highlighted: Bool, animated: Bool) {
        let color: UIColor =
            if usesCardStyle {
                highlighted ? .systemGray4 : .secondarySystemGroupedBackground
            } else {
                highlighted ? .tertiarySystemFill : (pinned ? .secondarySystemBackground : .systemBackground)
            }
        backgroundColor = usesCardStyle ? .clear : (pinned ? .secondarySystemBackground : .systemBackground)
        onlineMarker.ringColor = color
        guard animated else {
            rowView.backgroundColor = color
            return
        }
        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.rowView.backgroundColor = color
        }
    }

    private func configureViews() {
        rowView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowView)

        for item in [
            avatarView, storyRingView, titleLabel, headerAccessoryRow, messageLabel, trailingBadges, separatorView,
        ] {
            item.translatesAutoresizingMaskIntoConstraints = false
            rowView.addSubview(item)
        }
        rowView.addSubview(onlineMarker)
        avatarView.addGestureRecognizer(storyTapGesture)
        storyTapGesture.isEnabled = false
        separatorView.backgroundColor = .separator

        headerAccessoryRow.axis = .horizontal
        headerAccessoryRow.alignment = .center
        headerAccessoryRow.spacing = 4
        headerAccessoryRow.addArrangedSubview(deliveryView)
        headerAccessoryRow.addArrangedSubview(dateLabel)

        // Telegram keeps 6 pt between the mention badge and the unread count.
        trailingBadges.axis = .horizontal
        trailingBadges.alignment = .center
        trailingBadges.spacing = 6
        trailingBadges.addArrangedSubview(mentionBadgeView)
        trailingBadges.addArrangedSubview(trailingStatusView)
        mentionBadgeView.contentMode = .scaleAspectFit
        mentionBadgeView.isHidden = true

        for accessory in [muteView, pinView, unreadLabel] {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            trailingStatusView.addSubview(accessory)
        }
        // Pin and mute share the fixed trailing slot; unread always owns it when present.
        deliveryView.contentMode = .center

        for imageView in [pinView, muteView] {
            imageView.tintColor = .secondaryLabel
            imageView.contentMode = .scaleAspectFit
            imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        }
        titleLabel.textColor = .label
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .semibold),
            maximumPointSize: 19,
        )
        titleLabel.lineBreakMode = .byTruncatingTail
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15),
            maximumPointSize: 17,
        )
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dateLabel.textColor = .secondaryLabel
        dateLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13),
            maximumPointSize: 14,
        )
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        deliveryView.setContentCompressionResistancePriority(.required, for: .horizontal)
        unreadLabel.textColor = .white
        unreadLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        unreadLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        unreadLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func configureConstraints() {
        accessoryWidthConstraint = trailingStatusView.widthAnchor.constraint(equalToConstant: 0)
        // The stack collapses a hidden slot or badge to zero width.
        accessoryWidthConstraint.priority = .required - 1
        let mentionBadgeWidth = mentionBadgeView.widthAnchor.constraint(equalToConstant: 20)
        mentionBadgeWidth.priority = .required - 1
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 10),
            avatarView.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 60),
            avatarView.heightAnchor.constraint(equalToConstant: 60),
            onlineMarker.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: -2),
            onlineMarker.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: -2),
            onlineMarker.widthAnchor.constraint(equalToConstant: ChatListOnlineMarkerView.size),
            onlineMarker.heightAnchor.constraint(equalToConstant: ChatListOnlineMarkerView.size),
            storyRingView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            storyRingView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            storyRingView.widthAnchor.constraint(equalToConstant: 60),
            storyRingView.heightAnchor.constraint(equalToConstant: 60),
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerAccessoryRow.leadingAnchor, constant: -6),
            headerAccessoryRow.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -14),
            headerAccessoryRow.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: trailingBadges.leadingAnchor, constant: -6),
            messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: rowView.bottomAnchor, constant: -9),
            trailingBadges.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -14),
            trailingBadges.centerYAnchor.constraint(equalTo: messageLabel.centerYAnchor),
            trailingStatusView.heightAnchor.constraint(equalToConstant: 20),
            accessoryWidthConstraint,
            mentionBadgeWidth,
            mentionBadgeView.heightAnchor.constraint(equalToConstant: 20),
            pinView.centerXAnchor.constraint(equalTo: trailingStatusView.centerXAnchor),
            pinView.centerYAnchor.constraint(equalTo: trailingStatusView.centerYAnchor),
            pinView.widthAnchor.constraint(equalToConstant: 14),
            pinView.heightAnchor.constraint(equalToConstant: 14),
            muteView.centerXAnchor.constraint(equalTo: trailingStatusView.centerXAnchor),
            muteView.centerYAnchor.constraint(equalTo: trailingStatusView.centerYAnchor),
            muteView.widthAnchor.constraint(equalToConstant: 14),
            muteView.heightAnchor.constraint(equalToConstant: 14),
            unreadLabel.topAnchor.constraint(equalTo: trailingStatusView.topAnchor),
            unreadLabel.bottomAnchor.constraint(equalTo: trailingStatusView.bottomAnchor),
            unreadLabel.leadingAnchor.constraint(equalTo: trailingStatusView.leadingAnchor),
            unreadLabel.trailingAnchor.constraint(equalTo: trailingStatusView.trailingAnchor),
            separatorView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale),
        ])
        rowInsetConstraints = [
            rowView.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
        ]
        NSLayoutConstraint.activate(rowInsetConstraints)
        // Plain rows follow Telegram's title-then-message stack; a card centres the pair, as BetterTG's did.
        plainTextConstraints = [
            titleLabel.topAnchor.constraint(equalTo: rowView.topAnchor, constant: 9),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
        ]
        cardTextConstraints = [
            titleLabel.bottomAnchor.constraint(equalTo: rowView.centerYAnchor, constant: -2),
            messageLabel.topAnchor.constraint(equalTo: rowView.centerYAnchor, constant: 2),
        ]
    }

    private func applyStyle() {
        let horizontal = usesCardStyle ? Self.cardHorizontalInset : 0
        let vertical = usesCardStyle ? Self.cardVerticalInset : 0
        for constraint in rowInsetConstraints {
            let isHorizontal = constraint.firstAttribute == .leading || constraint.firstAttribute == .trailing
            constraint.constant = isHorizontal ? horizontal : vertical
        }
        NSLayoutConstraint.deactivate(usesCardStyle ? plainTextConstraints : cardTextConstraints)
        NSLayoutConstraint.activate(usesCardStyle ? cardTextConstraints : plainTextConstraints)
        rowView.layer.cornerRadius = usesCardStyle ? Self.cardCornerRadius : 0
        rowView.layer.cornerCurve = .continuous
        rowView.clipsToBounds = usesCardStyle
        separatorView.isHidden = usesCardStyle
        if usesCardStyle {
            titleLabel.font = .preferredFont(forTextStyle: .title3)
            messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        } else {
            titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                for: .systemFont(ofSize: 17, weight: .semibold),
                maximumPointSize: 19,
            )
            messageLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                for: .systemFont(ofSize: 15),
                maximumPointSize: 17,
            )
        }
        titleLabel.adjustsFontForContentSizeCategory = usesCardStyle
        messageLabel.adjustsFontForContentSizeCategory = usesCardStyle
        if let chat = configuredChat {
            // The secret chat lock is sized to the title font.
            titleLabel.attributedText = Self.title(for: chat, font: titleLabel.font)
        }
        updateBackground(highlighted: isHighlighted || isSelected, animated: false)
    }
}

// MARK: - ChatPreviewText

/// Telegram's preview wording for group and topic rows. Names come from ChatListSenderNames; a missing name is
/// appended to `missing` and the caller shows the generic text until it arrives.
@MainActor enum ChatPreviewText {
    /// The inline author prefix (ChatListItem useInlineAuthorPrefix): "You" for the account's messages and the
    /// sender's compact name otherwise. Chat senders and service actions have none.
    static func authorPrefix(for message: Message, client: TDLibClient, missing: inout [Int64]) -> String? {
        guard !MessageContentPresentation.make(message.content).isService else { return nil }
        if message.isOutgoing { return L10n.telegram("DialogList.You") }
        guard case .messageSenderUser(let sender) = message.senderId else { return nil }
        if let user = ChatListSenderNames.shared.user(userID: sender.userId, client: client) {
            return ChatListSenderNames.compactName(user)
        }
        missing.append(sender.userId)
        return nil
    }

    /// Service actions with names (plainServiceMessageString); a pin names its author without the pinned text.
    static func serviceText(
        for message: Message,
        chatTitle: String?,
        isChannel: Bool,
        client: TDLibClient,
        missing: inout [Int64],
        onResolved: @escaping () -> Void,
    ) -> String? {
        guard MessageContentPresentation.make(message.content).isService else { return nil }
        if ServiceMessageText.needsResolvedContext(message.content) {
            return ChatListSenderNames.shared.resolvedServiceText(
                for: message,
                isChannel: isChannel,
                client: client,
                completion: onResolved,
            )
        }
        let cache = ChatListSenderNames.shared
        var author: String?
        var senderUserID: Int64?
        var absent = [Int64]()
        switch message.senderId {
        case .messageSenderUser(let sender):
            senderUserID = sender.userId
            if let user = cache.user(userID: sender.userId, client: client) {
                author = ServiceMessageText.displayTitle(user)
            } else {
                absent.append(sender.userId)
            }
        case .messageSenderChat(let sender):
            author = sender.chatId == message.chatId ? chatTitle : nil
        }
        var names = [Int64: String]()
        for id in ServiceMessageText.memberIDs(message.content) {
            if let user = cache.user(userID: id, client: client) {
                names[id] = ServiceMessageText.displayTitle(user)
            } else {
                absent.append(id)
            }
        }
        guard absent.isEmpty else {
            missing += absent
            return nil
        }
        guard let author else { return nil }
        return ServiceMessageText.make(message.content, context: .init(
            author: author, isOutgoing: message.isOutgoing, isChannel: isChannel,
            senderUserID: senderUserID, names: names, pinned: nil,
        ))
    }

    static func prefixed(_ author: String?, _ summary: NSAttributedString) -> NSAttributedString {
        guard let author else { return summary }
        let result = NSMutableAttributedString(string: author + ": ", attributes: [.foregroundColor: UIColor.label])
        result.append(summary)
        return result
    }
}

// MARK: - ChatListSenderNames

/// Users named by chat-list rows (inline author prefixes, service wording), kept for the current TDLib client
/// only. TDLib answers getUser from its local store, so a miss costs one hop and the visible row updates when it
/// lands.
@MainActor final class ChatListSenderNames {
    private struct ServiceKey: Hashable {
        let chatID: Int64
        let messageID: Int64
    }

    static let shared = ChatListSenderNames()

    private var clientID: Int32?
    private var users = [Int64: User]()
    private var waiters = [Int64: [() -> Void]]()
    /// Service wording that needs more than names, by chat and message.
    private var serviceTexts = [ServiceKey: String]()
    private var serviceWaiters = [ServiceKey: [() -> Void]]()

    /// Telegram's compactDisplayTitle for users: the first name, else the last name.
    static func compactName(_ user: User) -> String {
        let first = user.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { return first }
        let last = user.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        return last.isEmpty ? L10n.telegram("User.DeletedAccount") : last
    }

    func user(userID: Int64, client: TDLibClient) -> User? {
        retain(client)
        return users[userID]
    }

    /// A renamed sender reads with the new name from the next row configure; only users already named are kept.
    func receive(_ user: User, clientID: Int32) {
        guard self.clientID == clientID, users[user.id] != nil else { return }
        users[user.id] = user
    }

    func resolve(userID: Int64, client: TDLibClient, completion: @escaping () -> Void) {
        retain(client)
        guard users[userID] == nil else { return completion() }
        let isFirstWaiter = waiters[userID] == nil
        waiters[userID, default: []].append(completion)
        guard isFirstWaiter else { return }
        let requestClientID = client.id
        Task { [weak self] in
            let user = try? await client.getUser(userId: userID)
            guard let self, clientID == requestClientID else { return }
            let completions = waiters.removeValue(forKey: userID) ?? []
            guard let user else { return }
            users[userID] = user
            completions.forEach { $0() }
        }
    }

    /// ServiceMessageText.resolve's wording for a service message that needs its checklist, game, chat or the
    /// account; nil until it lands, when `completion` runs.
    func resolvedServiceText(
        for message: Message,
        isChannel: Bool,
        client: TDLibClient,
        completion: @escaping () -> Void,
    ) -> String? {
        retain(client)
        let key = ServiceKey(chatID: message.chatId, messageID: message.id)
        if let text = serviceTexts[key] { return text }
        let isFirstWaiter = serviceWaiters[key] == nil
        serviceWaiters[key, default: []].append(completion)
        guard isFirstWaiter else { return nil }
        let requestClientID = client.id
        Task { [weak self] in
            let text = await ServiceMessageText.resolve(message, senderUser: nil, isChannel: isChannel, client: client)
            guard let self, clientID == requestClientID else { return }
            let completions = serviceWaiters.removeValue(forKey: key) ?? []
            guard let text else { return }
            serviceTexts[key] = text
            completions.forEach { $0() }
        }
        return nil
    }

    private func retain(_ client: TDLibClient) {
        guard clientID != client.id else { return }
        clientID = client.id
        users.removeAll()
        waiters.removeAll()
        serviceTexts.removeAll()
        serviceWaiters.removeAll()
    }
}

// MARK: - ChatListOnlineMarkerView

/// PresentationResourcesChatList.recentStatusOnlineIcon: a 10 pt green dot inside a 2 pt ring of the row's colour,
/// scaling in and out as PeerOnlineMarkerNode does.
final class ChatListOnlineMarkerView: UIView {
    static let size = CGFloat(14)

    var ringColor = UIColor.secondarySystemGroupedBackground {
        didSet { backgroundColor = ringColor }
    }

    private(set) var isVisible = false

    private let dot = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        backgroundColor = ringColor
        layer.cornerRadius = Self.size / 2
        dot.backgroundColor = .systemGreen
        dot.layer.cornerRadius = (Self.size - 4) / 2
        dot.frame = CGRect(x: 2, y: 2, width: Self.size - 4, height: Self.size - 4)
        addSubview(dot)
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        let changes = {
            self.alpha = visible ? 1 : 0
            self.transform = visible ? .identity : CGAffineTransform(scaleX: 0.01, y: 0.01)
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: [
            .beginFromCurrentState,
            .allowUserInteraction,
        ], animations: changes)
    }
}

// ChatEmptyStateView.swift

import TDLibKit
import UIKit

// MARK: - ChatEmptyStateView

/// Telegram's ChatEmptyNode on BetterTG's service pill: a card centred in an empty history. A person's chat shows
/// the greeting (No messages here yet, the hint and a greeting sticker that sends itself on a tap), Saved Messages the
/// cloud storage notes, a secret chat its invitation and what secret chats do, a group the account created what groups
/// can have, and any other chat the plain placeholder.
final class ChatEmptyStateView: UIView {
    enum Kind: Equatable {
        case regular
        case greeting
        case cloud
        /// The person's name in the secret chat's invitation, and the secret chat, whose direction picks it.
        case secret(name: String, secretChatID: Int)
        case group
    }

    private static let titleFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
    private static let messageFont = UIFont.systemFont(ofSize: 13)

    /// The greeting sticker's tap.
    var onSendSticker: ((Sticker) -> Void)?

    let kind: Kind

    private let client: TDLibClient
    private let cardView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var lines = [(icon: UIImageView?, label: UILabel)]()
    private let stickerView = CustomEmojiInlineView()
    private let stickerButton = UIControl()
    private var greetingSticker: Sticker?
    private var loadTask: Task<Void, Never>?

    #if DEBUG
        var probeCardFrame: CGRect {
            cardView.frame
        }

        var probeTexts: [String] {
            ([titleLabel, subtitleLabel] + lines.map(\.label)).compactMap(\.text).filter { !$0.isEmpty }
        }
    #endif

    /// 160 pt square, aspect-fitted to the sticker once it is known.
    private var greetingStickerSize: CGSize {
        let box = CGSize(width: 160, height: 160)
        guard let sticker = greetingSticker, sticker.width > 0, sticker.height > 0 else { return box }
        let scale = min(box.width / CGFloat(sticker.width), box.height / CGFloat(sticker.height))
        return CGSize(width: floor(CGFloat(sticker.width) * scale), height: floor(CGFloat(sticker.height) * scale))
    }

    init(kind: Kind, client: TDLibClient) {
        self.kind = kind
        self.client = client
        super.init(frame: .zero)
        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerCurve = .continuous
        addSubview(cardView)
        for label in [titleLabel, subtitleLabel] {
            label.numberOfLines = 0
            label.textColor = .secondaryLabel
            cardView.addSubview(label)
        }
        iconView.tintColor = .secondaryLabel
        cardView.addSubview(iconView)
        configureContent()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = layoutContent(maxWidth: max(1, bounds.width - 32))
        // ChatEmptyNode centres the card in the history's free space and rounds it up to 20 pt.
        cardView.frame = CGRect(
            x: floor((bounds.width - size.width) / 2),
            y: floor((bounds.height - size.height) / 2),
            width: size.width,
            height: size.height,
        )
        cardView.layer.cornerRadius = min(20, size.height / 2)
    }

    /// Only the greeting sticker takes touches; the history keeps the rest.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === stickerButton ? result : nil
    }

    /// ChatEmptyNode's content choice (`emptyChat`) for a chat's own history.
    static func kind(for chat: CustomChat, isBlocked: Bool, isThread: Bool) -> Kind {
        guard !isThread else { return .regular }
        if chat.isSavedMessages { return .cloud }
        if let secretChatID = chat.secretChatID {
            return .secret(name: chat.user?.compactDisplayTitle ?? chat.displayTitle, secretChatID: secretChatID)
        }
        switch chat.type {
        case .group(let group):
            if case .chatMemberStatusCreator = group.status { return .group }
            return .regular
        case .supergroup(let supergroup):
            guard !supergroup.isChannel, !supergroup.isBroadcastGroup, !supergroup.isDirectMessagesGroup,
                  case .chatMemberStatusCreator = supergroup.status else { return .regular }
            return .group
        case .bot:
            return .regular
        case .user(let user):
            let isDeleted =
                if case .userTypeDeleted = user.type {
                    true
                } else {
                    false
                }
            guard !isDeleted, !user.isSupport, user.verificationStatus?.isScam != true, !isBlocked else {
                return .regular
            }
            return .greeting
        }
    }

    private func configureContent() {
        switch kind {
        case .regular:
            titleLabel.font = Self.messageFont
            titleLabel.textAlignment = .center
            titleLabel.text = L10n.telegram("Conversation.EmptyPlaceholder")
        case .greeting:
            titleLabel.font = Self.titleFont
            titleLabel.textAlignment = .center
            titleLabel.text = L10n.telegram("Conversation.EmptyPlaceholder")
            subtitleLabel.font = Self.messageFont
            subtitleLabel.textAlignment = .center
            subtitleLabel.text = L10n.telegram("Conversation.GreetingText")
            stickerView.isUserInteractionEnabled = false
            stickerButton.addSubview(stickerView)
            stickerButton.isAccessibilityElement = true
            stickerButton.accessibilityTraits = .button
            stickerButton.accessibilityLabel = L10n.telegram("Message.Sticker")
            stickerButton.accessibilityIdentifier = "chat-empty-greeting-sticker"
            stickerButton.addAction(UIAction { [weak self] _ in self?.sendGreetingSticker() }, for: .touchUpInside)
            cardView.addSubview(stickerButton)
            loadGreetingSticker()
        case .cloud:
            iconView.image = UIImage(
                systemName: "cloud",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .light),
            )
            titleLabel.font = Self.titleFont
            titleLabel.textAlignment = .center
            titleLabel.text = L10n.telegram("Conversation.CloudStorageInfo.Title")
            addLines((1...4).map { L10n.telegram("Conversation.ClousStorageInfo.Description\($0)") }, icon: nil)
            for line in lines {
                line.label.font = .systemFont(ofSize: 14)
            }
        case .secret(let name, let secretChatID):
            titleLabel.font = Self.titleFont
            titleLabel.textAlignment = .center
            subtitleLabel.font = Self.messageFont
            subtitleLabel.text = L10n.telegram("Conversation.EncryptedDescriptionTitle")
            addLines((1...4).map { L10n.telegram("Conversation.EncryptedDescription\($0)") }, icon: "lock.fill")
            loadSecretChatTitle(name: name, secretChatID: secretChatID)
        case .group:
            titleLabel.font = Self.titleFont
            titleLabel.textAlignment = .center
            titleLabel.text = L10n.telegram("EmptyGroupInfo.Title")
            subtitleLabel.font = Self.messageFont
            subtitleLabel.text = L10n.telegram("EmptyGroupInfo.Subtitle")
            addLines(
                [L10n.telegram("EmptyGroupInfo.Line1", AppLocalization.formattedNumber(200_000))]
                    + (2...4).map { L10n.telegram("EmptyGroupInfo.Line\($0)") },
                icon: "checkmark",
            )
            loadGroupLimit()
        }
    }

    private func addLines(_ texts: [String], icon: String?) {
        for text in texts {
            let label = UILabel()
            label.numberOfLines = 0
            label.font = Self.messageFont
            label.textColor = .secondaryLabel
            label.text = text
            cardView.addSubview(label)
            var iconView: UIImageView?
            if let icon {
                let view = UIImageView(image: UIImage(
                    systemName: icon,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold),
                ))
                view.tintColor = .secondaryLabel
                cardView.addSubview(view)
                iconView = view
            }
            lines.append((iconView, label))
        }
    }

    /// Each content's ChatEmptyNode layout; returns the card's size.
    private func layoutContent(maxWidth: CGFloat) -> CGSize {
        func fit(_ label: UILabel, _ width: CGFloat) -> CGSize {
            let size = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            return CGSize(width: ceil(min(width, size.width)), height: ceil(size.height))
        }
        switch kind {
        case .regular:
            // ChatEmptyNodeRegularChatContent: 6 pt above and below, 10 pt at the sides.
            let text = fit(titleLabel, maxWidth - 20)
            titleLabel.frame = CGRect(origin: CGPoint(x: 10, y: 6), size: text)
            return CGSize(width: text.width + 20, height: text.height + 12)
        case .greeting:
            // ChatEmptyNodeGreetingChatContent: 15 pt around a 220 pt column, 5 pt between the parts, a 160 pt
            // sticker.
            let inset = CGFloat(15)
            var width = CGFloat(220)
            let title = fit(titleLabel, width)
            let text = fit(subtitleLabel, width)
            width = max(width, max(title.width, text.width))
            let stickerSize = greetingStickerSize
            titleLabel.frame = CGRect(
                x: inset + floor((width - title.width) / 2),
                y: inset,
                width: title.width,
                height: title.height,
            )
            subtitleLabel.frame = CGRect(
                x: inset + floor((width - text.width) / 2),
                y: titleLabel.frame.maxY + 5,
                width: text.width,
                height: text.height,
            )
            stickerButton.frame = CGRect(
                x: inset + floor((width - stickerSize.width) / 2),
                y: subtitleLabel.frame.maxY + 5,
                width: stickerSize.width,
                height: stickerSize.height,
            )
            stickerView.frame = stickerButton.bounds
            return CGSize(width: width + inset * 2, height: stickerButton.frame.maxY + inset)
        case .cloud:
            // ChatEmptyNodeCloudChatContent: the icon, 12 pt, the title, then the notes 4 pt apart.
            let inset = CGFloat(15)
            let textWidth = maxWidth - inset * 2 - 10
            var width = CGFloat(0)
            let iconSize = iconView.image?.size ?? .zero
            width = max(width, iconSize.width)
            let sizes = lines.map { fit($0.label, textWidth) }
            width = max(width, sizes.map(\.width).max() ?? 0)
            let title = fit(titleLabel, width)
            width = max(width, title.width)
            iconView.frame = CGRect(
                x: inset + floor((width - iconSize.width) / 2),
                y: inset,
                width: iconSize.width,
                height: iconSize.height,
            )
            titleLabel.frame = CGRect(
                x: inset + floor((width - title.width) / 2),
                y: iconView.frame.maxY + 12,
                width: title.width,
                height: title.height,
            )
            var y = titleLabel.frame.maxY + 4
            for (index, line) in lines.enumerated() {
                if index > 0 { y += 4 }
                line.label.frame = CGRect(x: inset, y: y, width: sizes[index].width, height: sizes[index].height)
                y += sizes[index].height
            }
            return CGSize(width: width + inset * 2, height: y + 4 + inset)
        case .group,
             .secret:
            // ChatEmptyNodeSecretChatContent and ChatEmptyNodeGroupChatContent: 15 pt around, the title, 5 pt, the
            // subtitle, then lines 11 pt apart with their icon 14 (lock) or 19 (check) pt before the text.
            let inset = CGFloat(15)
            let iconInset: CGFloat = kind == .group ? 19 : 14
            let textWidth = maxWidth - inset * 2 - 10
            var width = CGFloat(100)
            let sizes = lines.map { fit($0.label, textWidth - iconInset) }
            for size in sizes {
                width = max(width, iconInset + size.width)
            }
            let title = fit(titleLabel, max(width, min(textWidth, 240)))
            let subtitle = fit(subtitleLabel, width)
            width = max(width, max(title.width, subtitle.width))
            titleLabel.frame = CGRect(
                x: inset + floor((width - title.width) / 2),
                y: inset,
                width: title.width,
                height: title.height,
            )
            subtitleLabel.frame = CGRect(
                x: inset,
                y: titleLabel.frame.maxY + 5,
                width: subtitle.width,
                height: subtitle.height,
            )
            var y = subtitleLabel.frame.maxY + 11 / 2
            for (index, line) in lines.enumerated() {
                if let icon = line.icon {
                    let iconSize = icon.image?.size ?? .zero
                    icon.frame = CGRect(
                        x: inset,
                        y: y + (kind == .group ? 2 : 1),
                        width: iconSize.width,
                        height: iconSize.height,
                    )
                }
                line.label.frame = CGRect(
                    x: inset + iconInset,
                    y: y,
                    width: sizes[index].width,
                    height: sizes[index].height,
                )
                y += sizes[index].height + 11
            }
            return CGSize(width: width + inset * 2, height: y - 11 / 2 + inset)
        }
    }

    /// TelegramEngine.randomGreetingSticker: one of TDLib's greeting stickers at random.
    private func loadGreetingSticker() {
        let client = client
        loadTask = Task { [weak self] in
            guard let stickers = try? await client.send(TDNativeRequests.getGreetingStickers()),
                  let sticker = stickers.stickers.randomElement(), !Task.isCancelled, let self else { return }
            greetingSticker = sticker
            stickerView.configure(sticker: sticker, client: client)
            stickerView.setPlaybackVisible(true)
            stickerButton.accessibilityLabel = sticker.emoji.isEmpty
                ? L10n.telegram("Message.Sticker")
                : L10n.telegram("Message.StickerText", sticker.emoji)
            setNeedsLayout()
        }
    }

    /// The secret chat's direction decides the invitation: a chat the other side started reads "… invited you".
    private func loadSecretChatTitle(name: String, secretChatID: Int) {
        titleLabel.text = L10n.telegram("Conversation.EncryptedPlaceholderTitleOutgoing", name)
        let client = client
        loadTask = Task { [weak self] in
            guard let secret = try? await client.send(TDNativeRequests.getSecretChat(secretChatId: secretChatID)),
                  !Task.isCancelled, let self else { return }
            titleLabel.text = L10n.telegram(
                secret.isOutbound
                    ? "Conversation.EncryptedPlaceholderTitleOutgoing"
                    : "Conversation.EncryptedPlaceholderTitleIncoming",
                name,
            )
            setNeedsLayout()
        }
    }

    /// EmptyGroupInfo.Line1 takes `limitsConfiguration.maxSupergroupMemberCount`: TDLib's supergroup_size_max.
    private func loadGroupLimit() {
        let client = client
        loadTask = Task { [weak self] in
            guard case .optionValueInteger(let value) = try? await client.getOption(name: "supergroup_size_max"),
                  !Task.isCancelled, let self, let first = lines.first else { return }
            first.label.text = L10n.telegram(
                "EmptyGroupInfo.Line1",
                AppLocalization.formattedNumber(Int(clamping: value.value)),
            )
            setNeedsLayout()
        }
    }

    private func sendGreetingSticker() {
        guard let greetingSticker else { return }
        onSendSticker?(greetingSticker)
    }
}

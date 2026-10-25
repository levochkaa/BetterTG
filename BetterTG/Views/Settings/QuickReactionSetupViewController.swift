// QuickReactionSetupViewController.swift

import Combine
import TDLibKit
import UIKit

// MARK: - QuickReactionSetupViewController

/// QuickReactionSetupController: ReactionChatPreviewItem's demo message, Dino's line, which a double tap reacts to
/// with the quick reaction and its effect, then Choose Your Quick Reaction with the current one, which opens the
/// active emoji reactions (setDefaultReactionType). Custom emoji, a Premium choice, are not offered.
final class QuickReactionSetupViewController: SettingsListViewController {
    private var demoChat: CustomChat?
    private var demoReacted = false
    private var loadTask: Task<Void, Never>?
    private var changesCancellable: AnyCancellable?

    // MARK: Private

    private var quickReaction: ReactionType {
        DefaultReactionType.shared.type(for: client)
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("Settings.QuickReactionSetup.Title")
        tableView.register(QuickReactionDemoCell.self, forCellReuseIdentifier: QuickReactionDemoCell.reuseIdentifier)
        changesCancellable = DefaultReactionType.shared
            .changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reload() }
        let client = client
        loadTask = Task { [weak self] in
            // The demo bubble sits in the account's own chat, where it shows neither avatar nor author.
            guard let userID = TDLib.shared.activeAccount?.userID,
                  let chat = await RootVM.shared.getCustomChatForNavigation(from: userID, client: client), let self,
                  !Task.isCancelled, contextIsCurrent else { return }
            demoChat = chat
            reload()
        }
    }

    override func makeSections() -> [SettingsSection] {
        var sections = [SettingsSection]()
        if demoChat != nil {
            sections.append(SettingsSection(
                header: L10n.telegram("Settings.QuickReactionSetup.DemoHeader"),
                footer: L10n.telegram("Settings.QuickReactionSetup.DemoInfo"),
                rows: [SettingsRow(title: "")],
            ))
        }
        sections.append(SettingsSection(
            footer: L10n.telegram("Settings.QuickReactionSetup.ChooseQuickReactionInfo"),
            rows: [SettingsRow(
                title: L10n.telegram("Settings.QuickReactionSetup.ChooseQuickReaction"),
                accessory: .disclosure,
                action: { [weak self] in self?.presentPicker() },
                trailingView: SettingsTrailingView { [quickReaction, client] in
                    QuickReactionIconView(type: quickReaction, client: client)
                },
            )],
        ))
        return sections
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard demoChat != nil, indexPath.section == 0,
              let cell = tableView.dequeueReusableCell(
                  withIdentifier: QuickReactionDemoCell.reuseIdentifier,
                  for: indexPath,
              ) as? QuickReactionDemoCell
        else { return super.tableView(tableView, cellForRowAt: indexPath) }
        configureDemo(cell)
        return cell
    }

    private func configureDemo(_ cell: QuickReactionDemoCell) {
        guard let demoChat else { return }
        let reaction = demoReacted ? quickReaction : nil
        cell.configure(chat: demoChat, reaction: reaction, client: client) { [weak self, weak cell] in
            guard let self, let cell else { return }
            toggleDemoReaction(in: cell)
        }
    }

    /// ReactionChatPreviewItem's toggleReaction: the quick reaction goes on or off, and going on plays its effect.
    private func toggleDemoReaction(in cell: QuickReactionDemoCell) {
        demoReacted.toggle()
        configureDemo(cell)
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil)
        }
        guard demoReacted, !UIAccessibility.isReduceMotionEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let client = client
        let type = quickReaction
        DispatchQueue.main.async { [weak cell] in
            guard let icon = cell?.reactionIconView(for: type) else { return }
            if let emoji = type.standardEmoji {
                ReactionEffectOverlay.play(emoji: emoji, iconView: icon, client: client)
            } else if let customEmojiID = type.customEmojiID {
                Task { [weak icon] in
                    guard let sticker = await CustomEmojiStickerRepository.shared
                        .stickers(for: [customEmojiID], client: client)[customEmojiID], let icon
                    else { return }
                    ReactionEffectOverlay.play(customEmoji: sticker, iconView: icon, client: client)
                }
            }
        }
    }

    /// openQuickReaction: EmojiStatusSelectionController's grid over the row, the current reaction marked.
    private func presentPicker() {
        guard contextIsCurrent else { return }
        let emojis = DefaultReactionType.shared.activeEmojis(for: client)
        guard !emojis.isEmpty, let section = sections.indices.last,
              let cell = tableView.cellForRow(at: IndexPath(row: 0, section: section)) else { return }
        let picker = QuickReactionPickerViewController(emojis: emojis, selected: quickReaction.standardEmoji)
        picker.onSelect = { [weak self] emoji in
            self?.perform { client in
                _ = try await client.send(TDNativeRequests.setDefaultReactionType(
                    reactionType: .reactionTypeEmoji(.init(emoji: emoji)),
                ))
            }
        }
        picker.modalPresentationStyle = .popover
        if let popover = picker.popoverPresentationController {
            popover.sourceView = cell
            popover.sourceRect = CGRect(x: cell.bounds.maxX - 60, y: cell.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = [.up, .down]
            popover.delegate = picker
        }
        present(picker, animated: true)
    }
}

// MARK: - QuickReactionDemoCell

/// ReactionChatPreviewItem: Telegram's incoming demo message from Dino at 18:20, with the reaction chip while it is
/// on; a double tap toggles it.
private final class QuickReactionDemoCell: UITableViewCell {
    static let reuseIdentifier = "QuickReactionDemoCell"

    /// MessageCell draws upside down for the inverted timeline and resets its own transform, so a container flips it.
    private let flipView = UIView()
    private let messageCell = MessageCell(frame: .zero)
    private let polls = MessagePollInteractionStore()
    private var message: CustomMessage?
    private var onToggle: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        // ReactionChatPreviewItem draws the chat's background behind the bubble; BetterTG's chats have no wallpaper.
        backgroundColor = .systemBackground
        flipView.transform = CGAffineTransform(scaleX: 1, y: -1)
        flipView.addSubview(messageCell)
        contentView.addSubview(flipView)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        let height = messageHeight(width: width)
        flipView.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        flipView.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        messageCell.frame = flipView.bounds
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority _: UILayoutPriority,
        verticalFittingPriority _: UILayoutPriority,
    ) -> CGSize {
        CGSize(width: targetSize.width, height: messageHeight(width: targetSize.width) + 16)
    }

    private static func demoCustomMessage() -> CustomMessage {
        let message = demoMessage()
        return CustomMessage(
            message: message,
            formattedText: MessageContentPresentation.make(message).formattedText,
            properties: .default,
        )
    }

    /// The demo's EngineRawMessage: incoming, timestamp 66000, Telegram's demo text.
    private static func demoMessage() -> Message {
        Message(
            id: 1,
            senderId: .messageSenderUser(.init(userId: 0)),
            receiverId: nil,
            chatId: 0,
            sendingState: nil,
            schedulingState: nil,
            isOutgoing: false,
            isPinned: false,
            isFromOffline: false,
            canBeSaved: false,
            hasTimestampedMedia: false,
            isChannelPost: false,
            isPaidStarSuggestedPost: false,
            isPaidGramSuggestedPost: false,
            containsUnreadMention: false,
            containsUnreadPollVotes: false,
            date: 66000,
            editDate: 0,
            forwardInfo: nil,
            importInfo: nil,
            interactionInfo: nil,
            unreadReactions: [],
            factCheck: nil,
            suggestedPostInfo: nil,
            replyTo: nil,
            topicId: nil,
            selfDestructType: nil,
            selfDestructIn: 0,
            autoDeleteIn: 0,
            viaBotUserId: 0,
            guestBotCallerId: nil,
            senderBusinessBotUserId: 0,
            senderBoostCount: 0,
            senderTag: "",
            paidMessageStarCount: 0,
            authorSignature: "",
            mediaAlbumId: 0,
            effectId: 0,
            restrictionInfo: nil,
            summaryLanguageCode: "",
            content: .messageText(.init(
                linkPreview: nil,
                linkPreviewOptions: nil,
                text: .init(entities: [], text: L10n.telegram("Settings.QuickReactionSetup.DemoMessageText")),
            )),
            ephemeralContent: nil,
            replyMarkup: nil,
            ephemeralMessageId: 0,
            chatInstance: 0,
        )
    }

    func configure(chat: CustomChat, reaction: ReactionType?, client: TDLibClient, onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        let message = message ?? Self.demoCustomMessage()
        self.message = message
        let me = TDLib.shared.activeAccount?.userID
        message.reactions = reaction.map { type in
            MessageReactions(
                reactions: [MessageReaction(
                    type: type,
                    totalCount: 1,
                    isChosen: true,
                    usedSenderId: nil,
                    recentSenderIds: me.map { [.messageSenderUser(.init(userId: $0))] } ?? [],
                )],
                areTags: false,
                paidReactors: [],
                canGetAddedReactions: false,
            )
        }
        messageCell.onQuickReaction = { [weak self] in self?.onToggle?() }
        messageCell.configure(
            message: message,
            chat: chat,
            highlightedMessageID: nil,
            client: client,
            pollInteractionStore: polls,
            canAddReactions: false,
            selectionActive: false,
            selected: false,
            onSwipeToReply: nil,
            onSelectionToggle: nil,
            onReactionTap: { [weak self] _ in self?.onToggle?() },
            onMetadataNavigate: { _ in },
            onReplyQuoteExpand: {},
            onContentAction: { _ in },
            onMediaTap: { _, _ in },
            showsProfileImage: false,
        )
        setNeedsLayout()
    }

    func reactionIconView(for type: ReactionType) -> UIView? {
        messageCell.reactionIconView(for: type)
    }

    private func messageHeight(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        if abs(messageCell.bounds.width - width) > 0.5 {
            messageCell.frame = CGRect(x: 0, y: 0, width: width, height: max(44, messageCell.bounds.height))
        }
        messageCell.layoutIfNeeded()
        return ceil(messageCell.contentView
            .systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel,
            )
            .height)
    }
}

// MARK: - QuickReactionIconView

/// ItemListReactionItem's icon: a standard reaction's emoji, or a custom one's sticker, in 24 pt.
final class QuickReactionIconView: UIView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: 24, height: 24)
    }

    private let label = UILabel()
    private let stickerView = CustomEmojiInlineView()
    private var loadTask: Task<Void, Never>?

    init(type: ReactionType, client: TDLibClient) {
        super.init(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        label.font = .systemFont(ofSize: 20)
        label.textAlignment = .center
        label.frame = bounds
        stickerView.frame = bounds
        stickerView.isUserInteractionEnabled = false
        addSubview(label)
        addSubview(stickerView)
        isAccessibilityElement = true
        if let emoji = type.standardEmoji {
            label.text = emoji
            accessibilityLabel = emoji
        } else if let customEmojiID = type.customEmojiID {
            self.loadTask = Task { [weak self] in
                guard let sticker = await CustomEmojiStickerRepository.shared
                    .stickers(for: [customEmojiID], client: client)[customEmojiID], let self
                else { return }
                stickerView.configure(sticker: sticker, client: client)
                stickerView.setPlaybackVisible(true)
                accessibilityLabel = sticker.emoji
            }
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }
}

// MARK: - QuickReactionPickerViewController

/// EmojiStatusSelectionController in `.quickReactionSelection`: the active emoji reactions in a grid of 40 pt cells,
/// the current one on a tinted circle; a tap chooses one and closes the grid.
private final class QuickReactionPickerViewController: UIViewController, UICollectionViewDataSource,
UICollectionViewDelegate, UIPopoverPresentationControllerDelegate {
    private static let columns = 7
    private static let side: CGFloat = 44

    var onSelect: ((String) -> Void)?

    private let emojis: [String]
    private let selected: String?
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())

    init(emojis: [String], selected: String?) {
        self.emojis = emojis
        self.selected = selected
        super.init(nibName: nil, bundle: nil)
        let rows = min(5, (emojis.count + Self.columns - 1) / Self.columns)
        preferredContentSize = CGSize(
            width: CGFloat(Self.columns) * Self.side + 16,
            height: CGFloat(rows) * Self.side + 16,
        )
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(QuickReactionPickerCell.self, forCellWithReuseIdentifier: QuickReactionPickerCell.id)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    func adaptivePresentationStyle(
        for _: UIPresentationController,
        traitCollection _: UITraitCollection,
    ) -> UIModalPresentationStyle {
        .none
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        emojis.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: QuickReactionPickerCell.id, for: indexPath)
        let emoji = emojis[indexPath.item]
        (cell as? QuickReactionPickerCell)?.configure(emoji: emoji, isSelected: emoji == selected)
        return cell
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let emoji = emojis[indexPath.item]
        UISelectionFeedbackGenerator().selectionChanged()
        dismiss(animated: true)
        if emoji != selected { onSelect?(emoji) }
    }

    private func makeLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: Self.side, height: Self.side)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return layout
    }
}

// MARK: - QuickReactionPickerCell

private final class QuickReactionPickerCell: UICollectionViewCell {
    static let id = "QuickReactionPickerCell"

    private let label = UILabel()
    private let selectionView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        selectionView.backgroundColor = .tintColor.withAlphaComponent(0.2)
        selectionView.layer.cornerRadius = 18
        contentView.addSubview(selectionView)
        label.font = .systemFont(ofSize: 28)
        label.textAlignment = .center
        contentView.addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
        selectionView.frame = contentView.bounds.insetBy(dx: 4, dy: 4)
    }

    func configure(emoji: String, isSelected: Bool) {
        label.text = emoji
        selectionView.isHidden = !isSelected
        accessibilityLabel = emoji
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

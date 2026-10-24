// ChatInputSuggestionsView.swift

import TDLibKit
import UIKit

// MARK: - ChatInputSuggestionsView

/// Telegram's input context panels above the text: a bot's commands while "/" is typed (CommandChatInputContext-
/// PanelNode) or from the Menu button (CommandMenuChatInputContextPanelNode), and an inline bot's results as a list
/// (VerticalListContextResultsChatInputContextPanelNode) or a media strip (HorizontalListContextResultsChatInput-
/// ContextPanelNode). Tapping a command or a result sends it; a command's arrow puts it into the input instead. It also
/// shows recently used hashtags (HashtagChatInputContextPanelNode), emoji for a ":" keyword in a bubble over the caret
/// (EmojisChatInputContextPanelNode) and stickers for a lone emoji (InlineReactionSearchPanel).
final class ChatInputSuggestionsView: UIView, UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource,
UICollectionViewDelegateFlowLayout {
    enum Content: Equatable {
        case hidden
        case commands([ChatBotCommand], showsBotNames: Bool)
        case mentions([ChatMentionSuggestion])
        case inline(InlineBotQueryState)
        case hashtags(ChatHashtagSuggestions)
        /// The emoji and the caret's x in this view, which the bubble's arrow points at.
        case emojis([ChatEmojiSuggestion], caretX: CGFloat?)
        case stickers([Sticker])

        static func == (lhs: Content, rhs: Content) -> Bool {
            switch (lhs, rhs) {
            case (.hidden, .hidden):
                true
            case (.commands(let lhsCommands, let lhsNames), .commands(let rhsCommands, let rhsNames)):
                lhsCommands == rhsCommands && lhsNames == rhsNames
            case (.mentions(let lhsMentions), .mentions(let rhsMentions)):
                lhsMentions == rhsMentions
            case (.inline(let lhsState), .inline(let rhsState)):
                lhsState.botUserID == rhsState.botUserID && lhsState.query == rhsState.query
                    && lhsState.isLoading == rhsState.isLoading && lhsState.nextOffset == rhsState.nextOffset
                    && lhsState.button?.text == rhsState.button?.text
                    && lhsState.results.map(\.resultID) == rhsState.results.map(\.resultID)
            case (.hashtags(let lhsHashtags), .hashtags(let rhsHashtags)):
                lhsHashtags == rhsHashtags
            case (.emojis(let lhsEmoji, let lhsCaret), .emojis(let rhsEmoji, let rhsCaret)):
                lhsEmoji == rhsEmoji && lhsCaret == rhsCaret
            case (.stickers(let lhsStickers), .stickers(let rhsStickers)):
                lhsStickers.map(\.sticker.id) == rhsStickers.map(\.sticker.id)
            default:
                false
            }
        }
    }

    private enum Display {
        case list, gallery, stickers, emojis
    }

    private static let rowHeight: CGFloat = 52
    private static let hashtagRowHeight: CGFloat = 42
    private static let galleryHeight: CGFloat = 96
    private static let emojiBubbleHeight: CGFloat = 55

    var onSendCommand: ((ChatBotCommand) -> Void)?
    var onInsertCommand: ((ChatBotCommand) -> Void)?
    var onSelectMention: ((ChatMentionSuggestion) -> Void)?
    var onSelectInlineResult: ((InlineBotResult) -> Void)?
    var onLoadMoreInlineResults: (() -> Void)?
    var onInlineButton: ((_ username: String, _ parameter: String) -> Void)?
    var onSelectHashtag: ((String) -> Void)?
    var onRemoveHashtag: ((String) -> Void)?
    var onSelectEmoji: ((String) -> Void)?
    var onSelectSticker: ((Sticker) -> Void)?
    /// The peek menu of a suggested sticker (InlineReactionSearchPanel).
    var stickerPeekActions: ((Sticker) -> [TelegramContextMenuAction])?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let collectionView: UICollectionView
    private let stickerGrid: UICollectionView
    private let emojiBubble = ChatInputEmojiBubbleView()
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)
    private var content = Content.hidden
    private var client: TDLibClient?
    private var stickerGridWidth: CGFloat = 0

    private var inlineState: InlineBotQueryState? {
        if case .inline(let state) = content { return state }
        return nil
    }

    private var hashtagRows: [ChatHashtagSuggestions.Row] {
        if case .hashtags(let suggestions) = content { return suggestions.rows }
        return []
    }

    private var suggestedStickers: [Sticker] {
        if case .stickers(let stickers) = content { return stickers }
        return []
    }

    private var display: Display {
        switch content {
        case .stickers: .stickers
        case .emojis: .emojis
        case .inline: inlineState?.isMediaGallery == true && inlineButton == nil ? .gallery : .list
        case .commands,
             .hashtags,
             .hidden,
             .mentions: .list
        }
    }

    /// VerticalListContextResultsChatInputPanelButtonItem: the bot's "switch to the bot" button heads the list.
    private var inlineButton: (text: String, parameter: String)? {
        guard let button = inlineState?.button,
              case .inlineQueryResultsButtonTypeStartBot(let start) = button.type else { return nil }
        return (button.text, start.parameter)
    }

    private var panelWidth: CGFloat {
        bounds.width > 0 ? bounds.width : window?.bounds.width ?? 0
    }

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        let stickerLayout = UICollectionViewFlowLayout()
        stickerLayout.minimumInteritemSpacing = 2
        stickerLayout.minimumLineSpacing = 2
        stickerLayout.sectionInset = UIEdgeInsets(top: 7, left: 2, bottom: 4, right: 2)
        self.stickerGrid = UICollectionView(frame: .zero, collectionViewLayout: stickerLayout)
        super.init(frame: frame)
        isHidden = true
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
        tableView.backgroundColor = .clear
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        tableView.rowHeight = Self.rowHeight
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(
            ChatInputSuggestionCell.self,
            forCellReuseIdentifier: ChatInputSuggestionCell.reuseIdentifier,
        )
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            ChatInputGalleryResultCell.self,
            forCellWithReuseIdentifier: ChatInputGalleryResultCell.reuseIdentifier,
        )
        stickerGrid.backgroundColor = .clear
        stickerGrid.showsVerticalScrollIndicator = false
        stickerGrid.dataSource = self
        stickerGrid.delegate = self
        stickerGrid.register(ComposerStickerCell.self, forCellWithReuseIdentifier: ComposerStickerCell.reuseIdentifier)
        // InlineReactionSearchPanel's peek recognizer: holding a sticker previews it and holding on opens its menu.
        let stickerPeek = StickerPeekGestureRecognizer(target: nil, action: nil)
        stickerPeek.contentAtPoint = { [weak self] point in self?.stickerPeekContent(at: point) }
        stickerGrid.addGestureRecognizer(stickerPeek)
        emojiBubble.onSelect = { [weak self] emoji in self?.onSelectEmoji?(emoji) }
        for subview in [tableView, collectionView, stickerGrid, emojiBubble] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: topAnchor),
                subview.leadingAnchor.constraint(equalTo: leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: trailingAnchor),
                subview.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The sticker grid's rows follow the width, which may arrive after the stickers.
        guard display == .stickers, bounds.width > 0, bounds.width != stickerGridWidth else { return }
        stickerGridWidth = bounds.width
        stickerGrid.collectionViewLayout.invalidateLayout()
        if !isHidden {
            heightConstraint.constant = stickerPanelHeight(count: suggestedStickers.count, width: bounds.width)
        }
    }

    private static func sameQuery(_ lhs: Content, _ rhs: Content) -> Bool {
        switch (lhs, rhs) {
        case (.inline(let lhsState), .inline(let rhsState)):
            lhsState.botUserID == rhsState.botUserID && lhsState.query == rhsState.query
        case (.commands, .commands),
             (.mentions, .mentions):
            true
        default:
            false
        }
    }

    /// InlineReactionSearchStickersNode: five to eight stickers a row, by width.
    private static func stickerItemSize(width: CGFloat) -> (side: CGFloat, perRow: Int) {
        let perRow = min(8, max(5, Int(width / 80)))
        let side = floor((width - 2 * 2 - 2 * CGFloat(perRow - 1)) / CGFloat(perRow))
        return (max(side, 1), perRow)
    }

    func configure(_ newContent: Content, client: TDLibClient) {
        self.client = client
        guard newContent != content else { return }
        let previous = content
        content = newContent
        let display = display
        tableView.isHidden = display != .list
        collectionView.isHidden = display != .gallery
        stickerGrid.isHidden = display != .stickers
        emojiBubble.isHidden = display != .emojis
        let rows = tableView(tableView, numberOfRowsInSection: 0)
        let height: CGFloat =
            switch content {
            case .hidden: 0
            case .commands,
                 .mentions: min(CGFloat(rows), 4.5) * Self.rowHeight
            case .inline: display == .gallery ? Self.galleryHeight : min(CGFloat(rows), 3.5) * Self.rowHeight
            case .hashtags: min(CGFloat(rows), 4.5) * Self.hashtagRowHeight
            case .emojis(let emoji, _): emoji.isEmpty ? 0 : Self.emojiBubbleHeight
            case .stickers(let stickers): stickerPanelHeight(count: stickers.count, width: panelWidth)
            }
        isHidden = height == 0 || (display == .list && rows == 0)
        heightConstraint.constant = isHidden ? 0 : height
        switch display {
        case .gallery:
            collectionView.reloadData()
        case .list:
            tableView.reloadData()
        case .stickers:
            stickerGrid.reloadData()
        case .emojis:
            if case .emojis(let emoji, let caretX) = content { emojiBubble.configure(emoji, caretX: caretX) }
        }
        // A new query starts at the top; another page keeps the place.
        if !Self.sameQuery(previous, newContent) {
            tableView.setContentOffset(.zero, animated: false)
            collectionView.setContentOffset(.zero, animated: false)
            stickerGrid.setContentOffset(.zero, animated: false)
        }
    }

    // MARK: List

    func numberOfSections(in _: UITableView) -> Int { 1 }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        switch content {
        case .emojis,
             .hidden,
             .stickers: 0
        case .commands(let commands, _): commands.count
        case .mentions(let mentions): mentions.count
        case .inline(let state):
            state.results.count + (inlineButton == nil ? 0 : 1)
        case .hashtags: hashtagRows.count
        }
    }

    func tableView(_: UITableView, heightForRowAt _: IndexPath) -> CGFloat {
        if case .hashtags = content { return Self.hashtagRowHeight }
        return Self.rowHeight
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ChatInputSuggestionCell.reuseIdentifier,
            for: indexPath,
        ) as? ChatInputSuggestionCell else { return UITableViewCell() }
        switch content {
        case .emojis,
             .hidden,
             .stickers:
            break
        case .commands(let commands, let showsBotNames):
            guard let command = commands[safe: indexPath.row] else { break }
            let detail = showsBotNames
                ? [command.description, command.botUsername.map { "@" + $0 }]
                    .compactMap(\.self)
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                : command.description
            cell.configureCommand(title: "/" + command.command, detail: detail) { [weak self] in
                self?.onInsertCommand?(command)
            }
        case .mentions(let mentions):
            if let client,
               let mention = mentions[safe: indexPath.row] { cell.configureMention(mention, client: client) }
        case .inline(let state):
            if let button = inlineButton, indexPath.row == 0 {
                cell.configureButton(button.text)
            } else if let client,
                      let item = state.results[safe: indexPath.row - (inlineButton == nil ? 0 : 1)]
            {
                cell.configureResult(item.result, client: client)
            }
        case .hashtags:
            if case .hashtags(let suggestions) = content, let row = hashtagRows[safe: indexPath.row] {
                cell.configureHashtag(row, chat: suggestions.chat, client: client)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch content {
        case .emojis,
             .hidden,
             .stickers:
            break
        case .commands(let commands, _):
            if let command = commands[safe: indexPath.row] { onSendCommand?(command) }
        case .mentions(let mentions):
            if let mention = mentions[safe: indexPath.row] { onSelectMention?(mention) }
        case .inline(let state):
            if let button = inlineButton, indexPath.row == 0 {
                onInlineButton?(state.username, button.parameter)
            } else if let item = state.results[safe: indexPath.row - (inlineButton == nil ? 0 : 1)] {
                onSelectInlineResult?(item)
            }
        case .hashtags:
            if let row = hashtagRows[safe: indexPath.row] { onSelectHashtag?(row.hashtag) }
        }
    }

    /// HashtagChatInputPanelItem's reveal option: Delete forgets a recently used hashtag.
    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        guard case .recent(let hashtag) = hashtagRows[safe: indexPath.row] else { return nil }
        let delete = UIContextualAction(style: .destructive, title: L10n.telegram("Common.Delete")) {
            [weak self] _, _, completion in
            self?.onRemoveHashtag?(hashtag)
            completion(true)
        }
        let configuration = UISwipeActionsConfiguration(actions: [delete])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let state = inlineState, indexPath.row >= state.results.count - 3 else { return }
        onLoadMoreInlineResults?()
    }

    // MARK: Media Strip

    func collectionView(_ view: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        view === stickerGrid ? suggestedStickers.count : inlineState?.results.count ?? 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        if collectionView === stickerGrid {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ComposerStickerCell.reuseIdentifier,
                for: indexPath,
            )
            if let client, let sticker = suggestedStickers[safe: indexPath.item] {
                (cell as? ComposerStickerCell)?.configure(sticker: sticker, client: client)
            }
            return cell
        }
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ChatInputGalleryResultCell.reuseIdentifier,
            for: indexPath,
        )
        if let client, let item = inlineState?.results[safe: indexPath.item] {
            (cell as? ChatInputGalleryResultCell)?.configure(item.result, client: client)
        }
        return cell
    }

    func collectionView(_ view: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // A pick is an action, so the same item can be picked again while the panel stays.
        view.deselectItem(at: indexPath, animated: false)
        if view === stickerGrid {
            if let sticker = suggestedStickers[safe: indexPath.item] { onSelectSticker?(sticker) }
            return
        }
        guard let item = inlineState?.results[safe: indexPath.item] else { return }
        onSelectInlineResult?(item)
    }

    func collectionView(
        _ view: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath,
    ) {
        if view === stickerGrid {
            (cell as? ComposerStickerCell)?.setPlaybackVisible(true)
            return
        }
        guard let state = inlineState, indexPath.item >= state.results.count - 4 else { return }
        onLoadMoreInlineResults?()
    }

    func collectionView(_ view: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt _: IndexPath) {
        guard view === stickerGrid else { return }
        (cell as? ComposerStickerCell)?.setPlaybackVisible(false)
    }

    func collectionView(
        _ view: UICollectionView,
        layout _: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath,
    ) -> CGSize {
        if view === stickerGrid {
            let side = Self.stickerItemSize(width: view.bounds.width > 0 ? view.bounds.width : panelWidth).side
            return CGSize(width: side, height: side)
        }
        let height = Self.galleryHeight - 8
        guard let result = inlineState?.results[safe: indexPath.item]?.result else {
            return CGSize(width: height, height: height)
        }
        let size = InlineResultPreview(result).pixelSize
        guard size.width > 0, size.height > 0 else { return CGSize(width: height, height: height) }
        let width = (height * size.width / size.height).rounded()
        return CGSize(width: min(max(width, height * 0.6), height * 1.8), height: height)
    }

    /// One row shows whole; more show one and a half rows at first, the rest scroll.
    private func stickerPanelHeight(count: Int, width: CGFloat) -> CGFloat {
        guard count > 0, width > 0 else { return count > 0 ? 1 : 0 }
        let item = Self.stickerItemSize(width: width)
        return count > item.perRow ? floor(item.side * 1.5) : 7 + item.side + 4
    }

    private func stickerPeekContent(at point: CGPoint) -> StickerPeekContent? {
        guard let client,
              let path = stickerGrid.indexPathForItem(at: point),
              let sticker = suggestedStickers[safe: path.item],
              let cell = stickerGrid.cellForItem(at: path) else { return nil }
        return StickerPeekContent(
            sticker: sticker,
            client: client,
            sourceView: cell,
            actions: stickerPeekActions?(sticker) ?? [],
        )
    }
}

// MARK: - InlineResultPreview

/// What a list row or a strip cell shows for an inline result: its title and description, and the picture to load.
private struct InlineResultPreview {
    var title = ""
    var detail = ""
    var file: File?
    var minithumbnail: Data?
    var pixelSize = CGSize.zero

    init(_ result: TDNativeInlineQueryResult) {
        switch result {
        case .inlineQueryResultArticle(let value):
            self.title = value.title
            self.detail = value.description.isEmpty ? value.url : value.description
            use(value.thumbnail)
        case .inlineQueryResultContact(let value):
            self.title = [value.contact.firstName, value.contact.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            self.detail = value.contact.phoneNumber
            use(value.thumbnail)
        case .inlineQueryResultLocation(let value):
            self.title = value.title
            use(value.thumbnail)
        case .inlineQueryResultVenue(let value):
            self.title = value.venue.title
            self.detail = value.venue.address
            use(value.thumbnail)
        case .inlineQueryResultGame(let value):
            self.title = value.game.title
            self.detail = value.game.description
            use(value.game.photo)
        case .inlineQueryResultAnimation(let value):
            self.title = value.title
            self.minithumbnail = value.animation.minithumbnail?.data
            self.pixelSize = CGSize(width: CGFloat(value.animation.width), height: CGFloat(value.animation.height))
            use(value.animation.thumbnail)
        case .inlineQueryResultAudio(let value):
            self.title = value.audio.title.isEmpty ? value.audio.fileName : value.audio.title
            self.detail = value.audio.performer
            use(value.audio.albumCoverThumbnail)
        case .inlineQueryResultDocument(let value):
            self.title = value.title
            self.detail = value.description
            self.minithumbnail = value.document.minithumbnail?.data
            use(value.document.thumbnail)
        case .inlineQueryResultPhoto(let value):
            self.title = value.title
            self.detail = value.description
            use(value.photo)
        case .inlineQueryResultSticker(let value):
            self.title = value.sticker.emoji
            self.pixelSize = CGSize(width: CGFloat(value.sticker.width), height: CGFloat(value.sticker.height))
            if case .stickerFormatWebp = value.sticker.format {
                self.file = value.sticker.sticker
            } else {
                use(value.sticker.thumbnail)
            }
        case .inlineQueryResultVideo(let value):
            self.title = value.title
            self.detail = value.description
            self.minithumbnail = value.video.minithumbnail?.data
            self.pixelSize = CGSize(width: CGFloat(value.video.width), height: CGFloat(value.video.height))
            use(value.video.thumbnail)
        case .inlineQueryResultVoiceNote(let value):
            self.title = value.title
        }
    }

    /// Thumbnails ImageIO can draw; animated and video thumbnails fall back to the minithumbnail.
    private mutating func use(_ thumbnail: Thumbnail?) {
        guard let thumbnail else { return }
        if pixelSize == .zero { pixelSize = CGSize(width: CGFloat(thumbnail.width), height: CGFloat(thumbnail.height)) }
        switch thumbnail.format {
        case .thumbnailFormatGif,
             .thumbnailFormatJpeg,
             .thumbnailFormatPng,
             .thumbnailFormatWebp:
            file = thumbnail.file
        default:
            break
        }
    }

    private mutating func use(_ photo: Photo) {
        minithumbnail = photo.minithumbnail?.data
        let size = photo.sizes.first { $0.width >= 160 } ?? photo.sizes.last
        if let size {
            file = size.photo
            pixelSize = CGSize(width: CGFloat(size.width), height: CGFloat(size.height))
        }
    }
}

// MARK: - ChatInputSuggestionCell

private final class ChatInputSuggestionCell: UITableViewCell {
    static let reuseIdentifier = "ChatInputSuggestionCell"

    private let thumbnailView = TDImageLoadingView()
    private let avatarView = ProfileAvatarView()
    private let hashtagIcon = UIImageView()
    private let hashtagAvatar = ProfileAvatarView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let insertButton = UIButton(type: .system)
    private var onInsert: (() -> Void)?
    private lazy var textLeading = titleLabel.leadingAnchor.constraint(
        equalTo: contentView.layoutMarginsGuide.leadingAnchor,
    )
    private lazy var textLeadingAfterThumbnail = titleLabel.leadingAnchor.constraint(
        equalTo: thumbnailView.trailingAnchor,
        constant: 10,
    )
    private lazy var textLeadingAfterHashtag = titleLabel.leadingAnchor.constraint(
        equalTo: hashtagIcon.trailingAnchor,
        constant: 13,
    )
    private lazy var titleBottom = titleLabel.bottomAnchor.constraint(equalTo: contentView.centerYAnchor)
    private lazy var titleCenter = titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 6
        thumbnailView.backgroundColor = .tertiarySystemFill
        titleLabel.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.textColor = .secondaryLabel
        insertButton.setImage(UIImage(systemName: "arrow.up.left"), for: .normal)
        insertButton.tintColor = .secondaryLabel
        insertButton.accessibilityLabel = L10n.telegram("Common.Edit")
        insertButton.addAction(UIAction { [weak self] _ in self?.onInsert?() }, for: .touchUpInside)
        hashtagIcon.image = UIImage(
            systemName: "number",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold),
        )
        hashtagIcon.contentMode = .center
        // The badge takes the cell's accent; the image view's own tint is the white of the sign.
        hashtagIcon.tintColor = .white
        hashtagIcon.backgroundColor = tintColor
        hashtagIcon.layer.cornerRadius = 15
        hashtagIcon.clipsToBounds = true
        for subview in [thumbnailView, avatarView, hashtagIcon, hashtagAvatar, titleLabel, detailLabel, insertButton]
            as [UIView]
        {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 40),
            thumbnailView.heightAnchor.constraint(equalToConstant: 40),
            avatarView.leadingAnchor.constraint(equalTo: thumbnailView.leadingAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            hashtagIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            hashtagIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            hashtagIcon.widthAnchor.constraint(equalToConstant: 30),
            hashtagIcon.heightAnchor.constraint(equalToConstant: 30),
            hashtagAvatar.leadingAnchor.constraint(equalTo: hashtagIcon.leadingAnchor),
            hashtagAvatar.topAnchor.constraint(equalTo: hashtagIcon.topAnchor),
            hashtagAvatar.widthAnchor.constraint(equalToConstant: 30),
            hashtagAvatar.heightAnchor.constraint(equalToConstant: 30),
            titleLabel.trailingAnchor.constraint(equalTo: insertButton.leadingAnchor, constant: -8),
            titleBottom,
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 1),
            insertButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            insertButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            insertButton.widthAnchor.constraint(equalToConstant: 32),
            insertButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.cancel()
        thumbnailView.image = nil
        avatarView.prepareForReuse()
        hashtagAvatar.prepareForReuse()
        onInsert = nil
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        hashtagIcon.backgroundColor = tintColor
    }

    /// HashtagChatInputPanelItem: the hashtag badge, or the chat's photo for a tag naming the chat, "#tag" in
    /// semibold, and for "Use" rows what the tag finds.
    func configureHashtag(_ row: ChatHashtagSuggestions.Row, chat: SettingsPeer?, client: TDLibClient?) {
        titleLabel.textColor = .label
        switch row {
        case .useGeneric(let hashtag):
            titleLabel.text = L10n.telegram("Chat.HashtagSuggestion.UseGeneric.Title", "#" + hashtag)
            detailLabel.text = L10n.telegram("Chat.HashtagSuggestion.UseGeneric.Text")
        case .useLocal(let hashtag, let isChannel):
            titleLabel.text = L10n.telegram("Chat.HashtagSuggestion.UseLocal.Title", "#" + hashtag)
            detailLabel.text = L10n.telegram(
                isChannel
                    ? "Chat.HashtagSuggestion.UseLocal.Channel.Text"
                    : "Chat.HashtagSuggestion.UseLocal.Group.Text",
            )
        case .recent(let hashtag):
            titleLabel.text = "#" + hashtag
            detailLabel.text = nil
        }
        layout(thumbnail: false, insert: false, hashtag: true)
        let photoChat = row.hashtag.contains("@") ? chat : nil
        hashtagIcon.isHidden = photoChat != nil
        hashtagAvatar.isHidden = photoChat == nil
        if let photoChat, let client {
            hashtagAvatar.configure(
                file: photoChat.file,
                minithumbnail: photoChat.minithumbnail,
                placeholder: photoChat.placeholder,
                accountID: TDLib.shared.activeAccountID,
                accountUserID: 0,
                client: client,
            )
        }
        selectionStyle = .default
    }

    /// MentionChatInputPanelItem: the person's photo and name, with the username below.
    func configureMention(_ mention: ChatMentionSuggestion, client: TDLibClient) {
        layout(thumbnail: false, insert: false, avatar: true)
        titleLabel.text = mention.peer.title
        titleLabel.textColor = .label
        detailLabel.text = mention.username.map { "@" + $0 }
        avatarView.configure(
            file: mention.peer.file,
            minithumbnail: mention.peer.minithumbnail,
            placeholder: mention.peer.placeholder,
            accountID: TDLib.shared.activeAccountID,
            accountUserID: 0,
            client: client,
        )
        selectionStyle = .default
    }

    func configureCommand(title: String, detail: String, onInsert: @escaping () -> Void) {
        layout(thumbnail: false, insert: true)
        titleLabel.text = title
        titleLabel.textColor = .label
        detailLabel.text = detail
        self.onInsert = onInsert
        selectionStyle = .default
    }

    func configureResult(_ result: TDNativeInlineQueryResult, client: TDLibClient) {
        let preview = InlineResultPreview(result)
        layout(thumbnail: true, insert: false)
        titleLabel.text = preview.title
        titleLabel.textColor = .label
        detailLabel.text = preview.detail
        if let file = preview.file {
            thumbnailView.load(
                file: file,
                placeholderData: preview.minithumbnail,
                maximumPixelSize: 160,
                client: client,
            )
        } else {
            thumbnailView.loadPlaceholder(data: preview.minithumbnail, client: client)
        }
        selectionStyle = .default
    }

    func configureButton(_ title: String) {
        layout(thumbnail: false, insert: false)
        titleLabel.text = title
        titleLabel.textColor = tintColor
        detailLabel.text = nil
        selectionStyle = .default
    }

    private func layout(thumbnail: Bool, insert: Bool, avatar: Bool = false, hashtag: Bool = false) {
        thumbnailView.isHidden = !thumbnail
        avatarView.isHidden = !avatar
        hashtagIcon.isHidden = !hashtag
        hashtagAvatar.isHidden = true
        insertButton.isHidden = !insert
        // The avatar sits where the thumbnail does; the hashtag badge is narrower.
        textLeading.isActive = false
        textLeadingAfterThumbnail.isActive = false
        textLeadingAfterHashtag.isActive = false
        if hashtag {
            textLeadingAfterHashtag.isActive = true
        } else if thumbnail || avatar {
            textLeadingAfterThumbnail.isActive = true
        } else {
            textLeading.isActive = true
        }
        titleBottom.isActive = !hashtag || detailLabel.text?.isEmpty == false
        titleCenter.isActive = !titleBottom.isActive
    }
}

// MARK: - ChatInputGalleryResultCell

private final class ChatInputGalleryResultCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatInputGalleryResultCell"

    private let imageView = TDImageLoadingView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.backgroundColor = .tertiarySystemFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.cancel()
        imageView.image = nil
    }

    func configure(_ result: TDNativeInlineQueryResult, client: TDLibClient) {
        let preview = InlineResultPreview(result)
        if case .inlineQueryResultSticker = result {
            imageView.contentMode = .scaleAspectFit
            imageView.backgroundColor = .clear
        } else {
            imageView.contentMode = .scaleAspectFill
            imageView.backgroundColor = .tertiarySystemFill
        }
        if let file = preview.file {
            imageView.load(file: file, placeholderData: preview.minithumbnail, maximumPixelSize: 320, client: client)
        } else {
            imageView.loadPlaceholder(data: preview.minithumbnail, client: client)
        }
        accessibilityLabel = preview.title
    }
}

// MARK: - ChatInputEmojiBubbleView

/// EmojisChatInputContextPanelNode's bubble: a row of 45 pt emoji, at most the width less 10 pt a side, whose arrow
/// points down at the caret. A tap puts the emoji in place of the ":" word.
private final class ChatInputEmojiBubbleView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    private static let itemSide: CGFloat = 45
    private static let arrowHeight: CGFloat = 10
    private static let sideInset: CGFloat = 10
    private static let cornerRadius: CGFloat = 8

    var onSelect: ((String) -> Void)?

    private let shape = CAShapeLayer()
    private let collectionView: UICollectionView
    private var emoji = [ChatEmojiSuggestion]()
    private var caretX: CGFloat?

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: Self.itemSide, height: Self.itemSide)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        shape.lineWidth = 1 / max(1, traitCollection.displayScale)
        shape.shadowOpacity = 0.08
        shape.shadowRadius = 6
        shape.shadowOffset = CGSize(width: 0, height: 2)
        layer.addSublayer(shape)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.layer.cornerRadius = Self.cornerRadius
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ChatInputEmojiCell.self, forCellWithReuseIdentifier: ChatInputEmojiCell.reuseIdentifier)
        addSubview(collectionView)
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ChatInputEmojiBubbleView, _) in
            view.updateColors()
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = min(
            max(24, bounds.width - Self.sideInset * 2),
            max(24, CGFloat(emoji.count) * Self.itemSide),
        )
        let height = max(0, bounds.height - Self.arrowHeight)
        // The arrow sits 55 pt into the bubble unless the caret pulls the bubble along, clamped to the edges.
        let anchor = caretX ?? Self.sideInset + 55
        let maxX = max(Self.sideInset, bounds.width - Self.sideInset - width)
        let bubbleX = min(max(Self.sideInset, anchor - 55), maxX)
        let arrowInset = Self.cornerRadius + 9
        let arrowX = min(max(anchor, bubbleX + arrowInset), bubbleX + width - arrowInset)
        let bubble = CGRect(x: bubbleX, y: 0, width: width, height: height)
        let path = UIBezierPath(roundedRect: bubble, cornerRadius: Self.cornerRadius)
        let arrow = UIBezierPath()
        arrow.move(to: CGPoint(x: arrowX - 9, y: height - 0.5))
        arrow.addQuadCurve(
            to: CGPoint(x: arrowX, y: height + Self.arrowHeight - 1),
            controlPoint: CGPoint(x: arrowX - 3, y: height + 2),
        )
        arrow.addQuadCurve(
            to: CGPoint(x: arrowX + 9, y: height - 0.5),
            controlPoint: CGPoint(x: arrowX + 3, y: height + 2),
        )
        arrow.close()
        path.append(arrow)
        shape.path = path.cgPath
        shape.shadowPath = path.cgPath
        collectionView.frame = bubble
    }

    func configure(_ emoji: [ChatEmojiSuggestion], caretX: CGFloat?) {
        let changed = emoji != self.emoji
        self.emoji = emoji
        self.caretX = caretX
        if changed {
            collectionView.reloadData()
            collectionView.setContentOffset(.zero, animated: false)
        }
        setNeedsLayout()
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int { emoji.count }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ChatInputEmojiCell.reuseIdentifier,
            for: indexPath,
        )
        if let item = emoji[safe: indexPath.item] { (cell as? ChatInputEmojiCell)?.configure(item) }
        return cell
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        if let item = emoji[safe: indexPath.item] { onSelect?(item.emoji) }
    }

    private func updateColors() {
        shape.fillColor = UIColor.systemBackground.resolvedColor(with: traitCollection).cgColor
        shape.strokeColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }
}

// MARK: - ChatInputEmojiCell

/// EmojisChatInputPanelItem: the emoji in 32 pt type.
private final class ChatInputEmojiCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatInputEmojiCell"

    override var isHighlighted: Bool {
        didSet { contentView.alpha = isHighlighted ? 0.5 : 1 }
    }

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 32)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    func configure(_ item: ChatEmojiSuggestion) {
        label.text = item.emoji
        accessibilityLabel = item.emoji
        accessibilityHint = item.keyword
    }
}

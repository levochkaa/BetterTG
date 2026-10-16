// ChatInputSuggestionsView.swift

import TDLibKit
import UIKit

// MARK: - ChatInputSuggestionsView

/// Telegram's input context panels above the text: a bot's commands while "/" is typed (CommandChatInputContext-
/// PanelNode) or from the Menu button (CommandMenuChatInputContextPanelNode), and an inline bot's results as a list
/// (VerticalListContextResultsChatInputContextPanelNode) or a media strip (HorizontalListContextResultsChatInput-
/// ContextPanelNode). Tapping a command or a result sends it; a command's arrow puts it into the input instead.
final class ChatInputSuggestionsView: UIView, UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource,
UICollectionViewDelegateFlowLayout {
    enum Content: Equatable {
        case hidden
        case commands([ChatBotCommand], showsBotNames: Bool)
        case mentions([ChatMentionSuggestion])
        case inline(InlineBotQueryState)

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
            default:
                false
            }
        }
    }

    private static let rowHeight: CGFloat = 52
    private static let galleryHeight: CGFloat = 96

    var onSendCommand: ((ChatBotCommand) -> Void)?
    var onInsertCommand: ((ChatBotCommand) -> Void)?
    var onSelectMention: ((ChatMentionSuggestion) -> Void)?
    var onSelectInlineResult: ((InlineBotResult) -> Void)?
    var onLoadMoreInlineResults: (() -> Void)?
    var onInlineButton: ((_ username: String, _ parameter: String) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let collectionView: UICollectionView
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)
    private var content = Content.hidden
    private var client: TDLibClient?

    private var inlineState: InlineBotQueryState? {
        if case .inline(let state) = content { return state }
        return nil
    }

    /// VerticalListContextResultsChatInputPanelButtonItem: the bot's "switch to the bot" button heads the list.
    private var inlineButton: (text: String, parameter: String)? {
        guard let button = inlineState?.button,
              case .inlineQueryResultsButtonTypeStartBot(let start) = button.type else { return nil }
        return (button.text, start.parameter)
    }

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
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
        for subview in [tableView, collectionView] {
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

    private static func sameQuery(_ lhs: Content, _ rhs: Content) -> Bool {
        switch (lhs, rhs) {
        case (.inline(let lhsState), .inline(let rhsState)):
            lhsState.botUserID == rhsState.botUserID && lhsState.query == rhsState.query
        case (.commands, .commands), (.mentions, .mentions):
            true
        default:
            false
        }
    }

    func configure(_ newContent: Content, client: TDLibClient) {
        self.client = client
        guard newContent != content else { return }
        let previous = content
        content = newContent
        let usesGallery = inlineState?.isMediaGallery == true && inlineButton == nil
        tableView.isHidden = usesGallery
        collectionView.isHidden = !usesGallery
        let rows = tableView(tableView, numberOfRowsInSection: 0)
        let height: CGFloat =
            switch content {
            case .hidden: 0
            case .commands, .mentions: min(CGFloat(rows), 4.5) * Self.rowHeight
            case .inline: usesGallery ? Self.galleryHeight : min(CGFloat(rows), 3.5) * Self.rowHeight
            }
        isHidden = height == 0 || (!usesGallery && rows == 0)
        heightConstraint.constant = isHidden ? 0 : height
        if usesGallery {
            collectionView.reloadData()
        } else {
            tableView.reloadData()
        }
        // A new query starts at the top; another page keeps the place.
        if !Self.sameQuery(previous, newContent) {
            tableView.setContentOffset(.zero, animated: false)
            collectionView.setContentOffset(.zero, animated: false)
        }
    }

    // MARK: List

    func numberOfSections(in _: UITableView) -> Int { 1 }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        switch content {
        case .hidden: 0
        case .commands(let commands, _): commands.count
        case .mentions(let mentions): mentions.count
        case .inline(let state):
            state.results.count + (inlineButton == nil ? 0 : 1)
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ChatInputSuggestionCell.reuseIdentifier,
            for: indexPath,
        ) as? ChatInputSuggestionCell else { return UITableViewCell() }
        switch content {
        case .hidden:
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
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch content {
        case .hidden:
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
        }
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let state = inlineState, indexPath.row >= state.results.count - 3 else { return }
        onLoadMoreInlineResults?()
    }

    // MARK: Media Strip

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        inlineState?.results.count ?? 0
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ChatInputGalleryResultCell.reuseIdentifier,
            for: indexPath,
        )
        if let client, let item = inlineState?.results[safe: indexPath.item] {
            (cell as? ChatInputGalleryResultCell)?.configure(item.result, client: client)
        }
        return cell
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = inlineState?.results[safe: indexPath.item] else { return }
        onSelectInlineResult?(item)
    }

    func collectionView(_: UICollectionView, willDisplay _: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let state = inlineState, indexPath.item >= state.results.count - 4 else { return }
        onLoadMoreInlineResults?()
    }

    func collectionView(
        _: UICollectionView,
        layout _: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath,
    ) -> CGSize {
        let height = Self.galleryHeight - 8
        guard let result = inlineState?.results[safe: indexPath.item]?.result else {
            return CGSize(width: height, height: height)
        }
        let size = InlineResultPreview(result).pixelSize
        guard size.width > 0, size.height > 0 else { return CGSize(width: height, height: height) }
        let width = (height * size.width / size.height).rounded()
        return CGSize(width: min(max(width, height * 0.6), height * 1.8), height: height)
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
        case .thumbnailFormatGif, .thumbnailFormatJpeg, .thumbnailFormatPng, .thumbnailFormatWebp:
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
        for subview in [thumbnailView, avatarView, titleLabel, detailLabel, insertButton] as [UIView] {
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
            titleLabel.trailingAnchor.constraint(equalTo: insertButton.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.centerYAnchor),
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
        onInsert = nil
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

    private func layout(thumbnail: Bool, insert: Bool, avatar: Bool = false) {
        thumbnailView.isHidden = !thumbnail
        avatarView.isHidden = !avatar
        insertButton.isHidden = !insert
        // The avatar sits where the thumbnail does.
        textLeading.isActive = !thumbnail && !avatar
        textLeadingAfterThumbnail.isActive = thumbnail || avatar
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

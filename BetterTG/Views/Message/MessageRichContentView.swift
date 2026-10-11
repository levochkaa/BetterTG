// MessageRichContentView.swift

import AVKit
import TDLibKit
import UIKit

// MARK: - MessageRichContentState

@MainActor final class MessageRichContentState {
    var fullMessage: TDNativeRichMessage?
    var expanded = [String: Bool]()
    var revealedSpoilers = Set<String>()
    private(set) var revision = 0

    func invalidateContent() {
        fullMessage = nil
        revision += 1
    }
}

// MARK: - MessageRichContentView

/// UIKit counterpart of Telegram's ChatMessageRichDataBubbleContentNode and
/// InstantPageV2 block layout. Expansion lives on the message, never on a cell.
final class MessageRichContentView: UIView, MessageSupplementView {
    private let stack = UIStackView()
    private let source: TDNativeRichMessage
    private let messageID: Int64
    private let chatID: Int64
    private let client: TDLibClient
    private let state: MessageRichContentState
    private let onAction: (MessageContentAction) -> Void
    private var textViews = [MessageTextContentView]()
    private var images = [TDImageLoadingView]()
    private var attachments = [TelegramFileMessageView]()
    private var tasks = [Task<Void, Never>]()
    private var playbackVisible = false
    private let contentWidth = Utils.maxMessageContentWidth

    init(
        content: TDNativeRichMessage,
        messageID: Int64,
        chatID: Int64,
        client: TDLibClient,
        state: MessageRichContentState,
        onAction: @escaping (MessageContentAction) -> Void,
    ) {
        self.source = content
        self.messageID = messageID
        self.chatID = chatID
        self.client = client
        self.state = state
        self.onAction = onAction
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: contentWidth),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        render()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MessageRichContentView, _) in
            view.render()
            view.onAction(.richContentLayoutChanged)
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func prepareForReuse() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        clearViews()
    }

    func setPlaybackVisible(_ isVisible: Bool) {
        playbackVisible = isVisible
        textViews.forEach { $0.setCustomEmojiPlaybackVisible(isVisible) }
        attachments.forEach { $0.setPlaybackVisible(isVisible) }
    }

    private func clearViews() {
        textViews.forEach { $0.prepareForReuse() }
        images.forEach { $0.cancel() }
        attachments.forEach { $0.prepareForReuse() }
        textViews.removeAll()
        images.removeAll()
        attachments.removeAll()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    private func render() {
        clearViews()
        let content = state.fullMessage ?? source
        semanticContentAttribute = content.isRtl ? .forceRightToLeft : .unspecified
        append(content.blocks, to: stack, width: contentWidth, path: "root")
        if !content.isFull {
            let button = actionButton(L10n.telegram("Chat.RichText.ShowMore")) { [weak self] button in
                self?.loadFull(button)
            }
            button.accessibilityIdentifier = "rich-message-show-more"
            stack.addArrangedSubview(button)
        }
        setPlaybackVisible(playbackVisible)
        invalidateIntrinsicContentSize()
    }

    private func loadFull(_ button: UIButton) {
        guard chatID != 0, TDLib.shared.activeClient.id == client.id else { return }
        button.isEnabled = false
        let revision = state.revision
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                let full = try await client.send(TDNativeRequests.getFullRichMessage(
                    chatId: chatID,
                    messageId: messageID,
                ))
                guard !Task.isCancelled, TDLib.shared.activeClient.id == client.id,
                      state.revision == revision else { return }
                state.fullMessage = full
                render()
                onAction(.richContentLayoutChanged)
            } catch {
                guard !Task.isCancelled else { return }
                button.isEnabled = true
                button.setTitle(L10n.telegram("ChatImportActivity.Retry"), for: .normal)
            }
        })
    }

    private func text(
        _ value: TDNativeRichText,
        width: CGFloat,
        path: String,
        font: UIFont = .body,
    ) -> MessageTextContentView {
        let rich = MessageRichText(value, font: font, isRTL: source.isRtl, traits: traitCollection)
        let view = MessageTextContentView()
        view.configure(
            formattedText: rich.formatted,
            client: client,
            statusText: "",
            statusColor: .secondaryLabel,
            maximumWidth: max(1, width),
            spoilersRevealed: state.revealedSpoilers.contains(path),
            richAttributedText: rich.attributed,
        )
        view.accessibilityLabel = RichMessageText.plainText(
            value,
            revealSpoilers: state.revealedSpoilers.contains(path),
        )
        view.onRevealSpoilers = { [weak state, weak view] in
            state?.revealedSpoilers.insert(path)
            view?.accessibilityLabel = RichMessageText.plainText(value, revealSpoilers: true)
        }
        view.onOpenRichURL = { [weak self] url in
            guard let button = rich.buttons[url.absoluteString] else { return false }
            self?.perform(button)
            return true
        }
        textViews.append(view)
        return view
    }

    private func append(
        _ blocks: [TDNativePageBlock],
        to parent: UIStackView,
        width: CGFloat,
        path: String,
        depth: Int = 0,
    ) {
        guard depth < 32 else { return }
        for (index, block) in blocks.enumerated() {
            let key = "\(path).\(index)"
            func addText(_ value: TDNativeRichText, font: UIFont = .body) {
                parent.addArrangedSubview(text(value, width: width, path: key, font: font))
            }
            func nested(_ blocks: [TDNativePageBlock], _ target: UIStackView, inset: CGFloat = 0) {
                append(blocks, to: target, width: max(1, width - inset), path: key, depth: depth + 1)
            }
            func caption(_ value: TDNativePageBlockCaption?) {
                guard let value else { return }
                parent.addArrangedSubview(text(
                    value.text,
                    width: width,
                    path: key + ".caption",
                    font: .systemFont(ofSize: 14),
                ))
                if let credit = value.credit {
                    parent.addArrangedSubview(text(
                        credit,
                        width: width,
                        path: key + ".credit",
                        font: .systemFont(ofSize: 13),
                    ))
                }
            }
            switch block {
            case .pageBlockSectionHeading(let value):
                let sizes: [CGFloat] = [24, 21, 19, 18, 17, 16]
                addText(value.text, font: .systemFont(ofSize: sizes[min(5, max(0, value.size - 1))], weight: .semibold))
            case .pageBlockTitle(let value): addText(value.title, font: .systemFont(ofSize: 24, weight: .semibold))
            case .pageBlockHeader(let value): addText(value.header, font: .systemFont(ofSize: 24, weight: .semibold))
            case .pageBlockSubtitle(let value): addText(
                    value.subtitle,
                    font: .systemFont(ofSize: 21, weight: .semibold),
                )
            case .pageBlockSubheader(let value): addText(
                    value.subheader,
                    font: .systemFont(ofSize: 21, weight: .semibold),
                )
            case .pageBlockKicker(let value): addText(value.kicker, font: .systemFont(ofSize: 14, weight: .semibold))
            case .pageBlockParagraph(let value): addText(value.text)
            case .pageBlockFooter(let value): addText(value.footer, font: .systemFont(ofSize: 14))
            case .pageBlockThinking(let value):
                let view = text(value.text, width: width, path: key)
                view.alpha = 0.55
                parent.addArrangedSubview(view)
            case .pageBlockAuthorDate(let value): addText(value.author, font: .systemFont(ofSize: 14))
            case .pageBlockPreformatted(let value):
                let body = verticalStack(spacing: 6)
                if !value.language.isEmpty {
                    let header = actionButton(value.language + "  ⧉") { _ in
                        UIPasteboard.setPlainText(MessageRichText(value.text).formatted.text)
                    }
                    header.contentHorizontalAlignment = .leading
                    body.addArrangedSubview(header)
                }
                body.addArrangedSubview(text(
                    value.text,
                    width: width - 20,
                    path: key,
                    font: .monospacedSystemFont(ofSize: 15, weight: .regular),
                ))
                parent.addArrangedSubview(box(body, inset: 10, accent: true))
            case .pageBlockDivider:
                let divider = UIView()
                divider.backgroundColor = .separator
                divider.heightAnchor
                    .constraint(equalToConstant: 1 / max(1, traitCollection.displayScale))
                    .isActive = true
                parent.addArrangedSubview(divider)
            case .pageBlockList(let value):
                for (itemIndex, item) in value.items.enumerated() {
                    let marker = UILabel()
                    marker.font = .body
                    marker.text = item.hasCheckbox
                        ? (item.isChecked ? "☑" : "☐")
                        : (item.label.isEmpty ? "•" : item.label)
                    marker.textColor = .label
                    marker.setContentHuggingPriority(.required, for: .horizontal)
                    marker.setContentCompressionResistancePriority(.required, for: .horizontal)
                    let body = verticalStack(spacing: 6)
                    append(
                        item.blocks,
                        to: body,
                        width: max(1, width - 28),
                        path: "\(key).item\(itemIndex)",
                        depth: depth + 1,
                    )
                    let row = UIStackView(arrangedSubviews: [marker, body])
                    row.spacing = 8
                    row.alignment = .top
                    parent.addArrangedSubview(row)
                }
            case .pageBlockBlockQuote(let value):
                let body = verticalStack(spacing: 6)
                nested(value.blocks, body, inset: 20)
                if let credit = value.credit { body.addArrangedSubview(text(
                    credit,
                    width: width - 20,
                    path: key + ".credit",
                    font: .italic,
                )) }
                parent.addArrangedSubview(box(body, inset: 10, accent: true))
            case .pageBlockExpandableBlockQuote(let value):
                let body = verticalStack(spacing: 6)
                let expanded = state.expanded[key] ?? false
                let label = text(value.text, width: width - 20, path: key)
                if !expanded { label.textContainer.maximumNumberOfLines = 3
                    label.textContainer.lineBreakMode = .byTruncatingTail
                }
                body.addArrangedSubview(label)
                body
                    .addArrangedSubview(actionButton(expanded
                            ? L10n.telegram("ChatList.Search.ShowLess")
                            : L10n.telegram("Chat.RichText.ShowMore"))
                    { [weak self] _ in
                        self?.toggle(key, current: expanded)
                    })
                if let credit = value.credit { body.addArrangedSubview(text(
                    credit,
                    width: width - 20,
                    path: key + ".credit",
                    font: .italic,
                )) }
                parent.addArrangedSubview(box(body, inset: 10, accent: true))
            case .pageBlockPullQuote(let value):
                addText(value.text, font: .italic)
                if let credit = value.credit { addText(credit, font: .systemFont(ofSize: 14)) }
            case .pageBlockDetails(let value):
                let expanded = state.expanded[key] ?? value.isOpen
                let header = MessageRichText(value.header).formatted.text
                parent.addArrangedSubview(actionButton((expanded ? "▾ " : "▸ ") + header) { [weak self] _ in
                    self?.toggle(key, current: expanded)
                })
                if expanded { nested(value.blocks, parent) }
            case .pageBlockTable(let value):
                if let title = value.caption { addText(title, font: .bold) }
                parent.addArrangedSubview(table(value, width: width, path: key))
            case .pageBlockPhoto(let value):
                if let photo = value.photo,
                   let size = photo.sizes.max(by: { $0.width * $0.height < $1.width * $1.height })
                {
                    parent.addArrangedSubview(media(
                        file: size.photo,
                        preview: size.photo,
                        placeholder: photo.minithumbnail?.data,
                        size: CGSize(width: size.width, height: size.height),
                        width: width,
                        isVideo: false,
                        spoiler: value.hasSpoiler,
                        path: key,
                    ))
                }
                caption(value.caption)
            case .pageBlockVideo(let value):
                if let video = value.video {
                    parent.addArrangedSubview(media(
                        file: video.video,
                        preview: video.thumbnail?.file,
                        placeholder: video.minithumbnail?.data,
                        size: CGSize(width: video.width, height: video.height),
                        width: width,
                        isVideo: true,
                        spoiler: value.hasSpoiler,
                        path: key,
                    ))
                }
                caption(value.caption)
            case .pageBlockAnimation(let value):
                if let animation = value.animation {
                    parent.addArrangedSubview(media(
                        file: animation.animation,
                        preview: animation.thumbnail?.file,
                        placeholder: animation.minithumbnail?.data,
                        size: CGSize(width: animation.width, height: animation.height),
                        width: width,
                        isVideo: true,
                        spoiler: value.hasSpoiler,
                        path: key,
                    ))
                }
                caption(value.caption)
            case .pageBlockAudio(let value):
                addAttachment(
                    TelegramFileMessageView(audio: value.audio, client: client, onAction: onAction),
                    to: parent,
                )
                caption(value.caption)
            case .pageBlockDocument(let value):
                addAttachment(
                    TelegramFileMessageView(document: value.document, client: client, onAction: onAction),
                    to: parent,
                )
                caption(value.caption)
            case .pageBlockVoiceNote(let value):
                let voice = value.voiceNote
                let audio = Audio(
                    duration: voice.duration,
                    title: L10n.telegram("VoiceOver.Chat.VoiceMessage"),
                    performer: "",
                    fileName: "",
                    mimeType: voice.mimeType,
                    albumCoverMinithumbnail: nil,
                    albumCoverThumbnail: nil,
                    externalAlbumCovers: [],
                    audio: voice.voice,
                )
                addAttachment(TelegramFileMessageView(audio: audio, client: client, onAction: onAction), to: parent)
                caption(value.caption)
            case .pageBlockCollage(let value): nested(value.blocks, parent)
                caption(value.caption)
            case .pageBlockSlideshow(let value): nested(value.blocks, parent)
                caption(value.caption)
            case .pageBlockCover(let value): nested([value.cover], parent)
            case .pageBlockEmbeddedPost(let value): nested(value.blocks, parent)
                caption(value.caption)
            case .pageBlockButtonRow(let value):
                let buttons = value.buttons.map { button in
                    actionButton(MessageRichText(button.text).formatted.text) { [weak self] _ in self?.perform(button) }
                }
                let row = UIStackView(arrangedSubviews: buttons)
                row.distribution = .fillEqually
                row.spacing = 6
                parent.addArrangedSubview(row)
            case .pageBlockMathematicalExpression(let value):
                if let formula = MessageMathRenderer.block(value.expression, width: width, traits: traitCollection) {
                    parent.addArrangedSubview(formula)
                } else {
                    addText(.richTextPlain(TDNativeRichTextPlain(text: value.expression)), font: .monospaced)
                }
            case .pageBlockMap(let value):
                parent.addArrangedSubview(actionButton("📍 " + L10n.telegram("Map.Map")) { [weak self] _ in
                    self?.onAction(.openLocation(location: value.location, title: ""))
                })
                caption(value.caption)
            case .pageBlockChatLink(let value):
                parent
                    .addArrangedSubview(actionButton(value.title) { [weak self] _ in
                        self?.open("https://t.me/\(value.username)")
                    })
            case .pageBlockEmbedded(let value):
                if !value.url
                    .isEmpty { parent.addArrangedSubview(actionButton(value.url) { [weak self] _ in
                        self?.open(value.url)
                    }) }
                caption(value.caption)
            case .pageBlockRelatedArticles(let value):
                addText(value.header, font: .bold)
                for article in value.articles {
                    parent.addArrangedSubview(actionButton(article.title) { [weak self] _ in self?.open(article.url) })
                }
            case .pageBlockUnsupported:
                let label = UILabel()
                label.text = L10n.betterTG("Chat.UnsupportedBetterTG")
                label.textColor = .secondaryLabel
                parent.addArrangedSubview(label)
            case .pageBlockAnchor: break
            }
        }
    }

    private func toggle(_ key: String, current: Bool) {
        state.expanded[key] = !current
        render()
        onAction(.richContentLayoutChanged)
    }

    private func addAttachment(_ view: TelegramFileMessageView, to parent: UIStackView) {
        attachments.append(view)
        parent.addArrangedSubview(view)
    }

    private func table(_ value: TDNativePageBlockTable, width: CGFloat, path: String) -> UIView {
        // Row/column guides preserve TDLib's rowspan/colspan, including invisible
        // placeholder cells, while a horizontal scroll view keeps text readable.
        struct Cell { let value: TDNativePageBlockTableCell
            let row: Int
            let column: Int
        }
        var occupied = Set<String>()
        var cells = [Cell]()
        var columns = 1
        var rows = max(1, value.cells.count)
        for (row, values) in value.cells.enumerated() {
            var column = 0
            for cell in values {
                while occupied.contains("\(row):\(column)") {
                    column += 1
                }
                guard cell.text != nil else { column += 1
                    continue
                }
                cells.append(Cell(value: cell, row: row, column: column))
                for r in row..<(row + max(1, cell.rowspan)) {
                    for c in column..<(column + max(1, cell.colspan)) {
                        occupied.insert("\(r):\(c)")
                    }
                }
                rows = max(rows, row + max(1, cell.rowspan))
                column += max(1, cell.colspan)
                columns = max(columns, column)
            }
        }
        let scroll = UIScrollView()
        scroll.alwaysBounceHorizontal = false
        let grid = UIView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(grid)
        let cellWidth = max(100, width / CGFloat(columns))
        let tableWidth = cellWidth * CGFloat(columns)
        var rowHeights = Array(repeating: CGFloat(34), count: rows)
        var rendered = [(Cell, MessageTextContentView)]()
        let padding: CGFloat = value.isCompact ? 5 : 8
        for cell in cells {
            guard let content = cell.value.text else { continue }
            let span = max(1, cell.value.colspan)
            let label = text(
                content,
                width: cellWidth * CGFloat(span) - padding * 2,
                path: "\(path).\(cell.row).\(cell.column)",
                font: cell.value.isHeader ? .bold : .body,
            )
            let requiredHeight = label.intrinsicContentSize.height + padding * 2
            let rowSpan = max(1, cell.value.rowspan)
            for row in cell.row..<(cell.row + rowSpan) {
                rowHeights[row] = max(
                    rowHeights[row],
                    ceil(requiredHeight / CGFloat(rowSpan)),
                )
            }
            rendered.append((cell, label))
        }
        let totalHeight = rowHeights.reduce(0, +)
        for (cell, label) in rendered {
            let background = UIView(frame: CGRect(
                x: CGFloat(cell.column) * cellWidth,
                y: rowHeights.prefix(cell.row).reduce(0, +),
                width: cellWidth * CGFloat(max(
                    1,
                    cell.value.colspan,
                )),
                height: rowHeights[cell.row..<(cell.row + max(1, cell.value.rowspan))]
                    .reduce(
                        0,
                        +,
                    ),
            ))
            if cell.value
                .isHeader || (value.isStriped && cell.row % 2 == 1) { background.backgroundColor = .tertiarySystemFill }
            if value.isBordered { background.layer.borderWidth = 0.5
                background.layer.borderColor = UIColor.separator.cgColor
            }
            label.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(label)
            let align = cell.value.align
            label.textAlignment = align == .pageBlockHorizontalAlignmentCenter
                ? .center
                : align == .pageBlockHorizontalAlignmentRight ? .right : .left
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: padding),
                label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -padding),
            ])
            switch cell.value.valign {
            case .pageBlockVerticalAlignmentTop: label.topAnchor
                .constraint(
                    equalTo: background.topAnchor,
                    constant: padding,
                )
                .isActive = true
            case .pageBlockVerticalAlignmentBottom: label.bottomAnchor
                .constraint(
                    equalTo: background.bottomAnchor,
                    constant: -padding,
                )
                .isActive = true
            case .pageBlockVerticalAlignmentMiddle: label.centerYAnchor
                .constraint(equalTo: background.centerYAnchor)
                .isActive = true
            }
            grid.addSubview(background)
        }
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            grid.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            grid.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            grid.widthAnchor.constraint(equalToConstant: tableWidth),
            grid.heightAnchor.constraint(equalToConstant: totalHeight),
            scroll.heightAnchor.constraint(equalToConstant: totalHeight + (tableWidth > width ? 5 : 0)),
        ])
        return scroll
    }

    private func media(
        file: File,
        preview: File?,
        placeholder: Data?,
        size: CGSize,
        width: CGFloat,
        isVideo: Bool,
        spoiler: Bool,
        path: String,
    ) -> UIView {
        let button = UIButton(type: .custom)
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = 7
        button.clipsToBounds = true
        let image = TDImageLoadingView()
        image.contentMode = .scaleAspectFill
        image.isUserInteractionEnabled = false
        if let preview { image.load(file: preview, placeholderData: placeholder, maximumPixelSize: 900, client: client)
        }
        images.append(image)
        pin(image, to: button)
        button.heightAnchor
            .constraint(equalToConstant: min(420, max(90, width * size.height / max(1, size.width))))
            .isActive = true
        let label = UILabel()
        label.text = isVideo ? "▶︎" : nil
        label.font = .systemFont(ofSize: 36)
        label.textColor = .white
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        pin(label, to: button)
        if spoiler, !state.revealedSpoilers.contains(path) {
            let cover = TelegramSpoilerView()
            cover.backgroundColor = .secondarySystemBackground
            cover.isUserInteractionEnabled = false
            pin(cover, to: button)
            button.accessibilityLabel = "Reveal spoiler"
            button.addAction(UIAction { [weak self, weak cover] _ in
                guard let self else { return }
                if !state.revealedSpoilers.contains(path) {
                    state.revealedSpoilers.insert(path)
                    UIView.animate(
                        withDuration: 0.2,
                        animations: { cover?.alpha = 0 },
                        completion: { _ in cover?.removeFromSuperview() },
                    )
                } else { openMedia(file, isVideo: isVideo) }
            }, for: .touchUpInside)
        } else {
            button.accessibilityLabel = isVideo ? "Play video" : "Open photo"
            button.addAction(UIAction { [weak self] _ in self?.openMedia(file, isVideo: isVideo) }, for: .touchUpInside)
        }
        return button
    }

    private func openMedia(_ file: File, isVideo: Bool) {
        guard TDLib.shared.activeClient.id == client.id else { return }
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                let downloaded = try await client.downloadFile(
                    fileId: file.id,
                    limit: 0,
                    offset: 0,
                    priority: 32,
                    synchronous: true,
                )
                guard !Task.isCancelled, TDLib.shared.activeClient.id == client.id,
                      downloaded.local.isDownloadingCompleted else { return }
                let url = URL(fileURLWithPath: downloaded.local.path)
                if isVideo {
                    let controller = AVPlayerViewController()
                    controller.player = AVPlayer(url: url)
                    nearestViewController?.present(controller, animated: true) { controller.player?.play() }
                } else { onAction(.openDocument(url)) }
            } catch { showError(error.localizedDescription) }
        })
    }

    private func perform(_ button: TDNativeInlineButton) {
        guard TDLib.shared.activeClient.id == client.id else { return }
        switch button.type {
        case .inlineKeyboardButtonTypeUrl(let value): open(value.url)
        case .inlineKeyboardButtonTypeLoginUrl(let value): open(value.url)
        case .inlineKeyboardButtonTypeWebApp(let value): open(value.url)
        case .inlineKeyboardButtonTypeCopyText(let value): UIPasteboard.setPlainText(value.text)
        case .inlineKeyboardButtonTypeUser(let value): open("tg://user?id=\(value.userId)")
        case .inlineKeyboardButtonTypeCallback(let value):
            tasks.append(Task { [weak self] in
                guard let self else { return }
                do {
                    let answer = try await client.send(TDNativeRequests.getCallbackQueryAnswer(
                        chatId: chatID,
                        messageId: messageID,
                        payload: .callbackQueryPayloadData(TDNativeCallbackQueryPayloadData(data: value.data)),
                    ))
                    guard !Task.isCancelled, TDLib.shared.activeClient.id == client.id else { return }
                    if !answer.text.isEmpty { showError(answer.text) }
                    if !answer.url.isEmpty { open(answer.url) }
                } catch { showError(error.localizedDescription) }
            })
        case .inlineKeyboardButtonTypeDisabled: break
        default: showError(L10n.betterTG("Chat.UnsupportedBetterTG"))
        }
    }

    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        TelegramLinkRouter.shared.open(url, from: nearestViewController)
    }

    private func showError(_ text: String) {
        guard window != nil else { return }
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .cancel))
        nearestViewController?.present(alert, animated: true)
    }

    private func actionButton(_ title: String, action: @escaping (UIButton) -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.titleLabel?.numberOfLines = 0
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        button.addAction(UIAction { [weak button] _ in if let button { action(button) } }, for: .touchUpInside)
        return button
    }

    private func verticalStack(spacing: CGFloat) -> UIStackView {
        let view = UIStackView()
        view.axis = .vertical
        view.spacing = spacing
        return view
    }

    private func box(_ content: UIView, inset: CGFloat, accent: Bool) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.07)
        view.layer.cornerRadius = 5
        view.clipsToBounds = true
        pin(content, to: view, inset: inset)
        if accent {
            let bar = UIView()
            bar.backgroundColor = .systemBlue
            bar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                bar.topAnchor.constraint(equalTo: view.topAnchor),
                bar.bottomAnchor.constraint(equalTo: view.bottomAnchor), bar.widthAnchor.constraint(equalToConstant: 3),
            ])
        }
        return view
    }

    private func pin(_ child: UIView, to parent: UIView, inset: CGFloat = 0) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset),
        ])
    }
}

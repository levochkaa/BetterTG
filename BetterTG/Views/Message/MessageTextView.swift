// MessageTextView.swift

import Combine
import TDLibKit
import UIKit

final class MessageTextContentView: UITextView, UITextViewDelegate {
    private struct CustomEmojiRequest {
        let identifier: Int64
        let range: NSRange
    }

    private struct CustomEmojiPlacement {
        let range: NSRange
        let view: CustomEmojiInlineView
    }

    // MARK: Internal

    override var canBecomeFirstResponder: Bool { false }

    override var intrinsicContentSize: CGSize {
        guard attributedText.length > 0 else { return .zero }
        let measurement = measureText(maximumWidth: maximumLayoutWidth)
        return CGSize(
            width: min(maximumLayoutWidth, measurement.width),
            height: measurement.height,
        )
    }

    // MARK: Private

    var onRevealSpoilers: (() -> Void)?
    var onUnhandledTap: (() -> Void)?

    private var spoilerRanges = [NSRange]()
    private var spoilersRevealed = false
    private var spoilerViews = [TelegramSpoilerView]()
    private var lastSpoilerRects = [CGRect]()
    private var formattedText: FormattedText?
    private var spoilerState: MessageTextSpoilerState?
    private var spoilerSubscription: AnyCancellable?
    private var emojiClient: TDLibClient?
    private var lastLayoutWidth = CGFloat.zero
    private var maximumLayoutWidth = Utils.maxMessageContentWidth
    private let statusLabel = UILabel()

    private var customEmojiPlacements = [CustomEmojiPlacement]()
    private var customEmojiTask: Task<Void, Never>?
    private var customEmojiGeneration = 0
    private var customEmojiPlaybackVisible = false
    private var quoteHighlightRange: NSRange?
    private var quoteHighlightTask: Task<Void, Never>?
    private var quoteHighlightViews = [UIView]()

    #if DEBUG
        var debugQuoteHighlightCount: Int { quoteHighlightViews.count }
        var debugCustomEmojiGeneration: Int { customEmojiGeneration }
    #endif

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        backgroundColor = .clear
        isScrollEnabled = false
        isEditable = false
        // Telegram owns long-press handling at the message level. Links stay
        // tappable through our recognizer without installing UITextView's
        // selection/link context menus.
        isSelectable = false
        textContainerInset = .zero
        self.textContainer.lineFragmentPadding = 0
        self.textContainer.lineBreakMode = .byWordWrapping
        delegate = self
        linkTextAttributes = [.foregroundColor: UIColor.systemBlue]
        adjustsFontForContentSizeCategory = true
        setContentCompressionResistancePriority(.required, for: .vertical)
        statusLabel.font = .caption
        statusLabel.textAlignment = .right
        statusLabel.isUserInteractionEnabled = false
        addSubview(statusLabel)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleEntityTap(_:))))
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        let oldWidth = lastLayoutWidth
        super.layoutSubviews()
        statusLabel.sizeToFit()
        statusLabel.frame.origin = CGPoint(
            x: bounds.maxX - statusLabel.bounds.width,
            y: bounds.maxY - statusLabel.bounds.height,
        )
        bringSubviewToFront(statusLabel)
        layoutCustomEmojiViews()
        layoutQuoteHighlightViews()
        layoutSpoilers()
        lastLayoutWidth = bounds.width
        if abs(oldWidth - bounds.width) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }

    func configure(
        formattedText: FormattedText,
        client: TDLibClient,
        statusText: String,
        statusColor: UIColor,
        maximumWidth: CGFloat = Utils.maxMessageContentWidth,
        spoilersRevealed: Bool = false,
    ) {
        clearCustomEmojiViews()
        self.formattedText = formattedText
        self.spoilersRevealed = spoilersRevealed
        spoilerRanges = TelegramSpoilers.ranges(in: formattedText)
        maximumLayoutWidth = maximumWidth
        statusLabel.text = statusText
        statusLabel.textColor = statusColor
        statusLabel.sizeToFit()
        let result = NSMutableAttributedString(
            attributedString: NSAttributedString(getAttributedString(from: formattedText)),
        )
        for range in spoilerRanges {
            result.removeAttribute(.backgroundColor, range: range)
            if !spoilersRevealed {
                result.addAttributes([
                    .foregroundColor: UIColor.clear,
                    .underlineColor: UIColor.clear,
                    .strikethroughColor: UIColor.clear,
                ], range: range)
                result.removeAttribute(.link, range: range)
            }
        }
        result.append(statusSpacer(width: ceil(statusLabel.bounds.width) + 9))
        attributedText = result
        loadCustomEmoji(from: formattedText)
        bringSubviewToFront(statusLabel)
        invalidateIntrinsicContentSize()
        accessibilityLabel = TelegramSpoilers.accessibilityText(formattedText, revealed: spoilersRevealed)
        accessibilityCustomActions = !spoilersRevealed && !spoilerRanges.isEmpty
            ? [UIAccessibilityCustomAction(name: "Reveal spoiler") { [weak self] _ in self?.revealSpoilers() ?? false }]
            : nil
        layoutSpoilers()
    }

    func setMaximumLayoutWidth(_ width: CGFloat) {
        let resolvedWidth = max(1, width)
        guard abs(maximumLayoutWidth - resolvedWidth) > 0.5 else { return }
        maximumLayoutWidth = resolvedWidth
        invalidateIntrinsicContentSize()
    }

    func prepareForReuse() {
        clearQuoteHighlight()
        clearCustomEmojiViews()
        customEmojiPlaybackVisible = false
        spoilerSubscription = nil
        spoilerState = nil
        emojiClient = nil
        formattedText = nil
        onRevealSpoilers = nil
        onUnhandledTap = nil
        spoilerRanges.removeAll()
        spoilerViews.forEach { $0.removeFromSuperview() }
        spoilerViews.removeAll()
        lastSpoilerRects.removeAll()
        attributedText = NSAttributedString()
        statusLabel.text = nil
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityCustomActions = nil
    }

    func setCustomEmojiPlaybackVisible(_ isVisible: Bool) {
        customEmojiPlaybackVisible = isVisible
        for placement in customEmojiPlacements {
            placement.view.setPlaybackVisible(isVisible)
        }
    }

    func highlightQuote(position: Int, length: Int) {
        guard let formattedText,
              position >= 0,
              length > 0,
              position < formattedText.text.utf16.count
        else { return }
        clearQuoteHighlight()
        quoteHighlightRange = NSRange(
            location: position,
            length: min(length, formattedText.text.utf16.count - position),
        )
        layoutIfNeeded()
        layoutQuoteHighlightViews()
        for view in quoteHighlightViews {
            view.alpha = 0
            UIView.animate(withDuration: 0.18) { view.alpha = 1 }
        }
        quoteHighlightTask = Task { @MainActor [weak self] in
            #if DEBUG
                let visibleDuration = ProcessInfo.processInfo.arguments.contains("-ui-probe-message-metadata")
                    ? 30.0
                    : 1.2
            #else
                let visibleDuration = 1.2
            #endif
            try? await Task<Never, Never>.sleep(for: .seconds(visibleDuration))
            guard let self, !Task.isCancelled else { return }
            let views = quoteHighlightViews
            quoteHighlightViews.removeAll()
            quoteHighlightRange = nil
            UIView.animate(withDuration: 0.28) {
                views.forEach { $0.alpha = 0 }
            } completion: { _ in
                views.forEach { $0.removeFromSuperview() }
            }
            quoteHighlightTask = nil
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        textView.selectedTextRange = nil
    }

    @discardableResult func revealSpoilers() -> Bool {
        guard !spoilersRevealed, !spoilerRanges.isEmpty, let formattedText else { return false }
        let overlays = spoilerViews
        spoilerViews.removeAll()
        lastSpoilerRects.removeAll()
        configure(
            formattedText: formattedText,
            statusText: statusLabel.text ?? "",
            statusColor: statusLabel.textColor,
            maximumWidth: maximumLayoutWidth,
            spoilersRevealed: true,
        )
        UIView.animate(withDuration: 0.22, animations: { overlays.forEach { $0.alpha = 0 } }, completion: { _ in
            overlays.forEach { $0.removeFromSuperview() }
        })
        onRevealSpoilers?()
        return true
    }

    private func measureText(maximumWidth: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let storage = NSTextStorage(attributedString: attributedText)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: maximumWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        let usedRect = manager.usedRect(for: container)
        return (ceil(usedRect.width), ceil(usedRect.height))
    }

    private func loadCustomEmoji(from formattedText: FormattedText, client: TDLibClient) {
        let requests = formattedText.entities.compactMap { entity -> CustomEmojiRequest? in
            guard case .textEntityTypeCustomEmoji(let customEmoji) = entity.type else { return nil }
            let range = NSRange(location: entity.offset, length: entity.length)
            guard permitsCustomEmoji(range: range, generation: customEmojiGeneration)
            else { return nil }
            return CustomEmojiRequest(
                identifier: customEmoji.customEmojiId,
                range: range,
            )
        }
        guard !requests.isEmpty else { return }

        let generation = customEmojiGeneration
        customEmojiTask = Task { [weak self] in
            let stickers = await CustomEmojiStickerRepository.shared.stickers(
                for: requests.map(\.identifier),
                client: client,
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.customEmojiGeneration == generation else { return }
                self.installCustomEmoji(requests: requests, stickers: stickers, client: client)
            }
        }
    }

    private func installCustomEmoji(
        requests: [CustomEmojiRequest],
        stickers: [Int64: Sticker],
        client: TDLibClient,
    ) {
        let generation = customEmojiGeneration
        for request in requests {
            guard let sticker = stickers[request.identifier],
                  permitsCustomEmoji(range: request.range, generation: generation)
            else { continue }
            let emojiView = CustomEmojiInlineView()
            emojiView.isUserInteractionEnabled = false
            emojiView.configure(sticker: sticker, client: client)
            emojiView.onFirstFrameReady = { [weak self, weak emojiView] in
                guard let self, let emojiView,
                      customEmojiPlacements.contains(where: { $0.view === emojiView }),
                      permitsCustomEmoji(range: request.range, generation: generation)
                else { return }
                textStorage.addAttribute(.foregroundColor, value: UIColor.clear, range: request.range)
                setNeedsDisplay()
            }
            emojiView.setPlaybackVisible(customEmojiPlaybackVisible)
            addSubview(emojiView)
            customEmojiPlacements.append(CustomEmojiPlacement(
                range: request.range,
                view: emojiView,
            ))
        }
        setNeedsLayout()
    }

    private func clearCustomEmojiViews() {
        customEmojiGeneration += 1
        customEmojiTask?.cancel()
        customEmojiTask = nil
        for placement in customEmojiPlacements {
            placement.view.prepareForReuse()
            placement.view.removeFromSuperview()
        }
        customEmojiPlacements.removeAll()
    }

    private func clearQuoteHighlight() {
        quoteHighlightTask?.cancel()
        quoteHighlightTask = nil
        quoteHighlightRange = nil
        quoteHighlightViews.forEach { $0.removeFromSuperview() }
        quoteHighlightViews.removeAll()
    }

    private func layoutQuoteHighlightViews() {
        guard let range = quoteHighlightRange,
              NSMaxRange(range) <= textStorage.length,
              bounds.width > 0
        else { return }
        quoteHighlightViews.forEach { $0.removeFromSuperview() }
        quoteHighlightViews.removeAll()
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer,
        ) { [weak self] rect, _ in
            guard let self, !rect.isNull, !rect.isEmpty else { return }
            let highlight = UIView(frame: rect.offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
                .insetBy(
                    dx: -2,
                    dy: -1,
                ))
            highlight.isUserInteractionEnabled = false
            highlight.backgroundColor = UIColor.messageHighlight.withAlphaComponent(0.55)
            highlight.layer.cornerRadius = 4
            insertSubview(highlight, belowSubview: statusLabel)
            quoteHighlightViews.append(highlight)
        }
        for placement in customEmojiPlacements {
            bringSubviewToFront(placement.view)
        }
        bringSubviewToFront(statusLabel)
    }

    private func layoutCustomEmojiViews() {
        guard !customEmojiPlacements.isEmpty else { return }
        layoutManager.ensureLayout(for: textContainer)
        for placement in customEmojiPlacements {
            guard NSMaxRange(placement.range) <= textStorage.length else {
                placement.view.isHidden = true
                continue
            }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: placement.range,
                actualCharacterRange: nil,
            )
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            guard !rect.isNull, !rect.isEmpty else {
                placement.view.isHidden = true
                continue
            }
            rect.origin.x += textContainerInset.left
            rect.origin.y += textContainerInset.top
            let font = attributedText.attribute(.font, at: placement.range.location, effectiveRange: nil) as? UIFont
            let side = ceil(font?.lineHeight ?? UIFont.body.lineHeight)
            placement.view.frame = CGRect(
                x: round(rect.midX - side / 2),
                y: round(rect.midY - side / 2),
                width: side,
                height: side,
            )
            placement.view.isHidden = !spoilersRevealed && spoilerRanges.contains {
                NSIntersectionRange($0, placement.range).length > 0
            }
        }
        bringSubviewToFront(statusLabel)
    }

    private func statusSpacer(width: CGFloat) -> NSAttributedString {
        let spacerCharacter = "\u{00a0}"
        let spacerText = "\u{200b}" + spacerCharacter + spacerCharacter
        let characterWidth = (spacerCharacter as NSString)
            .size(
                withAttributes: [.font: statusLabel.font as Any],
            )
            .width
        let spacer = NSMutableAttributedString(
            string: spacerText,
            attributes: [
                .font: statusLabel.font as Any,
                .foregroundColor: UIColor.clear,
            ],
        )
        spacer.addAttribute(
            .kern,
            value: max(0, width - characterWidth * 2),
            range: NSRange(location: 1, length: 1),
        )
        return spacer
    }

    @objc private func handleEntityTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let formattedText else { return }
        let point = gesture.location(in: self)
        var fraction = CGFloat.zero
        let index = layoutManager.characterIndex(
            for: CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top),
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction,
        )
        if !spoilersRevealed, spoilerRanges.contains(where: { $0.contains(index) }) {
            _ = revealSpoilers()
            return
        }
        for entity in formattedText.entities {
            let range = NSRange(location: entity.offset, length: entity.length)
            guard range.contains(index) else { continue }
            switch entity.type {
            case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
                UIPasteboard.setPlainText(rawText(for: entity, in: formattedText.text))
            case .textEntityTypeUrl:
                open(getUrl(from: rawText(for: entity, in: formattedText.text)))
            case .textEntityTypeTextUrl(let textUrl):
                open(getUrl(from: textUrl.url))
            case .textEntityTypeEmailAddress:
                open(URL(string: "mailto:\(rawText(for: entity, in: formattedText.text))"))
            case .textEntityTypePhoneNumber:
                open(URL(string: "tel:\(rawText(for: entity, in: formattedText.text))"))
            default:
                continue
            }
        }
    }

    private func layoutSpoilers() {
        var rects = [CGRect]()
        if !spoilersRevealed, bounds.width > 0 {
            layoutManager.ensureLayout(for: textContainer)
            for range in spoilerRanges where NSMaxRange(range) <= textStorage.length {
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                layoutManager.enumerateEnclosingRects(
                    forGlyphRange: glyphs,
                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                    in: textContainer,
                ) { rect, _ in
                    if !rect.isEmpty, !rect.isNull {
                        rects.append(rect.offsetBy(dx: self.textContainerInset.left, dy: self.textContainerInset.top))
                    }
                }
            }
        }
        guard rects != lastSpoilerRects else { return }
        lastSpoilerRects = rects
        spoilerViews.forEach { $0.removeFromSuperview() }
        spoilerViews = rects.map { rect in
            let view = TelegramSpoilerView(frame: rect)
            addSubview(view)
            return view
        }
        bringSubviewToFront(statusLabel)
    }

    private func rawText(for entity: TextEntity, in text: String) -> String {
        let range = stringRange(for: text, start: entity.offset, length: entity.length)
        return String(text[range])
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        TelegramLinkRouter.shared.open(url, from: nearestViewController)
    }
}

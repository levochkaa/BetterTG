// MessageTextView.swift

import Combine
import TDLibKit
import UIKit

final class MessageTextContentView: UITextView, UITextViewDelegate, UIEditMenuInteractionDelegate {
    private final class QuoteTapDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var owner: MessageTextContentView?

        init(owner: MessageTextContentView) { self.owner = owner }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
        ) -> Bool {
            owner?.contextQuoteAction != nil
        }
    }

    private struct CustomEmojiRequest {
        let identifier: Int64
        let range: NSRange
    }

    private struct CustomEmojiPlacement {
        let range: NSRange
        let view: CustomEmojiInlineView
    }

    // MARK: Internal

    override var canBecomeFirstResponder: Bool { contextQuoteAction != nil }

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
    var onOpenRichURL: ((URL) -> Bool)?

    private var contextQuoteAction: ((NSRange) -> Void)?
    private lazy var quoteMenuInteraction = UIEditMenuInteraction(delegate: self)
    private var quoteMenuTask: Task<Void, Never>?
    private lazy var entityTapDelegate = QuoteTapDelegate(owner: self)
    private lazy var entityTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleEntityTap(_:)))
    private var spoilerRanges = [NSRange]()
    private var spoilersRevealed = false
    private var spoilerViews = [TelegramSpoilerView]()
    private var lastSpoilerRects = [CGRect]()
    private var formattedText: FormattedText?
    private var richAttributedText: NSAttributedString?
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

        entityTapGesture.delegate = entityTapDelegate
        addGestureRecognizer(entityTapGesture)
        addInteraction(quoteMenuInteraction)
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
        richAttributedText: NSAttributedString? = nil,
    ) {
        clearCustomEmojiViews()
        self.formattedText = formattedText
        self.richAttributedText = richAttributedText
        self.spoilersRevealed = spoilersRevealed
        spoilerRanges = TelegramSpoilers.ranges(in: formattedText)
        maximumLayoutWidth = maximumWidth
        statusLabel.text = statusText
        statusLabel.textColor = statusColor
        statusLabel.sizeToFit()
        let result = NSMutableAttributedString(
            attributedString: richAttributedText ?? NSAttributedString(getAttributedString(from: formattedText)),
        )
        for range in spoilerRanges {
            result.removeAttribute(.backgroundColor, range: range)
            if !spoilersRevealed {
                result.enumerateAttribute(.attachment, in: range) { value, attachmentRange, _ in
                    guard let attachment = value as? NSTextAttachment else { return }
                    let hidden = NSTextAttachment()
                    hidden.bounds = attachment.bounds
                    result.addAttribute(.attachment, value: hidden, range: attachmentRange)
                }
                result.addAttributes([
                    .foregroundColor: UIColor.clear,
                    .underlineColor: UIColor.clear,
                    .strikethroughColor: UIColor.clear,
                ], range: range)
                result.removeAttribute(.link, range: range)
            }
        }
        if !statusText.isEmpty { result.append(statusSpacer(width: ceil(statusLabel.bounds.width) + 9)) }
        attributedText = result
        loadCustomEmoji(from: formattedText)
        bringSubviewToFront(statusLabel)
        invalidateIntrinsicContentSize()
        accessibilityLabel = TelegramSpoilers.accessibilityText(formattedText, revealed: spoilersRevealed)
        // UITextView otherwise exposes its underlying unredacted text as Value.
        accessibilityValue = ""
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
        setContextQuoteAction(nil)
        clearQuoteHighlight()
        clearCustomEmojiViews()
        customEmojiPlaybackVisible = false
        spoilerSubscription = nil
        spoilerState = nil
        emojiClient = nil
        formattedText = nil
        richAttributedText = nil
        onRevealSpoilers = nil
        onUnhandledTap = nil
        onOpenRichURL = nil
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

    func setContextQuoteAction(_ action: ((NSRange) -> Void)?) {
        contextQuoteAction = action
        entityTapGesture.cancelsTouchesInView = action == nil
        isSelectable = action != nil && formattedText != nil
        if action == nil {
            quoteMenuTask?.cancel()
            quoteMenuTask = nil
            quoteMenuInteraction.dismissMenu()
            selectedTextRange = nil
            resignFirstResponder()
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard contextQuoteAction != nil else {
            textView.selectedTextRange = nil
            return
        }
        // The invisible timestamp spacer is outside the original message text.
        if let formattedText, selectedRange.location != NSNotFound {
            let bounded = NSIntersectionRange(
                selectedRange,
                NSRange(location: 0, length: formattedText.text.utf16.count),
            )
            if bounded != selectedRange { selectedRange = bounded }
            if bounded.length > 0, !isFirstResponder { becomeFirstResponder() }
            #if DEBUG
            if bounded.length > 0 {
                TelegramQuoteSelectionDiagnostics
                    .record(
                        "selection=\(bounded.location),\(bounded.length) responder=\(isFirstResponder) key=\(window?.isKeyWindow ?? false)",
                    )
            }
            #endif
            if bounded.length > 0, !spoilersRevealed,
               spoilerRanges.contains(where: { NSIntersectionRange($0, bounded).length > 0 })
            {
                revealSpoilers()
                selectedRange = bounded
            }
            scheduleQuoteMenu()
        }
    }

    func editMenuInteraction(
        _: UIEditMenuInteraction, menuFor _: UIEditMenuConfiguration, suggestedActions: [UIMenuElement],
    ) -> UIMenu? {
        #if DEBUG
        TelegramQuoteSelectionDiagnostics.record("owned-menu=\(selectedRange.location),\(selectedRange.length)")
        #endif
        return quoteMenu(for: selectedRange, suggestedActions: suggestedActions)
    }

    func editMenuInteraction(_: UIEditMenuInteraction, targetRectFor _: UIEditMenuConfiguration) -> CGRect {
        quoteSelectionRect()
    }

    func textView(
        _: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement],
    ) -> UIMenu? {
        quoteMenu(for: range, suggestedActions: suggestedActions)
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
            richAttributedText: richAttributedText,
        )
        UIView.animate(withDuration: 0.22, animations: { overlays.forEach { $0.alpha = 0 } }, completion: { _ in
            overlays.forEach { $0.removeFromSuperview() }
        })
        onRevealSpoilers?()
        return true
    }

    private func scheduleQuoteMenu() {
        quoteMenuTask?.cancel()
        let range = selectedRange
        guard contextQuoteAction != nil, range.location != NSNotFound, range.length > 0 else {
            quoteMenuInteraction.dismissMenu()
            return
        }
        quoteMenuTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self, contextQuoteAction != nil, selectedRange == range,
                  window != nil else { return }
            layoutIfNeeded()
            let rect = quoteSelectionRect()
            guard !rect.isNull, !rect.isEmpty else { return }
            quoteMenuInteraction.presentEditMenu(with: UIEditMenuConfiguration(
                identifier: "message-quote" as NSString,
                sourcePoint: CGPoint(x: rect.midX, y: rect.midY),
            ))
        }
    }

    private func quoteSelectionRect() -> CGRect {
        guard let selectedTextRange else { return .null }
        return firstRect(for: selectedTextRange)
    }

    private func quoteMenu(for range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let contextQuoteAction, range.length > 0 else { return nil }
        #if DEBUG
        TelegramQuoteSelectionDiagnostics
            .record("native-menu=\(range.location),\(range.length) responder=\(isFirstResponder)")
        #endif
        let hidden = !spoilersRevealed && spoilerRanges.contains { NSIntersectionRange($0, range).length > 0 }
        guard !hidden else { return UIMenu(children: []) }
        let quote = UIAction(title: L10n.telegram("Conversation.ContextMenuQuote")) { _ in contextQuoteAction(range) }
        return UIMenu(children: [quote] + suggestedActions)
    }

    private func measureText(maximumWidth: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let storage = NSTextStorage(attributedString: attributedText)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: maximumWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = textContainer.lineBreakMode
        container.maximumNumberOfLines = textContainer.maximumNumberOfLines
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
        if contextQuoteAction != nil {
            scheduleQuoteMenu()
            return
        }
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
        onUnhandledTap?()
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
        if onOpenRichURL?(url) == true { return }
        TelegramLinkRouter.shared.open(url, from: nearestViewController)
    }
}

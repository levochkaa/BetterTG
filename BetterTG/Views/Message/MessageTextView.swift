// MessageTextView.swift

import Combine
import TDLibKit
import UIKit

final class MessageTextContentView: UITextView, UITextViewDelegate, UIEditMenuInteractionDelegate,
    UITextDragDelegate
{
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
    /// The last text selected for Quote while the menu was open. Menu actions run after dismissal clears the
    /// selection, so the reply options' Quote Selected Part reads it from here.
    private(set) var lastQuoteSelection: NSRange?

    /// ChatMessageTextBubbleContentNode's requestToggleBlockCollapsed; without it the view toggles on its own.
    var onToggleQuoteBlock: ((Int) -> Void)?

    private var contextQuoteAction: ((NSRange) -> Void)?
    /// Copy-protected text stays selectable for Quote; Copy, Share and dragging the text out stay unavailable.
    private var contextQuoteAllowsCopy = true
    /// Read-only chats select text to copy it without offering Quote (ChatController's text selection actions).
    private var contextQuoteAllowsQuote = true
    /// TextSelectionNode's Translate for the selected text, when the chat offers Telegram's translation.
    private var contextTranslateAction: ((String) -> Void)?
    private lazy var quoteMenuInteraction = UIEditMenuInteraction(delegate: self)
    private var quoteMenuTask: Task<Void, Never>?
    private lazy var entityTapDelegate = QuoteTapDelegate(owner: self)
    private lazy var entityTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleEntityTap(_:)))
    private var spoilerViews = [TelegramSpoilerView]()
    private var lastSpoilerRects = [CGRect]()
    private var formattedText: FormattedText?
    private var richAttributedText: NSAttributedString?
    private var spoilerState: MessageTextSpoilerState?
    private var spoilerSubscription: AnyCancellable?
    private var emojiClient: TDLibClient?
    private var lastLayoutWidth = CGFloat.zero
    private var maximumLayoutWidth = Utils.maxMessageContentWidth
    private let statusLabel = UILabel()
    private var status = MessageStatusLine(text: "")
    private var statusColor = UIColor.secondaryLabel
    private var customEmojiPlacements = [CustomEmojiPlacement]()
    private var customEmojiTask: Task<Void, Never>?
    private var customEmojiGeneration = 0
    private var customEmojiPlaybackVisible = false
    private var quoteHighlightRange: NSRange?
    private var quoteHighlightTask: Task<Void, Never>?
    private var quoteHighlightViews = [UIView]()
    /// The chat search's query while this text belongs to a found message (updateSearchTextHighlightState).
    private var searchHighlightQuery: String?

    /// The text's quotes and code blocks, drawn behind it (TextNode's block quotes).
    private var textBlocks = [MessageTextBlock]()
    /// The expandable quotes the reader opened, by block index.
    private var expandedQuoteBlocks = Set<Int>()
    private lazy var collapsedLayout = MessageCollapsedTextLayout(next: layoutManager.delegate)
    private let blockDecorationView = MessageTextBlockDecorationView()

    #if DEBUG
        var debugQuoteHighlightCount: Int { quoteHighlightViews.count }
        var debugCustomEmojiGeneration: Int { customEmojiGeneration }
    #endif

    #if DEBUG
        var probeBlockCollapse: [MessageTextBlock.Collapse?] { textBlocks.map(\.collapse) }

        func probeTap(at point: CGPoint) {
            _ = toggleQuoteBlock(at: point)
        }

        var probeBlockFrames: [CGRect] {
            layoutManager.ensureLayout(for: textContainer)
            return textBlocks.compactMap { $0.frame(layoutManager: layoutManager, textContainer: textContainer) }
        }

        func probeFirstLineIndent(of blockIndex: Int) -> CGFloat? {
            guard textBlocks.indices.contains(blockIndex) else { return nil }
            let style = textStorage.attribute(
                .paragraphStyle,
                at: textBlocks[blockIndex].range.location,
                effectiveRange: nil,
            )
            return (style as? NSParagraphStyle)?.firstLineHeadIndent
        }
    #endif

    /// Spoiler presentation follows `spoilerState`; these mirror it for layout and hit testing.
    private var spoilerRanges: [NSRange] { spoilerState?.presentation.ranges ?? [] }
    private var spoilersRevealed: Bool { spoilerState?.revealed ?? true }

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
        insertSubview(blockDecorationView, at: 0)
        layoutManager.delegate = collapsedLayout

        entityTapGesture.delegate = entityTapDelegate
        addGestureRecognizer(entityTapGesture)
        addInteraction(quoteMenuInteraction)
        textDragDelegate = self
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
        layoutTextBlocks()
        layoutCustomEmojiViews()
        layoutQuoteHighlightViews()
        layoutSpoilers()
        lastLayoutWidth = bounds.width
        if abs(oldWidth - bounds.width) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if !contextQuoteAllowsCopy, action == #selector(copy(_:)) || action == #selector(cut(_:)) { return false }
        return super.canPerformAction(action, withSender: sender)
    }

    private static func removingSystemTranslate(from elements: [UIMenuElement]) -> [UIMenuElement] {
        elements.compactMap { element -> UIMenuElement? in
            if let menu = element as? UIMenu {
                return menu.replacingChildren(removingSystemTranslate(from: menu.children))
            }
            if let command = element as? UICommand,
               NSStringFromSelector(command.action).localizedCaseInsensitiveContains("translate")
            {
                return nil
            }
            if let action = element as? UIAction,
               action.identifier.rawValue.localizedCaseInsensitiveContains("translate")
            {
                return nil
            }
            return element
        }
    }

    func configure(
        formattedText: FormattedText,
        client: TDLibClient,
        statusText: String,
        statusColor: UIColor,
        statusViewCount: String? = nil,
        statusLine: MessageStatusLine? = nil,
        maximumWidth: CGFloat = Utils.maxMessageContentWidth,
        spoilersRevealed: Bool = false,
        spoilerState: MessageTextSpoilerState? = nil,
        richAttributedText: NSAttributedString? = nil,
        expandedQuoteBlocks: Set<Int> = [],
    ) {
        self.expandedQuoteBlocks = expandedQuoteBlocks
        // A scoped store owns the reveal. Without one, the caller records it and passes it in.
        let state = spoilerState ?? MessageTextSpoilerState(
            text: formattedText,
            source: nil,
            revealed: spoilersRevealed,
        )
        if spoilersRevealed, !state.revealed { state.reveal() }
        configurePresentation(
            state: state,
            client: client,
            status: statusLine ?? MessageStatusLine(viewCount: statusViewCount, text: statusText),
            statusColor: statusColor,
            maximumWidth: maximumWidth,
            richAttributedText: richAttributedText,
        )
    }

    func configurePresentation(
        state: MessageTextSpoilerState, client: TDLibClient?, statusText: String, statusColor: UIColor,
        maximumWidth: CGFloat, richAttributedText: NSAttributedString? = nil,
    ) {
        configurePresentation(
            state: state,
            client: client,
            status: MessageStatusLine(text: statusText),
            statusColor: statusColor,
            maximumWidth: maximumWidth,
            richAttributedText: richAttributedText,
        )
    }

    /// The status trails the last line as in Telegram's text bubble; it shows the view count after an eye icon.
    func configurePresentation(
        state: MessageTextSpoilerState, client: TDLibClient?, status: MessageStatusLine, statusColor: UIColor,
        maximumWidth: CGFloat, richAttributedText: NSAttributedString? = nil,
    ) {
        spoilerState = state
        emojiClient = client
        self.richAttributedText = richAttributedText
        formattedText = state.presentation.text
        spoilerSubscription = state.changes.sink { [weak self, weak state] in
            guard let self, let state, spoilerState === state else { return }
            renderText()
            if state.revealed { onRevealSpoilers?() }
        }
        maximumLayoutWidth = maximumWidth
        self.status = status
        self.statusColor = statusColor
        // The label's font follows its attributed text, so the status keeps its own.
        statusLabel.attributedText = status.attributedText(font: .caption, color: statusColor)
        statusLabel.sizeToFit()
        renderText()
    }

    func setMaximumLayoutWidth(_ width: CGFloat) {
        let resolvedWidth = max(1, width)
        guard abs(maximumLayoutWidth - resolvedWidth) > 0.5 else { return }
        maximumLayoutWidth = resolvedWidth
        // A folded quote's cut depends on the width.
        if textBlocks.contains(where: \.isCollapsible) { renderText() }
        invalidateIntrinsicContentSize()
    }

    func prepareForReuse() {
        setContextQuoteAction(nil)
        clearQuoteHighlight()
        searchHighlightQuery = nil
        clearCustomEmojiViews()
        customEmojiPlaybackVisible = false
        spoilerSubscription = nil
        spoilerState = nil
        emojiClient = nil
        formattedText = nil
        richAttributedText = nil
        onRevealSpoilers = nil
        onToggleQuoteBlock = nil
        expandedQuoteBlocks = []
        onUnhandledTap = nil
        onOpenRichURL = nil
        spoilerViews.forEach { $0.removeFromSuperview() }
        spoilerViews.removeAll()
        lastSpoilerRects.removeAll()
        attributedText = NSAttributedString()
        statusLabel.text = nil
        status = MessageStatusLine(text: "")
        statusColor = .secondaryLabel
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

    /// Marks the words matching a chat search query behind Telegram's text highlight color, or clears them.
    func setSearchHighlight(_ query: String?) {
        let query = query?.isEmpty == false ? query : nil
        guard query != searchHighlightQuery else { return }
        searchHighlightQuery = query
        guard spoilerState != nil else { return }
        renderText()
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

    func setContextQuoteAction(
        _ action: ((NSRange) -> Void)?,
        allowsCopy: Bool = true,
        allowsQuote: Bool = true,
        translate: ((String) -> Void)? = nil,
    ) {
        contextQuoteAction = action
        contextQuoteAllowsCopy = action == nil || allowsCopy
        contextQuoteAllowsQuote = action == nil || allowsQuote
        contextTranslateAction = action == nil ? nil : translate
        if action != nil { lastQuoteSelection = nil }
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

    /// Telegram's beginTextSelection for the reply options: the current quote, or else the whole text, starts selected.
    func beginQuoteSelection(range: NSRange?) {
        guard contextQuoteAction != nil, window != nil, let formattedText else { return }
        let full = NSRange(location: 0, length: formattedText.text.utf16.count)
        guard full.length > 0 else { return }
        let requested = range.map { NSIntersectionRange($0, full) }
        let selection = requested.flatMap { $0.length > 0 ? $0 : nil } ?? full
        becomeFirstResponder()
        selectedRange = selection
        lastQuoteSelection = selection
        scheduleQuoteMenu()
    }

    func textDraggableView(
        _: UIView & UITextDraggable, itemsForDrag dragRequest: UITextDragRequest,
    ) -> [UIDragItem] {
        contextQuoteAllowsCopy ? dragRequest.suggestedItems : []
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
            lastQuoteSelection = bounded.length > 0 ? bounded : nil
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
        guard let state = spoilerState, !state.revealed, !state.presentation.ranges.isEmpty else { return false }
        let overlays = spoilerViews
        spoilerViews.removeAll()
        lastSpoilerRects.removeAll()
        if !state.reveal() {
            // A caller-owned text records the reveal through `onRevealSpoilers`; a scoped state that
            // refused it is stale and stays concealed.
            guard !state.isScoped, state.isValid else {
                spoilerViews = overlays
                layoutSpoilers()
                return false
            }
            configurePresentation(
                state: MessageTextSpoilerState(text: state.original, source: nil, revealed: true),
                client: emojiClient,
                status: status,
                statusColor: statusColor,
                maximumWidth: maximumLayoutWidth,
                richAttributedText: richAttributedText,
            )
            onRevealSpoilers?()
        }
        UIView.animate(withDuration: 0.22, animations: { overlays.forEach { $0.alpha = 0 } }, completion: { _ in
            overlays.forEach { $0.removeFromSuperview() }
        })
        return true
    }

    func permitsCustomEmoji(range: NSRange, generation: Int) -> Bool {
        guard generation == customEmojiGeneration, let state = spoilerState,
              range.location >= 0, range.length > 0, range.location <= state.presentation.text.text.utf16.count,
              range.length <= state.presentation.text.text.utf16.count - range.location
        else { return false }
        return !state.presentation.conceals(range, revealed: state.revealed)
    }

    func activateEntity(at point: CGPoint, perform: (MessageTextSpoilerPresentation.Action) -> Void) {
        guard let state = spoilerState else { return }
        layoutManager.ensureLayout(for: textContainer)
        let location = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        var fraction = CGFloat.zero
        let index = layoutManager.characterIndex(
            for: location,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction,
        )
        guard index < state.presentation.text.text.utf16.count else { return }
        let glyphs = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: index, length: 1),
            actualCharacterRange: nil,
        )
        guard layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).contains(location) else { return }
        let action = state.presentation.action(at: index, revealed: state.revealed)
        if action == .reveal { revealSpoilers() }
        perform(action)
    }

    /// The link, mention or bot command a long press at `point` is on, which opens its own menu.
    func link(at point: CGPoint) -> MessageTextLink? {
        guard let state = spoilerState else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let inset = textContainerInset
        let location = CGPoint(x: point.x - inset.left, y: point.y - inset.top)
        var fraction = CGFloat.zero
        let index = layoutManager.characterIndex(
            for: location,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction,
        )
        guard index < state.presentation.text.text.utf16.count else { return nil }
        let glyphs = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: index, length: 1),
            actualCharacterRange: nil,
        )
        guard layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).contains(location),
              let link = state.presentation.longPressTarget(at: index, revealed: state.revealed),
              NSMaxRange(link.range) <= textStorage.length
        else { return nil }
        // Each line's glyphs, as InteractiveTextNode's attributeRects: selection rects would run on to the line's end.
        let linkGlyphs = layoutManager.glyphRange(forCharacterRange: link.range, actualCharacterRange: nil)
        var rects = [CGRect]()
        layoutManager.enumerateLineFragments(forGlyphRange: linkGlyphs) { [
            layoutManager,
            textContainer,
        ] _, _, _, lineGlyphs, _ in
            let glyphs = NSIntersectionRange(lineGlyphs, linkGlyphs)
            guard glyphs.length > 0 else { return }
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            if !rect.isEmpty, !rect.isNull { rects.append(rect.offsetBy(dx: inset.left, dy: inset.top)) }
        }
        guard !rects.isEmpty else { return nil }
        return MessageTextLink(target: link.target, rects: rects)
    }

    /// LinkHighlightingNode over `rects` below the text, in the link highlight color.
    func addLinkHighlight(_ rects: [CGRect]) -> UIView {
        let highlight = MessageLinkHighlightView(rects: rects, color: UIColor.systemBlue.withAlphaComponent(0.3))
        insertSubview(highlight, aboveSubview: blockDecorationView)
        return highlight
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
        // TextSelectionNode drops Copy and Share for protected content and keeps Quote.
        var quoteActions: [UIMenuElement] = contextQuoteAllowsQuote ? [quote] : []
        var systemActions = contextQuoteAllowsCopy ? suggestedActions : []
        if let contextTranslateAction, let formattedText, NSMaxRange(range) <= (formattedText.text as NSString).length {
            // Telegram's own Translate takes the system one's place.
            let selected = (formattedText.text as NSString).substring(with: range)
            quoteActions.append(UIAction(title: L10n.telegram("Conversation.ContextMenuTranslate")) { _ in
                contextTranslateAction(selected)
            })
            systemActions = Self.removingSystemTranslate(from: systemActions)
        }
        return UIMenu(children: quoteActions + systemActions)
    }

    private func renderText() {
        guard let state = spoilerState else { return }
        clearCustomEmojiViews()
        let text = state.presentation.text
        let result = NSMutableAttributedString(
            attributedString: richAttributedText ?? NSAttributedString(getAttributedString(from: text)),
        )
        textBlocks = richAttributedText == nil ? MessageTextBlock.blocks(in: text) : []
        MessageTextBlock.applyStyles(textBlocks, to: result)
        textBlocks = MessageTextBlock.applyCollapse(
            textBlocks,
            to: result,
            width: maximumLayoutWidth,
            expanded: expandedQuoteBlocks,
        )
        for range in state.presentation.ranges where NSMaxRange(range) <= result.length {
            result.removeAttribute(.backgroundColor, range: range)
            guard !state.revealed else { continue }
            result.enumerateAttribute(.attachment, in: range) { value, attachmentRange, _ in
                guard let attachment = value as? NSTextAttachment else { return }
                let hidden = NSTextAttachment()
                hidden.bounds = attachment.bounds
                result.addAttribute(.attachment, value: hidden, range: attachmentRange)
            }
            // Remove link styling last: UITextView linkTextAttributes can override foregroundColor.
            result.removeAttribute(.link, range: range)
            result.addAttributes([
                .foregroundColor: UIColor.clear,
                .underlineColor: UIColor.clear,
                .strikethroughColor: UIColor.clear,
            ], range: range)
        }
        if let query = searchHighlightQuery {
            let hiddenRanges = state.revealed ? [] : state.presentation.ranges
            for range in ChatSearchTextHighlight.ranges(in: result.string, query: query)
                where NSMaxRange(range) <= result.length
                && !hiddenRanges.contains(where: { NSIntersectionRange($0, range).length > 0 })
            {
                result.addAttribute(.backgroundColor, value: ChatSearchTextHighlight.color, range: range)
            }
        }
        if statusLabel.text?.isEmpty == false {
            // ChatMessageTextBubbleContentNode puts the status under a block that ends the text.
            if let last = textBlocks.last, NSMaxRange(last.range) >= (text.text as NSString).length {
                result.append(NSAttributedString(string: "\n", attributes: [.font: statusLabel.font as Any]))
            }
            result.append(statusSpacer(width: ceil(statusLabel.bounds.width) + 9))
        }
        attributedText = result
        setNeedsLayout()
        if let emojiClient { loadCustomEmoji(from: text, client: emojiClient) }
        bringSubviewToFront(statusLabel)
        invalidateIntrinsicContentSize()
        accessibilityLabel = state.presentation.accessibilityText(revealed: state.revealed)
        // UITextView otherwise derives a value from its original string; the safe label owns spoken text.
        accessibilityValue = ""
        accessibilityCustomActions = !state.revealed && !state.presentation.ranges.isEmpty
            ?
            [UIAccessibilityCustomAction(name: L10n.betterTG("Accessibility.RevealSpoiler")) { [weak self] _ in
                self?.revealSpoilers() ?? false
            }]
            : nil
        lastSpoilerRects.removeAll()
        layoutSpoilers()
    }

    private func measureText(maximumWidth: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let storage = NSTextStorage(attributedString: attributedText)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: maximumWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = textContainer.lineBreakMode
        container.maximumNumberOfLines = textContainer.maximumNumberOfLines
        let collapsed = MessageCollapsedTextLayout(next: nil)
        manager.delegate = collapsed
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        let usedRect = manager.usedRect(for: container)
        withExtendedLifetime(collapsed) {}
        // A block reaches past its widest line by the icon's room.
        let blockWidth = textBlocks.compactMap { $0.frame(layoutManager: manager, textContainer: container)?.maxX }
            .max() ?? 0
        return (ceil(max(usedRect.width, min(maximumWidth, blockWidth))), ceil(usedRect.height))
    }

    private func layoutTextBlocks() {
        guard !textBlocks.isEmpty else {
            blockDecorationView.update([])
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let inset = textContainerInset
        let items = textBlocks.compactMap { block -> (block: MessageTextBlock, frame: CGRect)? in
            block.frame(layoutManager: layoutManager, textContainer: textContainer)
                .map { (block, $0.offsetBy(dx: inset.left, dy: inset.top)) }
        }
        blockDecorationView.frame = CGRect(origin: .zero, size: CGSize(
            width: bounds.width,
            height: max(bounds.height, contentSize.height),
        ))
        blockDecorationView.update(items)
        sendSubviewToBack(blockDecorationView)
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
        guard gesture.state == .ended else { return }
        var handled = false
        activateEntity(at: gesture.location(in: self)) { [weak self] action in
            switch action {
            case .copy(let text):
                UIPasteboard.setPlainText(text)
                handled = true
            case .open(let url):
                self?.open(url)
                handled = true
            case .openUser(let userID):
                TelegramLinkRouter.shared.openUser(userID, from: self?.nearestViewController)
                handled = true
            case .botCommand(let command):
                if let chat = self?.nearestViewController as? ChatViewController {
                    chat.sendBotCommand(command)
                    handled = true
                }
            case .reveal:
                handled = true
            case .none:
                break
            }
        }
        if !handled, toggleQuoteBlock(at: gesture.location(in: self)) { handled = true }
        if !handled { onUnhandledTap?() }
    }

    /// InteractiveTextNode's tap on a folded or opened quote: it opens or folds again.
    private func toggleQuoteBlock(at point: CGPoint) -> Bool {
        layoutManager.ensureLayout(for: textContainer)
        let inset = textContainerInset
        guard let index = textBlocks.indices.first(where: { index in
            textBlocks[index].collapse != nil
                && textBlocks[index]
                .frame(layoutManager: layoutManager, textContainer: textContainer)?
                .offsetBy(dx: inset.left, dy: inset.top)
                .contains(point) == true
        }) else { return false }
        if let onToggleQuoteBlock {
            onToggleQuoteBlock(index)
        } else {
            if expandedQuoteBlocks.contains(index) {
                expandedQuoteBlocks.remove(index)
            } else {
                expandedQuoteBlocks.insert(index)
            }
            renderText()
        }
        return true
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

    private func open(_ url: URL?) {
        guard let url else { return }
        if onOpenRichURL?(url) == true { return }
        TelegramLinkRouter.shared.open(url, from: nearestViewController)
    }
}

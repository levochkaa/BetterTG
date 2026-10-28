// CustomTextField.swift

import TDLibKit
import UIKit
import UniformTypeIdentifiers

// MARK: - FormattedTextView

final class FormattedTextView: UITextView, UITextViewDelegate {
    // MARK: Live markdown

    /// Telegram's markdown marks, longest first, turned into formatting as soon as the closing mark is typed.
    private static let liveMarkdownMarks: [(mark: String, type: TextEntityType)] = [
        ("```", .textEntityTypePre),
        ("**", .textEntityTypeBold),
        ("__", .textEntityTypeItalic),
        ("~~", .textEntityTypeStrikethrough),
        ("||", .textEntityTypeSpoiler),
        ("`", .textEntityTypeCode),
    ]

    private static let liveMarkdownMarkCharacters: Set = ["*", "_", "~", "|", "`"]

    // MARK: Internal

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: min(max(naturalHeight, minimumHeight), maximumHeight))
    }

    /// The input's height limits: one line, and the point it starts to scroll (an expanded input sets both).
    var minimumHeight: CGFloat = 36 {
        didSet { heightLimitsChanged() }
    }

    var maximumHeight: CGFloat = 240 {
        didSet { heightLimitsChanged() }
    }

    /// Return typed into an empty input; true keeps the line break out (Swiftgram's empty multiline input).
    var onReturnInEmpty: (() -> Bool)?
    /// Backspace in an empty input.
    var onBackspaceWhileEmpty: (() -> Void)?
    var onEndEditing: (() -> Void)?

    var onTextChange: ((AttributedString) -> Void)?
    var onPasteImages: (([UIImage]) -> Void)?
    var onInteractionSettled: (() -> Void)?
    var onUserInteraction: (() -> Void)?
    /// The caret moved; the mention panel follows the "@" word at the caret.
    var onSelectionChange: (() -> Void)?

    private var isPresentingEditMenu = false
    /// The last edit typed one character a markdown mark ends with.
    private var checksLiveMarkdown = false
    /// Where a live markdown conversion left the caret: the next character typed there is plain.
    private var plainTypingLocation: Int?

    // MARK: Private

    private var placeholder: String
    private let placeholderLabel = UILabel()
    /// ChatTextInputPanelNode's contextPlaceholderNode: an inline bot's placeholder after the typed "@bot ", shown
    /// while the input still holds exactly that text.
    private var contextPlaceholder: (text: String, placeholder: String)?
    private let contextPlaceholderLabel = UILabel()
    private var lastWidth = CGFloat.zero
    private var isApplyingValue = false
    private lazy var emojiRenderer = ComposerCustomEmojiRenderer(textView: self)
    private var isApplyingUserText = false

    /// The text's height at the current width, unclamped.
    var naturalHeight: CGFloat {
        let width = bounds.width > 0 ? bounds.width : 220
        return sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    var permitsClientRestoration: Bool {
        markedTextRange == nil && !isApplyingUserText && !isPresentingEditMenu && !isTracking && !isDragging &&
            !isDecelerating
            && !(gestureRecognizers ?? []).contains { $0.state == .began || $0.state == .changed }
    }

    /// The client whose account owns this composer's chat; custom emoji stickers load through it.
    var customEmojiClient: TDLibClient? {
        get { emojiRenderer.client }
        set { emojiRenderer.client = newValue }
    }

    /// The keyboard's language for emoji keywords, with English after it as Telegram searches.
    private var keyboardLanguageCodes: [String]? {
        guard let language = textInputMode?.primaryLanguage, !["emoji", "dictation"].contains(language) else {
            return nil
        }
        return language.lowercased().hasPrefix("en") ? [language] : [language, "en-US"]
    }

    init(placeholder: String) {
        self.placeholder = placeholder
        let storage = NSTextStorage()
        let manager = ComposerEmojiLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: .zero)
        manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        delegate = self
        font = .body
        textColor = .label
        backgroundColor = .clear
        isEditable = true
        isSelectable = true
        isScrollEnabled = false
        textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textContainer.lineFragmentPadding = 0
        typingAttributes = ComposerText.typingAttributes(in: NSAttributedString(), at: 0)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = placeholder
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.font = .body
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -5),
        ])
        contextPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        contextPlaceholderLabel.numberOfLines = 1
        contextPlaceholderLabel.lineBreakMode = .byTruncatingTail
        contextPlaceholderLabel.isUserInteractionEnabled = false
        contextPlaceholderLabel.isHidden = true
        addSubview(contextPlaceholderLabel)
        NSLayoutConstraint.activate([
            contextPlaceholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            contextPlaceholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            contextPlaceholderLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -10),
        ])
        updatePlaceholder()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        let previousWidth = lastWidth
        super.layoutSubviews()
        emojiRenderer.layout()
        lastWidth = bounds.width
        if abs(previousWidth - bounds.width) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        emojiRenderer.layout()
    }

    override func deleteBackward() {
        let wasEmpty = text.isEmpty
        super.deleteBackward()
        if wasEmpty { onBackspaceWhileEmpty?() }
    }

    override func copy(_: Any?) {
        guard selectedRange.length > 0 else { return }
        UIPasteboard.setTelegramAttributedText(attributedText.attributedSubstring(from: selectedRange))
    }

    override func cut(_ sender: Any?) {
        guard isEditable, selectedRange.length > 0 else { return }
        copy(sender)
        insertTelegramText(NSAttributedString(string: ""))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onUserInteraction?()
        super.touchesBegan(touches, with: event)
    }

    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let selected = text(in: textRange), !selected.isEmpty else {
            return UIMenu(children: suggestedActions)
        }
        // ChatTextInputPanelNode's Format menu: Quote and Spoiler first, Code (a block) last.
        let format = UIMenu(title: L10n.telegram("TextFormat.Format"), children: [
            formattingAction(title: L10n.telegram("TextFormat.Quote"), type: .textEntityTypeBlockQuote),
            formattingAction(title: L10n.telegram("TextFormat.Spoiler"), type: .textEntityTypeSpoiler),
            formattingAction(title: L10n.telegram("TextFormat.Bold"), type: .textEntityTypeBold),
            formattingAction(title: L10n.telegram("TextFormat.Italic"), type: .textEntityTypeItalic),
            formattingAction(title: L10n.telegram("TextFormat.Monospace"), type: .textEntityTypeCode),
            UIAction(title: L10n.telegram("TextFormat.Link")) { [weak self] _ in self?.showLinkAlert() },
            formattingAction(title: L10n.telegram("TextFormat.Strikethrough"), type: .textEntityTypeStrikethrough),
            formattingAction(title: L10n.telegram("TextFormat.Underline"), type: .textEntityTypeUnderline),
            formattingAction(title: L10n.telegram("TextFormat.Code"), type: .textEntityTypePre),
        ])
        var actions = suggestedActions
        actions.insert(format, at: min(1, actions.count))
        return UIMenu(children: actions)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return UIPasteboard.general.hasImages || UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_: Any?) {
        if let data = UIPasteboard.general.data(forPasteboardType: TelegramEmojiPasteboardPayload.type),
           let payload = try? JSONDecoder().decode(TelegramEmojiPasteboardPayload.self, from: data)
        {
            // BetterTG's own companion payload is the only trusted source of custom emoji identity.
            let external =
                if let item = UIPasteboard.general.items.first,
                let raw = item[UTType.rtf.identifier],
                let rtf = (raw as? Data) ?? (raw as? String)?.data(using: .utf8),
                let formatted = try? NSAttributedString(data: rtf, documentAttributes: nil),
                formatted.string == payload.text {
                    formatted
                } else {
                    NSAttributedString(string: payload.text)
                }
            let value = NSMutableAttributedString(attributedString: ComposerText.importing(external))
            payload.apply(to: value)
            ComposerText.setCustomEmoji(TelegramCustomEmojiRun.extract(from: value), in: value)
            insertTelegramText(value)
            return
        }
        if let images = UIPasteboard.general.images, !images.isEmpty {
            receivePastedImages(images)
            return
        }
        let item = UIPasteboard.general.items.first
        let rawRTF = item?[UTType.rtf.identifier]
        if let data = (rawRTF as? String)?.data(using: .utf8) ?? rawRTF as? Data,
           let pasted = try? NSAttributedString(data: data, documentAttributes: nil)
        {
            receivePastedText(pasted)
        } else if let text = UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString {
            receivePastedText(NSAttributedString(string: text))
        }
    }

    func insertEmoji(_ emoji: String, customID: Int64? = nil) {
        let value = NSMutableAttributedString(attributedString: ComposerText
            .importing(NSAttributedString(string: emoji)))
        if let customID {
            ComposerText.setCustomEmoji(
                [TelegramCustomEmojiRun(id: customID, range: NSRange(location: 0, length: value.length))],
                in: value,
            )
        }
        insertTelegramText(value)
    }

    /// The emoji panel's backspace (EntityKeyboard's `deleteBackwards`), also while the panel holds the input
    /// instead of this view: removes the selection, or the character or emoji before the caret.
    func deleteBackwardFromPanel() {
        guard isEditable else { return }
        if markedTextRange != nil { unmarkText() }
        let string = text as NSString
        var range = selectedRange
        guard ComposerText.isValid(range, in: string) else { return }
        if range.length == 0 {
            guard range.location > 0 else { return }
            range = string.rangeOfComposedCharacterSequence(at: range.location - 1)
        }
        let updated = NSMutableAttributedString(attributedString: attributedText)
        updated.deleteCharacters(in: range)
        applyUserText(updated, selection: NSRange(location: range.location, length: 0))
    }

    func receivePastedImages(_ images: [UIImage]) { onPasteImages?(images) }

    func setAttributedText(_ value: AttributedString) {
        let value = ComposerText.uiKit(value)
        guard attributedText != value else { return }
        // The model echoes what the input method is composing. Replacing the text would end the marked
        // composition at every candidate; the semantic attributes settle once the composition ends.
        if markedTextRange != nil, value.string == text { return }
        isApplyingValue = true
        let selection = selectedRange
        attributedText = value.length == 0
            ? NSAttributedString(string: "", attributes: defaultAttributes())
            : value
        isApplyingValue = false
        selectedRange = NSRange(
            location: min(selection.location, value.length),
            length: min(selection.length, max(0, value.length - selection.location)),
        )
        typingAttributes = ComposerText.typingAttributes(in: attributedText, at: selectedRange.location)
        emojiRenderer.update()
        updatePlaceholder()
        invalidateIntrinsicContentSize()
    }

    func setPlaceholder(_ value: String) {
        guard placeholder != value else { return }
        placeholder = value
        updatePlaceholder()
    }

    /// The inline bot placeholder for the input `typedText`, or nil to remove it.
    func setContextPlaceholder(_ value: String?, after typedText: String) {
        let updated = value.map { (text: typedText, placeholder: $0) }
        guard updated?.text != contextPlaceholder?.text || updated?.placeholder != contextPlaceholder?.placeholder
        else { return }
        contextPlaceholder = updated
        updatePlaceholder()
    }

    func moveCaretToEnd() {
        selectedRange = NSRange(location: attributedText.length, length: 0)
        typingAttributes = ComposerText.typingAttributes(in: attributedText, at: selectedRange.location)
    }

    /// ChatContextQuery's mention query: the word after an "@" at the caret, where the "@" opens the text or follows a
    /// space, a newline, a period or a comma. The range covers the "@" and the word.
    func mentionQueryRange() -> (range: NSRange, query: String)? {
        guard markedTextRange == nil, selectedRange.length == 0 else { return nil }
        let string = text as NSString
        let caret = min(selectedRange.location, string.length)
        var index = caret - 1
        while index >= 0 {
            switch string.character(at: index) {
            case 0x0A,
                 0x20,
                 0x23,
                 0x2F,
                 0x3A:
                // A space or a newline ends the word; "#", "/" and ":" start other queries.
                return nil
            case 0x40:
                if index > 0, ![0x20, 0x0A, 0x2E, 0x2C].contains(string.character(at: index - 1)) { return nil }
                let range = NSRange(location: index, length: caret - index)
                return (range, string.substring(with: NSRange(location: index + 1, length: caret - index - 1)))
            default:
                index -= 1
            }
        }
        return nil
    }

    /// Replaces part of the text as the user's edit, such as a picked mention, with the caret after it.
    func replaceText(in range: NSRange, with value: NSAttributedString) {
        guard isEditable, markedTextRange == nil, ComposerText.isValid(range, in: text as NSString) else { return }
        let updated = NSMutableAttributedString(attributedString: attributedText)
        updated.replaceCharacters(in: range, with: value)
        applyUserText(updated, selection: NSRange(location: range.location + value.length, length: 0))
    }

    /// ChatContextQuery's other queries at the caret, with the range a pick replaces: a lone emoji as the whole text,
    /// the word after "#" (the range leaves the "#" out) or the word after ":" (the range takes the ":" in). The
    /// "#" or ":" opens the text or follows a space, a newline, a period or a comma, as the "@" of a mention does.
    func contextQuery() -> (query: ChatInputContextQuery, range: NSRange)? {
        guard markedTextRange == nil, selectedRange.length == 0 else { return nil }
        let string = text as NSString
        guard string.length > 0 else { return nil }
        let full = string as String
        let trimmed = full.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        if full.count < 3, trimmed.isLoneEmoji,
           attributedText.attribute(.init(TelegramCustomEmojiAttribute.name), at: 0, effectiveRange: nil) == nil
        {
            return (
                .stickers(emoji: trimmed.withoutSkinTone),
                NSRange(location: 0, length: (trimmed as NSString).length),
            )
        }
        let caret = min(selectedRange.location, string.length)
        var index = caret - 1
        while index >= 0 {
            let character = string.character(at: index)
            switch character {
            case 0x0A,
                 0x20,
                 0x2F,
                 0x40:
                // A space or a newline ends the word; "/" and "@" start a command or a mention.
                return nil
            case 0x23,
                 0x3A:
                if index > 0, ![0x20, 0x0A, 0x2E, 0x2C].contains(string.character(at: index - 1)) { return nil }
                let word = NSRange(location: index + 1, length: caret - index - 1)
                let query = string.substring(with: word)
                if character == 0x23 { return (.hashtag(query), word) }
                guard !query.isEmpty, let languageCodes = keyboardLanguageCodes else { return nil }
                return (
                    .emojiSearch(query, languageCodes: languageCodes),
                    NSRange(location: index, length: caret - index),
                )
            default:
                index -= 1
            }
        }
        return nil
    }

    func textViewDidChange(_: UITextView) {
        if checksLiveMarkdown, markedTextRange == nil, !isApplyingValue {
            checksLiveMarkdown = false
            if applyLiveMarkdown() { return }
        }
        if markedTextRange == nil {
            ComposerText.refresh(textStorage)
            typingAttributes = ComposerText.typingAttributes(in: attributedText, at: selectedRange.location)
            if plainTypingLocation == selectedRange.location {
                typingAttributes = ComposerText.typingAttributes(in: NSAttributedString(), at: 0)
            }
        }
        updatePlaceholder()
        invalidateIntrinsicContentSize()
        isScrollEnabled = naturalHeight > maximumHeight
        guard !isApplyingValue else { return }
        emojiRenderer.update()
        onUserInteraction?()
        onTextChange?(ComposerText.value(attributedText))
        onInteractionSettled?()
    }

    func textViewDidEndEditing(_: UITextView) {
        onEndEditing?()
    }

    func textViewDidChangeSelection(_: UITextView) {
        if let plainTypingLocation, selectedRange != NSRange(location: plainTypingLocation, length: 0) {
            self.plainTypingLocation = nil
        }
        if markedTextRange == nil {
            typingAttributes = ComposerText.typingAttributes(in: attributedText, at: selectedRange.location)
        }
        onInteractionSettled?()
        onSelectionChange?()
    }

    func textView(_: UITextView, willPresentEditMenuWith _: any UIEditMenuInteractionAnimating) {
        isPresentingEditMenu = true
    }

    func textView(_: UITextView, willDismissEditMenuWith animator: any UIEditMenuInteractionAnimating) {
        animator.addCompletion { [weak self] in
            self?.isPresentingEditMenu = false
            self?.onInteractionSettled?()
        }
    }

    func textView(
        _: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText replacement: String,
    ) -> Bool {
        guard ComposerText.isValid(range, in: text as NSString) else { return false }
        if replacement == "\n", text.isEmpty, markedTextRange == nil, onReturnInEmpty?() == true { return false }
        typingAttributes = ComposerText.typingAttributes(in: attributedText, at: range.location)
        if plainTypingLocation == range.location, range.length == 0 {
            typingAttributes = ComposerText.typingAttributes(in: NSAttributedString(), at: 0)
        }
        checksLiveMarkdown = (replacement as NSString).length == 1 && Self.liveMarkdownMarkCharacters
            .contains(replacement)
        // A custom emoji is one atomic glyph: a partial edit replaces the whole emoji.
        var atomicRange = range
        for emoji in TelegramCustomEmojiRun.extract(from: textStorage) where range.length > 0 && NSIntersectionRange(
            range,
            emoji.range,
        ).length > 0 {
            atomicRange = NSUnionRange(atomicRange, emoji.range)
        }
        guard atomicRange == range else {
            selectedRange = atomicRange
            insertTelegramText(NSAttributedString(string: replacement))
            return false
        }
        return true
    }

    func receivePastedText(_ text: NSAttributedString) {
        let wasApplyingUserText = isApplyingUserText
        isApplyingUserText = true
        defer {
            isApplyingUserText = wasApplyingUserText
            onInteractionSettled?()
        }
        if markedTextRange != nil { unmarkText() }
        guard ComposerText.isValid(selectedRange, in: self.text as NSString) else { return }
        let pasted = ComposerText.importing(text)
        let updated = NSMutableAttributedString(attributedString: attributedText)
        updated.replaceCharacters(in: selectedRange, with: pasted)
        applyUserText(updated, selection: NSRange(location: selectedRange.location + pasted.length, length: 0))
    }

    func toggleFormatting(_ type: TextEntityType) {
        guard markedTextRange == nil else { return }
        let updated = NSMutableAttributedString(attributedString: attributedText)
        ComposerText.toggle(type, in: updated, range: selectedRange)
        applyUserText(updated, selection: selectedRange)
    }

    private func heightLimitsChanged() {
        invalidateIntrinsicContentSize()
        isScrollEnabled = naturalHeight > maximumHeight
    }

    private func insertTelegramText(_ value: NSAttributedString) {
        guard isEditable else { return }
        if markedTextRange != nil { unmarkText() }
        let range = selectedRange
        guard ComposerText.isValid(range, in: text as NSString) else { return }
        let updated = NSMutableAttributedString(attributedString: attributedText)
        updated.replaceCharacters(in: range, with: value)
        applyUserText(updated, selection: NSRange(location: range.location + value.length, length: 0))
    }

    /// The text before the caret ends with a closing mark whose opening comes earlier: both marks go, the text
    /// between them takes the formatting, and the next character typed is plain. One undo step brings the marks
    /// back. A mark inside a longer run of its character (`***`, a backtick of ```) is not one; inline formatting
    /// stays on one line and doesn't start or end with a space.
    private func applyLiveMarkdown() -> Bool {
        guard selectedRange.length == 0 else { return false }
        let caret = selectedRange.location
        let string = text as NSString
        for (mark, type) in Self.liveMarkdownMarks {
            let length = (mark as NSString).length
            guard caret >= length * 2 + 1,
                  string.substring(with: NSRange(location: caret - length, length: length)) == mark
            else { continue }
            let markCharacter = string.character(at: caret - 1)
            if string.character(at: caret - length - 1) == markCharacter { continue }
            let open = string.range(
                of: mark,
                options: .backwards,
                range: NSRange(location: 0, length: caret - length - 1),
            )
            guard open.location != NSNotFound else { continue }
            if open.location > 0, string.character(at: open.location - 1) == markCharacter { continue }
            if string.character(at: open.location + length) == markCharacter { continue }
            var content = NSRange(location: open.location + length, length: caret - length - open.location - length)
            let value = string.substring(with: content)
            if type == .textEntityTypePre {
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            } else {
                guard !value.contains("\n"), value.trimmingCharacters(in: .whitespaces) == value else { continue }
            }
            let updated = NSMutableAttributedString(attributedString: attributedText)
            updated.deleteCharacters(in: NSRange(location: caret - length, length: length))
            updated.deleteCharacters(in: NSRange(location: open.location, length: length))
            content.location = open.location
            ComposerText.toggle(type, in: updated, range: content)
            applyUserText(updated, selection: NSRange(location: content.upperBound, length: 0))
            plainTypingLocation = content.upperBound
            typingAttributes = ComposerText.typingAttributes(in: NSAttributedString(), at: 0)
            return true
        }
        return false
    }

    private func applyUserText(_ value: NSAttributedString, selection: NSRange) {
        guard !attributedText.isEqual(to: value) else { return }
        let wasApplyingUserText = isApplyingUserText
        isApplyingUserText = true
        defer {
            isApplyingUserText = wasApplyingUserText
            onInteractionSettled?()
        }
        let previous = NSAttributedString(attributedString: attributedText!)
        let previousSelection = selectedRange
        undoManager?.registerUndo(withTarget: self) { target in
            target.applyUserText(previous, selection: previousSelection)
        }
        textStorage.setAttributedString(value)
        selectedRange = selection
        textViewDidChange(self)
    }

    private func formattingAction(title: String, type: TextEntityType) -> UIAction {
        UIAction(title: title) { [weak self] _ in
            self?.toggleFormatting(type)
        }
    }

    private func showLinkAlert() {
        let original = NSAttributedString(attributedString: attributedText!)
        let range = selectedRange
        let alert = UIAlertController(
            title: L10n.telegram("TextFormat.AddLinkTitle"),
            message: nil,
            preferredStyle: .alert,
        )
        alert.addTextField { $0.placeholder = L10n.telegram("TextFormat.AddLinkPlaceholder") }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  attributedText.isEqual(to: original),
                  let text = alert?.textFields?.first?.text
            else { return }
            let updated = NSMutableAttributedString(attributedString: original)
            ComposerText.setLink(text, in: updated, range: range)
            applyUserText(updated, selection: range)
        })
        nearestViewController?.present(alert, animated: true)
    }

    private func updatePlaceholder() {
        placeholderLabel.text = placeholder
        placeholderLabel.isHidden = !text.isEmpty
        updateContextPlaceholder()
    }

    /// Telegram lays the typed "@bot" out invisibly in front of the placeholder, so the placeholder starts where the
    /// text ends, on one line truncated at the end. Typing anything else hides it at once.
    private func updateContextPlaceholder() {
        guard let contextPlaceholder, markedTextRange == nil, text == contextPlaceholder.text,
              let typed = attributedText, typed.length > 0
        else {
            contextPlaceholderLabel.isHidden = true
            contextPlaceholderLabel.attributedText = nil
            return
        }
        let value = NSMutableAttributedString(attributedString: typed)
        let typedRange = NSRange(location: 0, length: value.length)
        for key: NSAttributedString.Key in [.backgroundColor, .underlineStyle, .strikethroughStyle, .link] {
            value.removeAttribute(key, range: typedRange)
        }
        value.addAttribute(.foregroundColor, value: UIColor.clear, range: typedRange)
        let placeholderFont = typed.attribute(.font, at: typed.length - 1, effectiveRange: nil) as? UIFont
            ?? font ?? .body
        value.append(NSAttributedString(
            string: contextPlaceholder.placeholder,
            attributes: [.font: placeholderFont, .foregroundColor: UIColor.placeholderText],
        ))
        contextPlaceholderLabel.attributedText = value
        contextPlaceholderLabel.isHidden = false
    }
}

private extension String {
    /// Telegram's `isSingleEmoji`.
    var isLoneEmoji: Bool {
        count == 1 && unicodeScalars.contains {
            $0.properties.isEmojiPresentation || $0.value == 0xFE0F || $0.value == 0x200D
        }
    }

    /// Telegram's `basicEmoji`: the emoji without its skin tone.
    var withoutSkinTone: String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: unicodeScalars.filter { !(0x1F3FB...0x1F3FF).contains($0.value) })
        return String(scalars)
    }
}

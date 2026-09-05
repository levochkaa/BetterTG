// CustomTextField.swift

import TDLibKit
import UIKit
import UniformTypeIdentifiers

// MARK: - FormattedTextView

final class FormattedTextView: UITextView, UITextViewDelegate {
    // MARK: Internal

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : 220
        let fitting = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: min(max(fitting.height, 36), 240))
    }

    var onTextChange: ((AttributedString) -> Void)?
    var onPasteImages: (([UIImage]) -> Void)?
    var onInteractionSettled: (() -> Void)?
    var onUserInteraction: (() -> Void)?

    private var isPresentingEditMenu = false

    // MARK: Private

    private var placeholder: String
    private let placeholderLabel = UILabel()
    private var lastWidth = CGFloat.zero
    private var isApplyingValue = false
    private lazy var emojiRenderer = ComposerCustomEmojiRenderer(textView: self)

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

    override func copy(_: Any?) {
        guard selectedRange.length > 0 else { return }
        UIPasteboard.setTelegramAttributedText(attributedText.attributedSubstring(from: selectedRange))
    }

    override func cut(_ sender: Any?) {
        guard isEditable, selectedRange.length > 0 else { return }
        copy(sender)
        insertTelegramText(NSAttributedString(string: ""))
    }

    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let selected = text(in: textRange), !selected.isEmpty else {
            return UIMenu(children: suggestedActions)
        }
        let format = UIMenu(title: L10n.telegram("TextFormat.Format"), children: [
            formattingAction(title: L10n.telegram("TextFormat.Bold"), type: .textEntityTypeBold),
            formattingAction(title: L10n.telegram("TextFormat.Italic"), type: .textEntityTypeItalic),
            formattingAction(title: L10n.telegram("TextFormat.Monospace"), type: .textEntityTypeCode),
            UIAction(title: L10n.telegram("TextFormat.Link")) { [weak self] _ in self?.showLinkAlert() },
            formattingAction(title: L10n.telegram("TextFormat.Strikethrough"), type: .textEntityTypeStrikethrough),
            formattingAction(title: L10n.telegram("TextFormat.Underline"), type: .textEntityTypeUnderline),
            formattingAction(title: L10n.telegram("TextFormat.Spoiler"), type: .textEntityTypeSpoiler),
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

    override func paste(_ sender: Any?) {
        if let data = UIPasteboard.general.data(forPasteboardType: TelegramEmojiPasteboardPayload.type),
           let payload = try? JSONDecoder().decode(TelegramEmojiPasteboardPayload.self, from: data)
        {
            let value =
                if let item = UIPasteboard.general.items.first,
                let raw = item[UTType.rtf.identifier],
                let rtf = (raw as? Data) ?? (raw as? String)?.data(using: .utf8),
                let formatted = try? NSAttributedString(data: rtf, documentAttributes: nil) {
                    NSMutableAttributedString(attributedString: formatted)
                } else {
                    NSMutableAttributedString(string: payload.text, attributes: defaultAttributes())
                }
            payload.apply(to: value)
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
        let value = NSMutableAttributedString(string: emoji, attributes: defaultAttributes())
        if let customID { value.addAttribute(
            .telegramCustomEmoji,
            value: NSNumber(value: customID),
            range: NSRange(location: 0, length: value.length),
        ) }
        insertTelegramText(value)
    }

    func setAttributedText(_ value: AttributedString) {
        let value = value.telegramNSAttributedString
        guard attributedText != value else { return }
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
        emojiRenderer.update()
        updatePlaceholder()
        invalidateIntrinsicContentSize()
    }

    func setPlaceholder(_ value: String) {
        guard placeholder != value else { return }
        placeholder = value
        updatePlaceholder()
    }

    func textViewDidChange(_: UITextView) {
        if markedTextRange == nil {
            ComposerText.refresh(textStorage)
            typingAttributes = ComposerText.typingAttributes(in: attributedText, at: selectedRange.location)
        }
        updatePlaceholder()
        invalidateIntrinsicContentSize()
        isScrollEnabled = intrinsicContentSize.height >= 240
        guard !isApplyingValue else { return }
        emojiRenderer.update()
        onTextChange?(AttributedString(telegramText: attributedText))
    }

    func textView(
        _: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText replacement: String,
    ) -> Bool {
        typingAttributes = defaultAttributes()
        var atomicRange = range
        for emoji in TelegramCustomEmojiRun.extract(from: textStorage) {
            if range.length > 0, NSIntersectionRange(range, emoji.range).length > 0 {
                atomicRange = NSUnionRange(atomicRange, emoji.range)
            }
        }
        if atomicRange != range {
            selectedRange = atomicRange
            insertTelegramText(NSAttributedString(string: replacement, attributes: defaultAttributes()))
            return false
        }
        guard isPastingText else { return true }
        defer { isPastingText = false }
        guard let item = UIPasteboard.general.items.first,
              let rawRTF = item[UTType.rtf.identifier],
              let data = (rawRTF as? String)?.data(using: .utf8)
              ?? rawRTF as? Data,
              let pasted = try? NSAttributedString(data: data, documentAttributes: nil)
        else { return true }

        let updated = NSMutableAttributedString(attributedString: textView.attributedText)
        updated.replaceCharacters(in: range, with: pasted)
        textView.attributedText = updated
        textViewDidChange(textView)
        return false
    }

    private func insertTelegramText(_ value: NSAttributedString) {
        guard isEditable else { return }
        let range = selectedRange
        textStorage.replaceCharacters(in: range, with: value)
        selectedRange = NSRange(location: range.location + value.length, length: 0)
        typingAttributes = defaultAttributes()
        textViewDidChange(self)
    }

    private func formattingAction(title: String, key: NSAttributedString.Key, value: Any) -> UIAction {
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
    }
}

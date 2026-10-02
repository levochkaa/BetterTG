// CustomTextField.swift

import TDLibKitDynamic
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
    private var isApplyingUserText = false

    var permitsClientRestoration: Bool {
        markedTextRange == nil && !isApplyingUserText && !isPresentingEditMenu && !isTracking && !isDragging &&
            !isDecelerating
            && !(gestureRecognizers ?? []).contains { $0.state == .began || $0.state == .changed }
    }

    init(placeholder: String) {
        self.placeholder = placeholder
        super.init(frame: .zero, textContainer: nil)
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
        lastWidth = bounds.width
        if abs(previousWidth - bounds.width) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onUserInteraction?()
        super.touchesBegan(touches, with: event)
    }

    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let selected = text(in: textRange), !selected.isEmpty else {
            return UIMenu(children: suggestedActions)
        }
        let format = UIMenu(title: "Format", children: [
            formattingAction(title: "Bold", type: .textEntityTypeBold),
            formattingAction(title: "Italic", type: .textEntityTypeItalic),
            formattingAction(title: "Monospace", type: .textEntityTypeCode),
            UIAction(title: "Link") { [weak self] _ in self?.showLinkAlert() },
            formattingAction(title: "Strikethrough", type: .textEntityTypeStrikethrough),
            formattingAction(title: "Underline", type: .textEntityTypeUnderline),
            formattingAction(title: "Spoiler", type: .textEntityTypeSpoiler),
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

    func receivePastedImages(_ images: [UIImage]) { onPasteImages?(Array(images.prefix(10))) }

    func setAttributedText(_ value: AttributedString) {
        let value = ComposerText.uiKit(value)
        guard attributedText != value else { return }
        isApplyingValue = true
        attributedText = value.length == 0
            ? NSAttributedString(string: "", attributes: defaultAttributes())
            : value
        isApplyingValue = false
        typingAttributes = ComposerText.typingAttributes(in: attributedText, at: selectedRange.location)
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
        onUserInteraction?()
        onTextChange?(ComposerText.value(attributedText))
        onInteractionSettled?()
    }

    func textViewDidChangeSelection(_: UITextView) {
        if markedTextRange == nil {
            typingAttributes = ComposerText.typingAttributes(in: attributedText, at: selectedRange.location)
        }
        onInteractionSettled?()
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
        replacementText _: String,
    ) -> Bool {
        guard ComposerText.isValid(range, in: text as NSString) else { return false }
        typingAttributes = ComposerText.typingAttributes(in: attributedText, at: range.location)
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
        let alert = UIAlertController(title: "Enter URL", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "https://example.com/" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak alert] _ in
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

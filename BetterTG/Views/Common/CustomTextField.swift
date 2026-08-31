// CustomTextField.swift

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
    var onPasteImages: (([SelectedImage]) -> Void)?

    // MARK: Private

    private var placeholder: String
    private let placeholderLabel = UILabel()
    private var lastWidth = CGFloat.zero
    private var isPastingText = false
    private var isApplyingValue = false

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
        typingAttributes = defaultAttributes()
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

    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let selected = text(in: textRange), !selected.isEmpty else {
            return UIMenu(children: suggestedActions)
        }
        let format = UIMenu(title: "Format", children: [
            formattingAction(title: "Bold", key: .font, value: UIFont.bold),
            formattingAction(title: "Italic", key: .font, value: UIFont.italic),
            formattingAction(title: "Monospace", key: .font, value: UIFont.monospaced),
            UIAction(title: "Link") { [weak self] _ in self?.showLinkAlert() },
            formattingAction(title: "Strikethrough", key: .strikethroughStyle, value: 1),
            formattingAction(title: "Underline", key: .underlineStyle, value: 1),
            formattingAction(title: "Spoiler", key: .backgroundColor, value: UIColor.systemGray),
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
        if let images = UIPasteboard.general.images, !images.isEmpty {
            let callback = onPasteImages
            Task {
                let selected = await Task.detached(priority: .userInitiated) {
                    images.compactMap { writeImage($0) }
                }.value
                callback?(selected)
            }
            return
        }
        isPastingText = true
        super.paste(sender)
    }

    func setAttributedText(_ value: AttributedString) {
        let value = NSAttributedString(value)
        guard attributedText != value else { return }
        isApplyingValue = true
        attributedText = value.length == 0
            ? NSAttributedString(string: "", attributes: defaultAttributes())
            : value
        isApplyingValue = false
        updatePlaceholder()
        invalidateIntrinsicContentSize()
    }

    func setPlaceholder(_ value: String) {
        guard placeholder != value else { return }
        placeholder = value
        updatePlaceholder()
    }

    func textViewDidChange(_: UITextView) {
        updatePlaceholder()
        invalidateIntrinsicContentSize()
        isScrollEnabled = intrinsicContentSize.height >= 240
        guard !isApplyingValue else { return }
        onTextChange?(AttributedString(attributedText))
    }

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText _: String,
    ) -> Bool {
        typingAttributes = defaultAttributes()
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

    private func formattingAction(title: String, key: NSAttributedString.Key, value: Any) -> UIAction {
        UIAction(title: title) { [weak self] _ in
            guard let self else { return }
            textStorage.addAttribute(key, value: value, range: selectedRange)
            textViewDidChange(self)
        }
    }

    private func showLinkAlert() {
        let alert = UIAlertController(title: "Enter URL", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "https://example.com/" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let text = alert?.textFields?.first?.text,
                  let url = URL(string: text)
            else { return }
            textStorage.addAttribute(.link, value: url, range: selectedRange)
            textViewDidChange(self)
        })
        nearestViewController?.present(alert, animated: true)
    }

    private func updatePlaceholder() {
        placeholderLabel.text = placeholder
        placeholderLabel.isHidden = !text.isEmpty
    }
}

// MessageTextView.swift

import TDLibKit
import UIKit

final class MessageTextContentView: UITextView, UITextViewDelegate {
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        backgroundColor = .clear
        isScrollEnabled = false
        isEditable = false
        isSelectable = true
        textContainerInset = .zero
        self.textContainer.lineFragmentPadding = 0
        delegate = self
        linkTextAttributes = [.foregroundColor: UIColor.systemBlue]
        adjustsFontForContentSizeCategory = true
        setContentCompressionResistancePriority(.required, for: .vertical)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleCodeTap(_:))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let targetWidth = bounds.width > 0 ? bounds.width : Utils.maxMessageContentWidth
        return sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
    }

    override func layoutSubviews() {
        let oldWidth = lastLayoutWidth
        super.layoutSubviews()
        lastLayoutWidth = bounds.width
        if abs(oldWidth - bounds.width) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }

    private var formattedText: FormattedText?
    private var lastLayoutWidth = CGFloat.zero

    func configure(formattedText: FormattedText) {
        self.formattedText = formattedText
        attributedText = NSAttributedString(getAttributedString(from: formattedText))
        invalidateIntrinsicContentSize()
        accessibilityLabel = formattedText.text
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        textView.selectedTextRange = nil
    }

    @objc private func handleCodeTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let formattedText else { return }
        let point = gesture.location(in: self)
        var fraction = CGFloat.zero
        let index = layoutManager.characterIndex(
            for: CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top),
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction,
        )
        for entity in formattedText.entities {
            let range = NSRange(location: entity.offset, length: entity.length)
            guard range.contains(index) else { continue }
            switch entity.type {
            case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
                let stringRange = stringRange(
                    for: formattedText.text,
                    start: entity.offset,
                    length: entity.length,
                )
                UIPasteboard.setPlainText(String(formattedText.text[stringRange]))
            default:
                break
            }
        }
    }
}

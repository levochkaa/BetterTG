// MessageTextView.swift

import TDLibKit
import UIKit

final class MessageTextContentView: UITextView, UITextViewDelegate {
    override var canBecomeFirstResponder: Bool { false }

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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        guard attributedText.length > 0 else { return .zero }
        let measurement = measureText(maximumWidth: maximumLayoutWidth)
        let statusWidth = ceil(statusLabel.bounds.width) + 9
        let statusFitsTrailingLine = measurement.trailingLineWidth + statusWidth <= maximumLayoutWidth
        let width = min(
            maximumLayoutWidth,
            ceil(max(measurement.width, statusFitsTrailingLine ? measurement.trailingLineWidth + statusWidth : statusWidth)),
        )
        let height = ceil(measurement.height + (statusFitsTrailingLine ? 0 : statusLabel.bounds.height))
        return CGSize(width: width, height: height)
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
        lastLayoutWidth = bounds.width
        if abs(oldWidth - bounds.width) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }

    private var formattedText: FormattedText?
    private var lastLayoutWidth = CGFloat.zero
    private var maximumLayoutWidth = Utils.maxMessageContentWidth
    private let statusLabel = UILabel()

    func configure(
        formattedText: FormattedText,
        statusText: String,
        statusColor: UIColor,
        maximumWidth: CGFloat = Utils.maxMessageContentWidth,
    ) {
        self.formattedText = formattedText
        maximumLayoutWidth = maximumWidth
        statusLabel.text = statusText
        statusLabel.textColor = statusColor
        statusLabel.sizeToFit()
        attributedText = NSAttributedString(getAttributedString(from: formattedText))
        bringSubviewToFront(statusLabel)
        invalidateIntrinsicContentSize()
        accessibilityLabel = formattedText.text
    }

    func setMaximumLayoutWidth(_ width: CGFloat) {
        let resolvedWidth = max(1, width)
        guard abs(maximumLayoutWidth - resolvedWidth) > 0.5 else { return }
        maximumLayoutWidth = resolvedWidth
        invalidateIntrinsicContentSize()
    }

    private func measureText(maximumWidth: CGFloat) -> (width: CGFloat, height: CGFloat, trailingLineWidth: CGFloat) {
        let storage = NSTextStorage(attributedString: attributedText)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: maximumWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        let usedRect = manager.usedRect(for: container)
        var trailingLineWidth = CGFloat.zero
        manager.enumerateLineFragments(
            forGlyphRange: manager.glyphRange(for: container),
        ) { _, lineUsedRect, _, _, _ in
            trailingLineWidth = lineUsedRect.maxX
        }
        return (ceil(usedRect.width), ceil(usedRect.height), ceil(trailingLineWidth))
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        textView.selectedTextRange = nil
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
                break
            }
            return
        }
    }

    private func rawText(for entity: TextEntity, in text: String) -> String {
        let range = stringRange(for: text, start: entity.offset, length: entity.length)
        return String(text[range])
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        UIApplication.shared.open(url)
    }
}

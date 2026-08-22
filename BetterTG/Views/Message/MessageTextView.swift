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
        isSelectable = true
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
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Keep links tappable, but let the cell's custom context-menu gesture own long presses.
        gestureRecognizers?
            .compactMap { $0 as? UILongPressGestureRecognizer }
            .forEach { $0.isEnabled = false }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleCodeTap(_:))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        guard attributedText.length > 0 else { return .zero }
        let measured = attributedText.boundingRect(
            with: CGSize(width: maximumLayoutWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil,
        )
        let width = min(maximumLayoutWidth, ceil(measured.width))
        let fitted = sizeThatFits(CGSize(width: max(width, 1), height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
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
    private var maximumLayoutWidth = Utils.maxMessageContentWidth
    private let statusLabel = UILabel()

    private static let transparentPixel: UIImage = UIGraphicsImageRenderer(
        size: CGSize(width: 1, height: 1),
    ).image { _ in }

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
        let result = NSMutableAttributedString(attributedString: NSAttributedString(getAttributedString(from: formattedText)))
        let statusSpacer = NSTextAttachment()
        statusSpacer.image = Self.transparentPixel
        statusSpacer.bounds = CGRect(
            x: 0,
            y: -2,
            width: ceil(statusLabel.bounds.width) + 9,
            height: statusLabel.font.lineHeight,
        )
        result.append(NSAttributedString(attachment: statusSpacer))
        attributedText = result
        bringSubviewToFront(statusLabel)
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

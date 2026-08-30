// MessageTextView.swift

import TDLibKitDynamic
import UIKit

final class MessageTextContentView: UITextView, UITextViewDelegate {
    private struct CustomEmojiRequest {
        let identifier: TdInt64
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

    private var formattedText: FormattedText?
    private var lastLayoutWidth = CGFloat.zero
    private var maximumLayoutWidth = Utils.maxMessageContentWidth
    private let statusLabel = UILabel()

    private var customEmojiPlacements = [CustomEmojiPlacement]()
    private var customEmojiTask: Task<Void, Never>?
    private var customEmojiGeneration = 0
    private var customEmojiPlaybackVisible = false

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
        lastLayoutWidth = bounds.width
        if abs(oldWidth - bounds.width) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }

    func configure(
        formattedText: FormattedText,
        statusText: String,
        statusColor: UIColor,
        maximumWidth: CGFloat = Utils.maxMessageContentWidth,
    ) {
        clearCustomEmojiViews()
        self.formattedText = formattedText
        maximumLayoutWidth = maximumWidth
        statusLabel.text = statusText
        statusLabel.textColor = statusColor
        statusLabel.sizeToFit()
        let result = NSMutableAttributedString(
            attributedString: NSAttributedString(getAttributedString(from: formattedText)),
        )
        result.append(statusSpacer(width: ceil(statusLabel.bounds.width) + 9))
        attributedText = result
        loadCustomEmoji(from: formattedText)
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

    func prepareForReuse() {
        clearCustomEmojiViews()
        customEmojiPlaybackVisible = false
        formattedText = nil
        attributedText = NSAttributedString()
        statusLabel.text = nil
    }

    func setCustomEmojiPlaybackVisible(_ isVisible: Bool) {
        customEmojiPlaybackVisible = isVisible
        for placement in customEmojiPlacements {
            placement.view.setPlaybackVisible(isVisible)
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        textView.selectedTextRange = nil
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

    private func loadCustomEmoji(from formattedText: FormattedText) {
        let requests = formattedText.entities.compactMap { entity -> CustomEmojiRequest? in
            guard case .textEntityTypeCustomEmoji(let customEmoji) = entity.type else { return nil }
            return CustomEmojiRequest(
                identifier: customEmoji.customEmojiId,
                range: NSRange(location: entity.offset, length: entity.length),
            )
        }
        guard !requests.isEmpty else { return }

        let generation = customEmojiGeneration
        customEmojiTask = Task { [weak self] in
            let stickers = await CustomEmojiStickerRepository.shared.stickers(
                for: requests.map(\.identifier),
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.customEmojiGeneration == generation else { return }
                self.installCustomEmoji(requests: requests, stickers: stickers)
            }
        }
    }

    private func installCustomEmoji(
        requests: [CustomEmojiRequest],
        stickers: [TdInt64: Sticker],
    ) {
        for request in requests {
            guard let sticker = stickers[request.identifier],
                  NSMaxRange(request.range) <= textStorage.length
            else { continue }
            let emojiView = CustomEmojiInlineView()
            emojiView.isUserInteractionEnabled = false
            emojiView.configure(sticker: sticker)
            emojiView.onFirstFrameReady = { [weak self, weak emojiView] in
                guard let self, let emojiView,
                      customEmojiPlacements.contains(where: { $0.view === emojiView }),
                      NSMaxRange(request.range) <= textStorage.length
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
            placement.view.isHidden = false
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

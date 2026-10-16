// CustomEmojiTextView.swift

import TDLibKit
import UIKit

// MARK: - CustomEmojiTextView

/// A text view that draws Telegram's custom emoji over their fallback glyphs, as the composer does
/// (ComposerCustomEmojiRenderer), for text that isn't a message's: a poll's question, options and explanation, and
/// the poll creator's fields. With scrolling off it sizes to its text at its width, like a multi-line label.
/// The poll creator's editable field subclasses it.
// swiftformat:disable:next preferFinalClasses
class CustomEmojiTextView: UITextView {
    // MARK: Private

    private lazy var emojiRenderer = ComposerCustomEmojiRenderer(textView: self)

    // MARK: Internal

    /// The client whose account owns the custom emoji; without one they stay plain glyphs.
    var customEmojiClient: TDLibClient? {
        get { emojiRenderer.client }
        set { emojiRenderer.client = newValue }
    }

    init() {
        let storage = NSTextStorage()
        let manager = ComposerEmojiLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        backgroundColor = .clear
        isScrollEnabled = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emojiRenderer.layout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        emojiRenderer.layout()
    }

    /// Places the custom emoji of the current text, after the text changed.
    final func updateCustomEmoji() {
        emojiRenderer.update()
    }

    /// Read-only text, which passes touches to the view behind it.
    final func configureForDisplay() {
        isEditable = false
        isSelectable = false
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    /// Shows formatted text in `font` and `color`, keeping the bold, italic and monospaced runs, with its custom emoji.
    final func setFormattedText(_ text: FormattedText, font: UIFont, color: UIColor = .label) {
        let value = NSMutableAttributedString(
            attributedString: getAttributedString(from: text, color).telegramNSAttributedString,
        )
        let range = NSRange(location: 0, length: value.length)
        value.enumerateAttribute(.font, in: range) { attribute, runRange, _ in
            let traits = (attribute as? UIFont)?.fontDescriptor
                .symbolicTraits
                .intersection([.traitBold, .traitItalic, .traitMonoSpace]) ?? []
            let runFont =
                if traits.contains(.traitMonoSpace) {
                    UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                } else {
                    font.fontDescriptor
                        .withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
                        .map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
                }
            value.addAttribute(.font, value: runFont, range: runRange)
        }
        attributedText = value
        accessibilityLabel = text.text
        updateCustomEmoji()
        invalidateIntrinsicContentSize()
    }
}

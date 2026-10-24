// MessageTextBlocks.swift

import TDLibKit
import UIKit

// MARK: - MessageTextBlock

/// TextNode's TextNodeBlockQuoteData in a message's text: a quote or a code block, drawn behind its paragraphs with
/// the background, the 3 pt accent line, the quote or code icon and, for code with a language, its title.
struct MessageTextBlock: Equatable {
    enum Kind: Equatable {
        case quote
        /// The language's capitalized name, if the code block has one.
        case code(title: String?)
    }

    /// TextNode: the text sits 9 pt in from the block, whose own edge is 2 pt in.
    static let leftInset = CGFloat(11)
    /// TextNode's blockQuoteIconInset beside the widest line, before the block's 4 pt edge.
    static let iconInset = CGFloat(7)
    static let spacing = CGFloat(6)
    static let titleFont = UIFont.systemFont(ofSize: 14, weight: .semibold)

    /// The text the entity covers, widened to whole paragraphs.
    let range: NSRange
    let kind: Kind

    var reservesIcon: Bool {
        switch kind {
        case .quote: true
        case .code(let title): title != nil
        }
    }

    /// The width taken beside the text, so long lines wrap clear of the icon: TextNode's 7 pt beside the widest
    /// line at least, the icon and its 4 pt from the block's edge otherwise.
    var rightReserve: CGFloat {
        guard reservesIcon, let icon = icon(tint: .label) else { return 4 }
        return max(Self.iconInset, icon.size.width + 2) + 4
    }

    /// The height above the text for a code block's title.
    var titleHeight: CGFloat {
        guard case .code(let title?) = kind, !title.isEmpty else { return 0 }
        return ceil(Self.titleFont.lineHeight) + 2
    }

    /// stringWithAppliedEntities' `.Pre` and `.BlockQuote` over TDLib's entities.
    static func blocks(in text: FormattedText) -> [Self] {
        let string = text.text as NSString
        var result = [Self]()
        for entity in text.entities {
            let kind: Kind
            switch entity.type {
            case .textEntityTypeBlockQuote,
                 .textEntityTypeExpandableBlockQuote:
                kind = .quote
            case .textEntityTypePre:
                kind = .code(title: nil)
            case .textEntityTypePreCode(let code):
                kind = .code(title: code.language.isEmpty ? nil : code.language.capitalized)
            default:
                continue
            }
            let range = NSRange(location: entity.offset, length: entity.length)
            guard range.length > 0, NSMaxRange(range) <= string.length else { continue }
            var paragraphs = string.paragraphRange(for: range)
            // The paragraph's own line break stays outside, so the block ends with its text.
            while paragraphs.length > 0,
                  let scalar = UnicodeScalar(string.character(at: NSMaxRange(paragraphs) - 1)),
                  CharacterSet.newlines.contains(scalar)
            {
                paragraphs.length -= 1
            }
            guard paragraphs.length > 0,
                  !result.contains(where: { NSIntersectionRange($0.range, paragraphs).length > 0 }) else { continue }
            result.append(Self(range: paragraphs, kind: kind))
        }
        return result.sorted { $0.range.location < $1.range.location }
    }

    /// The blocks' paragraph styles: indents clear of the line and the icon, spacing around the block and above a
    /// code block's title, and Telegram's block font one point smaller.
    static func applyStyles(_ blocks: [Self], to text: NSMutableAttributedString) {
        for block in blocks where NSMaxRange(block.range) <= text.length {
            let string = text.string as NSString
            var location = block.range.location
            while location < NSMaxRange(block.range) {
                let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
                let isFirst = paragraph.location <= block.range.location
                let isLast = NSMaxRange(paragraph) >= NSMaxRange(block.range)
                let style = (text.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil)
                    as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                style.firstLineHeadIndent = leftInset
                style.headIndent = leftInset
                style.tailIndent = -block.rightReserve
                if isFirst { style.paragraphSpacingBefore = spacing + block.titleHeight }
                if isLast { style.paragraphSpacing = spacing }
                text.addAttribute(.paragraphStyle, value: style, range: paragraph)
                location = max(NSMaxRange(paragraph), location + 1)
            }
            text.enumerateAttribute(.font, in: block.range) { value, range, _ in
                guard let font = value as? UIFont else { return }
                text.addAttribute(.font, value: font.withSize(max(1, font.pointSize - 1)), range: range)
            }
        }
    }

    /// Telegram's ReplyQuoteIcon and TextCodeIcon.
    func icon(tint: UIColor) -> UIImage? {
        guard reservesIcon else { return nil }
        let symbol = kind == .quote ? "quote.closing" : "chevron.left.forwardslash.chevron.right"
        return UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 7, weight: .bold))?
            .withTintColor(tint, renderingMode: .alwaysOriginal)
    }

    /// The block's frame in the text container: from 2 pt above its first line to 2 pt below its last, as wide as
    /// its widest line plus the icon's room.
    func frame(layoutManager: NSLayoutManager, textContainer _: NSTextContainer) -> CGRect? {
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        var maxX = CGFloat.zero
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, usedRect, _, _, _ in
            minY = min(minY, usedRect.minY)
            maxY = max(maxY, usedRect.maxY)
            maxX = max(maxX, usedRect.maxX)
        }
        guard minY < maxY else { return nil }
        if case .code(let title?) = kind {
            let titleWidth = ceil((title as NSString).size(withAttributes: [.font: Self.titleFont]).width)
            maxX = max(maxX, Self.leftInset + titleWidth)
        }
        let top = minY - 2 - titleHeight
        return CGRect(x: 0, y: top, width: maxX + rightReserve, height: maxY - top + 2)
    }
}

// MARK: - MessageTextBlockDecorationView

/// TextNode's block drawing behind the text: the rounded background, the accent line clipped to its left corners,
/// the quote or code icon at the top right and a code block's title.
final class MessageTextBlockDecorationView: UIView {
    private var items = [(block: MessageTextBlock, frame: CGRect)]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsDisplay()
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let accent = tintColor ?? .systemBlue
        let radius = CGFloat(4)
        for (block, frame) in items {
            context.saveGState()
            let shape = UIBezierPath(roundedRect: frame, cornerRadius: radius)
            accent.withAlphaComponent(0.1).setFill()
            shape.fill()
            shape.addClip()
            accent.setFill()
            UIBezierPath(rect: CGRect(x: frame.minX, y: frame.minY, width: 3, height: frame.height)).fill()
            context.restoreGState()
            if let icon = block.icon(tint: accent) {
                icon.draw(at: CGPoint(x: frame.maxX - 4 - icon.size.width, y: frame.minY + 4))
            }
            if case .code(let title?) = block.kind {
                (title as NSString).draw(
                    at: CGPoint(x: frame.minX + MessageTextBlock.leftInset, y: frame.minY + 3),
                    withAttributes: [.font: MessageTextBlock.titleFont, .foregroundColor: accent],
                )
            }
        }
    }

    func update(_ items: [(block: MessageTextBlock, frame: CGRect)]) {
        self.items = items
        isHidden = items.isEmpty
        setNeedsDisplay()
    }
}

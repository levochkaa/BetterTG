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

    /// InteractiveTextNode's collapsible quote state, for an expandable quote longer than three lines.
    enum Collapse: Equatable {
        case collapsed
        case expanded
    }

    /// TextNode: the text sits 9 pt in from the block, whose own edge is 2 pt in.
    static let leftInset = CGFloat(11)
    /// TextNode's blockQuoteIconInset beside the widest line, before the block's 4 pt edge.
    static let iconInset = CGFloat(7)
    static let spacing = CGFloat(6)
    static let titleFont = UIFont.systemFont(ofSize: 14, weight: .semibold)

    /// InteractiveTextNode folds a collapsed quote after this many lines.
    static let collapsedLineCount = 3
    /// The expand arrow (ExpandingItemVerticalRegularArrow) and its inset from the block's bottom right corner.
    static let arrowSize = CGSize(width: 16, height: 16)
    static let arrowInset = CGPoint(x: 6, y: 3)

    /// The text the entity covers, widened to whole paragraphs.
    let range: NSRange
    let kind: Kind
    /// An expandable quote, which folds to three lines.
    var isCollapsible = false
    /// Set once the quote runs past three lines: folded, or opened by a tap.
    var collapse: Collapse?
    /// The room an opened quote adds under its last line for the arrow, where the line leaves none beside it.
    var arrowRoomBelow = CGFloat.zero

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
            var isCollapsible = false
            switch entity.type {
            case .textEntityTypeBlockQuote:
                kind = .quote
            case .textEntityTypeExpandableBlockQuote:
                kind = .quote
                isCollapsible = true
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
            result.append(Self(range: paragraphs, kind: kind, isCollapsible: isCollapsible))
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

    /// Folds collapsible quotes longer than three lines in `text`, laid out `width` wide: from the third line's cut
    /// the text is marked hidden for MessageCollapsedTextLayout, with an ellipsis in place of its first character
    /// unless the third line ends its paragraph. An opened quote whose last line leaves no room for the arrow gets
    /// room under it. Returns the blocks with their collapse state.
    static func applyCollapse(
        _ blocks: [Self],
        to text: NSMutableAttributedString,
        width: CGFloat,
        expanded: Set<Int>,
    ) -> [Self] {
        guard blocks.contains(where: \.isCollapsible), width > 0 else { return blocks }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var result = blocks
        for index in result.indices where result[index].isCollapsible {
            let block = result[index]
            guard NSMaxRange(block.range) <= text.length else { continue }
            let glyphs = manager.glyphRange(forCharacterRange: block.range, actualCharacterRange: nil)
            var lines = [(glyphs: NSRange, used: CGRect)]()
            manager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, lineGlyphs, _ in
                lines.append((NSIntersectionRange(lineGlyphs, glyphs), used))
            }
            guard lines.count > collapsedLineCount else { continue }
            if expanded.contains(index) {
                result[index].collapse = .expanded
                // InteractiveTextNode widens the last line by 16 pt for the arrow, or adds 10 pt under it.
                let last = lines[lines.count - 1].used
                let limit = width - block.rightReserve
                if last.maxX + arrowSize.width > limit {
                    result[index].arrowRoomBelow = 10
                    let lastParagraph = (text.string as NSString).paragraphRange(
                        for: NSRange(location: NSMaxRange(block.range) - 1, length: 0),
                    )
                    let style = (text.attribute(.paragraphStyle, at: lastParagraph.location, effectiveRange: nil)
                        as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    style.paragraphSpacing += 10
                    text.addAttribute(.paragraphStyle, value: style, range: lastParagraph)
                }
                continue
            }
            result[index].collapse = .collapsed
            let line = lines[collapsedLineCount - 1]
            let lineChars = manager.characterRange(forGlyphRange: line.glyphs, actualGlyphRange: nil)
            let string = text.string as NSString
            var cut = NSMaxRange(lineChars)
            var ellipsis = true
            let endsParagraph = cut > lineChars.location
                && CharacterSet.newlines.contains(UnicodeScalar(string.character(at: cut - 1)) ?? " ")
            // The text stops clear of the arrow, with room for the ellipsis.
            let font = text.attribute(.font, at: lineChars.location, effectiveRange: nil) as? UIFont
                ?? .preferredFont(forTextStyle: .body)
            let ellipsisWidth = ceil(("\u{2026}" as NSString).size(withAttributes: [.font: font]).width)
            let limit = width - block.rightReserve - arrowSize.width - ellipsisWidth
            if endsParagraph, line.used.maxX <= limit + ellipsisWidth {
                cut -= 1
                ellipsis = false
            } else {
                var location = NSMaxRange(lineChars)
                while location > lineChars.location {
                    let glyph = manager.glyphIndexForCharacter(at: location - 1)
                    let x = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).maxX
                    if x <= limit { break }
                    location -= 1
                }
                while location > lineChars.location,
                      let scalar = UnicodeScalar(string.character(at: location - 1)),
                      CharacterSet.whitespacesAndNewlines.contains(scalar)
                {
                    location -= 1
                }
                cut = string.rangeOfComposedCharacterSequence(at: max(lineChars.location, location)).location
            }
            let hidden = NSRange(location: cut, length: NSMaxRange(block.range) - cut)
            guard hidden.length > 0 else { continue }
            text.addAttribute(.messageCollapsedText, value: true, range: hidden)
            if ellipsis {
                text.addAttribute(.messageCollapsedEllipsis, value: true, range: NSRange(location: cut, length: 1))
            }
            // The block's spacing below rides on its last paragraph, which the fold hides.
            if NSMaxRange(string.paragraphRange(for: NSRange(location: cut, length: 0))) < NSMaxRange(block.range) {
                text.addAttribute(.messageCollapsedSpacing, value: spacing, range: NSRange(location: cut, length: 1))
            }
        }
        return result
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
        return CGRect(x: 0, y: top, width: maxX + rightReserve, height: maxY - top + 2 + arrowRoomBelow)
    }

    /// The expand arrow's frame inside the block's frame.
    func arrowFrame(in frame: CGRect) -> CGRect {
        CGRect(
            origin: CGPoint(
                x: frame.maxX - Self.arrowInset.x - Self.arrowSize.width,
                y: frame.maxY - Self.arrowInset.y - Self.arrowSize.height,
            ),
            size: Self.arrowSize,
        )
    }
}

extension NSAttributedString.Key {
    /// Text a folded quote hides.
    static let messageCollapsedText = NSAttributedString.Key("BetterTGMessageCollapsedText")
    /// The hidden character drawn as the fold's ellipsis.
    static let messageCollapsedEllipsis = NSAttributedString.Key("BetterTGMessageCollapsedEllipsis")
    /// The block's spacing below, added to the folded line when its last paragraph is hidden.
    static let messageCollapsedSpacing = NSAttributedString.Key("BetterTGMessageCollapsedSpacing")
}

// MARK: - MessageCollapsedTextLayout

/// Lays out a folded quote for TextKit 1: hidden characters get null glyphs and their own lines no height, the cut
/// shows Telegram's ellipsis, and the folded line keeps the block's spacing below. It forwards everything else to the
/// layout manager's previous delegate.
final class MessageCollapsedTextLayout: NSObject, NSLayoutManagerDelegate {
    private weak var next: NSLayoutManagerDelegate?

    init(next: NSLayoutManagerDelegate?) {
        self.next = next
        super.init()
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || next?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        next?.responds(to: selector) == true ? next : nil
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<Int>,
        characterIndexes: UnsafePointer<Int>,
        font: UIFont,
        forGlyphRange glyphRange: NSRange,
    ) -> Int {
        guard let storage = layoutManager.textStorage, glyphRange.length > 0 else { return 0 }
        let count = glyphRange.length
        var touches = false
        for index in 0..<count where storage.attribute(
            .messageCollapsedText,
            at: characterIndexes[index],
            effectiveRange: nil,
        ) != nil {
            touches = true
            break
        }
        guard touches else { return 0 }
        var ellipsisGlyph = CGGlyph(0)
        var ellipsisCharacter = UniChar(0x2026)
        CTFontGetGlyphsForCharacters(font as CTFont, &ellipsisCharacter, &ellipsisGlyph, 1)
        let newGlyphs = UnsafeMutablePointer<CGGlyph>.allocate(capacity: count)
        let newProperties = UnsafeMutablePointer<Int>.allocate(capacity: count)
        defer {
            newGlyphs.deallocate()
            newProperties.deallocate()
        }
        var placedEllipsis = false
        for index in 0..<count {
            let character = characterIndexes[index]
            newGlyphs[index] = glyphs[index]
            newProperties[index] = properties[index]
            guard storage.attribute(.messageCollapsedText, at: character, effectiveRange: nil) != nil else { continue }
            if !placedEllipsis, ellipsisGlyph != 0,
               storage.attribute(.messageCollapsedEllipsis, at: character, effectiveRange: nil) != nil
            {
                newGlyphs[index] = ellipsisGlyph
                newProperties[index] = 0
                placedEllipsis = true
            } else {
                newProperties[index] = NSLayoutManager.GlyphProperty.null.rawValue
            }
        }
        layoutManager.setGlyphs(
            newGlyphs,
            properties: newProperties,
            characterIndexes: characterIndexes,
            font: font,
            forGlyphRange: glyphRange,
        )
        return count
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in _: NSTextContainer,
        forGlyphRange glyphRange: NSRange,
    ) -> Bool {
        guard let storage = layoutManager.textStorage, glyphRange.length > 0 else { return false }
        let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard NSMaxRange(characters) <= storage.length else { return false }
        var hiddenCount = 0
        var visibleEllipsis = false
        var extraSpacing = CGFloat.zero
        storage.enumerateAttributes(in: characters) { attributes, range, _ in
            guard attributes[.messageCollapsedText] != nil else { return }
            hiddenCount += range.length
            if attributes[.messageCollapsedEllipsis] != nil { visibleEllipsis = true }
            if let spacing = attributes[.messageCollapsedSpacing] as? CGFloat { extraSpacing = spacing }
        }
        guard hiddenCount > 0 else { return false }
        if hiddenCount == characters.length, !visibleEllipsis {
            lineFragmentRect.pointee.size.height = 0
            lineFragmentUsedRect.pointee.size = .zero
            baselineOffset.pointee = 0
            return true
        }
        guard extraSpacing > 0 else { return false }
        lineFragmentRect.pointee.size.height += extraSpacing
        return true
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
            if let collapse = block.collapse,
               let arrow = UIImage(named: "Message/ExpandQuoteArrow")?.withTintColor(
                   accent,
                   renderingMode: .alwaysOriginal,
               )
            {
                let arrowFrame = block.arrowFrame(in: frame)
                context.saveGState()
                if collapse == .expanded {
                    context.translateBy(x: arrowFrame.midX, y: arrowFrame.midY)
                    context.rotate(by: .pi)
                    context.translateBy(x: -arrowFrame.midX, y: -arrowFrame.midY)
                }
                arrow.draw(in: arrowFrame)
                context.restoreGState()
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

// ComposerText.swift

import TDLibKit
import UIKit

/// Composer semantics travel with the text, independently of its visual attributes.
enum ComposerText {
    struct Entity: Hashable {
        let id: UUID
        let type: TextEntityType
        let originalText: String?

        init(_ type: TextEntityType, originalText: String? = nil) {
            self.id = UUID()
            self.type = type
            self.originalText = originalText
        }
    }

    final class Entities: NSObject, NSCopying {
        override var hash: Int { values.hashValue }

        let values: [Entity]

        init(_ values: [Entity]) { self.values = values }

        override func isEqual(_ object: Any?) -> Bool { (object as? Entities)?.values == values }

        func copy(with _: NSZone? = nil) -> Any { self }
    }

    enum EntityAttribute: ObjectiveCConvertibleAttributedStringKey {
        typealias Value = [Entity]
        typealias ObjectiveCValue = Entities

        static let name = "BetterTG.Composer.Entities"

        static func objectiveCValue(for value: Value) -> Entities { Entities(value) }
        static func value(for object: Entities) -> Value { object.values }
    }

    struct Scope: AttributeScope {
        let entities: EntityAttribute
        /// Derived from custom emoji entities in `refresh`; the composer's emoji renderer reads it.
        let customEmoji: TelegramCustomEmojiAttribute
        let uiKit: AttributeScopes.UIKitAttributes
    }

    private static let key = NSAttributedString.Key(EntityAttribute.name)

    static func attributed(_ formatted: FormattedText) -> AttributedString {
        let text = NSMutableAttributedString(string: formatted.text, attributes: defaultAttributes())
        for entity in formatted.entities where isManual(entity.type) {
            let range = NSRange(location: entity.offset, length: entity.length)
            guard isValid(range, in: formatted.text as NSString), range.length > 0 else { continue }
            let original: String? =
                switch entity.type {
                case .textEntityTypeCustomEmoji,
                     .textEntityTypeDateTime,
                     .textEntityTypeMentionName:
                    (formatted.text as NSString).substring(with: range)
                default: nil
                }
            let value = Entity(entity.type, originalText: original)
            transform(text, in: range) { $0 + [value] }
        }
        refresh(text)
        return value(text)
    }

    static func value(_ text: NSAttributedString) -> AttributedString {
        // Normalize UIKit-owned attributes before bridging. A bridge failure may
        // lose presentation, never the independent semantic spans.
        let normalized = NSMutableAttributedString(attributedString: text)
        refresh(normalized)
        return (try? AttributedString(normalized, including: Scope.self)) ?? semanticValue(normalized)
    }

    static func uiKit(_ text: AttributedString) -> NSAttributedString {
        (try? NSAttributedString(text, including: Scope.self)) ?? semanticUIKit(text)
    }

    static func semanticValue(_ text: NSAttributedString) -> AttributedString {
        var result = AttributedString(text.string)
        for (attributes, range) in runs(text, in: NSRange(location: 0, length: text.length)) {
            guard isValid(range, in: text.string as NSString), let target = Range<AttributedString.Index>(
                range,
                in: result,
            )
            else { continue }
            result[target][EntityAttribute.self] = values(attributes)
        }
        return result
    }

    static func semanticUIKit(_ text: AttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: String(text.characters))
        for run in text.runs {
            result.addAttribute(
                key,
                value: Entities(run[EntityAttribute.self] ?? []),
                range: NSRange(run.range, in: text),
            )
        }
        refresh(result)
        return result
    }

    static func formatted(_ text: AttributedString) -> FormattedText { formatted(uiKit(text)) }

    static func formatted(_ text: NSAttributedString) -> FormattedText {
        let spans = spans(text)
        let entities = spans.flatMap { entity, ranges -> [TextEntity] in
            guard isManual(entity.type), entity.originalText == nil
                || (ranges.count == 1 && (text.string as NSString).substring(with: ranges[0]) == entity.originalText)
            else { return [] }
            return ranges.map { TextEntity(length: $0.length, offset: $0.location, type: entity.type) }
        }
        // User formatting can cross another entity. Split only decorative
        // spans, so TDLib sees nested ranges without losing payload identities.
        let nested = entities.flatMap { entity -> [TextEntity] in
            guard isStyle(entity.type) else { return [entity] }
            let start = entity.offset
            let end = start + entity.length
            var cuts = Set([start, end])
            for other in entities {
                let otherStart = other.offset
                let otherEnd = otherStart + other.length
                if start < otherStart, otherStart < end, end < otherEnd { cuts.insert(otherStart) }
                if otherStart < start, start < otherEnd, otherEnd < end { cuts.insert(otherEnd) }
            }
            let sorted = cuts.sorted()
            return zip(sorted, sorted.dropFirst()).map { TextEntity(length: $1 - $0, offset: $0, type: entity.type) }
        }
        .sorted {
            if $0.offset != $1.offset { return $0.offset < $1.offset }
            if $0.length != $1.length { return $0.length > $1.length }
            return String(describing: $0.type) < String(describing: $1.type)
        }
        return FormattedText(entities: nested, text: text.string)
    }

    /// RTF has visual attributes, not trusted Telegram identity or spoiler semantics.
    static func importing(_ external: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: external.string, attributes: defaultAttributes())
        external.enumerateAttributes(in: NSRange(location: 0, length: external.length)) { attributes, range, _ in
            guard isValid(range, in: external.string as NSString) else { return }
            result.addAttribute(key, value: Entities(inferredStyles(attributes)), range: range)
        }
        refresh(result)
        return result
    }

    static func refresh(_ text: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: text.length)
        let invalidIDs = Set(spans(text).compactMap { entity, ranges -> UUID? in
            guard let original = entity.originalText else { return nil }
            return ranges.count == 1 && (text.string as NSString).substring(with: ranges[0]) == original
                ? nil
                : entity.id
        })
        let runs = runs(text, in: full)
        text.beginEditing()
        for (attributes, range) in runs {
            guard isValid(range, in: text.string as NSString) else {
                text.setAttributes(defaultAttributes().merging([key: Entities([])]) { _, new in new }, range: range)
                continue
            }
            let entities = values(attributes).filter { !invalidIDs.contains($0.id) }
            var visual = defaultAttributes()
            let types = entities.map(\.type)
            let traits: UIFontDescriptor.SymbolicTraits = [
                types.contains(.textEntityTypeBold) ? .traitBold : [],
                types.contains(.textEntityTypeItalic) ? .traitItalic : [],
            ]
            if types.contains(where: isCode) { visual[.font] = UIFont.monospaced }
            else if let descriptor = UIFont.body.fontDescriptor.withSymbolicTraits(traits) {
                visual[.font] = UIFont(descriptor: descriptor, size: UIFont.body.pointSize)
            }
            if types.contains(.textEntityTypeUnderline) { visual[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if types
                .contains(.textEntityTypeStrikethrough)
            {
                visual[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if types.contains(.textEntityTypeSpoiler) { visual[.backgroundColor] = UIColor.systemGray }
            for type in types {
                switch type {
                case .textEntityTypeTextUrl(let link):
                    if let url = URL(string: link.url) { visual[.link] = url }
                case .textEntityTypeCustomEmoji(let emoji):
                    visual[.telegramCustomEmoji] = NSNumber(value: emoji.customEmojiId)
                default:
                    break
                }
            }
            visual[key] = Entities(entities)
            text.setAttributes(visual, range: range)
        }
        text.endEditing()
    }

    static func toggle(_ type: TextEntityType, in text: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0, isValid(range, in: text.string as NSString) else { return }
        let selected = runs(text, in: range)
        let removes = selected.allSatisfy { values($0.0).contains { $0.type == type } }
        if !removes, !isCode(type),
           selected.contains(where: { values($0.0).contains { isExclusive($0.type) } }) { return }
        let entity = Entity(type)
        transform(text, in: range) { current in
            if removes { return current.filter { $0.type != type } }
            return (isCode(type) ? [] : current.filter { $0.type != type }) + [entity]
        }
        refresh(text)
    }

    static func setLink(_ url: String, in text: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0, isValid(range, in: text.string as NSString), permitsLink(url),
              !runs(text, in: range).contains(where: { values($0.0).contains { isExclusive($0.type) } })
        else { return }
        let entity = Entity(.textEntityTypeTextUrl(.init(url: url)))
        transform(text, in: range) { current in
            current.filter {
                switch $0.type {
                case .textEntityTypeCustomEmoji,
                     .textEntityTypeMentionName,
                     .textEntityTypeTextUrl: false
                default: true
                }
            } + [entity]
        }
        refresh(text)
    }

    /// Gives each run its own custom emoji entity. Runs inside code keep plain text, as in Telegram.
    static func setCustomEmoji(_ emojis: [TelegramCustomEmojiRun], in text: NSMutableAttributedString) {
        for emoji in emojis where emoji.id != 0 && emoji.range.length > 0 {
            guard isValid(emoji.range, in: text.string as NSString),
                  !runs(text, in: emoji.range).contains(where: { values($0.0).contains { isExclusive($0.type) } })
            else { continue }
            let entity = Entity(
                .textEntityTypeCustomEmoji(.init(customEmojiId: emoji.id)),
                originalText: (text.string as NSString).substring(with: emoji.range),
            )
            transform(text, in: emoji.range) { current in
                current.filter {
                    switch $0.type {
                    case .textEntityTypeCustomEmoji,
                         .textEntityTypeMentionName,
                         .textEntityTypeTextUrl: false
                    default: true
                    }
                } + [entity]
            }
        }
        refresh(text)
    }

    static func typingAttributes(in text: NSAttributedString, at offset: Int) -> [NSAttributedString.Key: Any] {
        guard text.length > 0 else { return defaultAttributes().merging([key: Entities([])]) { _, new in new } }
        let attributes = text.attributes(at: max(0, min(offset - 1, text.length - 1)), effectiveRange: nil)
        let interior = offset > 0 && offset < text.length
            ? values(text.attributes(at: offset, effectiveRange: nil))
            : []
        let entities = values(attributes).filter {
            switch $0.type {
            case .textEntityTypeBold,
                 .textEntityTypeCode,
                 .textEntityTypeItalic: true
            case .textEntityTypeBlockQuote,
                 .textEntityTypeExpandableBlockQuote,
                 .textEntityTypePre,
                 .textEntityTypePreCode:
                interior.contains($0)
            default: false
            }
        }
        let sample = NSMutableAttributedString(string: " ", attributes: [key: Entities(entities)])
        refresh(sample)
        return sample.attributes(at: 0, effectiveRange: nil)
    }

    static func isValid(_ range: NSRange, in text: NSString) -> Bool {
        guard range.location >= 0, range.length >= 0, range.location <= text.length,
              range.length <= text.length - range.location else { return false }
        return [range.location, range.location + range.length].allSatisfy { offset in
            offset == 0 || offset == text.length
                || !(0xD800...0xDBFF).contains(text.character(at: offset - 1))
                || !(0xDC00...0xDFFF).contains(text.character(at: offset))
        }
    }

    private static func spans(_ text: NSAttributedString) -> [Entity: [NSRange]] {
        var result = [Entity: [NSRange]]()
        for (attributes, range) in runs(text, in: NSRange(location: 0, length: text.length)) {
            guard isValid(range, in: text.string as NSString), range.length > 0 else { continue }
            for entity in values(attributes) {
                var ranges = result[entity, default: []]
                if let last = ranges.last, NSMaxRange(last) == range.location {
                    ranges[ranges.count - 1] = NSUnionRange(last, range)
                } else { ranges.append(range) }
                result[entity] = ranges
            }
        }
        return result
    }

    private static func transform(
        _ text: NSMutableAttributedString,
        in range: NSRange,
        _ body: ([Entity]) -> [Entity],
    ) {
        for (attributes, subrange) in runs(text, in: range) {
            text.addAttribute(key, value: Entities(body(values(attributes))), range: subrange)
        }
    }

    private static func runs(_ text: NSAttributedString, in range: NSRange) -> [(
        [NSAttributedString.Key: Any],
        NSRange,
    )] {
        var result = [([NSAttributedString.Key: Any], NSRange)]()
        text.enumerateAttributes(in: range) { attributes, range, _ in result.append((attributes, range)) }
        return result
    }

    private static func values(_ attributes: [NSAttributedString.Key: Any]) -> [Entity] {
        (attributes[key] as? Entities)?.values ?? inferredStyles(attributes)
    }

    private static func inferredStyles(_ attributes: [NSAttributedString.Key: Any]) -> [Entity] {
        let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
        if traits.contains(.traitMonoSpace) { return [Entity(.textEntityTypeCode)] }
        var types = [TextEntityType]()
        if traits.contains(.traitBold) { types.append(.textEntityTypeBold) }
        if traits.contains(.traitItalic) { types.append(.textEntityTypeItalic) }
        if (attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0 != 0 { types.append(.textEntityTypeUnderline) }
        if (attributes[.strikethroughStyle] as? NSNumber)?
            .intValue ?? 0 != 0 { types.append(.textEntityTypeStrikethrough) }
        if let value = attributes[.link], let url = (value as? URL)?.absoluteString ?? value as? String,
           permitsLink(url)
        {
            types.append(.textEntityTypeTextUrl(.init(url: url)))
        }
        return types.map { Entity($0) }
    }

    private static func permitsLink(_ value: String) -> Bool {
        guard let scheme = URL(string: value)?.scheme?.lowercased() else { return false }
        return ["http", "https", "tg"].contains(scheme)
    }

    private static func isExclusive(_ type: TextEntityType) -> Bool {
        if case .textEntityTypeDateTime = type { return true }
        return isCode(type)
    }

    private static func isStyle(_ type: TextEntityType) -> Bool {
        switch type {
        case .textEntityTypeBold,
             .textEntityTypeItalic,
             .textEntityTypeSpoiler,
             .textEntityTypeStrikethrough,
             .textEntityTypeUnderline: true
        default: false
        }
    }

    private static func isCode(_ type: TextEntityType) -> Bool {
        switch type {
        case .textEntityTypeCode,
             .textEntityTypePre,
             .textEntityTypePreCode: true
        default: false
        }
    }

    private static func isManual(_ type: TextEntityType) -> Bool {
        switch type {
        case .textEntityTypeBlockQuote,
             .textEntityTypeBold,
             .textEntityTypeCode,
             .textEntityTypeCustomEmoji,
             .textEntityTypeDateTime,
             .textEntityTypeExpandableBlockQuote,
             .textEntityTypeItalic,
             .textEntityTypeMentionName,
             .textEntityTypePre,
             .textEntityTypePreCode,
             .textEntityTypeSpoiler,
             .textEntityTypeStrikethrough,
             .textEntityTypeTextUrl,
             .textEntityTypeUnderline: true
        default: false
        }
    }
}

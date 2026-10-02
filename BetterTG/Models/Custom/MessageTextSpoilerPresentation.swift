// MessageTextSpoilerPresentation.swift

import Combine
import TDLibKitDynamic
import UIKit

// MARK: - MessageTextSpoilerPresentation

/// Display-only projection. Never substitute this value into a draft or TDLib write.
struct MessageTextSpoilerPresentation {
    enum Action: Equatable {
        case none
        case reveal
        case copy(String)
        case open(URL)
    }

    let text: FormattedText
    let ranges: [NSRange]

    init(_ original: FormattedText) {
        let utf16 = original.text as NSString
        let length = utf16.length
        let entities = original.entities.filter { entity in
            entity.offset >= 0 && entity.length > 0 && entity.offset <= length
                && entity.length <= length - entity.offset
                && Self.isScalarBoundary(entity.offset, in: utf16)
                && Self.isScalarBoundary(entity.offset + entity.length, in: utf16)
        }
        self.text = FormattedText(entities: entities, text: original.text)
        let acceptedEntities = Set(entities)
        let malformedSpoiler = original.entities.contains {
            if case .textEntityTypeSpoiler = $0.type { return !acceptedEntities.contains($0) }
            return false
        }
        let candidates = malformedSpoiler && length > 0
            ? [NSRange(location: 0, length: length)]
            : entities.compactMap { entity -> NSRange? in
                guard case .textEntityTypeSpoiler = entity.type else { return nil }
                return NSRange(location: entity.offset, length: entity.length)
            }
        var merged = [NSRange]()
        for range in candidates.sorted(by: { $0.location < $1.location }) {
            if let previous = merged.last, range.location <= NSMaxRange(previous) {
                merged[merged.count - 1] = NSUnionRange(previous, range)
            } else { merged.append(range) }
        }
        self.ranges = merged
    }

    static func summary(for message: Message, revealed: Bool = false) -> String {
        let content = MessageContentPresentation.make(message)
        guard let formatted = content.formattedText, !formatted.text.isEmpty,
              let range = content.summary.range(of: formatted.text, options: .backwards)
        else { return content.summary }
        return content.summary.replacingCharacters(
            in: range, with: Self(formatted).accessibilityText(revealed: revealed),
        )
    }

    private static func isScalarBoundary(_ offset: Int, in text: NSString) -> Bool {
        guard offset > 0, offset < text.length else { return true }
        return !(0xD800...0xDBFF).contains(text.character(at: offset - 1))
            || !(0xDC00...0xDFFF).contains(text.character(at: offset))
    }

    func conceals(_ range: NSRange, revealed: Bool) -> Bool {
        !revealed && ranges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    func accessibilityText(revealed: Bool = false) -> String {
        guard !revealed else { return text.text }
        let result = NSMutableString(string: text.text)
        for range in ranges.reversed() {
            result.replaceCharacters(in: range, with: "Spoiler")
        }
        return String(result)
    }

    func attributedText(revealed: Bool = false) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(getAttributedString(from: text))
        for range in ranges {
            result.removeAttribute(.backgroundColor, range: range)
            if !revealed {
                // Remove link styling last: UITextView linkTextAttributes can override foregroundColor.
                for key: NSAttributedString.Key in [.link, .underlineStyle, .strikethroughStyle] {
                    result.removeAttribute(key, range: range)
                }
                result.addAttributes(
                    [.foregroundColor: UIColor.clear, .backgroundColor: UIColor.systemGray],
                    range: range,
                )
            }
        }
        return result
    }

    func action(at index: Int, revealed: Bool) -> Action {
        guard index >= 0, index < text.text.utf16.count else { return .none }
        if !revealed, ranges.contains(where: { NSLocationInRange(index, $0) }) { return .reveal }
        for entity in text.entities {
            let range = NSRange(location: entity.offset, length: entity.length)
            guard NSLocationInRange(index, range) else { continue }
            let raw = (text.text as NSString).substring(with: range)
            let url: URL?
            switch entity.type {
            case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
                return conceals(range, revealed: revealed) ? .reveal : .copy(raw)
            case .textEntityTypeUrl: url = getUrl(from: raw)
            case .textEntityTypeTextUrl(let value): url = getUrl(from: value.url)
            case .textEntityTypeEmailAddress: url = URL(string: "mailto:\(raw)")
            case .textEntityTypePhoneNumber: url = URL(string: "tel:\(raw)")
            default: continue
            }
            if let url { return conceals(range, revealed: revealed) ? .reveal : .open(url) }
        }
        return .none
    }
}

// MARK: - MessageTextSpoilerState

@MainActor final class MessageTextSpoilerState {
    let original: FormattedText
    let presentation: MessageTextSpoilerPresentation
    let changes = PassthroughSubject<Void, Never>()
    private(set) var revealed = false

    private let source: TdUpdateSource?
    private var valid = true

    init(text: FormattedText, source: TdUpdateSource?) {
        self.original = text
        self.presentation = MessageTextSpoilerPresentation(text)
        self.source = source
    }

    @discardableResult func reveal() -> Bool {
        guard valid, source != nil, !revealed, !presentation.ranges.isEmpty else { return false }
        revealed = true
        changes.send()
        return true
    }

    func invalidate() { valid = false }
}

// MARK: - MessageTextSpoilerStore

/// Cell-lifetime authority: no account-global numeric message IDs or persisted reveals.
@MainActor final class MessageTextSpoilerStore {
    private(set) var states = [Int64: MessageTextSpoilerState]()

    private var source: TdUpdateSource?
    private var chatID: Int64?

    func configure(source: TdUpdateSource?, chatID: Int64, texts: [Int64: FormattedText]) {
        if self.source != source || self.chatID != chatID { reset() }
        self.source = source
        self.chatID = chatID
        for (id, state) in states where texts[id] != state.original {
            state.invalidate()
            states.removeValue(forKey: id)
        }
        for (id, text) in texts where states[id] == nil {
            states[id] = MessageTextSpoilerState(text: text, source: source)
        }
    }

    func reset() {
        states.values.forEach { $0.invalidate() }
        states.removeAll()
        source = nil
        chatID = nil
    }
}

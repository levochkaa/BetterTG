// TelegramTextAttributes.swift

import Foundation
import UIKit

// MARK: - TelegramCustomEmojiAttribute

enum TelegramCustomEmojiAttribute: CodableAttributedStringKey, ObjectiveCConvertibleAttributedStringKey {
    typealias Value = Int64
    typealias ObjectiveCValue = NSNumber

    static let name = "BetterTG.CustomEmojiID"

    static func objectiveCValue(for value: Int64) -> NSNumber { NSNumber(value: value) }
    static func value(for object: NSNumber) -> Int64 { object.int64Value }
}

extension AttributeScopes {
    struct TelegramTextAttributes: AttributeScope {
        let customEmoji: TelegramCustomEmojiAttribute
        let uiKit: UIKitAttributes
    }

    var telegramText: TelegramTextAttributes.Type { TelegramTextAttributes.self }
}

extension NSAttributedString.Key {
    static let telegramCustomEmoji = NSAttributedString.Key(TelegramCustomEmojiAttribute.name)
}

extension AttributedString {
    init(telegramText: NSAttributedString) {
        self = (try? AttributedString(telegramText, including: \.telegramText)) ?? AttributedString(telegramText)
    }

    var telegramNSAttributedString: NSAttributedString {
        (try? NSAttributedString(self, including: \.telegramText)) ?? NSAttributedString(self)
    }
}

// MARK: - TelegramCustomEmojiRun

struct TelegramCustomEmojiRun {
    let id: Int64
    let range: NSRange

    static func extract(from value: NSAttributedString) -> [Self] {
        var result = [Self]()
        let string = value.string as NSString
        value.enumerateAttribute(.telegramCustomEmoji, in: NSRange(
            location: 0,
            length: value.length,
        )) { attribute, range, _ in
            guard let id = attribute as? NSNumber, id.int64Value != 0 else { return }
            var cursor = range.location
            while cursor < NSMaxRange(range) {
                let character = string.rangeOfComposedCharacterSequence(at: cursor)
                if character.location >= range.location, NSMaxRange(character) <= NSMaxRange(range) {
                    result.append(Self(id: id.int64Value, range: character))
                }
                cursor = NSMaxRange(character)
            }
        }
        return result
    }
}

// MARK: - TelegramEmojiPasteboardPayload

/// RTF carries formatting; this small companion preserves custom emoji IDs
/// through BetterTG copy/paste without placing opaque attachments in the text.
struct TelegramEmojiPasteboardPayload: Codable {
    struct Emoji: Codable {
        let id: Int64
        let offset: Int
        let length: Int
    }

    static let type = "com.levochkaaa.BetterTG.custom-emoji-text"

    let text: String
    let emojis: [Emoji]

    init(_ value: NSAttributedString) {
        self.text = value.string
        self.emojis = TelegramCustomEmojiRun.extract(from: value).map { Emoji(
            id: $0.id,
            offset: $0.range.location,
            length: $0.range.length,
        ) }
    }

    func apply(to value: NSMutableAttributedString) {
        guard value.string == text else { return }
        for emoji in emojis where emoji.id != 0 && emoji.offset >= 0 && emoji.length > 0
            && emoji.offset <= value.length && emoji.length <= value.length - emoji.offset
        {
            guard Range(NSRange(location: emoji.offset, length: emoji.length), in: value.string) != nil
            else { continue }
            value.addAttribute(
                .telegramCustomEmoji,
                value: NSNumber(value: emoji.id),
                range: NSRange(location: emoji.offset, length: emoji.length),
            )
        }
    }
}

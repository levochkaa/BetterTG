// ComposerTextBreaker.swift

import Foundation

// MARK: - ComposerTextBreaker

/// Telegram's `trimChatInputText` and `breakChatInputText`: sent text loses leading and trailing whitespace, and
/// text longer than a message splits into messages of at most 4096 UTF-16 units, each ending at the last newline
/// or full stop that fits.
enum ComposerTextBreaker {
    static let messageLengthLimit = 4096

    static func trimmed(_ text: AttributedString) -> AttributedString {
        let characters = text.characters
        var start = characters.startIndex
        var end = characters.endIndex
        while start < end, characters[start].isWhitespace {
            start = characters.index(after: start)
        }
        while end > start, characters[characters.index(before: end)].isWhitespace {
            end = characters.index(before: end)
        }
        return AttributedString(text[start..<end])
    }

    static func messages(_ text: AttributedString) -> [AttributedString] {
        let text = trimmed(text)
        guard length(of: text) > messageLengthLimit else { return text.characters.isEmpty ? [] : [text] }
        let characters = text.characters
        var result = [AttributedString]()
        var start = characters.startIndex
        while start < characters.endIndex {
            var end = start
            var length = 0
            var lastBreak: AttributedString.Index?
            while end < characters.endIndex {
                let character = characters[end]
                let units = character.utf16.count
                guard length + units <= messageLengthLimit else { break }
                length += units
                end = characters.index(after: end)
                if character == "\n" || character == "." { lastBreak = end }
            }
            if end < characters.endIndex, let lastBreak { end = lastBreak }
            let chunk = trimmed(AttributedString(text[start..<end]))
            if !chunk.characters.isEmpty { result.append(chunk) }
            start = end
        }
        return result
    }

    static func length(of text: AttributedString) -> Int {
        text.characters.reduce(0) { $0 + $1.utf16.count }
    }
}

// MARK: - ComposerCaptionTooLongError

/// A caption over TDLib's `message_caption_length_max`, which the server would reject only after the composer
/// cleared.
struct ComposerCaptionTooLongError: LocalizedError {
    let limit: Int

    var errorDescription: String? { L10n.betterTG("Composer.CaptionTooLong", limit) }
}

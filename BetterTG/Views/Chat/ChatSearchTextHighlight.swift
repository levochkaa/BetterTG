// ChatSearchTextHighlight.swift

import UIKit

// MARK: - ChatSearchTextHighlight

/// How Telegram marks a chat search's query in found messages (ChatMessageTextBubbleContentNode
/// updateSearchTextHighlightState): the words that match it, behind its textHighlightColor.
enum ChatSearchTextHighlight {
    /// textHighlightColor of Telegram's day and night themes.
    static let color = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(rgb: 0xF5C038) : UIColor(rgb: 0xFFE438)
    }

    /// Telegram's findSubstringRanges: each word of `string`, split at apostrophes, whose start matches a query word
    /// and
    /// which differs from it by less than 37% of the longer length. A query word after # or @ also takes the sign.
    static func ranges(in string: String, query: String) -> [NSRange] {
        let words = query
            .split { !$0.isLetter && !$0.isNumber && $0 != "#" && $0 != "@" }
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && $0 != "#" && $0 != "@" }
        guard !words.isEmpty else { return [] }
        let text = string as NSString
        var result = [NSRange]()
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: text.length),
            options: .byWords,
        ) { substring, range, _, _ in
            guard let substring else { return }
            var parts = [(String, NSRange)]()
            if let apostrophe = substring.firstIndex(of: "'") {
                let left = String(substring[..<apostrophe])
                let right = String(substring[substring.index(after: apostrophe)...])
                let leftLength = left.utf16.count
                if !left.isEmpty { parts.append((left, NSRange(location: range.location, length: leftLength))) }
                if !right.isEmpty {
                    parts.append((right, NSRange(
                        location: range.location + leftLength + 1,
                        length: range.length - leftLength - 1,
                    )))
                }
            } else {
                parts.append((substring, range))
            }
            for (part, partRange) in parts {
                let lowered = part.lowercased()
                for queryWord in words {
                    var word = queryWord
                    var hasLeadingSymbol = false
                    if word.hasPrefix("#") || word.hasPrefix("@") {
                        hasLeadingSymbol = true
                        word.removeFirst()
                    }
                    let matched = zip(word, lowered).prefix { $0.0 == $0.1 }.count
                    guard matched > 0 else { continue }
                    let length = Double(max(word.count, lowered.count))
                    guard abs(length - Double(matched)) / length < 0.37 else { continue }
                    var found = partRange
                    if hasLeadingSymbol, found.location > 0 {
                        found = NSRange(location: found.location - 1, length: found.length + 1)
                    }
                    result.append(found)
                }
            }
        }
        return result
    }
}

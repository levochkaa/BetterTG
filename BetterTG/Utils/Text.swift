// Text.swift

import TDLibKit
import UIKit

func defaultAttributes(_ foregroundColor: UIColor = .label) -> [NSAttributedString.Key: Any] {
    [
        .font: UIFont.body as Any,
        .foregroundColor: foregroundColor,
    ]
}

func getAttributedString(
    from formattedText: FormattedText,
    _ foregroundColor: UIColor = .label,
    withDate: Bool = false,
) -> AttributedString {
    let attributedString = NSMutableAttributedString(
        string: formattedText.text,
        attributes: defaultAttributes(foregroundColor),
    )

    for entity in formattedText.entities {
        setEntity(entity, base: formattedText.text, for: attributedString)
    }

    if withDate {
        attributedString.append(NSMutableAttributedString.dateString)
    }

    return AttributedString(telegramText: attributedString)
}

func setEntity(_ entity: TextEntity, base text: String, for attributedString: NSMutableAttributedString) {
    let range = NSRange(location: entity.offset, length: entity.length)
    let stringRange = stringRange(for: text, start: entity.offset, length: entity.length)
    let raw = String(text[stringRange])

    switch entity.type {
    case .textEntityTypeBold:
        attributedString.addAttribute(.font, value: UIFont.bold, range: range)
    case .textEntityTypeItalic:
        attributedString.addAttribute(.font, value: UIFont.italic, range: range)
    case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
        attributedString.addAttribute(.font, value: UIFont.monospaced, range: range)
    case .textEntityTypeUnderline:
        attributedString.addAttribute(.underlineStyle, value: 1, range: range)
    case .textEntityTypeStrikethrough:
        attributedString.addAttribute(.strikethroughStyle, value: 1, range: range)
    case .textEntityTypePhoneNumber:
        attributedString.addAttribute(.link, value: URL(string: "tel://\(raw)") as Any, range: range)
    case .textEntityTypeEmailAddress:
        attributedString.addAttribute(.link, value: URL(string: "mailto://\(raw)") as Any, range: range)
    case .textEntityTypeUrl:
        attributedString.addAttribute(.link, value: getUrl(from: raw) as Any, range: range)
    case .textEntityTypeTextUrl(let textUrl):
        attributedString.addAttribute(.link, value: getUrl(from: textUrl.url) as Any, range: range)
    case .textEntityTypeMention:
        attributedString.addAttribute(
            .link,
            value: URL(string: "https://t.me/" + raw.drop(while: { $0 == "@" })) as Any,
            range: range,
        )
    case .textEntityTypeMentionName(let mention):
        // TDLib reads a tg://user link back as the same mention.
        attributedString.addAttribute(.link, value: URL(string: "tg://user?id=\(mention.userId)") as Any, range: range)
    case .textEntityTypeSpoiler:
        attributedString.addAttribute(.backgroundColor, value: UIColor.gray, range: range)
    case .textEntityTypeCustomEmoji(let emoji):
        attributedString.addAttribute(.telegramCustomEmoji, value: NSNumber(value: emoji.customEmojiId), range: range)
    default:
        break
    }
}

func getEntities(from text: AttributedString) -> [TextEntity] {
    ComposerText.formatted(text).entities
}

func getUrl(from string: String) -> URL? {
    URL(string: string.contains("://") ? string : "https://\(string)")
}

func stringRange(
    for string: String,
    start: Int,
    length: Int,
) -> Range<String.Index> {
    let startIndex = string.utf16.index(string.startIndex, offsetBy: start)
    let endIndex = string.utf16.index(startIndex, offsetBy: length)
    return startIndex..<endIndex
}

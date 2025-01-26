// Text.swift

import SwiftUI
import TDLibKit

func defaultAttributes(_ foregroundColor: Color = .white) -> [NSAttributedString.Key: Any] {
    [
        .font: UIFont.body as Any,
        .foregroundColor: UIColor(foregroundColor)
    ]
}

func getAttributedString(from formattedText: FormattedText, _ foregroundColor: Color = .white, withDate: Bool = false) -> AttributedString {
    let attributedString = NSMutableAttributedString(
        string: formattedText.text,
        attributes: defaultAttributes(foregroundColor)
    )
    
    for entity in formattedText.entities {
        setEntity(entity, base: formattedText.text, for: attributedString)
    }
    
    if withDate {
        attributedString.append(NSMutableAttributedString.dateString)
    }
    
    return AttributedString(attributedString)
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
        case .textEntityTypeSpoiler:
            attributedString.addAttribute(.backgroundColor, value: UIColor.gray, range: range)
//        case .textEntityTypeCustomEmoji: // (let textEntityTypeCustomEmoji)
//            guard showAnimojis else { break }
//            attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
        default:
            break
    }
}

func getEntities(from text: AttributedString) -> [TextEntity] {
    var entities = [TextEntity]()
    let attributedText = NSAttributedString(text)
    let textRange = NSRange(location: 0, length: text.string.count)
    attributedText.enumerateAttributes(in: textRange) { attributes, range, _ in
        for attribute in attributes {
            guard let entity = getEntity(from: attribute, using: range) else { continue }
            entities.append(entity)
        }
    }
    return entities
}

func getEntity(from attribute: (key: NSAttributedString.Key, value: Any), using range: NSRange) -> TextEntity? {
    switch attribute.key {
        case .font:
            guard let uiFont = attribute.value as? UIFont else { return nil }
            switch uiFont {
                case UIFont.bold:
                    return .init(.textEntityTypeBold, range: range)
                case UIFont.italic:
                    return .init(.textEntityTypeItalic, range: range)
                case UIFont.monospaced:
                    return .init(.textEntityTypeCode, range: range)
                default:
                    break
            }
        case .link:
            guard let url = attribute.value as? URL else { return nil }
            return .init(.textEntityTypeTextUrl(.init(url: url.absoluteString)), range: range)
        case .strikethroughStyle:
            return .init(.textEntityTypeStrikethrough, range: range)
        case .underlineStyle:
            return .init(.textEntityTypeUnderline, range: range)
        case .backgroundColor:
            return .init(.textEntityTypeSpoiler, range: range)
        default:
            return nil
    }
    return nil
}

func getUrl(from string: String) -> URL? {
    URL(string: string.contains("://") ? string : "https://\(string)")
}

func stringRange(
    for string: String,
    start: Int,
    length: Int
) -> Range<String.Index> {
    let startIndex = string.utf16.index(string.startIndex, offsetBy: start)
    let endIndex = string.utf16.index(startIndex, offsetBy: length)
    return startIndex..<endIndex
}

// Text.swift

import TDLibKit

func captionText(from dateString: String) -> some View {
    Text(dateString)
        .font(.caption)
        .foregroundColor(.white).opacity(0.5)
}

func defaultAttributes(_ foregroundColor: Color = .white) -> [NSAttributedString.Key: Any] {
    [
        .font: UIFont.body as Any,
        .foregroundColor: UIColor(foregroundColor)
    ]
}

func getAttributedString(from formattedText: FormattedText, _ foregroundColor: Color = .white) -> AttributedString {
    let attributedString = NSMutableAttributedString(
        string: formattedText.text,
        attributes: defaultAttributes(foregroundColor)
    )
    
    for entity in formattedText.entities {
        setEntity(entity, base: formattedText.text, for: attributedString)
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

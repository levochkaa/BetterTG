// MessageView+FormattedText.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder func formattedTextView(_ formattedText: FormattedText) -> some View {
        Text(attributedString(for: formattedText))
            .readSize { textSize = $0 }
            .overlay {
                if textSize != .zero {
                    LottieEmojis(
                        customEmojiAnimations: customMessage.customEmojiAnimations,
                        entities: formattedText.entities,
                        text: formattedText.text,
                        textSize: textSize
                    )
                }
            }
    }
    
    func attributedString(for formattedText: FormattedText) -> AttributedString {
        var result = AttributedString(formattedText.text)
        
        for entity in formattedText.entities {
            let stringRange = stringRange(for: formattedText.text, start: entity.offset, length: entity.length)
            let range = attributedStringRange(for: result, from: stringRange)
            let raw = String(formattedText.text[stringRange])
            
            switch entity.type {
                case .textEntityTypeBold:
                    result[range].font = .system(.body).bold()
                case .textEntityTypeItalic:
                    result[range].font = .system(.body).italic()
                case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
                    result[range].font = .system(.body).monospaced()
                case .textEntityTypeUnderline:
                    result[range].underlineStyle = .single
                case .textEntityTypeStrikethrough:
                    result[range].strikethroughStyle = .single
                case .textEntityTypePhoneNumber:
                    result[range].link = URL(string: "tel:\(raw)")
                case .textEntityTypeEmailAddress:
                    result[range].link = URL(string: "mailto:\(raw)")
                case .textEntityTypeUrl:
                    if hasWhitelistedPrefix(raw) {
                        result[range].link = URL(string: raw)
                    } else {
                        result[range].link = URL(string: "https://\(raw)")
                    }
                case .textEntityTypeTextUrl(let textEntityTypeTextUrl):
                    if hasWhitelistedPrefix(textEntityTypeTextUrl.url) {
                        result[range].link = URL(string: textEntityTypeTextUrl.url)
                    } else {
                        result[range].link = URL(string: "https://\(textEntityTypeTextUrl.url)")
                    }
                case .textEntityTypeCustomEmoji:
                    result[range].foregroundColor = .clear
                default:
                    log("Error, not implemented: \(entity.type); for: \(formattedText)")
            }
        }
        
        return result
    }
    
    func hasWhitelistedPrefix(_ url: String) -> Bool {
        url.hasPrefix("https://") || url.hasPrefix("http://") || url.hasPrefix("tg://")
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
    
    func attributedStringRange(
        for attrString: AttributedString,
        from stringRange: Range<String.Index>
    ) -> Range<AttributedString.Index> {
        let lowerBound = AttributedString.Index(stringRange.lowerBound, within: attrString)!
        let upperBound = AttributedString.Index(stringRange.upperBound, within: attrString)!
        return lowerBound..<upperBound
    }
}

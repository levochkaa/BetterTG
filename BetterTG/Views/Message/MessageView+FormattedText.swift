// MessageView+FormattedText.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder func formattedTextView(_ formattedText: FormattedText) -> some View {
        ZStack {
            Text(formattedText.text)
                .readSize { textSize = $0 }
                .opacity(0)
            
            Text(attributedString(for: formattedText))
                .frame(width: textSize.width, height: textSize.height, alignment: .top)
                .overlay {
                    if textSize != .zero {
                        LottieEmojis(
                            customEmojiAnimations: customMessage.customEmojiAnimations,
                            text: formattedText.text,
                            textSize: textSize
                        )
                        .allowsHitTesting(false)
                    }
                }
        }
    }
    
    func attributedString(for formattedText: FormattedText) -> AttributedString {
        var result = AttributedString(formattedText.text)
        var emojisProcessed = 0
        
        for entity in formattedText.entities {
            let offset = entity.offset + (emojisProcessed * 3)
            var range: Range<AttributedString.Index>
            if case .textEntityTypeCustomEmoji = entity.type {
                range = attributedStringRange(for: result, start: offset, length: entity.length - 1)
            } else {
                range = attributedStringRange(for: result, start: offset, length: entity.length)
            }
            
            let stringRange = stringRange(for: formattedText.text, start: entity.offset, length: entity.length)
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
                    let attrString = AttributedString("     ") // count = 5
                    result.replaceSubrange(range, with: attrString)
                    emojisProcessed += 1
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
        start: Int,
        length: Int
    ) -> Range<AttributedString.Index> {
        let startIndex = attrString.index(attrString.startIndex, offsetByCharacters: start)
        let endIndex = attrString.index(startIndex, offsetByCharacters: length)
        return startIndex..<endIndex
    }
}

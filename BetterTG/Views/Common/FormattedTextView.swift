// FormattedTextView.swift

import SwiftUI
import TDLibKit

struct FormattedTextView: View {
    
    @State var formattedText: FormattedText
    
    let logger = Logger("FormattedTextView")
    
    init(_ formattedText: FormattedText) {
        self._formattedText = State(initialValue: formattedText)
    }
    
    var attributedString: AttributedString {
        var result = AttributedString(formattedText.text)
        
        for entity in formattedText.entities {
            let stringRange = stringRange(for: formattedText.text, start: entity.offset, length: entity.length)
            let range = attributedStringRange(from: stringRange, for: result)
            let raw = String(formattedText.text[stringRange])
            let error = "Error, not implemented: \(entity.type); for: \(formattedText)"
            
            switch entity.type {
                case .textEntityTypeBold:
                    result[range].font = .system(.body).bold()
                case .textEntityTypeItalic:
                    result[range].font = .system(.body).italic()
                case .textEntityTypeCode:
                    result[range].font = .system(.body).monospaced()
                case .textEntityTypeUnderline:
                    result[range].underlineStyle = .single
                case .textEntityTypeStrikethrough:
                    result[range].strikethroughStyle = .single
                case .textEntityTypeUrl:
                    if !raw.hasPrefix("https://") || !raw.hasPrefix("http://") {
                        result[range].link = URL(string: "https://\(raw)")
                    } else {
                        result[range].link = URL(string: raw)
                    }
                case .textEntityTypePhoneNumber:
                    result[range].link = URL(string: "tel:\(raw)")
                case .textEntityTypeEmailAddress:
                    result[range].link = URL(string: "mailto:\(raw)")
                case .textEntityTypeTextUrl(let textEntityTypeTextUrl):
                    result[range].link = URL(string: textEntityTypeTextUrl.url)
                case .textEntityTypeHashtag:
                    logger.log(error)
                case .textEntityTypeMention:
                    logger.log(error)
                case .textEntityTypeSpoiler:
                    logger.log(error)
                case .textEntityTypeMediaTimestamp: // (let textEntityTypeMediaTimestamp)
                    logger.log(error)
                case .textEntityTypeMentionName: // (let textEntityTypeMentionName)
                    logger.log(error)
                case .textEntityTypeCustomEmoji: // (let textEntityTypeCustomEmoji)
                    logger.log(error)
                case .textEntityTypeBotCommand:
                    logger.log(error)
                case .textEntityTypeBankCardNumber:
                    logger.log(error)
                case .textEntityTypeCashtag:
                    logger.log(error)
                    
                // don't know what the hell is this
                case .textEntityTypePre, .textEntityTypePreCode: // (let textEntityTypePreCode)
                    break
            }
        }
        
        return result
    }
    
    var body: some View {
        Text(attributedString)
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
        from stringRange: Range<String.Index>,
        for attrString: AttributedString
    ) -> Range<AttributedString.Index> {
        let lowerBound = AttributedString.Index(stringRange.lowerBound, within: attrString)!
        let upperBound = AttributedString.Index(stringRange.upperBound, within: attrString)!
        return lowerBound..<upperBound
    }
}

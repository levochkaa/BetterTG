// Message+formattedText.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder func formattedTextView(_ formattedText: FormattedText) -> some View {
        ZStack {
            let attributedString = attributedString(for: formattedText)
            
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .readSize { draggableTextSize = $0 }
                .hidden()
            
            Text(attributedString)
                .fixedSize(horizontal: false, vertical: true)
                .readSize { textSize = $0 }
                .draggable(getDraggableString(from: attributedString)) {
                    Text(attributedString)
                        .frame(width: draggableTextSize.width, height: draggableTextSize.height)
                        .multilineTextAlignment(.leading)
                        .padding(8)
                        .foregroundColor(.white)
                        .background(.gray6)
                        .cornerRadius([.bottomLeft, .bottomRight, .topLeft, .topRight])
                }
                .overlay {
                    if textSize != .zero {
                        AnimojiView(
                            animojis: customMessage.animojis,
                            formattedText: formattedText,
                            textSize: textSize
                        )
                        .equatable()
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    messageDate
                        .menuOnPress { menu }
                        .offset(y: 3)
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
                    result[range].font = .body.bold()
                case .textEntityTypeItalic:
                    result[range].font = .body.italic()
                case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
                    result[range].font = .body.monospaced()
                case .textEntityTypeUnderline:
                    result[range].underlineStyle = .single
                case .textEntityTypeStrikethrough:
                    result[range].strikethroughStyle = .single
                case .textEntityTypePhoneNumber:
                    result[range].link = URL(string: "tel:\(raw)")
                case .textEntityTypeEmailAddress:
                    result[range].link = URL(string: "mailto:\(raw)")
                case .textEntityTypeUrl:
                    result[range].link = getUrl(from: raw)
                case .textEntityTypeTextUrl(let textEntityTypeTextUrl):
                    result[range].link = getUrl(from: textEntityTypeTextUrl.url)
                case .textEntityTypeCustomEmoji:
                    result[range].foregroundColor = .clear
                default:
//                    log("Error, not implemented: \(entity.type); for: \(formattedText)")
                    continue
            }
        }
        
        var dateAttributedString = AttributedString("000:00")
        let range = dateAttributedString.startIndex..<dateAttributedString.endIndex
        dateAttributedString[range].font = .caption
        dateAttributedString[range].foregroundColor = .gray6
        result.append(dateAttributedString)
        
        return result
    }
    
    func getUrl(from string: String) -> URL? {
        URL(string: string.contains("://") ? string : "https://\(string)")
    }
    
    @available(iOS 16.1, *)
    func getDraggableString(from attributedString: AttributedString) -> AttributedString {
        return attributedString
    }
    
    @available(iOS 16, *)
    func getDraggableString(from attributedString: AttributedString) -> String {
        return NSAttributedString(attributedString).string
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

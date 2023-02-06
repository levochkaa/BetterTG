// Message+formattedText.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder func formattedTextView(_ formattedText: FormattedText) -> some View {
        ZStack {
            Text(attributedString(for: formattedText))
                .fixedSize(horizontal: false, vertical: true)
                .readSize { textSize = $0 }
                .if(redactionReasons.isEmpty) {
                    $0.draggable(text) {
                        Text(attributedStringWithoutDate)
                            .frame(width: draggableTextSize.width, height: draggableTextSize.height)
                            .multilineTextAlignment(.leading)
                            .padding(8)
                            .foregroundColor(.white)
                            .background(.gray6)
                            .cornerRadius([.bottomLeft, .bottomRight, .topLeft, .topRight])
                    }
                }
                .overlay {
                    Text(attributedStringWithoutDate)
                        .fixedSize(horizontal: false, vertical: true)
                        .readSize { draggableTextSize = $0 }
                        .hidden()
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
                        .disabled(!redactionReasons.isEmpty)
                }
        }
    }
    
    func attributedString(for formattedText: FormattedText) -> AttributedString {
        var result = AttributedString(formattedText.text)
        var resultWithoutEmojis = AttributedString(formattedText.text)
        
        for entity in formattedText.entities {
            let stringRange = stringRange(for: formattedText.text, start: entity.offset, length: entity.length)
            let range = attributedStringRange(for: result, from: stringRange)
            let raw = String(formattedText.text[stringRange])
            
            switch entity.type {
                case .textEntityTypeBold:
                    result[range].font = .body.bold()
                    resultWithoutEmojis[range].font = .body.bold()
                case .textEntityTypeItalic:
                    result[range].font = .body.italic()
                    resultWithoutEmojis[range].font = .body.italic()
                case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
                    result[range].font = .body.monospaced()
                    resultWithoutEmojis[range].font = .body.monospaced()
                case .textEntityTypeUnderline:
                    result[range].underlineStyle = .single
                    resultWithoutEmojis[range].underlineStyle = .single
                case .textEntityTypeStrikethrough:
                    result[range].strikethroughStyle = .single
                    resultWithoutEmojis[range].strikethroughStyle = .single
                case .textEntityTypePhoneNumber:
                    result[range].link = URL(string: "tel://\(raw)")
                    resultWithoutEmojis[range].link = URL(string: "tel://\(raw)")
                case .textEntityTypeEmailAddress:
                    result[range].link = URL(string: "mailto://\(raw)")
                    resultWithoutEmojis[range].link = URL(string: "mailto://\(raw)")
                case .textEntityTypeUrl:
                    result[range].link = getUrl(from: raw)
                    resultWithoutEmojis[range].link = getUrl(from: raw)
                case .textEntityTypeTextUrl(let textEntityTypeTextUrl):
                    result[range].link = getUrl(from: textEntityTypeTextUrl.url)
                    resultWithoutEmojis[range].link = getUrl(from: textEntityTypeTextUrl.url)
                case .textEntityTypeCustomEmoji:
                    result[range].foregroundColor = .clear
                default:
//                    log("Error, not implemented: \(entity.type); for: \(formattedText)")
                    continue
            }
        }
        
        Task.main { [resultWithoutEmojis] in
            attributedStringWithoutDate = resultWithoutEmojis
        }
        
        var dateAttributedString = AttributedString(" 00:00")
        let range = dateAttributedString.startIndex..<dateAttributedString.endIndex
        dateAttributedString[range].font = .caption
        dateAttributedString[range].foregroundColor = .clear
        result.append(dateAttributedString)
        
        return result
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
    
    func attributedStringRange(
        for attrString: AttributedString,
        from stringRange: Range<String.Index>
    ) -> Range<AttributedString.Index> {
        let lowerBound = AttributedString.Index(stringRange.lowerBound, within: attrString)!
        let upperBound = AttributedString.Index(stringRange.upperBound, within: attrString)!
        return lowerBound..<upperBound
    }
}

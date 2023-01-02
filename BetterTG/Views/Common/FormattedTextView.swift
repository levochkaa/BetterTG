// FormattedTextView.swift

import SwiftUI
import TDLibKit

struct FormattedTextView: View {
    
    @State var formattedText: FormattedText
    @State var customMessage: CustomMessage
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    @State var shownText: AttributedString = ""
    @State var processedText = ""
    @State var pointText = ""
    
    let tdApi: TdApi = .shared
    let logger = Logger("FormattedTextView")
    let nc: NotificationCenter = .default
    
    init(_ formattedText: FormattedText, from customMessage: CustomMessage) {
        self._formattedText = State(initialValue: formattedText)
        self._customMessage = State(initialValue: customMessage)
        self._processedText = State(initialValue: formattedText.text)
        self._pointText = State(initialValue: formattedText.text)
    }
    
    func attributedString() -> AttributedString {
        var result = AttributedString(processedText)
        var emojisProcessed = 0
        
        for entity in formattedText.entities {
            let offset = entity.offset + (emojisProcessed * 3)
            let stringRange = stringRange(for: processedText, start: entity.offset, length: entity.length)
            var range = attributedStringRange(for: result, start: offset, length: entity.length)
            let raw = String(processedText[stringRange])
            let error = "Error, not implemented: \(entity.type); for: \(formattedText)"
            
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
                case .textEntityTypeUrl:
                    if hasWhitelistedPrefix(raw) {
                        result[range].link = URL(string: raw)
                    } else {
                        result[range].link = URL(string: "https://\(raw)")
                    }
                case .textEntityTypePhoneNumber:
                    result[range].link = URL(string: "tel:\(raw)")
                case .textEntityTypeEmailAddress:
                    result[range].link = URL(string: "mailto:\(raw)")
                case .textEntityTypeTextUrl(let textEntityTypeTextUrl):
                    if hasWhitelistedPrefix(textEntityTypeTextUrl.url) {
                        result[range].link = URL(string: textEntityTypeTextUrl.url)
                    } else {
                        result[range].link = URL(string: "https://\(textEntityTypeTextUrl.url)")
                    }
                case .textEntityTypeCustomEmoji: // (let textEntityTypeCustomEmoji)
                    range = attributedStringRange(for: result, start: offset, length: entity.length - 1)
                    let attrString = AttributedString("     ") // count = 5
                    result.replaceSubrange(range, with: attrString)
                    emojisProcessed += 1
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
                case .textEntityTypeBotCommand:
                    logger.log(error)
                case .textEntityTypeBankCardNumber:
                    logger.log(error)
                case .textEntityTypeCashtag:
                    logger.log(error)
            }
        }
        
        processedText = NSMutableAttributedString(result).string
        return result
    }
    
    var body: some View {
        Text(shownText)
            .overlay {
                LottieEmojis(
                    customEmojiAnimations: customMessage.customEmojiAnimations,
                    text: pointText
                )
//                ForEach(customMessage.customEmojiAnimations) { customEmojiAnimation in
//                    LottieEmoji(
//                        customEmojiAnimation: customEmojiAnimation,
//                        pointText: $pointText
//                    )
//                    .onAppear {
//                        logger.log("appeared \(customEmojiAnimation.realEmoji)")
//                    }
//                }
                    .allowsHitTesting(false)
            }
            .onAppear {
                shownText = attributedString()
            }
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

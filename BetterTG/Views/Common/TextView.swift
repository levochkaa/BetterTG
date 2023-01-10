// TextView.swift

import SwiftUI
import TDLibKit
import Lottie

struct TextView: UIViewRepresentable {
    
    let formattedText: FormattedText
    let customEmojiAnimations: [CustomEmojiAnimation]
    let textSize: CGSize
    
    func makeUIView(context: Context) -> UITextView {
        let frame = CGRect(origin: CGPoint(x: 0, y: 0), size: textSize)
        let textView = UITextView(frame: frame)
        textView.font = Font.body.toUIFont()
        textView.backgroundColor = UIColor.systemGray6
        textView.isScrollEnabled = false
        textView.dataDetectorTypes = .all
        textView.isEditable = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        
        let attributedText = NSMutableAttributedString(string: formattedText.text, attributes: [
            .font: Font.body.toUIFont() as Any,
            .foregroundColor: UIColor.white
        ])
        
        var emojiIndex = 0
        
        for entity in formattedText.entities {
            let range = NSRange(location: entity.offset, length: entity.length)
            let stringRange = stringRange(for: formattedText.text, start: entity.offset, length: entity.length)
            let raw = String(formattedText.text[stringRange])
            
            switch entity.type {
                case .textEntityTypeBold:
                    attributedText.addAttribute(.font, value: Font.body.bold().toUIFont() as Any, range: range)
                case .textEntityTypeItalic:
                    attributedText.addAttribute(.font, value: Font.body.italic().toUIFont() as Any, range: range)
                case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
                    attributedText.addAttribute(.font, value: Font.body.monospaced().toUIFont() as Any, range: range)
                case .textEntityTypeUnderline:
                    attributedText.addAttribute(.underlineStyle, value: 1, range: range)
                case .textEntityTypeStrikethrough:
                    attributedText.addAttribute(.strikethroughStyle, value: 1, range: range)
                case .textEntityTypePhoneNumber:
                    attributedText.addAttribute(.link, value: URL(string: "tel:\(raw)") as Any, range: range)
                case .textEntityTypeEmailAddress:
                    attributedText.addAttribute(.link, value: URL(string: "mailto:\(raw)") as Any, range: range)
                case .textEntityTypeUrl:
                    attributedText.addAttribute(
                        .link,
                        value: URL(string: whitelisted(raw) ? raw : "https://\(raw)") as Any,
                        range: range
                    )
                case .textEntityTypeTextUrl(let textUrl):
                    attributedText.addAttribute(
                        .link,
                        value: URL(string: whitelisted(textUrl.url) ? textUrl.url : "https://\(textUrl.url)") as Any,
                        range: range
                    )
                case .textEntityTypeCustomEmoji: // (let textEntityTypeCustomEmoji)
                    // because of crash on messages with unsupported emojis
                    if emojiIndex >= customEmojiAnimations.count { break }
                    
                    textView.attributedText = attributedText
                    
                    let glyphIndex = textView.layoutManager.glyphIndexForCharacter(
                        at: entity.offset + entity.length - 1
                    )
                    
                    var rangeOfCharacter = NSRange()
                    textView.layoutManager.characterRange(
                        forGlyphRange: NSRange(location: glyphIndex, length: 1),
                        actualGlyphRange: &rangeOfCharacter
                    )
                    
                    var point = textView.layoutManager.boundingRect(
                        forGlyphRange: rangeOfCharacter,
                        in: textView.textContainer
                    ).origin
                    point.y -= 1.5
                    
                    let animationView = LottieAnimationView(
                        animation: customEmojiAnimations[emojiIndex].lottieAnimation
                    )
                    animationView.loopMode = .loop
                    animationView.contentMode = .scaleAspectFit
                    animationView.frame = CGRect(origin: point, size: CGSize(width: 24, height: 24))
                    animationView.play()
                    
                    emojiIndex += 1
                    
                    attributedText.replaceCharacters(in: range,
                                                     with: NSAttributedString(string: "  ", attributes: [.kern: 8]))
                    
                    textView.addSubview(animationView)
                default:
                    break
            }
        }
        
        textView.attributedText = attributedText
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        //
    }
    
    func whitelisted(_ url: String) -> Bool {
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
}

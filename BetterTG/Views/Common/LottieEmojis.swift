// LottieEmojis.swift

import SwiftUI
import TDLibKit
import Lottie

struct LottieEmojis: UIViewRepresentable {
    
    let customEmojiAnimations: [CustomEmojiAnimation]
    let entities: [TextEntity]
    let text: String
    let textSize: CGSize
    
    func makeUIView(context: Context) -> UIView {
        let frame = CGRect(origin: CGPoint(x: 0, y: 0), size: textSize)
        let view = UIView(frame: frame)
        var emojiIndex = 0
        let filteredEntities = entities.filter {
            if case .textEntityTypeCustomEmoji = $0.type {
                return true
            }
            return false
        }
        
        for customEmojiAnimation in customEmojiAnimations {
            let textView = UITextView(frame: frame)
            textView.text = text
            textView.font = Font.body.toUIFont()
            textView.isScrollEnabled = false
            textView.dataDetectorTypes = .all
            textView.isEditable = false
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textView.textContainer.lineFragmentPadding = 0
            textView.textContainerInset = .zero
            
            let entity = filteredEntities[emojiIndex]
            
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
            
            let animationView = LottieAnimationView(animation: customEmojiAnimation.lottieAnimation)
            animationView.loopMode = .loop
            animationView.contentMode = .scaleAspectFit
            animationView.frame = CGRect(origin: point, size: CGSize(width: 24, height: 24))
            animationView.play()
            
            emojiIndex += 1
            
            view.addSubview(animationView)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

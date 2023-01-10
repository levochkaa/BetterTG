// LottieEmojis.swift

import SwiftUI
import TDLibKit
import Lottie

struct LottieEmojis: UIViewRepresentable {
    
    let customEmojiAnimations: [CustomEmojiAnimation]
    let text: String
    let textSize: CGSize
    
    func makeUIView(context: Context) -> UIView {
        let frame = CGRect(origin: CGPoint(x: 0, y: 0), size: textSize)
        let view = UIView(frame: frame)
        var text = self.text
        
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
            
            guard let (index, character) = text.enumerated().first(where: { $1.isEmoji }) else {
                log("Error getting index and character from text: \(text)")
                continue
            }
            
            let glyphIndex = textView.layoutManager.glyphIndexForCharacter(
                at: index // entity.offset + entity.length - 1
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
            
            guard let characterRange = text.range(of: String(character)) else {
                log("Error getting characterRange: \(character); \(text)")
                continue
            }
            
            text.replaceSubrange(characterRange, with: "     ") // count = 5
            view.addSubview(animationView)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

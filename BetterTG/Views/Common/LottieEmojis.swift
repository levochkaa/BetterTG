// LottieEmojis.swift

import SwiftUI
import Lottie

struct LottieEmojis: UIViewRepresentable {
    
    let customEmojiAnimations: [CustomEmojiAnimation]
    let text: String
    let textSize: CGSize
    
    func makeUIView(context: Context) -> UIView {
        var frame = CGRect(x: 0, y: 0, width: textSize.width + 20, height: textSize.height)
        let view = UIView(frame: frame)
        var text = self.text
        for customEmojiAnimation in customEmojiAnimations {
            let textView = UITextView(frame: frame)
            textView.text = text
            textView.font = Font.body.toUIFont()
            
            guard let (index, character) = text.enumerated().first(where: { $1.isEmoji }) else {
                log("Error getting index and character from text: \(text)")
                continue
            }
            
            let textArray = Array(text)
            var emojiLine: CGFloat = 0
            var indexLine = 0
            textView.layoutManager.enumerateLineFragments(
                forGlyphRange: NSRange(location: 0, length: textView.layoutManager.numberOfGlyphs)
            ) { _, _, _, range, _ in
                for i in 0...(range.index() - range.location) {
                    if range.index() - i < textArray.count && textArray[range.location...range.index() - i]
                        .contains(character) {
                        emojiLine = CGFloat(indexLine)
                        return
                    }
                }
                indexLine += 1
            }
            let point = textView.layoutManager.location(forGlyphAt: index)
            let resultPoint = CGPoint(x: point.x - 5, y: -1.3 + emojiLine * 22) // just random numbers
            
            let animationView = LottieAnimationView(animation: customEmojiAnimation.lottieAnimation)
            animationView.loopMode = .loop
            animationView.contentMode = .scaleAspectFit
            animationView.frame = CGRect(origin: resultPoint, size: CGSize(width: 24, height: 24))
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

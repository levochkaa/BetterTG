// LottieEmojis.swift

import SwiftUI
import Lottie

struct LottieEmojis: UIViewRepresentable {
    
    let customEmojiAnimations: [CustomEmojiAnimation]
    let text: String
    let textSize: CGSize
    
    // swiftlint:disable function_body_length
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        var text = self.text
        var newSize = textSize
        newSize.width += 20
        for customEmojiAnimation in customEmojiAnimations {
            let textView = UITextView()
            textView.frame = CGRect(origin: CGPoint(x: 0, y: 0), size: newSize)
            textView.text = text
            textView.font = Font.body.toUIFont()
            
            guard let (index, character) = text.enumerated().first(where: { $1.isEmoji }) else {
                log("Error getting index and character from text: \(text)")
                continue
            }
            
            var lines = [NSRange]()
            for glyphIndex in 0..<textView.layoutManager.numberOfGlyphs {
                var effectiveRange = NSRange()
                textView.layoutManager.lineFragmentUsedRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: &effectiveRange
                )
                
                let location = effectiveRange.location
                var length = effectiveRange.length
                
                if location + length <= text.count, Array(text)[location..<(location + length)].contains("\n") {
                    length -= 1
                }
                
                let range = NSRange(location: location, length: length)
                if !lines.contains(range) { lines.append(range) }
            }
            
            let textArray = Array(text)
            var emojiLine: CGFloat = 0
            for (index, line) in lines.enumerated() {
                for i in 0...(line.index() - line.location) {
                    if line.index() - i < textArray.count && textArray[line.location...line.index() - i]
                        .contains(character) {
                        emojiLine = CGFloat(index)
                    }
                }
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

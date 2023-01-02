// LottieEmojis.swift

import SwiftUI
import Lottie

extension Character {
    /// A simple emoji is one scalar and presented to the user as an Emoji
    var isSimpleEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        return firstScalar.properties.isEmoji && firstScalar.value > 0x238C
    }
    
    /// Checks if the scalars will be merged into an emoji
    var isCombinedIntoEmoji: Bool { unicodeScalars.count > 1 && unicodeScalars.first?.properties.isEmoji ?? false }
    
    /// Checks if the Character is Emoji
    var isEmoji: Bool { isSimpleEmoji || isCombinedIntoEmoji }
}

extension String {
    var isSingleEmoji: Bool { count == 1 && containsEmoji }
    
    var containsEmoji: Bool { contains { $0.isEmoji } }
    
    var containsOnlyEmoji: Bool { !isEmpty && !contains { !$0.isEmoji } }
    
    var emojiString: String { emojis.map { String($0) }.reduce("", +) }
    
    var emojis: [Character] { filter { $0.isEmoji } }
    
    var emojiScalars: [UnicodeScalar] { filter { $0.isEmoji }.flatMap { $0.unicodeScalars } }
}

struct LottieEmojis: UIViewRepresentable {
    
    let customEmojiAnimations: [CustomEmojiAnimation]
    let text: String
    
    let logger = Logger("LottieEmoji")
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        
        var text = self.text
        for customEmojiAnimation in customEmojiAnimations {
            let textView = UITextView()
            textView.text = text
            textView.font = Font.body.toUIFont()
            
            var index = 0
            var character: Character = " "
            for (i, char) in text.enumerated() where char.isEmoji {
                index = i
                character = char
                break
            }
            
            var lines = [NSRange]()
            for glyphIndex in 0..<textView.layoutManager.numberOfGlyphs {
                var effectiveRange = NSRange()
                textView.layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
                let location = effectiveRange.location
                var length = effectiveRange.length
                if location + length <= text.count,
                   Array(text)[location..<(location + length)].contains("\n") {
                    length -= 1
                }
                if !lines.contains(where: { $0.location == location && $0.length == length }) {
                    lines.append(NSRange(location: location, length: length))
                }
            }
            
            var emojiLine: CGFloat = 0.0
            for (index, line) in lines.enumerated() {
                if line.location + line.length <= text.count,
                   Array(text)[line.location..<(line.location + line.length)].contains(character) {
                    emojiLine = CGFloat(index)
                    break
                }
            }
            
            let point = textView.layoutManager.location(forGlyphAt: index)
            let resultPoint = CGPoint(x: point.x - 5, y: -1.3 + emojiLine * 22)
            
            let animationView = LottieAnimationView(animation: customEmojiAnimation.lottieAnimation)
            animationView.loopMode = .loop
            animationView.contentMode = .scaleAspectFit
            animationView.frame = CGRect(origin: resultPoint, size: CGSize(width: 24, height: 24))
            animationView.play()
            text.replaceSubrange(text.range(of: String(character))!, with: "     ")
            view.addSubview(animationView)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

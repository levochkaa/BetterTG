// AnimojiView.swift

import SwiftUI
import TDLibKit
import Lottie
import Gzip
import MobileVLCKit
import SDWebImage

struct AnimojiView: UIViewRepresentable {
    
    let animojis: [Animoji]
    let formattedText: FormattedText
    let textSize: CGSize
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        loadEmojis(for: view, isInit: true)
        return view
    }
    
    func loadEmojis(for view: UIView, isInit: Bool = false) {
        let frame = CGRect(origin: CGPoint(x: 0, y: 0), size: textSize)
        view.frame = frame
        
        var emojiIndex = 0
        let filteredEntities = formattedText.entities.filter {
            if case .textEntityTypeCustomEmoji = $0.type { return true }
            return false
        }
        
        let textView = UITextView(frame: frame)
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.text = formattedText.text
        textView.isScrollEnabled = false
        textView.dataDetectorTypes = .all
        textView.isEditable = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        
        for animoji in animojis {
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
            
            let frame = CGRect(origin: point, size: CGSize(width: 24, height: 24))
            
            if isInit {
                renderAnimoji(animoji, for: view, with: frame)
            } else {
                UIView.animate(withDuration: Utils.defaultAnimationDuration) {
                    view.subviews[emojiIndex].frame = frame
                }
            }
            
            emojiIndex += 1
        }
    }
    
    func renderAnimoji(_ animoji: Animoji, for view: UIView, with frame: CGRect) {
        switch animoji.type {
            case .webp(let url):
                let webpUiImageView = UIImageView(frame: frame)
                webpUiImageView.sd_setImage(with: url)
                view.addSubview(webpUiImageView)
            case .webm(let url): // sometimes working, sometimes don't, when works, it's awful
                let webmUiView = UIView(frame: frame)
                let media = VLCMedia(url: url)

                let mediaList = VLCMediaList()
                mediaList.add(media)

                let mediaListPlayer = VLCMediaListPlayer(drawable: webmUiView)
                mediaListPlayer.mediaList = mediaList
                
                mediaListPlayer.repeatMode = .repeatCurrentItem
                mediaListPlayer.play(media)
                
                view.addSubview(webmUiView)
            case .tgs(let url):
                do {
                    let data = try Data(contentsOf: url)
                    let decompressed = try data.gunzipped()
                    let animation = try LottieAnimation.from(data: decompressed)
                    let animationView = LottieAnimationView(animation: animation)
                    
                    animationView.loopMode = .loop
                    animationView.contentMode = .scaleAspectFit
                    animationView.frame = frame
                    animationView.play()
                    
                    view.addSubview(animationView)
                } catch {
                    log("Error loading custom emoji animation (tgs): \(error)")
                }
        }
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        loadEmojis(for: uiView)
    }
}

extension AnimojiView: Equatable {
    static func == (lhs: AnimojiView, rhs: AnimojiView) -> Bool {
        lhs.textSize == rhs.textSize
    }
}

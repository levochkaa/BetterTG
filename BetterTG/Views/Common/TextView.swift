// TextView.swift

import TDLibKit
import Lottie
import Gzip
import MobileVLCKit
import SDWebImage

struct TextView: View {
    @State var formattedText: FormattedText
    var appendingDate: Bool = false
    
    var body: some View {
        _TextView(formattedText: formattedText)
            .frame(size: getTextViewSize(for: formattedText, appendingDate: appendingDate))
    }
    
    /// SwiftUI is fucked.
    func getTextViewSize(for formattedText: FormattedText, appendingDate: Bool) -> CGSize {
        let attributedString = NSMutableAttributedString(getAttributedString(from: formattedText))
        if appendingDate {
            attributedString.append(NSAttributedString(string: " 00:00", attributes: [.font: UIFont.caption as Any]))
        }
        let textStorage = NSTextStorage(attributedString: attributedString)
        let size = CGSize(width: Utils.maxMessageContentWidth, height: .greatestFiniteMagnitude)
        let boundingRect = CGRect(origin: .zero, size: size)
        let textContainer = NSTextContainer(size: size)
        textContainer.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.glyphRange(forBoundingRect: boundingRect, in: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)
        return rect.integral.size
    }
}

private struct _TextView: UIViewRepresentable {
    
    let formattedText: FormattedText
    
//    @AppStorage("showAnimojis") var showAnimojis = true
    
    var filteredEntities: [TextEntity] {
        formattedText.entities
            .filter {
                if case .textEntityTypeCustomEmoji = $0.type { return true }
                return false
            }
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: false)
        textView.font = .body
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.dataDetectorTypes = .all
        textView.isEditable = false
        textView.isSelectable = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        setText(textView, isInit: true)
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.attributedText != NSAttributedString(string: formattedText.text) {
            setText(textView, isInit: false)
        }
    }
    
    func setText(_ textView: UITextView, isInit: Bool) {
        let attributedString = NSMutableAttributedString(
            string: formattedText.text,
            attributes: defaultAttributes
        )
        
        for entity in formattedText.entities {
            setEntity(entity, base: formattedText.text, for: attributedString)
        }
        
        let dateAttributedString = NSMutableAttributedString(
            string: " 00:00",
            attributes: [
                .font: UIFont.caption,
                .foregroundColor: UIColor.clear
            ]
        )
        attributedString.append(dateAttributedString)
        
        textView.attributedText = attributedString
        
//        if showAnimojis {
//            Task { @MainActor in
//                setAnimojis(textView, isInit: isInit)
//            }
//        }
    }
    
//    @State var shouldSetAnimojis = true
//    
//    func setAnimojis(_ textView: UITextView, isInit: Bool) {
//        guard shouldSetAnimojis else { return }
//        shouldSetAnimojis = false
//        Task {
//            let animojis = await viewModel.getAnimojis(from: formattedText.entities)
//            await MainActor.run {
//                var emojiIndex = 0
//                animojis.forEach { animoji in
//                    let entity = filteredEntities[emojiIndex]
//                    let frame = getFrame(textView, from: entity)
//                    renderAnimoji(textView, animoji: animoji, with: frame)
////                    if isInit {
////                        renderAnimoji(textView, animoji: animoji, with: frame)
////                    } else {
////                        UIView.animate(withDuration: Utils.defaultAnimationDuration) {
////                            textView.subviews[emojiIndex].frame = frame
////                        }
////                    }
//                    emojiIndex += 1
//                }
//                shouldSetAnimojis = true
//            }
//        }
//    }
    
//    func renderAnimoji(_ textView: UIView, animoji: Animoji, with frame: CGRect) {
//        switch animoji.type {
//            case .webp(let url):
//                let webpUiImageView = UIImageView(frame: frame)
//                webpUiImageView.sd_setImage(with: url)
//                textView.addSubview(webpUiImageView)
//            case .webm(let url): // sometimes working, sometimes don't, when works, it's awful
//                let webmUiView = UIView(frame: frame)
//                let media = VLCMedia(url: url)
//                
//                let mediaList = VLCMediaList()
//                mediaList.add(media)
//                
//                let mediaListPlayer = VLCMediaListPlayer(drawable: webmUiView)
//                mediaListPlayer.mediaList = mediaList
//                
//                mediaListPlayer.repeatMode = .repeatCurrentItem
//                mediaListPlayer.play(media)
//                
//                textView.addSubview(webmUiView)
//            case .tgs(let url):
//                do {
//                    let data = try Data(contentsOf: url)
//                    let decompressed = try data.gunzipped()
//                    let animation = try LottieAnimation.from(data: decompressed)
//                    let animationView = LottieAnimationView(animation: animation)
//                    
//                    animationView.loopMode = .loop
//                    animationView.contentMode = .scaleAspectFit
//                    animationView.frame = frame
//                    animationView.play()
//                    
//                    textView.addSubview(animationView)
//                } catch {
//                    log("Error loading custom emoji animation (tgs): \(error)")
//                }
//        }
//    }
    
//    func getFrame(_ textView: UITextView, from entity: TextEntity) -> CGRect {
//        let glyphIndex = textView.layoutManager.glyphIndexForCharacter(
//            at: entity.offset + entity.length - 1
//        )
//        
//        var rangeOfCharacter = NSRange()
//        textView.layoutManager.characterRange(
//            forGlyphRange: NSRange(location: glyphIndex, length: 1),
//            actualGlyphRange: &rangeOfCharacter
//        )
//        
//        var point = textView.layoutManager.boundingRect(
//            forGlyphRange: rangeOfCharacter,
//            in: textView.textContainer
//        ).origin
//        point.y -= 1.5
//        
//        return CGRect(origin: point, size: CGSize(width: 24, height: 24))
//    }
}

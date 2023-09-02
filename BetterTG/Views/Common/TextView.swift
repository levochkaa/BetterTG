// TextView.swift

import TDLibKit
import Lottie
import Gzip
import MobileVLCKit
import SDWebImage

struct TextView: UIViewRepresentable {
    
    let formattedText: FormattedText
    
    @Environment(ChatViewModel.self) var viewModel
    
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
            attributes: [
                .font: UIFont.body as Any,
                .foregroundColor: UIColor.white
            ]
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

func getAttributedString(from formattedText: FormattedText) -> AttributedString {
    let attributedString = NSMutableAttributedString(
        string: formattedText.text,
        attributes: [
            .font: UIFont.body as Any,
            .foregroundColor: UIColor.white
        ]
    )
    
    for entity in formattedText.entities {
        setEntity(entity, base: formattedText.text, for: attributedString)
    }
    
    return AttributedString(attributedString)
}

func setEntity(_ entity: TextEntity, base text: String, for attributedString: NSMutableAttributedString) {
    let range = NSRange(location: entity.offset, length: entity.length)
    let stringRange = stringRange(for: text, start: entity.offset, length: entity.length)
    let raw = String(text[stringRange])
    
    switch entity.type {
        case .textEntityTypeBold:
            attributedString.addAttribute(.font, value: UIFont.bold, range: range)
        case .textEntityTypeItalic:
            attributedString.addAttribute(.font, value: UIFont.italic, range: range)
        case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
            attributedString.addAttribute(.font, value: UIFont.monospaced, range: range)
        case .textEntityTypeUnderline:
            attributedString.addAttribute(.underlineStyle, value: 1, range: range)
        case .textEntityTypeStrikethrough:
            attributedString.addAttribute(.strikethroughStyle, value: 1, range: range)
        case .textEntityTypePhoneNumber:
            attributedString.addAttribute(.link, value: URL(string: "tel://\(raw)") as Any, range: range)
        case .textEntityTypeEmailAddress:
            attributedString.addAttribute(.link, value: URL(string: "mailto://\(raw)") as Any, range: range)
        case .textEntityTypeUrl:
            attributedString.addAttribute(.link, value: getUrl(from: raw) as Any, range: range)
        case .textEntityTypeTextUrl(let textUrl):
            attributedString.addAttribute(.link, value: getUrl(from: textUrl.url) as Any, range: range)
        case .textEntityTypeSpoiler:
            attributedString.addAttribute(.backgroundColor, value: UIColor.gray, range: range)
//        case .textEntityTypeCustomEmoji: // (let textEntityTypeCustomEmoji)
//            guard showAnimojis else { break }
//            attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
        default:
            break
    }
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

// TextView.swift

import TDLibKit
import Lottie
import Gzip
import MobileVLCKit
import SDWebImage

struct TextView: UIViewRepresentable {
    
    let formattedText: FormattedText
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: false)
        textView.font = .body
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.isEditable = false
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
        let attributedString = NSMutableAttributedString(getAttributedString(from: formattedText))
        let dateAttributedString = NSMutableAttributedString(
            string: " 00:00",
            attributes: [
                .font: UIFont.caption,
                .foregroundColor: UIColor.clear
            ]
        )
        attributedString.append(dateAttributedString)
        textView.attributedText = attributedString
    }
}

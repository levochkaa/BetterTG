// MessageTextView.swift

import SwiftUI
import TDLibKit

struct MessageTextView: View {
    @State var formattedText: FormattedText
    @State var size: CGSize
    
    var body: some View {
        TextView(formattedText: formattedText)
            .frame(size: size)
    }
}

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
        setText(textView)
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.attributedText != NSAttributedString(string: formattedText.text) {
            setText(textView)
        }
    }
    
    func setText(_ textView: UITextView) {
        textView.attributedText = NSMutableAttributedString(getAttributedString(from: formattedText))
    }
}

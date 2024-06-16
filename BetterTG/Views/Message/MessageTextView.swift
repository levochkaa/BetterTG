// MessageTextView.swift

import SwiftUI
import TDLibKit

var cachedTextSizes: [FormattedText: CGSize] = [:]

struct MessageTextView: View {
    let formattedText: FormattedText
    
    var body: some View {
        TextView(formattedText: formattedText)
            .frame(size: size(for: formattedText))
    }
    
    private func size(for formattedText: FormattedText) -> CGSize {
        if let cached = cachedTextSizes[formattedText] { return cached }
        let attributedString = NSMutableAttributedString(getAttributedString(from: formattedText))
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
        let result = rect.integral.size
        cachedTextSizes[formattedText] = result
        return result
    }
}

struct TextView: UIViewRepresentable {
    let formattedText: FormattedText
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
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
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        func textViewDidChangeSelection(_ textView: UITextView) {
            textView.selectedTextRange = nil
        }
    }
}

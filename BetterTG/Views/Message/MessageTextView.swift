// MessageTextView.swift

import SwiftUI
import TDLibKit

var cachedTextSizes = [FormattedText: CGSize]()

// MARK: - MessageTextView

struct MessageTextView: View {
    // MARK: Internal

    let formattedText: FormattedText
    
    var body: some View {
        TextView(formattedText: formattedText)
            .frame(size: size(for: formattedText))
    }
    
    // MARK: Private

    private func size(for formattedText: FormattedText) -> CGSize {
        if let cached = cachedTextSizes[formattedText] { return cached }
        let attributedString = NSMutableAttributedString(getAttributedString(from: formattedText, withDate: true))
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

// MARK: - TextView

struct TextView: UIViewRepresentable {
    // MARK: Internal

    final class Coordinator: NSObject, UITextViewDelegate {
        // MARK: Lifecycle

        init(textView: UITextView, formattedText: FormattedText) {
            self.textView = textView
            self.formattedText = formattedText
        }
        
        // MARK: Internal

        let textView: UITextView
        let formattedText: FormattedText
        
        lazy var layoutManager: NSLayoutManager = {
            let layoutManager = NSLayoutManager()
            layoutManager.addTextContainer(textContainer)
            return layoutManager
        }()
        
        lazy var textStorage: NSTextStorage = {
            let textStorage = NSTextStorage()
            textStorage.addLayoutManager(layoutManager)
            return textStorage
        }()
        
        lazy var textContainer: NSTextContainer = {
            let textContainer = NSTextContainer()
            textContainer.lineFragmentPadding = textView.textContainer.lineFragmentPadding
            textContainer.lineBreakMode = textView.textContainer.lineBreakMode
            textContainer.maximumNumberOfLines = textView.textContainer.maximumNumberOfLines
            return textContainer
        }()
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            textView.selectedTextRange = nil
        }
        
        @objc func handleTap(_ tapGesture: UITapGestureRecognizer) {
            let text = formattedText.text
            for entity in formattedText.entities {
                let range = NSRange(location: entity.offset, length: entity.length)
                switch entity.type {
                case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
                    if didTap(tapGesture: tapGesture, range: range) {
                        let stringRange = stringRange(for: text, start: entity.offset, length: entity.length)
                        UIPasteboard.setPlainText(String(text[stringRange]))
                    }
                default:
                    continue
                }
            }
        }
        
        /// https://stackoverflow.com/a/62169577/15055547
        func didTap(tapGesture: UITapGestureRecognizer, range: NSRange) -> Bool {
            textStorage.setAttributedString(textView.attributedText!)
            let labelSize = textView.bounds.size
            textContainer.size = labelSize
            let locationOfTouch = tapGesture.location(in: textView)
            let textBoundingBox = layoutManager.usedRect(for: textContainer)
            let textContainerOffset = CGPoint(
                x: (labelSize.width - textBoundingBox.size.width) * 0.5 - textBoundingBox.origin.x,
                y: (labelSize.height - textBoundingBox.size.height) * 0.5 - textBoundingBox.origin.y,
            )
            let locationOfTouchInTextContainer = CGPoint(
                x: locationOfTouch.x - textContainerOffset.x,
                y: locationOfTouch.y - textContainerOffset.y,
            )
            let indexOfCharacter = layoutManager.characterIndex(
                for: locationOfTouchInTextContainer,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil,
            )
            return range.contains(indexOfCharacter)
        }
    }

    let formattedText: FormattedText

    func makeUIView(context: Context) -> UITextView {
        textView.delegate = context.coordinator
        textView.font = .body
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        setText(textView)
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(context.coordinator.handleTap),
        )
        textView.addGestureRecognizer(tapGesture)
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context _: Context) {
        if textView.attributedText != formattedText.withDate {
            setText(textView)
        }
    }
    
    func setText(_ textView: UITextView) {
        textView.attributedText = NSMutableAttributedString(getAttributedString(from: formattedText, withDate: true))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(textView: textView, formattedText: formattedText)
    }
    
    // MARK: Private

    @State private var textView = UITextView(usingTextLayoutManager: false)
}

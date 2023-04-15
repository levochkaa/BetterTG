// MessageView+FormattedText.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder func formattedTextView(_ formattedText: FormattedText) -> some View {
        if isPreview {
            Text(formattedText.text)
                .fixedSize(horizontal: false, vertical: true)
                .readSize { textSize = $0 }
        } else if !redactionReasons.isEmpty {
            Text(formattedText.text)
                .fixedSize(horizontal: false, vertical: true)
                .readSize { textSize = $0 }
        } else {
            TextView(formattedText: formattedText)
                .frame(size: getTextViewSize(for: formattedText.text))
                .overlay(alignment: .bottomTrailing) {
                    messageDate
                        .offset(y: 3)
                }
        }
    }
    
    /// SwiftUI is fucked.
    private func getTextViewSize(for text: String) -> CGSize {
        let textStorage = NSTextStorage(
            attributedString: NSAttributedString(
                string: text + " 00:00",
                attributes: [NSAttributedString.Key.font: UIFont.body as Any]
            )
        )
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

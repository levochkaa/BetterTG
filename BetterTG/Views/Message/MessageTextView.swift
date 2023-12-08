// MessageTextView.swift

import SwiftUI
import TDLibKit

struct MessageTextView: View {
    @State var formattedText: FormattedText
    @State private var dynamicHeight: CGFloat = 0
    
    var body: some View {
        TextView(formattedText: formattedText)
            .frame(size: size)
    }
    
    var size: CGSize {
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
        return rect.integral.size
    }
}

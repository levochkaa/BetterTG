// MessageView.swift

import SwiftUI
import TDLibKit

struct MessageView: View {
    
    @Binding var customMessage: CustomMessage
    let isOutgoing: Bool
    
    init(customMessage: Binding<CustomMessage>) {
        self._customMessage = customMessage
        self.isOutgoing = customMessage.wrappedValue.message.isOutgoing
    }
    
    @Environment(ChatViewModel.self) var viewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let forwardedFrom = customMessage.forwardedFrom {
                ForwardedFromView(name: forwardedFrom)
            }
            
            if customMessage.replyUser != nil, customMessage.replyToMessage != nil {
                ReplyMessageView(customMessage: $customMessage, type: .replied)
            }
            
            MessageContentView(customMessage: $customMessage)
            
            if let formattedText = customMessage.formattedText {
                MessageTextView(formattedText: formattedText, size: size(for: formattedText))
                    .padding(8)
            }
        }
        .background(.gray6)
        .cornerRadius(20)
        .contextMenu { contextMenu }
    }
    
    func size(for formattedText: FormattedText) -> CGSize {
        if let cached = viewModel.cachedTextSizes[formattedText] { return cached }
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
        viewModel.cachedTextSizes[formattedText] = result
        return result
    }
}

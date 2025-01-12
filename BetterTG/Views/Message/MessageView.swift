// MessageView.swift

import SwiftUI
import TDLibKit

struct MessageView: View {
    @Binding var customMessage: CustomMessage
    @Binding var highlightedMessageId: Int64?
    @Binding var replyMessage: CustomMessage?
    @Binding var editCustomMessage: CustomMessage?
    let scrollTo: (Int64) -> Void
    let deleteMessage: (Int64, Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let forwardedFrom = customMessage.forwardedFrom {
                ForwardedFromView(name: forwardedFrom)
            }
            
            if customMessage.replyUser != nil, let replyToMessage = customMessage.replyToMessage {
                ReplyMessageView(
                    customMessage: customMessage,
                    type: .replied,
                    onTap: { scrollTo(replyToMessage.id) }
                )
            }
            
            if customMessage.messagePhoto != nil 
                || customMessage.messageVoiceNote != nil
                || !customMessage.album.isEmpty {
                MessageContentView(customMessage: $customMessage)
            }
            
            if let formattedText = customMessage.formattedText {
                MessageTextView(formattedText: formattedText)
                    .padding(8)
                    .padding(.top, customMessage.replyUser != nil && customMessage.replyToMessage != nil ? -10 : 0)
            }
        }
        .background(highlightedMessageId == customMessage.id ? .white.opacity(0.5) : .gray6)
        .clipShape(.rect(cornerRadius: 20))
        .customContextMenu(cornerRadius: 20, contextMenuActions)
    }
}

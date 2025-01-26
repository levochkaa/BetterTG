// MessageView.swift

import SwiftUI
import TDLibKit

struct MessageView: View {
    @State var customMessage: CustomMessage
    @Environment(ChatVM.self) var chatVM
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let forwardedFrom = customMessage.forwardedFrom {
                ForwardedFromView(name: forwardedFrom)
            }
            
            if customMessage.replyUser != nil, let replyToMessage = customMessage.replyToMessage {
                ReplyMessageView(
                    customMessage: customMessage,
                    type: .replied,
                    onTap: { chatVM.scrollTo(id: replyToMessage.id) }
                )
            }
            
            if customMessage.messagePhoto != nil 
                || customMessage.messageVoiceNote != nil
                || !customMessage.album.isEmpty {
                MessageContentView(customMessage: customMessage)
            }
            
            if let formattedText = customMessage.formattedText {
                MessageTextView(formattedText: formattedText)
                    .padding(8)
                    .padding(
                        .top,
                        customMessage.replyUser != nil && customMessage.replyToMessage != nil
                        || customMessage.forwardedFrom != nil ? -8 : 0
                    )
            }
        }
        .background(chatVM.highlightedMessageId == customMessage.id ? .white.opacity(0.5) : .gray6)
        .clipShape(.rect(cornerRadius: 20))
        .overlay(alignment: .bottomTrailing) {
            Text(chatVM.dateFormatter.string(from: customMessage.date))
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(3)
                .background(Color.gray6)
                .clipShape(.rect(cornerRadius: 10))
                .padding(5)
                .opacity(0.5)
        }
        .customContextMenu(cornerRadius: 20, contextMenuActions)
    }
}

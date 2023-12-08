// MessageView.swift

import SwiftUI
import TDLibKit

struct MessageView: View {
    
    @State var customMessage: CustomMessage
    let isOutgoing: Bool
    
    init(customMessage: CustomMessage) {
        self._customMessage = State(initialValue: customMessage)
        self.isOutgoing = customMessage.message.isOutgoing
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
                MessageTextView(formattedText: formattedText)
                    .padding(8)
            }
        }
        .background(.gray6)
        .cornerRadius(20)
        .contextMenu { contextMenu }
    }
}

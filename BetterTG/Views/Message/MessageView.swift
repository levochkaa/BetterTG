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
    
    @State var canBeRead = true
    
    @State var forwardedWidth: Int = 0
    @State var replyWidth: Int = 0
    @State var contentWidth: Int = 0
    @State var textWidth: Int = 0
    @State var editWidth: Int = 0
    
    var body: some View {
        VStack(alignment: customMessage.message.isOutgoing ? .trailing : .leading, spacing: 1) {
            if let forwardedFrom = customMessage.forwardedFrom {
                ForwardedFromView(name: forwardedFrom)
                    .background(backgroundColor(for: .forwarded))
                    .cornerRadius(corners(for: .forwarded))
                    .width($forwardedWidth)
            }
            
            if customMessage.replyUser != nil, customMessage.replyToMessage != nil {
                ReplyMessageView(customMessage: customMessage, type: .replied)
                    .background(backgroundColor(for: .reply))
                    .cornerRadius(corners(for: .reply))
                    .width($replyWidth)
            }
            
            MessageContentView(customMessage: customMessage, textWidth: textWidth)
                .background(backgroundColor(for: .content))
                .cornerRadius(corners(for: .content))
                .width($contentWidth)
            
            if let formattedText = customMessage.formattedText,
               let formattedTextSize = customMessage.formattedTextSize {
                MessageTextView(
                    formattedText: formattedText,
                    formattedTextSize: formattedTextSize,
                    formattedMessageDate: customMessage.formattedMessageDate
                )
                .background(backgroundColor(for: .text))
                .cornerRadius(corners(for: .text))
                .width($textWidth)
            }
            
            if customMessage.message.editDate != 0 {
                captionText(from: "edited")
                    .padding(3)
                    .background(backgroundColor(for: .edit))
                    .cornerRadius(corners(for: .edit))
                    .width($editWidth)
            }
        }
        .contextMenu { contextMenu }
        .onVisible {
            guard canBeRead else { return }
            defer { canBeRead = false }
            viewModel.viewMessage(id: customMessage.message.id)
        }
    }
    
    func backgroundColor(for type: MessagePart) -> Color {
        switch type {
            case .text, .content:
                if viewModel.highlightedMessageId == customMessage.id {
                    return .white.opacity(0.5)
                }
                fallthrough
            default:
                return customMessage.sendFailed ? .red : .gray6
        }
    }
}

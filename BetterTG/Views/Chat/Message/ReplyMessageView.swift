// ReplyMessageView.swift

import SwiftUI
import TDLibKit

struct ReplyMessageView: View {
    
    @State var customMessage: CustomMessage
    @State var isReply = false
    @EnvironmentObject var viewModel: ChatViewVM
    
    var body: some View {
        if isReply || customMessage.replyToMessage != nil {
            HStack {
                Capsule()
                    .if(isReply) {
                        $0.fill(.white)
                    } else: {
                        $0.fill(customMessage.message.isOutgoing ? .white : .black)
                    }
                    .frame(width: 2, height: 30)
                
                VStack(alignment: .leading) {
                    if isReply, let senderUser = customMessage.senderUser {
                        Text(senderUser.firstName)
                        message(for: customMessage.message.content)
                    } else if let replyUser = customMessage.replyUser,
                              let reply = customMessage.replyToMessage {
                        Text(replyUser.firstName)
                        message(for: reply.content)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
                
                if isReply {
                    Spacer()
                }
            }
            .onTapGesture {
                withAnimation {
                    viewModel.scrollViewProxy?.scrollTo(customMessage.message.replyToMessageId, anchor: .center)
                }
            }
        }
    }
    
    @ViewBuilder func message(for content: MessageContent) -> some View {
        switch content {
            case let .messageText(messageText):
                Text(messageText.text.text)
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }
}

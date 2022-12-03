// MessageView+ReplyMessage.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder func replyMessage(_ msg: CustomMessage) -> some View {
        if let reply = msg.replyToMessage {
            HStack {
                Capsule()
                    .fill(msg.message.isOutgoing ? .white : .black)
                    .frame(width: 2, height: 30)
                
                VStack(alignment: .leading) {
                    if let replyUser = msg.replyUser {
                        Text(replyUser.firstName)
                    }
                    
                    switch reply.content {
                        case let .messageText(messageText):
                            Text(messageText.text.text)
                        case .messageUnsupported:
                            Text("TDLib not supported")
                        default:
                            Text("BTG not supported")
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
            }
            .onTapGesture {
                if !showContextMenu {
                    withAnimation {
                        viewModel.scrollViewProxy?.scrollTo(msg.message.replyToMessageId, anchor: .center)
                    }
                }
            }
        }
    }
}

// ChatView+Message.swift

import SwiftUI
import TDLibKit

extension ChatView {
    @ViewBuilder func message(_ msg: CustomMessage) -> some View {
        VStack(alignment: .leading) {
            replyMessage(msg)
            
            switch msg.message.content {
                case let .messageText(messageText):
                    Text(messageText.text.text)
                case .messageUnsupported:
                    Text("TDLib not supported")
                default:
                    Text("BTG not supported")
            }
        }
        .multilineTextAlignment(.leading)
        .foregroundColor(msg.message.isOutgoing ? .white : .black)
    }
}

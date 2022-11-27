// ChatView+Message.swift

import SwiftUI
import TDLibKit

extension ChatView {
    @ViewBuilder func message(_ msg: Message) -> some View {
        Group {
            switch msg.content {
                case let .messageText(messageText):
                    Text(messageText.text.text)
                case .messageUnsupported:
                    Text("TDLib not supported")
                default:
                    Text("BTG not supported")
            }
        }
            .multilineTextAlignment(.leading)
            .foregroundColor(msg.isOutgoing ? .white : .black)
    }
}

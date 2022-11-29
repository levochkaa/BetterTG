// ChatView+ReplyMessage.swift

import SwiftUI
import TDLibKit

extension ChatView {
    @ViewBuilder func replyMessage(_ msg: CustomMessage) -> some View {
        if let reply = msg.replyToMessage {
            Button {
                withAnimation {
                    viewModel.scrollViewProxy?.scrollTo(msg.message.replyToMessageId, anchor: .center)
                }
            } label: {
                HStack {
                    Capsule()
                        .fill(msg.message.isOutgoing ? .white : .black)
                        .frame(width: 3)

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
                }
            }
                .buttonStyle(.plain)
                .frame(height: 30)
        }
    }
}

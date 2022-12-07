// ReplyMessageView.swift

import SwiftUI
import TDLibKit

struct ReplyMessageView: View {
    
    @State var customMessage: CustomMessage
    @State var isReply = false
    @State var isEdit = false
    @EnvironmentObject var viewModel: ChatViewVM
    
    let nc: NotificationCenter = .default
    
    var body: some View {
        if isReply || customMessage.replyToMessage != nil || isEdit {
            HStack {
                Capsule()
                    .if(isReply || isEdit) {
                        $0.fill(.white)
                    } else: {
                        $0.fill(customMessage.message.isOutgoing ? .white : .black)
                    }
                    .frame(width: 2, height: 30)
                
                VStack(alignment: .leading) {
                    if isEdit {
                        Text("Edit message")
                        message(for: customMessage.message.content)
                    } else if isReply, let senderUser = customMessage.senderUser {
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
                
                if isReply || isEdit {
                    Spacer()
                }
            }
            .onTapGesture {
                withAnimation {
                    if isEdit {
                        viewModel.scrollTo(id: viewModel.editMessage?.message.id)
                    } else if isReply {
                        viewModel.scrollTo(id: viewModel.replyMessage?.message.id)
                    } else {
                        viewModel.scrollTo(id: customMessage.replyToMessage?.id)
                    }
                }
            }
            .onReceive(nc.publisher(for: .messageEdited)) { notification in
                guard let messageEdited = notification.object as? UpdateMessageEdited else { return }
                
                if messageEdited.messageId == customMessage.replyToMessage?.id {
                    Task {
                        let message = try await viewModel.getMessage(id: messageEdited.messageId)
                        var customMessage = try await viewModel.getCustomMessage(from: customMessage.message)
                        customMessage.replyToMessage = message
                        await MainActor.run { [customMessage] in
                            withAnimation {
                                self.customMessage = customMessage
                            }
                        }
                    }
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

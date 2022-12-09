// ReplyMessageView.swift

import SwiftUI
import TDLibKit

struct ReplyMessageView: View {
    
    @State var customMessage: CustomMessage
    @State var type: ReplyMessageType?
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    let nc: NotificationCenter = .default
    
    var body: some View {
        if type != nil || customMessage.replyToMessage != nil {
            HStack {
                Capsule()
                    .if(type != nil) {
                        $0.fill(.white)
                    } else: {
                        $0.fill(customMessage.message.isOutgoing ? .white : .black)
                    }
                    .frame(width: 2, height: 30)
                
                VStack(alignment: .leading) {
                    if type == .edit {
                        Text("Edit message")
                        InlineMessageContentView(message: customMessage.message)
                    } else if type == .reply, let senderUser = customMessage.senderUser {
                        Text(senderUser.firstName)
                        InlineMessageContentView(message: customMessage.message)
                    } else if let replyUser = customMessage.replyUser, let reply = customMessage.replyToMessage {
                        Text(replyUser.firstName)
                        InlineMessageContentView(message: reply)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
                
                if type != nil {
                    Spacer()
                }
            }
            .onTapGesture {
                withAnimation {
                    if type == .edit {
                        viewModel.scrollTo(id: viewModel.editMessage?.message.id)
                    } else if type == .reply {
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
                        let customMessage = await viewModel.getCustomMessage(from: customMessage.message)
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
}

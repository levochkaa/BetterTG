// ReplyMessageView.swift

import SwiftUI
import TDLibKit

struct ReplyMessageView: View {
    
    @State var customMessage: CustomMessage
    @State var type: ReplyMessageType
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Capsule()
                .fill(.white)
                .frame(width: 2, height: 30)
            
            HStack(alignment: .center, spacing: 5) {
                Group {
                    switch type {
                        case .replied:
                            if let replyToMessage = customMessage.replyToMessage {
                                inlineMessageContent(for: replyToMessage)
                            }
                        case .edit, .reply:
                            inlineMessageContent(for: customMessage.message)
                    }
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    switch type {
                        case .edit, .reply:
                            Text(type == .edit ? "Edit message" : customMessage.senderUser?.firstName ?? "Name")
                            inlineMessageContentText(from: customMessage.message)
                        case .replied:
                            if let replyUser = customMessage.replyUser,
                                let replyToMessage = customMessage.replyToMessage {
                                Text(replyUser.firstName)
                                inlineMessageContentText(from: replyToMessage)
                            }
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
            }
            
            if type != .replied {
                Spacer()
            }
        }
        .padding(.horizontal, 5)
        .contentShape(RoundedRectangle(cornerRadius: 15))
        .onTapGesture {
            withAnimation {
                switch type {
                    case .edit:
                        viewModel.scrollTo(id: viewModel.editCustomMessage?.message.id)
                    case .reply:
                        viewModel.scrollTo(id: viewModel.replyMessage?.message.id)
                    case .replied:
                        viewModel.scrollTo(id: customMessage.replyToMessage?.id)
                }
            }
        }
        .onReceive(nc.publisher(for: .messageEdited)) { notification in
            guard let messageEdited = notification.object as? UpdateMessageEdited,
                  messageEdited.chatId == customMessage.message.chatId,
                  messageEdited.messageId == customMessage.replyToMessage?.id
            else { return }
            
            Task {
                let customMessage = await viewModel.getCustomMessage(from: customMessage.message)
                
                await MainActor.run {
                    withAnimation {
                        self.customMessage = customMessage
                    }
                }
            }
        }
    }
}

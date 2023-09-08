// ReplyMessageView.swift

import TDLibKit

struct ReplyMessageView: View {
    
    @State var customMessage: CustomMessage
    @State var type: ReplyMessageType
    
    @Environment(ChatViewModel.self) var viewModel
    
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
                        viewModel.scrollTo(id: viewModel.editCustomMessage?.id)
                    case .reply:
                        viewModel.scrollTo(id: viewModel.replyMessage?.id)
                    case .replied:
                        viewModel.scrollTo(id: viewModel.messages.first(where: {
                            $0.message.id == customMessage.replyToMessage?.id
                        })?.id)
                }
            }
        }
    }
}

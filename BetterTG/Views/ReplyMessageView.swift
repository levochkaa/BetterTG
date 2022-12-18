// ReplyMessageView.swift

import SwiftUI
import TDLibKit

struct ReplyMessageView: View {
    
    @State var customMessage: CustomMessage
    @State var type: ReplyMessageType
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    let nc: NotificationCenter = .default
    
    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Capsule()
                .if(type == .edit || type == .reply) {
                    $0.fill(.white)
                } else: {
                    $0.fill(customMessage.message.isOutgoing ? .white : .black)
                }
                .frame(width: 2, height: 30)
            
            HStack(alignment: .center, spacing: 5) {
                InlineMessageContentView(message: customMessage.message, type: type)
                
                VStack(alignment: .leading, spacing: 0) {
                    switch type {
                        case .edit:
                            Text("Edit message")
                            inlineMessageContentText(from: customMessage.message)
                        case .reply:
                            Text(customMessage.senderUser?.firstName ?? "Name")
                            inlineMessageContentText(from: customMessage.message)
                        case .last:
                            EmptyView()
                        case let .replied(replyUser, replyMessage):
                            Text(replyUser.firstName)
                            inlineMessageContentText(from: replyMessage)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
            }
            
            if type == .reply || type == .edit {
                Spacer()
            }
        }
        .onTapGesture {
            withAnimation {
                switch type {
                    case .edit:
                        viewModel.scrollTo(id: viewModel.editMessage?.message.id)
                    case .reply:
                        viewModel.scrollTo(id: viewModel.replyMessage?.message.id)
                    case .last:
                        break
                    case let .replied(_, replyMessage):
                        viewModel.scrollTo(id: replyMessage.id)
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
    
    @ViewBuilder func inlineMessageContentText(from message: Message) -> some View {
        switch message.content {
            case let .messageText(messageText):
                Text(messageText.text.text)
            case let .messagePhoto(messagePhoto):
                Text(messagePhoto.caption.text.isEmpty ? "Photo" : messagePhoto.caption.text)
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }
}

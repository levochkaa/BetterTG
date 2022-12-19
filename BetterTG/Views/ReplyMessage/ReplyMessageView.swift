// ReplyMessageView.swift

import SwiftUI
import TDLibKit

struct ReplyMessageView: View {
    
    @State var customMessage: CustomMessage
    @State var type: ReplyMessageType
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    let nc: NotificationCenter = .default
    let logger = Logger(label: "ReplyMessage")
    
    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Capsule()
                .fill(.white)
                .frame(width: 2, height: 30)
            
            HStack(alignment: .center, spacing: 5) {
                Group {
                    switch type {
                        case let .replied(_, replyToMessage):
                            inlineMessageContent(for: replyToMessage)
                        case .edit, .reply:
                            inlineMessageContent(for: customMessage.message)
                    }
                }
                .environmentObject(viewModel)
                
                VStack(alignment: .leading, spacing: 0) {
                    switch type {
                        case .edit, .reply:
                            Text(type == .edit ? "Edit message" : customMessage.senderUser?.firstName ?? "Name")
                            inlineMessageContentText(from: customMessage.message)
                        case let .replied(replyUser, replyToMessage):
                            Text(replyUser.firstName)
                            inlineMessageContentText(from: replyToMessage)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
            }
            
            if [.edit, .reply].contains(type) {
                Spacer()
            }
        }
        .padding(.horizontal, 5)
        .onTapGesture {
            withAnimation {
                switch type {
                    case .edit:
                        viewModel.scrollTo(id: viewModel.editMessage?.message.id)
                    case .reply:
                        viewModel.scrollTo(id: viewModel.replyMessage?.message.id)
                    case .replied:
                        viewModel.scrollTo(id: customMessage.replyToMessage?.id)
                }
            }
        }
        .onReceive(nc.publisher(for: .messageEdited)) { notification in
            guard let messageEdited = notification.object as? UpdateMessageEdited,
                  messageEdited.messageId != customMessage.replyToMessage?.id
            else { return }
            
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

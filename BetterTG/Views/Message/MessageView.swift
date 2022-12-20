// MessageView.swift

import SwiftUIX
import TDLibKit

struct MessageView: View {
    
    @State var customMessage: CustomMessage
    
    @Binding var openedPhotoInfo: OpenedPhotoInfo?
    var openedPhotoNamespace: Namespace.ID?
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    @State var replyWidth: Double = 0
    @State var textWidth: Double = 0
    @State var contentWidth: Double = 0
    @State var editWidth: Double = 0
    
    let logger = Logger(label: "MessageView")
    let nc: NotificationCenter = .default
    
    var body: some View {
        VStack(alignment: customMessage.message.isOutgoing ? .trailing : .leading, spacing: 1) {
            if customMessage.replyUser != nil, customMessage.replyToMessage != nil {
                ReplyMessageView(customMessage: customMessage, type: .replied)
                    .padding(5)
                    .background(backgroundColor(for: .reply))
                    .cornerRadius(corners(for: .reply), 15)
                    .readSize { replyWidth = $0.width }
            }
            
            messageContent
                .padding(1)
                .background(backgroundColor(for: .content))
                .cornerRadius(corners(for: .content), 15)
                .readSize { contentWidth = $0.width }
            
            messageText
                .multilineTextAlignment(.leading)
                .padding(8)
                .background(backgroundColor(for: .text))
                .cornerRadius(corners(for: .text), 15)
                .readSize { textWidth = $0.width }
            
            if customMessage.message.editDate != 0 {
                Text("edited")
                    .font(.caption)
                    .foregroundColor(.white).opacity(0.5)
                    .padding(3)
                    .background(backgroundColor(for: .edit))
                    .cornerRadius(corners(for: .edit), 15)
                    .readSize { editWidth = $0.width }
            }
        }
        .contextMenu {
            contextMenu
        }
        .onReceive(nc.publisher(for: .messageEdited)) { notification in
            guard let messageEdited = notification.object as? UpdateMessageEdited,
                  messageEdited.chatId == customMessage.message.chatId,
                  messageEdited.messageId == customMessage.message.id
            else { return }
            
            Task {
                guard let customMessage = await viewModel.getCustomMessage(fromId: messageEdited.messageId)
                else { return }
                
                await MainActor.run {
                    withAnimation {
                        self.customMessage = customMessage
                    }
                }
            }
        }
    }
    
    func backgroundColor(for type: MessagePart) -> Color {
        switch type {
            case .text, .content:
                if viewModel.highlightedMessageId == customMessage.message.id {
                    return .white.opacity(0.5)
                }
                fallthrough
            default:
                if customMessage.sendFailed { return .red }
                return customMessage.sendSucceded ? .gray6 : .black
        }
    }
}

// InlineMessageContentView.swift

import SwiftUIX
import TDLibKit

struct InlineMessageContentView: View {
    
    @State var customMessage: CustomMessage
    @State var type: ReplyMessageType
    
    @OptionalEnvironmentObject var rootViewModel: RootViewModel?
    @OptionalEnvironmentObject var chatViewModel: ChatViewModel?
    
    let nc: NotificationCenter = .default
    let logger = Logger(label: "InlineMessageContent")
    
    var body: some View {
        Group {
            switch type {
                case .last:
                    switch customMessage.message.content {
                        case let .messagePhoto(messagePhoto):
                            HStack(alignment: .center, spacing: 5) {
                                makeMessagePhoto(from: messagePhoto)
                                
                                Text(messagePhoto.caption.text.isEmpty ? "Photo" : messagePhoto.caption.text)
                            }
                        case let .messageText(messageText):
                            Text(messageText.text.text)
                        case .messageUnsupported:
                            Text("TDLib not supported")
                        default:
                            Text("BTG not supported")
                    }
                case .replied:
                    if let replyMessage = customMessage.replyToMessage {
                        switch replyMessage.content {
                            case let .messagePhoto(messagePhoto):
                                makeMessagePhoto(from: messagePhoto)
                            default:
                                EmptyView()
                        }
                    }
                case .edit, .reply:
                    switch customMessage.message.content {
                        case let .messagePhoto(messagePhoto):
                            makeMessagePhoto(from: messagePhoto)
                        default:
                            EmptyView()
                    }
            }
        }
        .onReceive(nc.publisher(for: .chatLastMessage)) { notification in
            guard let updateChatLastMessage = notification.object as? UpdateChatLastMessage,
                  let lastMessage = updateChatLastMessage.lastMessage,
                  updateChatLastMessage.chatId == customMessage.message.chatId,
                  let rootViewModel
            else { return }
            
            Task {
                guard let message = await rootViewModel.tdGetMessage(chatId: customMessage.message.chatId,
                                                                     messageId: lastMessage.id)
                else { return }
                
                await MainActor.run {
                    withAnimation {
                        self.customMessage = CustomMessage(message: message)
                    }
                }
            }
        }
        .onReceive(nc.publisher(for: .messageEdited)) { notification in
            guard let updateMessageEdited = notification.object as? UpdateMessageEdited,
                  updateMessageEdited.messageId == customMessage.message.id,
                  let chatViewModel
            else { return }
            
            Task {
                guard let customMessage = await chatViewModel.getCustomMessage(fromId: customMessage.message.id)
                else { return }
                
                await MainActor.run {
                    withAnimation {
                        self.customMessage = customMessage
                    }
                }
            }
        }
    }
}

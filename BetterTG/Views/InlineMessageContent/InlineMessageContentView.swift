// InlineMessageContentView.swift

import SwiftUIX
import TDLibKit

struct InlineMessageContentView: View {
    
    @State var message: Message
    @State var type: ReplyMessageType?
    
    @OptionalEnvironmentObject var rootViewModel: RootViewModel?
    @OptionalEnvironmentObject var chatViewModel: ChatViewModel?
    
    let nc: NotificationCenter = .default
    let logger = Logger(label: "InlineMessageContent")
    
    var body: some View {
        Group {
            switch type {
                case .last:
                    switch message.content {
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
                case let .replied(_, replyMessage):
                    switch replyMessage.content {
                        case let .messagePhoto(messagePhoto):
                            makeMessagePhoto(from: messagePhoto)
                        default:
                            EmptyView()
                    }
                default: // .edit and .reply
                    switch message.content {
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
                  updateChatLastMessage.chatId == message.chatId,
                  let rootViewModel
            else { return }
            
            Task {
                guard let message = await rootViewModel.tdGetMessage(chatId: message.chatId, messageId: lastMessage.id)
                else { return }
                
                await MainActor.run {
                    withAnimation {
                        self.message = message
                    }
                }
            }
        }
        .onReceive(nc.publisher(for: .messageEdited)) { notification in
            guard let updateMessageEdited = notification.object as? UpdateMessageEdited,
                  updateMessageEdited.messageId == message.id,
                  let chatViewModel
            else { return }
            
            Task {
                guard let message = await chatViewModel.tdGetMessage(id: message.id) else { return }
                
                await MainActor.run {
                    withAnimation {
                        self.message = message
                    }
                }
            }
        }
    }
}

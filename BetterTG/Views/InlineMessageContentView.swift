// InlineMessageContentView.swift

import SwiftUI
import SwiftUIX
import TDLibKit

struct InlineMessageContentView: View {
    
    @State var message: Message
    
    @OptionalEnvironmentObject var rootViewModel: RootViewModel?
    @OptionalEnvironmentObject var chatViewModel: ChatViewModel?
    
    let nc: NotificationCenter = .default
    let logger = Logger(label: "InlineMessageContent")
    
    var body: some View {
        Group {
            switch message.content {
                case let .messageText(messageText):
                    Text(messageText.text.text)
                case .messageUnsupported:
                    Text("TDLib not supported")
                default:
                    Text("BTG not supported")
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

// MessageView.swift

import SwiftUI
import TDLibKit

struct MessageView: View {
    
    @State var customMessage: CustomMessage
    @State var showContextMenu = false
    
    @ObservedObject var viewModel: ChatViewVM
    @State var onDismiss: (() -> Void)?
    
    let contextMenuButtonHeight: CGFloat = 40
    let spacing: CGFloat = 5
    
    var body: some View {
        ZStack(alignment: customMessage.message.isOutgoing ? .bottomTrailing : .bottomLeading) {
            VStack(alignment: .leading) {
                replyMessage(customMessage)
                
                switch customMessage.message.content {
                    case let .messageText(messageText):
                        Text(messageText.text.text)
                    case .messageUnsupported:
                        Text("TDLib not supported")
                    default:
                        Text("BTG not supported")
                }
            }
            .multilineTextAlignment(.leading)
            .foregroundColor(customMessage.message.isOutgoing ? .white : .black)
            .messageBubble(for: customMessage.message)
            
            if showContextMenu {
                customContextMenu(buttons: [
                    ContextButtonInfo(text: "Delete for me", systemImage: "trash", role: .destructive) {
                        Task {
                            try await viewModel.deleteMessages(
                                ids: [customMessage.message.id],
                                deleteForBoth: false
                            )
                        }
                    },
                    ContextButtonInfo(text: "**Delete for both**", systemImage: "trash.fill", role: .destructive) {
                        Task {
                            try await viewModel.deleteMessages(
                                ids: [customMessage.message.id],
                                deleteForBoth: true
                            )
                        }
                    }
                ])
            }
        }
    }
}

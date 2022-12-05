// MessageView.swift

import SwiftUI
import TDLibKit

struct MessageView: View {
    
    @State var customMessage: CustomMessage
    @ObservedObject var viewModel: ChatViewVM
    
    var body: some View {
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
        .contextMenu {
            contextMenu
        }
    }
}

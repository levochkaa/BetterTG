// MessageView.swift

import SwiftUI
import TDLibKit

struct MessageView: View {
    
    @State var customMessage: CustomMessage
    @EnvironmentObject var viewModel: ChatViewVM
    
    @State private var replySize: CGSize = .zero
    @State private var textSize: CGSize = .zero
    @State private var bottomTextSize: CGSize = .zero
    
    let logger = Logger(label: "MessageView")
    let nc: NotificationCenter = .default
    
    var body: some View {
        VStack(alignment: .leading) {
            ReplyMessageView(customMessage: customMessage)
                .readSize { size in
                    replySize = size
                }
            
            HStack(alignment: .bottom) {
                Group {
                    switch customMessage.message.content {
                        case let .messageText(messageText):
                            Text(messageText.text.text)
                        case .messageUnsupported:
                            Text("TDLib not supported")
                        default:
                            Text("BTG not supported")
                    }
                }
                .readSize { size in
                    textSize = size
                }
                
                if customMessage.message.editDate != 0 {
                    Spacer()
                        .frame(maxWidth: spacerMaxWidth())
                    
                    Text("edited")
                        .font(.caption)
                        .foregroundColor(.editedGray)
                        .opacity(0.5)
                        .frame(alignment: .bottomTrailing)
                        .readSize { size in
                            bottomTextSize = size
                        }
                }
            }
        }
        .multilineTextAlignment(.leading)
        .foregroundColor(customMessage.message.isOutgoing ? .white : .black)
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .if(customMessage.message.isOutgoing) {
                    $0.fill(viewModel.highlightedMessageId != customMessage.message.id ? .blue : .blue.opacity(0.5))
                } else: {
                    $0.fill(viewModel.highlightedMessageId != customMessage.message.id ? .white : .white.opacity(0.5))
                }
            
        }
        .frame(
            maxWidth: SystemUtils.size.width * 0.8,
            alignment: customMessage.message.isOutgoing ? .trailing : .leading
        )
        .contextMenu {
            contextMenu
        }
        .onReceive(nc.publisher(for: .messageEdited)) { notification in
            guard let messageEdited = notification.object as? UpdateMessageEdited else { return }
            
            if messageEdited.messageId == customMessage.message.id {
                Task {
                    let customMessage = try await viewModel.getCustomMessage(fromId: messageEdited.messageId)
                    await MainActor.run {
                        withAnimation {
                            self.customMessage = customMessage
                        }
                    }
                }
            }
        }
    }
    
    func spacerMaxWidth() -> CGFloat {
        if replySize.width < (bottomTextSize.width + textSize.width) {
            return 5
        } else if replySize.width > (bottomTextSize.width + textSize.width) {
            return replySize.width - (bottomTextSize.width + textSize.width)
        } else {
            return 5
        }
        // maxWidth = 5 just for spacing between `messageText` and `bottomText`
    }
}

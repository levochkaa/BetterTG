// MessageView.swift

import SwiftUI
import TDLibKit

struct MessageView: View {
    
    @State var customMessage: CustomMessage
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    @State var replySize: CGSize = .zero
    @State var textSize: CGSize = .zero
    @State var bottomTextSize: CGSize = .zero
    
    var spacerMaxWidth: CGFloat {
        // maxWidth = 5 just for spacing between `messageText` and `bottomText`
        if replySize.width < (bottomTextSize.width + textSize.width) {
            return 5
        } else if replySize.width > (bottomTextSize.width + textSize.width) {
            return replySize.width - (bottomTextSize.width + textSize.width)
        } else {
            return 5
        }
    }
    
    let logger = Logger(label: "MessageView")
    let nc: NotificationCenter = .default
    
    var body: some View {
        VStack(alignment: .leading) {
            ReplyMessageView(customMessage: customMessage)
                .environmentObject(viewModel)
                .readSize { size in
                    replySize = size
                }
            
            HStack(alignment: .bottom) {
                messageContent
                    .readSize { size in
                        textSize = size
                    }
                
                if customMessage.message.editDate != 0 {
                    Spacer()
                        .frame(maxWidth: spacerMaxWidth)
                    
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
            maxWidth: Utils.size.width * 0.8,
            alignment: customMessage.message.isOutgoing ? .trailing : .leading
        )
        .contextMenu {
            contextMenu
        }
        .onReceive(nc.publisher(for: .messageEdited)) { notification in
            guard let messageEdited = notification.object as? UpdateMessageEdited else { return }

            if messageEdited.messageId == customMessage.message.id {
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
    }
}

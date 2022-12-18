// MessageView.swift

import SwiftUI
import TDLibKit

struct MessageView: View {
    
    @State var customMessage: CustomMessage
    
    @Binding var openedPhotoInfo: OpenedPhotoInfo?
    var openedPhotoNamespace: Namespace.ID?
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    @State var replySize: CGSize = .zero
    @State var textSize: CGSize = .zero
    @State var contentSize: CGSize = .zero
    @State var bottomTextSize: CGSize = .zero
    
    var spacerMaxWidth: CGFloat {
        if contentSize != .zero {
            return contentSize.width - (bottomTextSize.width + textSize.width)
        } else if replySize.width < (bottomTextSize.width + textSize.width) {
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
            if let replyUser = customMessage.replyUser, let replyMessage = customMessage.replyToMessage {
                ReplyMessageView(customMessage: customMessage, type: .replied(replyUser, replyMessage))
                    .environmentObject(viewModel)
                    .readSize { size in
                        replySize = size
                    }
            }
            
            MessageContentView(
                customMessage: customMessage,
                openedPhotoInfo: $openedPhotoInfo,
                openedPhotoNamespace: openedPhotoNamespace
            )
            .readSize { size in
                contentSize = size
            }
                        
            HStack(alignment: .bottom) {
                messageContentText
                    .readSize { size in
                        textSize = size
                    }
                
                if customMessage.message.editDate != 0 {
                    Spacer()
                        .frame(maxWidth: spacerMaxWidth)
                    
                    Text("edited")
                        .font(.caption)
                        .foregroundColor(.editedGray).opacity(0.5)
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

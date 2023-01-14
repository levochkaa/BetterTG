// MessageView.swift

import SwiftUI
import SwiftUIX
import TDLibKit

struct MessageView: View {
    
    @State var customMessage: CustomMessage
    
    @Binding var openedPhotoInfo: OpenedPhotoInfo?
    var rootNamespace: Namespace.ID?
    
    @EnvironmentObject var viewModel: ChatViewModel
    
    @State var recognized = false
    @State var recognizedText = "..."
    @State var isListeningVoiceNote = false
    @State var recognizeSpeech = false
    @Namespace var voiceNoteNamespace
    
    @State var isOutgoing = true
    
    @State var replyWidth: Double = 0
    @State var textWidth: Double = 0
    @State var contentWidth: Double = 0
    @State var editWidth: Double = 0
    
    @State var textSize: CGSize = .zero
    
    let recognizedTextId = "recognizedTextId"
    let playId = "playId"
    let currentTimeId = "currentTimeId"
    let durationId = "durationId"
    let chevronId = "chevronId"
    let speechId = "speechId"
    
    var body: some View {
        VStack(alignment: customMessage.message.isOutgoing ? .trailing : .leading, spacing: 1) {
            if customMessage.replyUser != nil, customMessage.replyToMessage != nil {
                ReplyMessageView(customMessage: customMessage, type: .replied)
                    .padding(5)
                    .background(backgroundColor(for: .reply))
                    .cornerRadius(corners(for: .reply), 15)
                    .readSize { replyWidth = $0.width }
            }
            
            HStack(alignment: .center, spacing: 5) {
                if textWidth == .zero && isOutgoing {
                    menuButton
                }
                
                messageContent
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .padding(1)
                    .background(backgroundColor(for: .content))
                    .cornerRadius(corners(for: .content), 15)
                    .readSize { contentWidth = $0.width }
                
                if textWidth == .zero && !isOutgoing {
                    menuButton
                }
            }
            
            messageText
                .multilineTextAlignment(.leading)
                .padding(8)
                .foregroundColor(.white)
                .background(backgroundColor(for: .text))
                .cornerRadius(corners(for: .text), 15)
                .readSize { textWidth = $0.width }
                .menuOnPress {
                    menu
                }
            
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
        .onAppear {
            isOutgoing = customMessage.message.isOutgoing
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
                return customMessage.sendFailed ? .red : .gray6
        }
    }
}

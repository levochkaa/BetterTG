// MessageView.swift

import TDLibKit

struct MessageView: View {
    
    @State var customMessage: CustomMessage
    let isOutgoing: Bool
    
    init(customMessage: CustomMessage) {
        self._customMessage = State(initialValue: customMessage)
        self.isOutgoing = customMessage.message.isOutgoing
    }
    
    @Environment(ChatViewModel.self) var viewModel
    
    @State var canBeRead = true
    
    @State var forwardedWidth: Int = 0
    @State var replyWidth: Int = 0
    @State var contentWidth: Int = 0
    @State var textWidth: Int = 0
    @State var editWidth: Int = 0
    
    var body: some View {
        VStack(alignment: customMessage.message.isOutgoing ? .trailing : .leading, spacing: 1) {
            if let forwardedFrom = customMessage.forwardedFrom {
                ForwardedFromView(name: forwardedFrom)
                    .background(backgroundColor(for: .forwarded))
                    .cornerRadius(corners(for: .forwarded))
                    .width($forwardedWidth)
            }
            
            if customMessage.replyUser != nil, customMessage.replyToMessage != nil {
                ReplyMessageView(customMessage: customMessage, type: .replied)
                    .background(backgroundColor(for: .reply))
                    .cornerRadius(corners(for: .reply))
                    .width($replyWidth)
            }
            
            HStack(spacing: 0) {
                if isOutgoing, let messageVoiceNote = customMessage.messageVoiceNote, textWidth == .zero {
                    voiceNoteSide(from: messageVoiceNote.voiceNote)
                }
                
                MessageContentView(customMessage: customMessage, textWidth: textWidth)
                    .background(backgroundColor(for: .content))
                    .cornerRadius(corners(for: .content))
                    .width($contentWidth)

                if !isOutgoing, let messageVoiceNote = customMessage.messageVoiceNote, textWidth == .zero {
                    voiceNoteSide(from: messageVoiceNote.voiceNote)
                }
            }
            
            if let formattedText = customMessage.formattedText,
               let formattedTextSize = customMessage.formattedTextSize {
                MessageTextView(
                    formattedText: formattedText,
                    formattedTextSize: formattedTextSize,
                    formattedMessageDate: customMessage.formattedMessageDate
                )
                .background(backgroundColor(for: .text))
                .cornerRadius(corners(for: .text))
                .width($textWidth)
            }
            
            if customMessage.message.editDate != 0 {
                captionText(from: "edited")
                    .padding(3)
                    .background(backgroundColor(for: .edit))
                    .cornerRadius(corners(for: .edit))
                    .width($editWidth)
            }
        }
        .contextMenu { contextMenu }
        .onVisible {
            guard canBeRead else { return }
            defer { canBeRead = false }
            viewModel.viewMessage(id: customMessage.message.id)
        }
    }
    
    func backgroundColor(for type: MessagePart) -> Color {
        switch type {
            case .text, .content:
                if viewModel.highlightedMessageId == customMessage.id {
                    return .white.opacity(0.5)
                }
                fallthrough
            default:
                return customMessage.sendFailed ? .red : .gray6
        }
    }
    
    func voiceNoteSide(from voiceNote: VoiceNote) -> some View {
        VStack {
            if !voiceNote.voice.local.path.isEmpty, voiceNote.voice.local.path == viewModel.savedMediaPath {
                Image(systemName: "xmark")
                    .padding(3)
                    .background(.gray6)
                    .cornerRadius(15)
                    .onTapGesture {
                        viewModel.mediaStop()
                    }
                    .transition(.move(edge: isOutgoing ? .trailing : .leading).combined(with: .opacity))
            }
            
            Spacer()
            
            messageOverlayDate(customMessage.formattedMessageDate)
        }
        .padding(5)
    }
}

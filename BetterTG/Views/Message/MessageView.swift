// MessageView.swift

import TDLibKit

struct MessageView: View {
    
    @State var customMessage: CustomMessage
    @State var isOutgoing: Bool
    
    init(customMessage: CustomMessage) {
        self._customMessage = State(initialValue: customMessage)
        self._isOutgoing = State(initialValue: customMessage.message.isOutgoing)
    }
    
    @Environment(ChatViewModel.self) var viewModel
    @Environment(RootViewModel.self) var rootViewModel
    
    @Namespace var namespace
    
    @State var recognized = false
    @State var recognizedText = "..."
    @State var isListeningVoiceNote = false
    @State var recognizeSpeech = false
    
    @State var canBeRead = true
    
    @State var forwardedWidth: Int = 0
    @State var replyWidth: Int = 0
    @State var contentWidth: Int = 0
    @State var textWidth: Int = 0
    @State var editWidth: Int = 0
    
    let recognizedTextId = "recognizedTextId"
    let playId = "playId"
    let currentTimeId = "currentTimeId"
    let durationId = "durationId"
    let chevronId = "chevronId"
    let speechId = "speechId"
    
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
            
            HStack(alignment: .bottom, spacing: 0) {
                if case .messageVoiceNote(let messageVoiceNote) = customMessage.message.content,
                   isOutgoing, textWidth == 0 {
                    voiceNoteSide(from: messageVoiceNote.voiceNote)
                }
                
                messageContent
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .padding(1)
                    .background(backgroundColor(for: .content))
                    .cornerRadius(corners(for: .content))
                    .width($contentWidth)

                if case .messageVoiceNote(let messageVoiceNote) = customMessage.message.content,
                   !isOutgoing, textWidth == 0 {
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
        .contextMenu {
            menu
        }
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
}

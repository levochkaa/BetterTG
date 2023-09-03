// RootView+LastOrDraft.swift

import TDLibKit

extension RootView {
    @ViewBuilder func lastOrDraftMessage(for customChat: CustomChat) -> some View {
        Group {
            if let draftMessage = customChat.draftMessage {
                draftMessageView(for: draftMessage)
            } else if let lastMessage = customChat.lastMessage {
                lastMessageView(for: lastMessage)
            }
        }
        .foregroundColor(.gray)
    }
    
    @ViewBuilder func draftMessageView(for draftMessage: DraftMessage) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text("Draft: ")
                .foregroundColor(.red)
            
            if draftMessage.replyToMessageId != 0 {
                Text("reply ")
                    .foregroundColor(.white)
            }
            
            switch draftMessage.inputMessageText {
                case .inputMessageText(let inputMessageText):
                    TextView(formattedText: inputMessageText.text)
                default:
                    Text("BTG not supported")
            }
        }
    }
    
    @ViewBuilder func lastMessageView(for lastMessage: Message) -> some View {
        switch lastMessage.content {
            case .messagePhoto(let messagePhoto):
                HStack(alignment: .center, spacing: 5) {
                    makePhotoPreview(from: messagePhoto)
                    
                    if messagePhoto.caption.text.isEmpty {
                        Text("Photo")
                    } else {
                        TextView(formattedText: messagePhoto.caption)
                    }
                }
            case .messageVoiceNote(let messageVoiceNote):
                HStack(alignment: .bottom, spacing: 0) {
                    Text("Voice")
                        .foregroundColor(.white)
                    
                    if !messageVoiceNote.caption.text.isEmpty {
                        Text(": ")
                            .foregroundColor(.white)
                        
                        TextView(formattedText: messageVoiceNote.caption)
                    }
                }
            case .messageText(let messageText):
                TextView(formattedText: messageText.text)
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }
}

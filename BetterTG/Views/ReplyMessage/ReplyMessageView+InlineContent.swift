// ReplyMessageView+InlineContent.swift

import TDLibKit

extension ReplyMessageView {
    @ViewBuilder func inlineMessageContentText(from message: Message) -> some View {
        switch message.content {
            case .messageText(let messageText):
                TextView(formattedText: messageText.text, lineLimit: 1)
            case .messagePhoto(let messagePhoto):
                if messagePhoto.caption.text.isEmpty {
                    Text("Photo")
                } else {
                    TextView(formattedText: messagePhoto.caption, lineLimit: 1)
                }
            case .messageVoiceNote(let messageVoiceNote):
                HStack(alignment: .bottom) {
                    Text("Voice")
                        .foregroundColor(.white)
                    
                    if !messageVoiceNote.caption.text.isEmpty {
                        Text(": ")
                            .foregroundColor(.white)
                        
                        TextView(formattedText: messageVoiceNote.caption, lineLimit: 1)
                    }
                }
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }
}

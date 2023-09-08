// ReplyMessageView+InlineContent.swift

import TDLibKit

extension ReplyMessageView {
    @ViewBuilder func inlineMessageContentText(from message: Message) -> some View {
        switch message.content {
            case .messageText(let messageText):
                Text(getAttributedString(from: messageText.text))
            case .messagePhoto(let messagePhoto):
                if messagePhoto.caption.text.isEmpty {
                    Text("Photo")
                } else {
                    Text(getAttributedString(from: messagePhoto.caption))
                }
            case .messageVoiceNote(let messageVoiceNote):
                HStack(alignment: .bottom) {
                    Text("Voice")
                        .foregroundColor(.white)
                    
                    if !messageVoiceNote.caption.text.isEmpty {
                        Text(": ")
                            .foregroundColor(.white)
                        
                        Text(getAttributedString(from: messageVoiceNote.caption))
                    }
                }
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }
}

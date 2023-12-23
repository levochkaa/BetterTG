// ReplyMessageView+InlineContent.swift

import SwiftUI
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
                HStack(alignment: .bottom, spacing: 0) {
                    Text("Voice")
                        .foregroundStyle(.white)
                    
                    if !messageVoiceNote.caption.text.isEmpty {
                        Text(": ")
                            .foregroundStyle(.white)
                        
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

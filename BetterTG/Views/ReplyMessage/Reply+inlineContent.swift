// Reply+inlineContent.swift

import SwiftUI
import TDLibKit

extension ReplyMessageView {
    @ViewBuilder func inlineMessageContentText(from message: Message) -> some View {
        switch message.content {
            case .messageText(let messageText):
                Text(messageText.text.text)
            case .messagePhoto(let messagePhoto):
                Text(messagePhoto.caption.text.isEmpty ? "Photo" : messagePhoto.caption.text)
            case .messageVoiceNote(let messageVoiceNote):
                HStack(alignment: .bottom) {
                    Text("Voice")
                        .foregroundColor(.white)
                    
                    if !messageVoiceNote.caption.text.isEmpty {
                        Text(": ")
                            .foregroundColor(.white)
                    }
                    
                    Text(messageVoiceNote.caption.text)
                }
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }
}

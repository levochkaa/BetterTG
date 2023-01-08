// MessageView+Text.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var messageText: some View {
        Group {
            switch customMessage.message.content {
                case .messageText(let messageText):
                    formattedTextView(messageText.text)
                case .messagePhoto(let messagePhoto):
                    if !messagePhoto.caption.text.isEmpty {
                        formattedTextView(messagePhoto.caption)
                    }
                case .messageVoiceNote(let messageVoiceNote):
                    if !messageVoiceNote.caption.text.isEmpty {
                        formattedTextView(messageVoiceNote.caption)
                    }
                case .messageUnsupported:
                    Text("TDLib not supported")
                default:
                    Text("BTG not supported")
            }
        }
    }
}

// Message+text.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var messageText: some View {
        Group {
            switch customMessage.message.content {
                case .messageText(let messageText):
                    formattedTextView(messageText.text)
                        .onAppear { text = messageText.text.text }
                case .messagePhoto(let messagePhoto):
                    if !messagePhoto.caption.text.isEmpty {
                        formattedTextView(messagePhoto.caption)
                            .onAppear { text = messagePhoto.caption.text }
                    }
                case .messageVoiceNote(let messageVoiceNote):
                    if !messageVoiceNote.caption.text.isEmpty {
                        formattedTextView(messageVoiceNote.caption)
                            .onAppear { text = messageVoiceNote.caption.text }
                    }
                case .messageUnsupported:
                    Text("TDLib not supported")
                default:
                    Text("BTG not supported")
            }
        }
    }
}

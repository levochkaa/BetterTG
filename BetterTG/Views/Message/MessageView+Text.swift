// MessageView+Text.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var messageText: some View {
        Group {
            switch customMessage.message.content {
                case .messageText(let messageText):
                    FormattedTextView(messageText.text)
                case .messagePhoto(let messagePhoto):
                    if !messagePhoto.caption.text.isEmpty {
                        Text(messagePhoto.caption.text)
                    }
                case .messageVoiceNote(let messageVoiceNote):
                    if !messageVoiceNote.caption.text.isEmpty {
                        Text(messageVoiceNote.caption.text)
                    }
                case .messageUnsupported:
                    Text("TDLib not supported")
                default:
                    Text("BTG not supported")
            }
        }
    }
}

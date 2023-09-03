// MessageView+Text.swift

import TDLibKit

extension MessageView {
    @ViewBuilder var messageText: some View {
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
    
    @ViewBuilder func formattedTextView(_ formattedText: FormattedText) -> some View {
        TextView(formattedText: formattedText, appendingDate: true, maxWidth: Utils.maxMessageContentWidth)
            .overlay(alignment: .bottomTrailing) {
                messageDate
                    .offset(y: 3)
            }
    }
    
    @ViewBuilder var messageDate: some View {
        Text(formatted(customMessage.message.date))
            .font(.caption)
            .foregroundColor(.white).opacity(0.5)
    }
    
    private func formatted(_ time: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        return dateFormatter.string(from: date)
    }
}

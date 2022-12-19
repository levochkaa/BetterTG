// MessageView+Text.swift

import SwiftUI

extension MessageView {
    @ViewBuilder var messageText: some View {
        Group {
            switch customMessage.message.content {
                case let .messageText(messageText):
                    Text(messageText.text.text)
                case let .messagePhoto(messagePhoto):
                    if !messagePhoto.caption.text.isEmpty {
                        Text(messagePhoto.caption.text)
                    }
                case .messageUnsupported:
                    Text("TDLib not supported")
                default:
                    Text("BTG not supported")
            }
        }
    }
}

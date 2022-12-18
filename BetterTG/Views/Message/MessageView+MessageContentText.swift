// MessageView+MessageContentText.swift

import SwiftUI
import TDLibKit

extension MessageView {
    @ViewBuilder var messageContentText: some View {
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

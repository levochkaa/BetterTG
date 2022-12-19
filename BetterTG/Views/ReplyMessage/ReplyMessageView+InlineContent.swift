// ReplyMessageView+InlineContent.swift

import SwiftUI
import TDLibKit

extension ReplyMessageView {
    @ViewBuilder func inlineMessageContentText(from message: Message) -> some View {
        switch message.content {
            case let .messageText(messageText):
                Text(messageText.text.text)
            case let .messagePhoto(messagePhoto):
                Text(messagePhoto.caption.text.isEmpty ? "Photo" : messagePhoto.caption.text)
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }
}

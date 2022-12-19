// ReplyMessageView+Content.swift

import SwiftUI
import TDLibKit

extension ReplyMessageView {
    @ViewBuilder func inlineMessageContent(for message: Message) -> some View {
        switch message.content {
            case let .messagePhoto(messagePhoto):
                makeMessagePhoto(from: messagePhoto)
            default:
                EmptyView()
        }
    }
}

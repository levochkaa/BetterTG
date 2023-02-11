// Reply+content.swift

import SwiftUI
import TDLibKit

extension ReplyMessageView {
    @ViewBuilder func inlineMessageContent(for message: Message) -> some View {
        switch message.content {
            case .messagePhoto(let messagePhoto):
                makeMessagePhoto(from: messagePhoto)
            default:
                EmptyView()
        }
    }
}

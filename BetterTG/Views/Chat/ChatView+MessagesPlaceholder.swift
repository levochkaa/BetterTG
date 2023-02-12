// ChatView+MessagesPlaceholder.swift

import SwiftUI
import TDLibKit

extension ChatView {
    @ViewBuilder var messagesPlaceholder: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                messagesList(CustomMessage.placeholder(), redacted: true)
                    .redacted(reason: .placeholder)
            }
        }
        .flippedUpsideDown()
        .scrollDisabled(true)
        .background(.black)
    }
}

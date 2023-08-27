// ChatView+MessagesList.swift

import SwiftUI

extension ChatView {
    @ViewBuilder func messagesList(_ customMessages: [CustomMessage]) -> some View {
        ForEach(customMessages) { customMessage in
            HStack {
                if customMessage.message.isOutgoing { Spacer() }
                
                MessageView(customMessage: customMessage)
                    .frame(
                        maxWidth: Utils.size.width * 0.8,
                        alignment: customMessage.message.isOutgoing ? .trailing : .leading
                    )
                    .flippedUpsideDown()
                
                if !customMessage.message.isOutgoing { Spacer() }
            }
            .id(customMessage.message.id)
            .padding(customMessage.message.isOutgoing ? .trailing : .leading)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top),
                    removal: .move(edge: customMessage.message.isOutgoing ? .trailing : .leading)
                )
                .combined(with: .opacity)
            )
        }
    }
}

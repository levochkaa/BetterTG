// ChatView+MessageBubble.swift

import SwiftUI
import TDLibKit

extension View {
    func messageBubble(for msg: Message) -> some View {
        self
            .padding(8)
            .background {
                if msg.isOutgoing {
                    RoundedRectangle(cornerRadius: 20)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.blue)
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundColor(.white)
                }
            }
            .frame(
                maxWidth: SystemUtils.size.width * 0.8,
                alignment: msg.isOutgoing ? .trailing : .leading
            )
    }
}

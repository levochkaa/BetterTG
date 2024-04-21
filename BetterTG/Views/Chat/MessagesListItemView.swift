// MessagesListItemView.swift

import SwiftUI

struct MessagesListItemView: View {
    @Binding var customMessage: CustomMessage
    var isOutgoing: Bool { customMessage.message.isOutgoing }
    
    var body: some View {
        HStack(spacing: 0) {
            if isOutgoing { Spacer(minLength: 0) }
            
            MessageView(customMessage: $customMessage)
                .frame(maxWidth: Utils.maxMessageContentWidth, alignment: isOutgoing ? .trailing : .leading)
            
            if !isOutgoing { Spacer(minLength: 0) }
        }
        .padding(isOutgoing ? .trailing : .leading, 16)
        .transition(
            .asymmetric(
                insertion: .move(edge: .top),
                removal: .move(edge: isOutgoing ? .trailing : .leading)
            )
            .combined(with: .opacity)
        )
    }
}

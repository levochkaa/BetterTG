// ChatView+MessagesScroll.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var messagesList: some View {
        ForEach(viewModel.messages) { customMessage in
            HStack {
                if customMessage.message.isOutgoing { Spacer() }
                
                MessageView(
                    customMessage: customMessage,
                    focused: $focused,
                    openedMessageContextMenu: $openedMessageContextMenu,
                    openedPhotoInfo: $openedPhotoInfo,
                    rootNamespace: rootNamespace
                )
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
                    insertion: .move(edge: .bottom),
                    removal: .move(edge: customMessage.message.isOutgoing ? .trailing : .leading)
                )
                .combined(with: .opacity)
            )
        }
    }
}

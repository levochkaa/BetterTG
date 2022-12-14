// ChatView+MessagesScroll.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var messagesList: some View {
        ForEach(viewModel.messages) { customMessage in
            HStack {
                if customMessage.message.isOutgoing { Spacer() }
                
                MessageView(
                    customMessage: customMessage,
                    openedPhotoInfo: $openedPhotoInfo,
                    openedPhotoNamespace: openedPhotoNamespace
                )
                .frame(
                    maxWidth: Utils.size.width * 0.8,
                    alignment: customMessage.message.isOutgoing ? .trailing : .leading
                )
                
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
            .onAppear {
                guard let scrollViewProxy = viewModel.scrollViewProxy else { return }
                
                // for init scrollTo bottom
                if let initSavedFirstMessage = viewModel.initSavedFirstMessage,
                   customMessage.message.id == initSavedFirstMessage.message.id {
                    viewModel.scrollToLast()
                    viewModel.initSavedFirstMessage = nil
                }
                
                // for scrollTo top, when loading messages
                if let savedFirstMessage = viewModel.savedFirstMessage,
                   let firstId = viewModel.messages.first?.message.id,
                   customMessage.message.id == firstId {
                    scrollViewProxy.scrollTo(savedFirstMessage.message.id, anchor: .top)
                    viewModel.savedFirstMessage = nil
                }
            }
        }
    }
}

// ChatView+ListOfMessages.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var listOfMessages: some View {
        ScrollView {
            ZStack {
                LazyVStack {
                    ForEach(viewModel.messages) { msg in
                        HStack {
                            if msg.message.isOutgoing {
                                Spacer()
                            }

                            message(msg)
                                .messageBubble(for: msg.message)

                            if !msg.message.isOutgoing {
                                Spacer()
                            }
                        }
                            .id(msg.message.id)
                            .padding(msg.message.isOutgoing ? .trailing : .leading)
                            .flippedUpsideDown()
                    }
                    if viewModel.loadingMessages {
                        ProgressView()
                    }
                }
                
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named(scroll))
                    )
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .flippedUpsideDown()
    }
}

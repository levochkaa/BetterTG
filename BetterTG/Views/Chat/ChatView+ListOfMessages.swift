// ChatView+ListOfMessages.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var listOfMessages: some View {
        ScrollView {
            ZStack {
                LazyVStack {
                    ForEach(viewModel.messages) { msg in
                        HStack {
                            if msg.isOutgoing {
                                Spacer()
                            }

                            message(msg)
                                .messageBubble(for: msg)

                            if !msg.isOutgoing {
                                Spacer()
                            }
                        }
                            .id(msg.id)
                            .padding(msg.isOutgoing ? .trailing : .leading)
                            .flippedUpsideDown()
                    }
                }

                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: Int(proxy.frame(in: .named(scroll)).minY)
                    )
                }
            }
        }
            .scrollDismissesKeyboard(.interactively)
            .flippedUpsideDown()
    }
}

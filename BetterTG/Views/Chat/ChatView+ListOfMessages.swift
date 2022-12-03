// ChatView+ListOfMessages.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var listOfMessages: some View {
        ScrollView {
            ZStack {
                LazyVStack {
                    ForEach(viewModel.messages) { msg in
                        HStack {
                            if msg.message.isOutgoing { Spacer() }
                            
                            MessageView(customMessage: msg, viewModel: viewModel)
                                .onTapGesture {
                                    // empty, to let scroll view work on messages
                                }
                                .onLongPressGesture {
                                    withAnimation {
                                        shownContextMenuMessage = msg
                                    }
                                }
                                .anchorPreference(key: BoundsPreferenceKey.self, value: .bounds) { anchor in
                                    return [[msg.message.id: viewModel]: anchor]
                                }
                            
                            if !msg.message.isOutgoing { Spacer() }
                        }
                        .id(msg.message.id)
                        .padding(msg.message.isOutgoing ? .trailing : .leading)
                        .transition(.move(edge: .top)) // actually bottom, because flipped
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

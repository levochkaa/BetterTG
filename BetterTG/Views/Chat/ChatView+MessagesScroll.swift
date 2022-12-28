// ChatView+MessagesScroll.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var messagesScroll: some View {
        ScrollView {
            ZStack {
                LazyVStack {
                    Group {
                        if viewModel.loadingMessages {
                            ProgressView()
                        } else {
                            AsyncButton("Load messages") {
                                await viewModel.loadMessages()
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    
                    messagesList
                }
                
                GeometryReader { geometryProxy in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometryProxy.frame(in: .named(scroll))
                    )
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollDisabled(viewModel.loadingMessages)
    }
}

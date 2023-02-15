// ChatView+MessagesScroll.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var messagesScroll: some View {
        ScrollView(showsIndicators: false) {
            ZStack {
                LazyVStack(spacing: 5) {
                    messagesList(viewModel.messages)
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
        .flippedUpsideDown()
    }
}

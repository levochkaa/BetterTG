// ChatView+MessagesScroll.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var messagesScroll: some View {
        ScrollView {
            ZStack {
                LazyVStack {
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
        .flippedUpsideDown()
    }
}

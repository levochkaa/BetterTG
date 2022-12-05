// ChatView+ScrollToBottomButton.swift

import SwiftUI

extension ChatView {
    @ViewBuilder var scrollToBottomButton: some View {
        Image(systemName: "arrow.down")
            .padding(10)
            .background(.black)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(.blue, lineWidth: 1)
            )
            .padding(.trailing)
            .onTapGesture {
                guard let lastId = viewModel.messages.last?.message.id else { return }
                
                withAnimation {
                    viewModel.scrollViewProxy?.scrollTo(lastId, anchor: .bottom)
                }
            }
    }
}

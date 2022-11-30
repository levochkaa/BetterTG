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
            .padding(.bottom, 5)
            .onTapGesture {
                guard let firstId = viewModel.messages.first?.message.id else {
                    return
                }
                
                withAnimation {
                    viewModel.scrollViewProxy?.scrollTo(firstId, anchor: .bottom)
                }
            }
    }
}

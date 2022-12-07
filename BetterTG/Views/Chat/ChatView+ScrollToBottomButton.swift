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
                viewModel.scrollToLast()
            }
    }
}

// textField.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var textField: some View {
        TextField(
            "Message...",
            text: viewModel.editCustomMessage == nil ? $viewModel.text : $viewModel.editMessageText,
            axis: .vertical
        )
        .unredacted()
        .disabled(!redactionReasons.isEmpty)
        .focused(focused)
        .lineLimit(10)
        .padding(5)
        .background(.gray6)
        .cornerRadius(15)
        .onReceive(viewModel.$text.debounce(for: 2, scheduler: DispatchQueue.main)) { _ in
            Task {
                await viewModel.updateDraft()
                
                if !viewModel.text.isEmpty {
                    await viewModel.tdSendChatAction(.chatActionTyping)
                } else {
                    await viewModel.tdSendChatAction(.chatActionCancel)
                }
            }
        }
    }
}

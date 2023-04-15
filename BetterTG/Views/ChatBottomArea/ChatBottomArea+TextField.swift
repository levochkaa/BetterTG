// ChatBottomArea+TextField.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var textField: some View {
        Group {
            if viewModel.editCustomMessage == nil {
                CustomTextField("Message...", text: $viewModel.text)
            } else {
                CustomTextField("Edit...", text: $viewModel.editMessageText, focus: true)
            }
        }
        .unredacted()
        .disabled(!redactionReasons.isEmpty)
        .focused(focused)
        .lineLimit(10)
        .padding(.horizontal, 5)
        .background(.gray6)
        .cornerRadius(15)
        .onReceive(viewModel.$text.debounce(for: 2, scheduler: DispatchQueue.main)) { _ in
            Task {
                await viewModel.updateDraft()
                
                if !viewModel.text.characters.isEmpty {
                    await viewModel.tdSendChatAction(.chatActionTyping)
                } else {
                    await viewModel.tdSendChatAction(.chatActionCancel)
                }
            }
        }
    }
}

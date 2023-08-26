// ChatBottomArea+TextField.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var textField: some View {
        @Bindable var viewModel = viewModel
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
    }
}

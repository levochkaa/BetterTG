// ChatBottomArea+TextField.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var textField: some View {
        WithBindable<ChatViewModel> { bindableViewModel in
            if viewModel.editCustomMessage == nil {
                CustomTextField("Message...", text: bindableViewModel.text)
            } else {
                CustomTextField("Edit...", text: bindableViewModel.editMessageText, focus: true)
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

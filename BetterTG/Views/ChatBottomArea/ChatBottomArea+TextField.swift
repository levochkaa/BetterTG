// ChatBottomArea+TextField.swift

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
        .focused(focused)
        .lineLimit(10)
        .padding(.horizontal, 5)
        .background(.gray6)
        .cornerRadius(15)
        .onChange(of: viewModel.text) { _, text in
            textDebouncer.call(delay: 2) {
                Task { [viewModel] in
                    await viewModel.updateDraft()
                    
                    if !text.characters.isEmpty {
                        await viewModel.tdSendChatAction(.chatActionTyping)
                    } else {
                        await viewModel.tdSendChatAction(.chatActionCancel)
                    }
                }
            }
        }
    }
}

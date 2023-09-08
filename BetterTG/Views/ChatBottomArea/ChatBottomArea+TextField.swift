// ChatBottomArea+TextField.swift

import Combine

extension ChatBottomArea {
    @ViewBuilder var textField: some View {
        @Bindable var viewModel = viewModel
        Group {
            if viewModel.editCustomMessage == nil {
                CustomTextField("Message...", text: $viewModel.text)
                    .onReceive(nc.publisher(for: .localPasteImages)) { notification in
                        guard let images = notification.object as? [SelectedImage],
                              viewModel.displayedImages.count < 10
                        else { return }
                        withAnimation {
                            viewModel.displayedImages.add(
                                contentsOf: Array(images.prefix(10 - viewModel.displayedImages.count))
                            )
                        }
                    }
            } else {
                CustomTextField("Edit...", text: $viewModel.editMessageText, focus: true)
            }
        }
        .focused(focused)
        .lineLimit(10)
        .padding(.horizontal, 5)
        .background(.gray6)
        .cornerRadius(15)
        .onReceive(
            Just(viewModel.text)
                .throttle(
                    for: 2,
                    scheduler: DispatchQueue.global(qos: .background),
                    latest: true
                )
        ) { text in
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

// ChatBottomArea+TextField.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var textField: some View {
        TextField(
            textFieldPrompt(),
            text: textFieldText(),
            axis: .vertical
        )
        .focused(focused)
        .lineLimit(10)
        .padding(5)
        .background(Color.gray6)
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
    
    func textFieldText() -> Binding<String> {
        switch viewModel.bottomAreaState {
            case .message, .reply, .caption, .voice:
                return $viewModel.text
            case .edit:
                return $viewModel.editMessageText
        }
    }
    
    func textFieldPrompt() -> String {
        switch viewModel.bottomAreaState {
            case .voice:
                return "Message..."
            default:
                return "\(viewModel.bottomAreaState)...".capitalized
        }
    }
}

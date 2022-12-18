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
        .cornerRadius(10)
        .onReceive(viewModel.$text.debounce(for: 2, scheduler: DispatchQueue.main)) { _ in
            Task {
                await viewModel.updateDraft()
            }
        }
    }
    
    func textFieldText() -> Binding<String> {
        switch viewModel.bottomAreaState {
            case .message, .reply, .caption:
                return $viewModel.text
            case .edit:
                return $viewModel.editMessageText
        }
    }
    
    func textFieldPrompt() -> String {
        return "\(viewModel.bottomAreaState)...".capitalized
    }
}

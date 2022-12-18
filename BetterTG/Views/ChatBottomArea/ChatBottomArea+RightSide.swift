// ChatBottomArea+RightSide.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var rightSide: some View {
        Button {
            Task {
                switch viewModel.bottomAreaState {
                    case .message, .reply, .caption:
                        await viewModel.sendMessage()
                    case .edit:
                        await viewModel.editMessage()
                }
            }
        } label: {
            Group {
                switch viewModel.bottomAreaState {
                    case .message, .reply:
                        Image("send")
                            .resizable()
                            .disabled(viewModel.text.isEmpty)
                    case .edit:
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .disabled(viewModel.editMessageText.isEmpty)
                    case .caption:
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                }
            }
            .clipShape(Circle())
            .frame(width: 32, height: 32)
            .transition(.scale)
        }
    }
}

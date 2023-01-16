// topSide.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var topSide: some View {
        switch viewModel.bottomAreaState {
            case .edit:
                if let editMessage = viewModel.editMessage {
                    replyMessageView(editMessage, type: .edit)
                }
            case .reply, .caption:
                if let replyMessage = viewModel.replyMessage {
                    replyMessageView(replyMessage, type: .reply)
                }
            case .message, .voice:
                EmptyView()
        }
    }
    
    @ViewBuilder func replyMessageView(_ customMessage: CustomMessage, type: ReplyMessageType) -> some View {
        HStack {
            ReplyMessageView(customMessage: customMessage, type: type)
                .padding(5)
                .background(Color.gray6)
                .cornerRadius(15)
            
            Image(systemName: "xmark")
                .onTapGesture {
                    viewModel.bottomAreaState = .voice
                }
        }
    }
}

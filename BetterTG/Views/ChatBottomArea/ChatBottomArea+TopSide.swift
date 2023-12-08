// ChatBottomArea+TopSide.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var topSide: some View {
        Group {
            if let editMessage = viewModel.editCustomMessage {
                replyMessageView(editMessage, type: .edit)
            } else if let replyMessage = viewModel.replyMessage {
                replyMessageView(replyMessage, type: .reply)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    @ViewBuilder func replyMessageView(_ customMessage: CustomMessage, type: ReplyMessageType) -> some View {
        HStack {
            ReplyMessageView(customMessage: .constant(customMessage), type: type)
                .background(.gray6)
                .cornerRadius(15)
                .id(customMessage.id)
            
            Image(systemName: "xmark")
                .onTapGesture {
                    withAnimation {
                        viewModel.replyMessage = nil
                        viewModel.editCustomMessage = nil
                    }
                }
        }
    }
}

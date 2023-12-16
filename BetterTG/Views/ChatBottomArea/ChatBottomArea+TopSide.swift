// ChatBottomArea+TopSide.swift

import SwiftUI

extension ChatBottomArea {
    @ViewBuilder var topSide: some View {
        if let editMessage = viewModel.editCustomMessage {
            replyMessageView(editMessage, type: .edit)
        } else if let replyMessage = viewModel.replyMessage {
            replyMessageView(replyMessage, type: .reply)
        }
    }
    
    @ViewBuilder func replyMessageView(_ customMessage: CustomMessage, type: ReplyMessageType) -> some View {
        HStack {
            ReplyMessageView(customMessage: .constant(customMessage), type: type)
                .background(.gray6)
                .clipShape(RoundedRectangle(cornerRadius: 15))
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

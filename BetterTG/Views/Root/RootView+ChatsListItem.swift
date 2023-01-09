// RootView+ChatsListItem.swift

import SwiftUIX
import TDLibKit

extension RootView {
    @ViewBuilder func chatsListItem(for chat: Chat) -> some View {
        HStack {
            chatsListPhoto(for: chat)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(chat.title)
                    .font(.title2)
                    .foregroundColor(.white)
                
                lastOrDraftMessage(for: chat)
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(5)
        .background(.gray6)
        .cornerRadius(20)
        .padding(.horizontal, 10)
    }
}

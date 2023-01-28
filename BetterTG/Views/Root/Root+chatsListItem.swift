// Root+chatsListItem.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder func chatsListItem(for customChat: CustomChat) -> some View {
        HStack {
            chatsListPhoto(for: customChat.chat)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(customChat.chat.title)
                    .font(.title2)
                    .foregroundColor(.white)
                
                lastOrDraftMessage(for: customChat)
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

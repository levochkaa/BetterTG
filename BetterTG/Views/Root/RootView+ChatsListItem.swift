// RootView+ChatsListItem.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder func chatsListItem(
        for customChat: CustomChat,
        redacted: Bool = false,
        chatList: ChatList
    ) -> some View {
        HStack {
            if !redacted {
                chatsListPhoto(for: customChat.chat)
            } else {
                Circle()
                    .frame(width: 64)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .unredacted()
                    }
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Text(customChat.chat.title)
                    .font(.title2)
                    .foregroundColor(.white)
                
                lastOrDraftMessage(for: customChat)
            }
            .lineLimit(1)
            
            if let isPinned = customChat.positions.first(where: { $0.list == chatList })?.isPinned, isPinned {
                Spacer()
                
                Button(systemImage: "pin.fill") {
                    viewModel.togglePinned(chatId: customChat.chat.id, chatList: chatList, value: !isPinned)
                }
                .font(.title2)
                .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(5)
        .background(.gray6)
        .cornerRadius(20)
        .padding(.horizontal, 10)
    }
}

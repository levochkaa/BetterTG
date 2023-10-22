// RootView+ChatsListItem.swift

import SwiftUI
import TDLibKit

extension RootView {
    @ViewBuilder func chatsListItem(for customChat: CustomChat) -> some View {
        HStack {
            if let isPinned = customChat.positions.main?.isPinned, isPinned {
                Button(systemImage: "pin.fill") {
                    viewModel.togglePinned(chatId: customChat.chat.id, value: !isPinned)
                }
                .font(.title2)
                .foregroundStyle(.white)
                .padding(.leading, 10)
            }
            
            chatsListPhoto(for: customChat.chat)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(customChat.chat.title)
                    .font(.title2)
                    .foregroundStyle(.white)
                
                lastOrDraftMessage(for: customChat)
            }
            .lineLimit(1)
            
            if customChat.unreadCount != 0 {
                Spacer()
                
                Circle()
                    .fill(.blue)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text("\(customChat.unreadCount)")
                            .font(.callout)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(.trailing, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(5)
        .background(.gray6)
        .cornerRadius(20)
        .padding(.horizontal, 10)
    }
}

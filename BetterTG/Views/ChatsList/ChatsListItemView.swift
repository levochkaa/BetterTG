// ChatsListItemView.swift

import SwiftUI
import TDLibKit

struct ChatsListItemView: View {
    @State var folder: CustomFolder
    @State var customChat: CustomChat
    
    var body: some View {
        HStack {
            if customChat.position.isPinned {
                Button(systemImage: "pin.fill") {
                    Task.background {
                        try await td.toggleChatIsPinned(
                            chatId: customChat.chat.id,
                            chatList: folder.chatList,
                            isPinned: !customChat.position.isPinned
                        )
                    }
                }
                .font(.title2)
                .foregroundStyle(.white)
                .padding(.leading, 10)
            }
            
            let chat = customChat.chat
            ProfileImageView(
                photo: chat.photo?.big,
                minithumbnail: chat.photo?.minithumbnail,
                title: chat.title,
                userId: chat.id,
                fontSize: 40
            )
            .frame(width: 64, height: 64)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(customChat.chat.title)
                    .font(.title2)
                    .foregroundStyle(.white)
                
                LastOrDraftMessageView(customChat: customChat)
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
        .background(Color.gray6)
        .clipShape(.rect(cornerRadius: 20))
        .padding(.horizontal, 10)
    }
}

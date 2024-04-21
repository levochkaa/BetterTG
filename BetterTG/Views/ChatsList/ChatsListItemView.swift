// ChatsListItemView.swift

import SwiftUI
import TDLibKit

struct ChatsListItemView: View {
    @State var customChat: CustomChat
    
    var body: some View {
        HStack {
            if let isPinned = customChat.positions.main?.isPinned, isPinned {
                Button(systemImage: "pin.fill") {
                    Task.background {
                        try await td.toggleChatIsPinned(
                            chatId: customChat.chat.id, chatList: .chatListMain, isPinned: !isPinned
                        )
                    }
                }
                .font(.title2)
                .foregroundStyle(.white)
                .padding(.leading, 10)
            }
            
            ChatsListItemPhotoView(customChat: $customChat)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(customChat.chat.title)
                    .font(.title2)
                    .foregroundStyle(.white)
                
                LastOrDraftMessageView(customChat: $customChat)
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
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 10)
    }
}

private struct ChatsListItemPhotoView: View {
    @Binding var customChat: CustomChat
    
    var body: some View {
        ZStack {
            if let photo = customChat.chat.photo {
                AsyncTdImage(id: photo.small.id) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    if let image = Image(data: photo.minithumbnail?.data) {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        PlaceholderView(customChat: $customChat)
                    }
                }
            } else {
                PlaceholderView(customChat: $customChat)
            }
        }
        .clipShape(Circle())
        .frame(width: 64, height: 64)
    }
}

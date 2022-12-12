// RootView+ChatsListItem.swift

import SwiftUIX
import TDLibKit

extension RootView {
    @ViewBuilder func chatsListItem(for chat: Chat) -> some View {
        HStack {
            chatsListPhoto(for: chat)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(chat.title)
                    .lineLimit(1)
                    .font(.title2)
                    .foregroundColor(.white)
                
                if let draftMessage = chat.draftMessage {
                    draftMessageView(for: draftMessage)
                        .lineLimit(1)
                        .foregroundColor(.gray)
                } else if let lastMessage = chat.lastMessage {
                    InlineMessageContentView(message: lastMessage)
                        .environmentObject(viewModel)
                        .lineLimit(1)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            if viewModel.pinnedChatIds.contains(chat.id) {
                Image(systemName: "pin.fill")
                    .foregroundColor(.white)
                    .padding(.trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(5)
        .background(Color.gray6)
        .cornerRadius(20)
        .padding(.horizontal, 10)
    }
    
    @ViewBuilder func chatsListPhoto(for chat: Chat) -> some View {
        Group {
            if let photo = chat.photo {
                AsyncTdImage(id: photo.small.id) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Group {
                        if let minithumbnail = photo.minithumbnail,
                           let image = Image(data: minithumbnail.data) {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            PlaceholderView(userId: chat.id, title: chat.title)
                        }
                    }
                }
            } else {
                PlaceholderView(userId: chat.id, title: chat.title)
            }
        }
        .clipShape(Circle())
        .frame(width: 64, height: 64)
    }
    
    @ViewBuilder func draftMessageView(for draftMessage: DraftMessage) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text("Draft: ")
                .foregroundColor(.red)
            
            if draftMessage.replyToMessageId != 0 {
                Text("reply ")
                    .foregroundColor(.white)
            }
            
            switch draftMessage.inputMessageText {
                case let .inputMessageText(inputMessageText):
                    Text(inputMessageText.text.text)
                default:
                    Text("BTG not supported")
            }
        }
    }
}

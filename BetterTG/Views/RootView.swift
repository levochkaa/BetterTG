// RootView.swift

import SwiftUI
import TDLibKit

struct RootView: View {
    
    @StateObject private var viewModel = RootViewVM()
    
    var body: some View {
        if let loggedIn = viewModel.loggedIn {
            if loggedIn {
                bodyView
            } else {
                LoginView()
            }
        } else {
            Text("Loading...")
        }
    }

    @ViewBuilder var bodyView: some View {
        NavigationStack {
            mainChatsListView
                .navigationTitle("BetterTG")
        }
    }
    
    @ViewBuilder var mainChatsListView: some View {
        ScrollView {
            LazyVStack {
                ForEach(viewModel.mainChats, id: \.id) { chat in
                    NavigationLink {
                        ChatView(for: chat)
                    } label: {
                        chatListView(for: chat)
                    }
                }
            }
        }
    }
    
    @ViewBuilder func lastMessage(_ msg: Message) -> some View {
        switch msg.content {
            case let .messageText(messageText):
                Text(messageText.text.text)
            case .messageUnsupported:
                Text("TDLib not supported")
            default:
                Text("BTG not supported")
        }
    }

    @ViewBuilder func draftMessage(_ msg: DraftMessage) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text("Draft: ")
                .foregroundColor(.red)

            switch msg.inputMessageText {
                case let .inputMessageText(inputMessageText):
                    Text(inputMessageText.text.text)
                default:
                    Text("BTG not supported")
            }
        }
    }

    @ViewBuilder func chatListView(for chat: Chat) -> some View {
        HStack {
            Group {
                if let photo = chat.photo {
                    AsyncTdImage(id: photo.small.id) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        Group {
                            if let thumbnailData = photo.minithumbnail?.data,
                               let thumbnailUiImage = UIImage(data: thumbnailData) {
                                Image(uiImage: thumbnailUiImage)
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

            VStack(alignment: .leading) {
                Text(chat.title)
                    .lineLimit(1)
                    .font(.title2)
                    .foregroundColor(.white)

                if let draftMessage = chat.draftMessage {
                    self.draftMessage(draftMessage)
                        .lineLimit(1)
                        .foregroundColor(.gray)
                } else {
                    if let lastMessage = chat.lastMessage {
                        self.lastMessage(lastMessage)
                            .lineLimit(1)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(5)
            .background(Color.gray6)
            .cornerRadius(20)
            .padding(.horizontal, 10)
    }
}

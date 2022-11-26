// RootView.swift

import SwiftUI
import TDLibKit

struct RootView: View {

    @StateObject private var viewModel = RootViewVM()

    let scroll = "rootScroll"
    static let chatSize = 84 // 64 for avatar + (5 * 2) padding around + 10 padding between chats
    let maxChatsOnScreen = Int(SystemUtils.size.height / CGFloat(chatSize))

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
                .navigationDestination(for: Chat.self) { chat in
                    ChatView(for: chat)
                }
        }
    }

    @ViewBuilder var mainChatsListView: some View {
        ScrollView {
            ZStack {
                LazyVStack {
                    ForEach(viewModel.mainChats, id: \.id) { chat in
                        NavigationLink(value: chat) {
                            chatListView(for: chat)
                        }
                    }
                }
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: Int(proxy.frame(in: .named(scroll)).maxY)
                    )
                }
            }
        }
            .coordinateSpace(name: scroll)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                if viewModel.loadingUsers {
                    return
                }

                if viewModel.mainChats.count <= maxChatsOnScreen {
                    let approximateValue = viewModel.loadedUsers * RootView.chatSize
                    let bottom = approximateValue - 30
                    let top = approximateValue + 30
                    if (bottom...top).contains(value) {
                        Task {
                            try await viewModel.loadMainChats()
                        }
                    }
                } else {
                    if (700...1100).contains(value) {
                        Task {
                            try await viewModel.loadMainChats()
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

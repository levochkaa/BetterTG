// RootView.swift

import SwiftUI
import TDLibKit

struct RootView: View {
    
    @StateObject private var viewModel = RootViewVM()
    
    @State private var showConfirmChatDelete = false
    @State private var confirmedChatId: Int64 = 0
    
    let scroll = "rootScroll"
    
    static let spacing: CGFloat = 8
    static let chatListViewHeight = Int(74 + RootView.spacing) // 64 for avatar + (5 * 2) padding around
    static let maxChatsOnScreen = Int(SystemUtils.size.height / CGFloat(RootView.chatListViewHeight))
    
    let nc: NotificationCenter = .default
    let tdApi: TdApi = .shared
    let logger = Logger(label: "RootView")
    
    @Environment(\.scenePhase) var scenePhase
    
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
//        UINavigationBar.appearance().compactAppearance = appearance
//        UINavigationBar.appearance().standardAppearance = appearance
//        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
    }
    
    var body: some View {
        Group {
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
        .onAppear {
            let window = UIApplication
                .shared
                .connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first
            window?.overrideUserInterfaceStyle = .dark
        }
    }
    
    @ViewBuilder var bodyView: some View {
        NavigationStack {
            mainChatsListView
                .navigationTitle("BetterTG")
                .onChange(of: scenePhase) { newPhase in
                    Task {
                        switch newPhase {
                            case .active:
                                logger.log("App is Active")
                                try await viewModel.fetchChatsHistory()
                            case .inactive:
                                logger.log("App is Inactive")
                            case .background:
                                logger.log("App is in a Background")
                            @unknown default:
                                logger.log("Unknown state of an App")
                        }
                    }
                }
                .confirmationDialog("Are you sure?", isPresented: $showConfirmChatDelete, titleVisibility: .visible) {
                    AsyncButton("Delete", role: .destructive) {
                        try await viewModel.deleteChat(id: confirmedChatId)
                    }
                }
        }
    }
    
    @ViewBuilder var mainChatsListView: some View {
        ScrollView {
            ZStack {
                LazyVStack(spacing: RootView.spacing) {
                    ForEach(viewModel.mainChats, id: \.id) { chat in
                        NavigationLink {
                            ChatView(chat: chat)
                        } label: {
                            chatListView(for: chat)
                                .contextMenu {
                                    chatListContextMenu(for: chat.id)
                                } preview: {
                                    NavigationStack {
                                        ChatViewPreview(chat: chat)
                                    }
                                }
                        }
                        .onAppear {
                            Task {
                                // preloading chatHistory
                                _ = try await tdApi.getChatHistory(
                                    chatId: chat.id,
                                    fromMessageId: 0,
                                    limit: 30,
                                    offset: 0,
                                    onlyLocal: false
                                )
                            }
                        }
                    }
                    if viewModel.loadingUsers {
                        ProgressView()
                    }
                }
                .padding(.top, 8)
                
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named(scroll))
                    )
                }
            }
        }
        .coordinateSpace(name: scroll)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            if viewModel.loadingUsers { return }
            
            let maxY = Int(value.maxY)
            
            if viewModel.mainChats.count <= RootView.maxChatsOnScreen {
                let approximateValue = viewModel.loadedUsers * RootView.chatListViewHeight
                let bottom = approximateValue - 30
                let top = approximateValue + 30
                let range = (bottom...top)
                if range.contains(maxY) {
                    Task {
                        try await viewModel.loadMainChats()
                    }
                }
            } else {
                let range = (700...1100)
                if range.contains(maxY) {
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
    
    @ViewBuilder func chatListContextMenu(for id: Int64) -> some View {
        Button("Delete", role: .destructive) {
            showConfirmChatDelete = true
            confirmedChatId = id
        }
    }
    
    @ViewBuilder func chatListPhotoView(for chat: Chat) -> some View {
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
    }
    
    @ViewBuilder func chatListView(for chat: Chat) -> some View {
        HStack {
            chatListPhotoView(for: chat)
            
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
}

// RootView.swift

import TDLibKit

struct RootView: View {
    
    @Bindable var viewModel = RootViewModel()
    
    @State var showConfirmChatDelete = false
    @State var deleteChatForAllUsers = false
    @State var confirmedChat: Chat?
    
    @State var query = ""
    @State var selectedTab: Tab = .chats
    
    @Namespace var namespace
    
    @AppStorage("loggedIn") var loggedIn = false
    
    let chatId = "chatId"
    
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        Group {
            if loggedIn {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        channels
                    }
                    .tag(Tab.channels)
                    .tabItem {
                        Label("Channels", systemImage: "stop")
                    }
                    
                    NavigationStack {
                        bodyView
                    }
                    .tag(Tab.chats)
                    .tabItem {
                        Label("Chats", systemImage: "message")
                    }
                    
                    NavigationStack {
                        settings
                    }
                    .tag(Tab.settings)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                }
            } else {
                LoginView()
            }
        }
        .transition(.opacity)
        .animation(value: loggedIn)
        .environment(viewModel)
        .onAppear {
            if viewModel.namespace == nil {
                viewModel.namespace = namespace
            }
        }
        .onReceive(nc.publisher(for: .ready)) { _ in loggedIn = true }
        .onReceive(nc.mergeMany([.closed, .closing, .loggingOut, .waitPhoneNumber, .waitCode, .waitPassword])) { _ in
            loggedIn = false
        }
    }
    
    var bodyView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.filteredSortedChats(query)) { customChat in
                    NavigationLink(value: customChat) {
                        chatsListItem(for: customChat)
                            .matchedGeometryEffect(id: customChat.chat.id, in: namespace)
                    }
                    .contextMenu {
                        contextMenu(for: customChat)
                    } preview: {
                        NavigationStack {
                            ChatView(customChat: customChat)
                                .environment(viewModel)
                                .environment(\.isPreview, true)
                        }
                    }
                    .task {
                        await viewModel.tdGetChatHistory(chatId: customChat.chat.id)
                    }
                }
            }
            .padding(.top, 8)
            .animation(value: viewModel.mainChats)
        }
        .searchable(text: $query, prompt: "Search chats...")
        .navigationTitle("BetterTG")
        .navigationDestination(for: CustomChat.self) { customChat in
            ChatView(customChat: customChat)
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhase(newPhase)
        }
        .confirmationDialog(
            "Are you sure you want to delete chat with \(confirmedChat?.title ?? "User")?",
            isPresented: $showConfirmChatDelete
        ) {
            Button("Delete", role: .destructive) {
                guard let id = confirmedChat?.id else { return }
                Task {
                    await viewModel.tdDeleteChatHistory(chatId: id, forAll: deleteChatForAllUsers)
                }
            }
        }
        .overlay {
            if let openedItem = viewModel.openedItem {
                ItemView(item: openedItem)
                    .zIndex(1)
            }
        }
    }
    
    var channels: some View {
        Text("Channels")
    }
    
    var settings: some View {
        Text("Settings")
    }
}

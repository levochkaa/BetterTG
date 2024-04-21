// RootView.swift

import SwiftUI
import TDLibKit

struct RootView: View {
    
    @State var viewModel = RootViewModel()
    
    @State var showConfirmChatDelete = false
    @State var deleteChatForAllUsers = false
    @State var confirmedChat: Chat?
    
    @State var query = ""
    
    @Namespace var namespace
    
    @AppStorage("loggedIn") var loggedIn = false
    
    let chatId = "chatId"
    
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        Group {
            if loggedIn {
                bodyView
            } else {
                LoginView()
            }
        }
        .transition(.opacity)
        .environment(viewModel)
        .onReceive(nc.publisher(for: .authorizationStateReady)) { _ in withAnimation { loggedIn = true } }
        .onReceive(nc.mergeMany([
            .authorizationStateClosed,
            .authorizationStateClosing,
            .authorizationStateLoggingOut,
            .authorizationStateWaitPhoneNumber,
            .authorizationStateWaitCode,
            .authorizationStateWaitPassword
        ])) { _ in
            withAnimation {
                loggedIn = false
            }
        }
    }
    
    var bodyView: some View {
        NavigationStack {
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
                            LazyView {
                                NavigationStack {
                                    ChatView(customChat: customChat)
                                        .environment(viewModel)
                                        .environment(\.isPreview, true)
                                }
                            }
                        }
                        .task {
                            await viewModel.tdGetChatHistory(chatId: customChat.chat.id)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .searchable(text: $query, prompt: "Search chats...")
            .navigationTitle("BetterTG")
            .navigationDestination(for: CustomChat.self) { customChat in
                ChatView(customChat: customChat)
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
            .onChange(of: scenePhase) { _, newPhase in
                guard case .active = newPhase else { return }
                Task {
                    await viewModel.mainChats.asyncForEach { customChat in
                        await viewModel.tdGetChatHistory(chatId: customChat.chat.id)
                    }
                }
            }
        }
    }
}

// RootView.swift

import SwiftUI
import TDLibKit

struct RootView: View {
    
    @StateObject var viewModel = RootViewModel()
    
    @State var showConfirmChatDelete = false
    @State var deleteChatForAllUsers = false
    @State var confirmedChat: Chat?
    
    @State var query = ""
    @State var queryArchived = ""
    
    @State var showArchivedChats = false
    
    @Namespace var namespace
    
    let chatId = "chatId"
    
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        Group {
            if let loggedIn = viewModel.loggedIn {
                if loggedIn {
                    bodyView
                } else {
                    LoginView()
                }
            } else {
                NavigationStack {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            chatsList(CustomChat.placeholder, redacted: true)
                                .redacted(reason: .placeholder)
                        }
                        .padding(.top, 8)
                    }
                    .navigationTitle("BetterTG")
                    .searchable(text: .constant(""), prompt: "Search chats...")
                    .disabled(true)
                    .scrollDisabled(true)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(systemImage: "square.stack") {}
                                .disabled(true)
                        }
                    }
                }
            }
        }
        .environmentObject(viewModel)
        .onAppear {
            if viewModel.namespace == nil {
                viewModel.namespace = namespace
            }
        }
    }
    
    @ViewBuilder var bodyView: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    switch viewModel.searchScope {
                        case .chats:
                            chatsList(viewModel.filteredSortedChats(query.lowercased()))
                        case .global:
                            chatsList(viewModel.searchedGlobalChats)
                    }
                    
                }
                .padding(.top, 8)
                .animation(.default, value: viewModel.mainChats)
                .animation(.default, value: viewModel.searchedGlobalChats)
            }
            .navigationTitle("BetterTG")
            .searchable(text: $query, prompt: "Search chats...")
            .searchScopes($viewModel.searchScope) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue)
                }
            }
            .onSubmit(of: .search) {
                viewModel.searchGlobalChats(query.lowercased())
            }
            .onChange(of: viewModel.searchScope) { scope in
                guard scope == .global else { return }
                
                if query.isEmpty {
                    viewModel.searchScope = .chats
                } else {
                    viewModel.searchGlobalChats(query)
                }
            }
            .onChange(of: query) { _ in
                if query.isEmpty {
                    viewModel.searchScope = .chats
                }
            }
            .onChange(of: scenePhase) { newPhase in
                viewModel.handleScenePhase(newPhase)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(systemImage: "square.stack") {
                        showArchivedChats = true
                    }
                }
            }
            .navigationDestination(isPresented: $showArchivedChats) {
                archivedChatsView
            }
            .confirmationDialog(
                "Are you sure you want to delete chat with \(confirmedChat?.title ?? "User")?",
                isPresented: $showConfirmChatDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let id = confirmedChat?.id else { return }
                    Task {
                        await viewModel.tdDeleteChatHistory(id: id, forAll: deleteChatForAllUsers)
                    }
                }
            }
        }
        .overlay {
            if viewModel.openedItems != nil {
                ItemsPreview()
            }
        }
    }
}

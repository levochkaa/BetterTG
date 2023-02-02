// RootView.swift

import SwiftUI
import TDLibKit

struct RootView: View {
    
    @StateObject var viewModel = RootViewModel()
    
    @State var showConfirmChatDelete = false
    @State var deleteChatForAllUsers = false
    @State var confirmedChat: Chat?

    @State var openedPhotoInfo: OpenedPhotoInfo?
    @Namespace var rootNamespace
    
    @State var query = ""
    
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
                Text("Loading...")
            }
        }
    }
    
    @ViewBuilder var bodyView: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        switch viewModel.searchScope {
                            case .chats:
                                chatsList(viewModel.filteredSortedMainChats(query.lowercased()))
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
            
            if openedPhotoInfo != nil {
                PhotoViewer(
                    photoInfo: $openedPhotoInfo,
                    namespace: rootNamespace
                )
                .zIndex(1)
            }
        }
    }
}

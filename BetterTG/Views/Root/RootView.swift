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
                        mainChatsList
                    }
                    .padding(.top, 8)
                }
                .navigationTitle("BetterTG")
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
                            await viewModel.tdDeleteChatHystory(id: id, forAll: deleteChatForAllUsers)
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

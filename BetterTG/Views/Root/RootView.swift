// RootView.swift

import SwiftUI
import SwiftUIX
import TDLibKit

struct RootView: View {
    
    @StateObject var viewModel = RootViewModel()
    
    @State var showConfirmChatDelete = false
    @State var confirmedChat: Chat?

    @State var openedMessageContextMenu: CustomMessage?
    @State var openedPhotoInfo: OpenedPhotoInfo?
    @Namespace var rootNamespace
    
    let chatId = "chatId"
    @Namespace var chatNamespace
    
    let scroll = "rootScroll"
    
    static let spacing: CGFloat = 8
    static let chatListViewHeight = Int(74 + RootView.spacing) // 64 for avatar + (5 * 2) padding around
    static let maxChatsOnScreen = Int(Utils.size.height / CGFloat(RootView.chatListViewHeight))
    
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
            UIApplication.window?.overrideUserInterfaceStyle = .dark
        }
    }
    
    @ViewBuilder var bodyView: some View {
        ZStack {
            NavigationStack {
                mainChatsScroll
                    .navigationTitle("BetterTG")
                    .onChange(of: scenePhase) { newPhase in
                        Task {
                            switch newPhase {
                                case .active:
                                    log("App is Active")
                                    await viewModel.fetchChatsHistory()
                                case .inactive:
                                    log("App is Inactive")
                                case .background:
                                    log("App is in a Background")
                                @unknown default:
                                    log("Unknown state of an App")
                            }
                        }
                    }
                    .confirmationDialog(
                        "Are you sure you want to delete chat with \(confirmedChat?.title ?? "User")?",
                        isPresented: $showConfirmChatDelete,
                        titleVisibility: .visible
                    ) {
                        AsyncButton("Delete", role: .destructive) {
                            guard let id = await confirmedChat?.id else { return }
                            await viewModel.tdDeleteChat(id: id)
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

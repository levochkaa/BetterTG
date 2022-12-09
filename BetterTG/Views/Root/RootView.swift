// RootView.swift

import SwiftUI
import TDLibKit

struct RootView: View {
    
    @StateObject var viewModel = RootViewModel()
    
    @State var showConfirmChatDelete = false
    @State var confirmedChat: Chat?
    
    let scroll = "rootScroll"
    
    static let spacing: CGFloat = 8
    static let chatListViewHeight = Int(74 + RootView.spacing) // 64 for avatar + (5 * 2) padding around
    static let maxChatsOnScreen = Int(Utils.size.height / CGFloat(RootView.chatListViewHeight))
    
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
            mainChatsList
                .navigationTitle("BetterTG")
                .onChange(of: scenePhase) { newPhase in
                    Task {
                        switch newPhase {
                            case .active:
                                logger.log("App is Active")
                                await viewModel.fetchChatsHistory()
                            case .inactive:
                                logger.log("App is Inactive")
                            case .background:
                                logger.log("App is in a Background")
                            @unknown default:
                                logger.log("Unknown state of an App")
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
    }
}

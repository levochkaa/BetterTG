// RootView.swift

import SwiftUI
import TDLibKit

struct RootView: View {
    
    @Bindable var viewModel = RootViewModel()
    
    @State var showConfirmChatDelete = false
    @State var deleteChatForAllUsers = false
    @State var confirmedChat: Chat?
    
    @State var query = ""
    @State var queryArchived = ""
    
    @State var showArchivedChats = false
    @State var showSettings = false
    
    @Namespace var namespace
    
    @AppStorage("showArchivedChatsButton") var showArchivedChatsButton = true
    
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
                bodyPlaceholder
            }
        }
        .transition(.opacity)
        .animation(value: viewModel.loggedIn)
        .environment(viewModel)
        .onAppear {
            if viewModel.namespace == nil {
                viewModel.namespace = namespace
            }
        }
    }
}

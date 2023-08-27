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
        .animation(value: loggedIn)
        .environment(viewModel)
        .onAppear {
            if viewModel.namespace == nil {
                viewModel.namespace = namespace
            }
        }
        .onReceive(nc.mergeMany([.closed, .closing, .loggingOut, .waitPhoneNumber, .waitCode, .waitPassword])) { _ in
            loggedIn = false
        }
        .onReceive(nc.publisher(for: .ready)) { _ in
            loggedIn = true
        }
    }
}

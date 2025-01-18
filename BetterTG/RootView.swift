// RootView.swift

import SwiftUI

struct RootView: View {
    @State private var rootVM = RootVM.shared
    
    var body: some View {
        ZStack {
            if rootVM.loggedIn {
                MainView()
            } else {
                LoginView()
            }
        }
        .transition(.opacity)
    }
}

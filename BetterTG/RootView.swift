// RootView.swift

import SwiftUI

struct RootView: View {
    // MARK: Internal

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

    // MARK: Private

    @State private var rootVM = RootVM.shared
}

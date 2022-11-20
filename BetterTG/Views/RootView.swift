// RootView.swift

import SwiftUI

struct RootView: View {

    @StateObject private var viewModel = RootViewVM()

    var body: some View {
        if viewModel.loggedIn {
            bodyView
        } else {
            LoginView()
        }
    }

    @ViewBuilder var bodyView: some View {
        Text("List of chats")
    }
}

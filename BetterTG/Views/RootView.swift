// RootView.swift

import SwiftUI

struct RootView: View {

    @StateObject private var viewModel = RootViewVM()

    var body: some View {
        if viewModel.loggedIn {
            Text("")
        } else {
            LoginView()
        }
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}

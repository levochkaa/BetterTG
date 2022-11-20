// LoginView.swift

import SwiftUI

struct LoginView: View {

    @StateObject var viewModel = LoginViewVM()

    @State var showSelectCountryView = false
    @State var searchCountries = ""
    @FocusState var focused

    let logger = Logger(label: "Login")
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    switch viewModel.loginState {
                        case .phoneNumber:
                            phoneNumberView
                        case .code:
                            codeView
                        case .twoFactor:
                            twoFactorView
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    )
                    .combined(with: .opacity)
                )
            }
            .animation(.spring(), value: viewModel.loginState)
            .navigationTitle("Login")
            .alert("Error", isPresented: $viewModel.showError, actions: {}, message: {
                Text(viewModel.errorMessage)
            })
        }
    }
}

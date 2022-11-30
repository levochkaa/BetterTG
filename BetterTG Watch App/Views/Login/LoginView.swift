// LoginView.swift

import SwiftUI
import TDLibKit

struct LoginView: View {
    
    @StateObject var viewModel = LoginViewVM()
    
    let logger = Logger(label: "Login")
    
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

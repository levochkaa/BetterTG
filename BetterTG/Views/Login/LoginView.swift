// LoginView.swift

import SwiftUI

struct LoginView: View {
    
    @StateObject var viewModel = LoginViewModel()
    
    @State var showSelectCountryView = false
    @State var searchCountries = ""
    @FocusState var focusedPhoneNumber
    @FocusState var focusedTwoFactor
    @FocusState var focusedCode
    
    var body: some View {
        NavigationStack {
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
            .animation(value: viewModel.loginState)
            .navigationTitle("Login")
            .errorAlert(
                show: $viewModel.errorShown,
                text: "There was an error with Authorization state. Please, restart the app."
            )
        }
    }
}

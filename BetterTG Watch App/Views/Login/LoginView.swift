// LoginView.swift

import SwiftUI
import TDLibKit

struct LoginView: View {

    @ObservedObject var rootVM: RootViewVM
    @StateObject var viewModel = LoginViewVM()

    @State var loginState: LoginState = .phoneNumber

    @State var countryNums = [PhoneNumberInfo]()
    @State var selectedCountryNum = PhoneNumberInfo(country: "RU", phoneNumberPrefix: "7")
    @State var phoneNumber = ""
    @State var code = ""
    @State var hint = ""
    @State var twoFactor = ""

    @State var showError = false
    @State var errorMessage = ""

    let logger = Logger(label: "Login")

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    switch loginState {
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
            .animation(.spring(), value: loginState)
            .navigationTitle("Login")
            .alert("Error", isPresented: $showError, actions: {}, message: {
                Text(errorMessage)
            })
        }
    }

    func handleAuthorizationState() async {
        do {
            let state = try await viewModel.getAuthorizationState()
            logger.log("\(state)")

            switch try await viewModel.getAuthorizationState() {
                case .authorizationStateWaitPassword(_):
                    try await viewModel.checkAuth(password: twoFactor)
                    await handleAuthorizationState()

                case .authorizationStateWaitCode(_):
                    try await viewModel.checkAuth(code: code)
                    switch try await viewModel.getAuthorizationState() {
                        case let .authorizationStateWaitPassword(authorizationStateWaitPassword):
                            hint = authorizationStateWaitPassword.passwordHint
                            loginState = .twoFactor
                        default:
                            await handleAuthorizationState()
                    }

                case .authorizationStateWaitPhoneNumber:
                    try await viewModel.checkAuth(
                        phoneNumber: "\(selectedCountryNum.phoneNumberPrefix)\(phoneNumber)")
                    loginState = .code

                case .authorizationStateReady:
                    rootVM.loggedIn = true

                default:
                    errorMessage = "Something is wrong, try to reopen the app or reinstall it"
                    showError = true
            }

        } catch {
            guard let tdError = error as? TDLibKit.Error else { return }
            logger.log("HandlingAuthStateError: \(tdError.code) - \(tdError.message)", level: .error)
            errorMessage = "\(tdError.message)"
            showError = true
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(rootVM: RootViewVM())
    }
}

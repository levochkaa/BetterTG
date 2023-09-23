// LoginView.swift

struct LoginView: View {
    
    @State var viewModel = LoginViewModel()
    
    @State var showSelectCountryView = false
    @State var searchCountries = ""
    @FocusState var focused: LoginState?
    
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
    
    @ViewBuilder func bottomButton(_ action: @escaping () -> Void) -> some View {
        Spacer()
        
        Button {
            action()
            Task {
                await viewModel.handleAuthorizationState()
            }
        } label: {
            Text("Continue")
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding(.bottom, 10)
    }
}

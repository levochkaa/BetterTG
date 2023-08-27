// LoginView+TwoFactor.swift

extension LoginView {
    @ViewBuilder var twoFactorView: some View {
        VStack {
            SpacingAround {
                Text("2FA Password")
                    .font(.largeTitle)
            }
            
            SecureField(viewModel.hint.isEmpty ? "2FA" : viewModel.hint, text: $viewModel.twoFactor)
                .focused($focused, equals: .twoFactor)
                .textContentType(.password)
                .keyboardType(.alphabet)
                .padding()
                .background(.gray6)
                .cornerRadius(10)
            
            bottomButton {
                focused = nil
            }
        }
        .padding()
    }
}

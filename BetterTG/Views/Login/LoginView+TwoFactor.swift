// LoginView+TwoFactor.swift

import SwiftUI

extension LoginView {
    @ViewBuilder var twoFactorView: some View {
        VStack {
            Spacer()
            
            Text("2FA Password")
                .font(.largeTitle)
            
            Spacer()
            
            SecureField(viewModel.hint.isEmpty ? "2FA" : viewModel.hint, text: $viewModel.twoFactor)
                .focused($focusedTwoFactor)
                .textContentType(.password)
                .keyboardType(.alphabet)
                .padding()
                .background(.gray6)
                .cornerRadius(10)
            
            Spacer()
            
            Button {
                focusedTwoFactor = false
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
        .padding()
        .onAppear {
            focusedTwoFactor = true
        }
    }
}

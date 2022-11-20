// LoginView+TwoFactor.swift

import SwiftUI

extension LoginView {
    @ViewBuilder var twoFactorView: some View {
        VStack {
            Spacer()
            
            Text("2FA Password")
                .font(.largeTitle)
            
            Spacer()
            
            TextField(viewModel.hint.isEmpty ? "2FA" : viewModel.hint, text: $viewModel.twoFactor)
                .focused($focused)
                .padding()
                .background(Color.gray6)
                .cornerRadius(10)
            
            Spacer()
            
            Button {
                Task {
                    await viewModel.handleAuthorizationState()
                }
            } label: {
                Text("Continue")
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .padding()
        .onAppear {
            focused = true
        }
    }
}

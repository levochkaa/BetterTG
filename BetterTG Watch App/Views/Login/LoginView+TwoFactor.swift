// LoginView+TwoFactor.swift

import SwiftUI
import TDLibKit

extension LoginView {
    @ViewBuilder var twoFactorView: some View {
        TextField(viewModel.hint.isEmpty ? "2FA" : viewModel.hint, text: $viewModel.twoFactor)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await viewModel.handleAuthorizationState()
                        }
                    } label: {
                        Text("Continue")
                    }
                }
            }
    }
}

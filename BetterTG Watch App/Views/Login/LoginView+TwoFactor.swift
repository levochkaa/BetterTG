// LoginView+TwoFactor.swift

import SwiftUI
import TDLibKit

extension LoginView {
    @ViewBuilder var twoFactorView: some View {
        TextField(hint.isEmpty ? "2FA" : hint, text: $twoFactor)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await handleAuthorizationState()
                        }
                    } label: {
                        Text("Continue")
                    }
                }
            }
    }
}

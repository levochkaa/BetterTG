// LoginView+Code.swift

import SwiftUI
import TDLibKit

extension LoginView {
    @ViewBuilder var codeView: some View {
        TextField("Code", text: $viewModel.code)
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

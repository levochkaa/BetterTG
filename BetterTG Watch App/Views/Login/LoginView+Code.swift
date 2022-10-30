// LoginView+Code.swift

import SwiftUI
import TDLibKit

extension LoginView {
    @ViewBuilder var codeView: some View {
        TextField("Code", text: $code)
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

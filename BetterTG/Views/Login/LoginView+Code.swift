// LoginView+Code.swift

import SwiftUI

extension LoginView {
    @ViewBuilder var codeView: some View {
        VStack {
            SpacingAround {
                Text("Code from Telegram")
                    .font(.largeTitle)
            }
            
            TextField("Code", text: $viewModel.code)
                .focused($focusedCode)
                .keyboardType(.numberPad)
                .padding()
                .background(.gray6)
                .cornerRadius(10)
            
            bottomButton {
                focusedCode = false
            }
        }
        .padding()
        .onAppear {
            focusedCode = true
        }
    }
}

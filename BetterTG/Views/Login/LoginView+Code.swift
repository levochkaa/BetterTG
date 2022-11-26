// LoginView+Code.swift

import SwiftUI

extension LoginView {
    @ViewBuilder var codeView: some View {
        VStack {
            Spacer()
            
            Text("Code from Telegram")
                .font(.largeTitle)
            
            Spacer()
            
            TextField("Code", text: $viewModel.code)
                .focused($focused)
                .keyboardType(.numberPad)
                .padding()
                .background(Color.gray6)
                .cornerRadius(10)
            
            Spacer()
            
            Button {
                focused = false
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

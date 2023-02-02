// code.swift

import SwiftUI

extension LoginView {
    @ViewBuilder var codeView: some View {
        VStack {
            Spacer()
            
            Text("Code from Telegram")
                .font(.largeTitle)
            
            Spacer()
            
            TextField("Code", text: $viewModel.code)
                .focused($focusedCode)
                .keyboardType(.numberPad)
                .padding()
                .background(.gray6)
                .cornerRadius(10)
            
            Spacer()
            
            Button {
                focusedCode = false
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
            focusedCode = true
        }
    }
}

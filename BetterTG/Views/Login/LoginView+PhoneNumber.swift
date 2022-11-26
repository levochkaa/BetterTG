// LoginView+PhoneNumber.swift

import SwiftUI

extension LoginView {
    @ViewBuilder var phoneNumberView: some View {
        VStack(spacing: 10) {
            Spacer()
            
            Text("Your phone")
                .font(.largeTitle)
            
            Spacer()
            
            VStack {
                Button {
                    focused = false
                    showSelectCountryView.toggle()
                } label: {
                    Text(viewModel.selectedCountryNum.name)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("+\(viewModel.selectedCountryNum.phoneNumberPrefix)")

                    TextField("Phone Number", text: $viewModel.phoneNumber)
                        .focused($focused)
                        .keyboardType(.numberPad)
                }
            }
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
        .sheet(isPresented: $showSelectCountryView) {
            selectCountryView
        }
        .onAppear {
            focused = true
            viewModel.loadCountries()
        }
    }
}

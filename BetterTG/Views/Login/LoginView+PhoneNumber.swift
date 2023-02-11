// LoginView+PhoneNumber.swift

import SwiftUI

extension LoginView {
    @ViewBuilder var phoneNumberView: some View {
        VStack(spacing: 10) {
            SpacingAround {
                Text("Your phone")
                    .font(.largeTitle)
            }
            
            GroupBox {
                HStack {
                    Text("+\(viewModel.selectedCountryNum.phoneNumberPrefix)")
                    
                    TextField("Phone Number", text: $viewModel.phoneNumber)
                        .focused($focusedPhoneNumber)
                        .keyboardType(.numberPad)
                }
            } label: {
                Button(viewModel.selectedCountryNum.name) {
                    focusedPhoneNumber = false
                    showSelectCountryView.toggle()
                }
            }
            
            Spacer()
            
            Button {
                focusedPhoneNumber = false
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
        .sheet(isPresented: $showSelectCountryView) {
            selectCountryView
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            focusedPhoneNumber = true
            viewModel.loadCountries()
        }
    }
}

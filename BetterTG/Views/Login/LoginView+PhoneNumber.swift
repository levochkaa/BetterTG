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
            
            bottomButton {
                focusedPhoneNumber = false
            }
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

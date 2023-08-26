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
                        .focused($focused, equals: .phoneNumber)
                        .keyboardType(.numberPad)
                }
            } label: {
                Button(viewModel.selectedCountryNum.name) {
                    showSelectCountryView.toggle()
                }
            }
            
            bottomButton {
                focused = .code
            }
        }
        .padding()
        .sheet(isPresented: $showSelectCountryView) {
            selectCountryView
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            viewModel.loadCountries()
        }
    }
}

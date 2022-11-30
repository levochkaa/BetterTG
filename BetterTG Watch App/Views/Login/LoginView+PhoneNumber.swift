// LoginView+PhoneNumber.swift

import SwiftUI
import TDLibKit

extension LoginView {
    @ViewBuilder var phoneNumberView: some View {
        VStack {
            Picker("Country Code", selection: $viewModel.selectedCountryNum) {
                ForEach(viewModel.countryNums, id: \.self) { info in
                    HStack {
                        Text(info.country)
                        
                        Spacer()
                        
                        Text("+\(info.phoneNumberPrefix)")
                    }
                }
            }
            .pickerStyle(.navigationLink)
            
            TextField("Phone Number", text: $viewModel.phoneNumber)
        }
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
        .onAppear {
            viewModel.loadCountries()
        }
    }
}

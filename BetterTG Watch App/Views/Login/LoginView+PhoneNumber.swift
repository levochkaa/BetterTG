// LoginView+PhoneNumber.swift

import SwiftUI
import TDLibKit

extension LoginView {
    @ViewBuilder var phoneNumberView: some View {
        VStack {
            Picker("Country Code", selection: $selectedCountryNum) {
                ForEach(countryNums, id: \.self) { info in
                    HStack {
                        Text(info.country)

                        Spacer()

                        Text("+\(info.phoneNumberPrefix)")
                    }
                }
            }
            .pickerStyle(.navigationLink)

            TextField("Phone Number", text: $phoneNumber)
        }
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
        .onAppear {
            Task {
                let countries = try await viewModel.getCountries()
                let countryCode = try await viewModel.getCountryCode()

                guard let country = countries
                    .first(where: { $0.countryCode == countryCode })
                else { return }

                selectedCountryNum = PhoneNumberInfo(
                    country: country.countryCode,
                    phoneNumberPrefix: country.callingCodes[0]
                )
                countryNums = countries
                    .map {
                        PhoneNumberInfo(country: $0.countryCode, phoneNumberPrefix: $0.callingCodes[0])
                    }
                    .sorted {
                        $0.country < $1.country
                    }

                logger.log("Selected Country: \(selectedCountryNum)")
                logger.log("All countryNums: \(countryNums)")
            }
        }
    }
}

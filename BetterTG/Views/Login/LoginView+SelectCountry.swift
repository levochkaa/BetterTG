// LoginView+SelectCountry.swift

import SwiftUI

extension LoginView {
    @ViewBuilder var selectCountryView: some View {
        NavigationStack {
            let countries = viewModel.getFilteredCountries(query: searchCountries)
            List(countries, id: \.self) { info in
                Button {
                    viewModel.selectedCountryNum = info
                    showSelectCountryView.toggle()
                } label: {
                    HStack {
                        Text(info.name)

                        Spacer()

                        Text("+\(info.phoneNumberPrefix)")

                        if info == viewModel.selectedCountryNum {
                            Image(systemName: "checkmark")
                        }
                    }
                        .foregroundColor(.white)
                }
                    .listRowBackground(Color.black)
            }
                .background(.black)
                .scrollContentBackground(.hidden)
                .navigationTitle("Country")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchCountries, placement: .navigationBarDrawer(displayMode: .always))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showSelectCountryView.toggle()
                        }
                    }
                }
        }
    }
}

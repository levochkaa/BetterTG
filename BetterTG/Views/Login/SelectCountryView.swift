// SelectCountryView.swift

import SwiftUI
@preconcurrency import TDLibKit

struct SelectCountryView: View {
    @Binding var showSelectCountryView: Bool
    @Binding var selectedCountryNum: PhoneNumberInfo
    
    @State var countryNums = [PhoneNumberInfo]()
    @State var query = ""
    
    var filteredCountries: [PhoneNumberInfo] {
        countryNums
            .filter { country in
                query.isEmpty
                || country.name.lowercased().contains(query.lowercased())
                || country.phoneNumberPrefix.lowercased().contains(query.lowercased())
                || country.country.lowercased().contains(query.lowercased())
            }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredCountries, id: \.self) { info in
                Button {
                    selectedCountryNum = info
                    showSelectCountryView.toggle()
                } label: {
                    HStack {
                        Text(info.name)
                        Spacer()
                        Text("+\(info.phoneNumberPrefix)")
                    }
                    .foregroundStyle(.white)
                }
            }
            .background(.black)
            .padding(.top, -20)
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showSelectCountryView.toggle()
                    }
                }
            }
        }
        .task { await loadCountries() }
    }
    
    func loadCountries() async {
        guard let countries = try? await td.getCountries().countries,
              let countryCode = try? await td.getCountryCode().text,
              let country = countries.first(where: { $0.countryCode == countryCode })
        else { return }
        
        let selectedCountryNum = PhoneNumberInfo(
            country: country.countryCode,
            phoneNumberPrefix: country.callingCodes[0],
            name: country.englishName
        )
        let countryNums = countries
            .map {
                PhoneNumberInfo(
                    country: $0.countryCode,
                    phoneNumberPrefix: $0.callingCodes[0],
                    name: $0.englishName
                )
            }
            .sorted { $0.name < $1.name }
        
        self.selectedCountryNum = selectedCountryNum
        self.countryNums = countryNums
    }
}

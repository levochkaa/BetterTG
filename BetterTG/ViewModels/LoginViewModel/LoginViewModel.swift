// LoginViewModel.swift

import SwiftUI
import Combine
import TDLibKit

class LoginViewModel: ObservableObject {
    @Published var loginState: LoginState = .phoneNumber
    
    @Published var countryNums = [PhoneNumberInfo]()
    @Published var selectedCountryNum = PhoneNumberInfo(
        country: "RU",
        phoneNumberPrefix: "7",
        name: "Russian Federation"
    )
    
    @Published var phoneNumber = ""
    @Published var code = ""
    @Published var hint = ""
    @Published var twoFactor = ""
    
    init() {
        setPublishers()
        
        Task {
            switch await self.tdGetAuthorizationState() {
                case .authorizationStateWaitPassword:
                    self.loginState = .twoFactor
                case .authorizationStateWaitCode:
                    self.loginState = .code
                default:
                    break
            }
        }
    }
    
    func handleAuthorizationState() async {
        switch await tdGetAuthorizationState() {
            case .authorizationStateWaitPassword:
                await tdCheckAuthenticationPassword(password: twoFactor)
            case .authorizationStateWaitCode:
                await tdCheckAuthenticationCode(code: code)
            case .authorizationStateWaitPhoneNumber:
                await tdSetAuthenticationPhoneNumber(
                    phoneNumber: "\(selectedCountryNum.phoneNumberPrefix)\(phoneNumber)"
                )
            default:
                break
        }
    }
    
    func loadCountries() {
        Task {
            guard let countries = await tdGetCountries(),
                  let countryCode = await tdGetCountryCode(),
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
                .sorted {
                    $0.name < $1.name
                }
            
            await MainActor.run {
                self.selectedCountryNum = selectedCountryNum
                self.countryNums = countryNums
            }
        }
    }
    
    func getFilteredCountries(query: String) -> [PhoneNumberInfo] {
        let countries = countryNums
        let query = query.lowercased()
        
        return query.isEmpty ? countries : countries.filter { country in
            country.name.lowercased().contains(query)
            || country.phoneNumberPrefix.lowercased().contains(query)
            || country.country.lowercased().contains(query)
        }
    }
}

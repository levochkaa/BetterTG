// LoginViewModel.swift

import SwiftUI
import Combine
import TDLibKit
import Observation

@Observable final class LoginViewModel {
    var loginState: LoginState = .phoneNumber
    
    var countryNums = [PhoneNumberInfo]()
    var selectedCountryNum = PhoneNumberInfo(
        country: "RU",
        phoneNumberPrefix: "7",
        name: "Russian Federation"
    )
    
    var phoneNumber = ""
    var code = ""
    var hint = ""
    var twoFactor = ""
    
    var errorShown = false
    
    var cancellables = Set<AnyCancellable>()
    
    init() {
        setPublishers()
        
        Task {
            let authState = await tdGetAuthorizationState()
            await MainActor.run {
                withAnimation {
                    switch authState {
                        case .authorizationStateWaitPassword: loginState = .twoFactor
                        case .authorizationStateWaitCode: loginState = .code
                        case .authorizationStateClosed, .authorizationStateClosing, .authorizationStateLoggingOut:
                            errorShown = true
                        default: break
                    }
                }
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
    
    func loadCountries() async {
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

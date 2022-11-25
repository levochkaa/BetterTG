// LoginViewVM.swift

import SwiftUI
import Combine
import TDLibKit

class LoginViewVM: ObservableObject {
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
    
    @Published var showError = false
    @Published var errorMessage = ""
    
    private let tdApi: TdApi = .shared
    private let logger = Logger(label: "LoginVM")
    private let nc: NotificationCenter = .default
    
    init() {
        self.setPublishers()
    }
    
    func setPublishers() {
        nc.publisher(for: .waitPassword) { notification in
            self.loginState = .twoFactor
            if let waitPassword = notification.object as? AuthorizationStateWaitPassword {
                self.hint = waitPassword.passwordHint
            }
        }
        
        nc.publisher(for: .waitCode) { _ in
            self.loginState = .code
        }
        
        nc.mergeMany([
            nc.publisher(for: .waitPhoneNumber),
            nc.publisher(for: .closed),
            nc.publisher(for: .closing),
            nc.publisher(for: .loggingOut)
        ]) { _ in
            self.loginState = .phoneNumber
        }
    }
    
    func getAuthorizationState() async throws -> AuthorizationState {
        return try await tdApi.getAuthorizationState()
    }
    
    func resendAuthCode() async throws {
        _ = try await tdApi.resendAuthenticationCode()
    }
    
    func checkAuth(phoneNumber: String) async throws {
        _ = try await tdApi.setAuthenticationPhoneNumber(
            phoneNumber: phoneNumber,
            settings: nil
        )
    }
    
    func checkAuth(code: String) async throws {
        _ = try await tdApi.checkAuthenticationCode(code: code)
    }
    
    func checkAuth(password: String) async throws {
        _ = try await tdApi.checkAuthenticationPassword(password: password)
    }
    
    func getCountries() async throws -> [CountryInfo] {
        return try await tdApi.getCountries().countries
    }
    
    func getCountryCode() async throws -> String {
        return try await tdApi.getCountryCode().text
    }
    
    func handleAuthorizationState() async {
        do {
            switch try await getAuthorizationState() {
            case .authorizationStateWaitPassword:
                try await checkAuth(password: twoFactor)
            case .authorizationStateWaitCode:
                try await checkAuth(code: code)
            case .authorizationStateWaitPhoneNumber:
                try await checkAuth(
                    phoneNumber: "\(selectedCountryNum.phoneNumberPrefix)\(phoneNumber)"
                )
            default:
                break
            }
        } catch {
            guard let tdError = error as? TDLibKit.Error else { return }
            logger.log("HandlingAuthStateError: \(tdError.code) - \(tdError.localizedDescription)")
            
            DispatchQueue.main.async {
                self.errorMessage = "\(tdError.message)"
                self.showError = true
            }
        }
    }
    
    func loadCountries() {
        Task {
            let countries = try await getCountries()
            let countryCode = try await getCountryCode()

            guard let country = countries
                .first(where: { $0.countryCode == countryCode })
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
            DispatchQueue.main.async {
                self.selectedCountryNum = selectedCountryNum
                self.countryNums = countryNums
            }
        }
    }
    
    func getFilteredCountries(query: String) -> [PhoneNumberInfo] {
        let countries = self.countryNums
        let query = query.lowercased()
        
        if query.isEmpty {
            return countries
        } else {
            return countries.filter {
                $0.name.lowercased().contains(query)
                || $0.phoneNumberPrefix.lowercased().contains(query)
                || $0.country.lowercased().contains(query)
            }
        }
    }
}

// LoginViewModel+Td.swift

import TDLibKit

extension LoginViewModel {
    func tdGetAuthorizationState() async -> AuthorizationState? {
        do {
            return try await td.getAuthorizationState()
        } catch {
            log("Error getting authState: \(error)")
            return nil
        }
    }
    
    func tdResendAuthenticationCode() async {
        do {
            try await td.resendAuthenticationCode()
        } catch {
            log("Error resending authCode: \(error)")
        }
    }
    
    func tdSetAuthenticationPhoneNumber(phoneNumber: String) async {
        do {
            try await td.setAuthenticationPhoneNumber(
                phoneNumber: phoneNumber,
                settings: nil
            )
        } catch {
            log("Error checking authPhoneNumber: \(error)")
        }
    }
    
    func tdCheckAuthenticationCode(code: String) async {
        do {
            try await td.checkAuthenticationCode(code: code)
        } catch {
            log("Error checking authCode: \(error)")
        }
    }
    
    func tdCheckAuthenticationPassword(password: String) async {
        do {
            try await td.checkAuthenticationPassword(password: password)
        } catch {
            log("Error checking authPassword: \(error)")
        }
    }
    
    func tdGetCountries() async -> [CountryInfo]? {
        do {
            return try await td.getCountries().countries
        } catch {
            log("Error getting countries: \(error)")
            return nil
        }
    }
    
    func tdGetCountryCode() async -> String? {
        do {
            return try await td.getCountryCode().text
        } catch {
            log("Error getting countryCode: \(error)")
            return nil
        }
    }
}

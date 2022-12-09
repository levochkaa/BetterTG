// LoginViewModel+Td.swift

import SwiftUI
import TDLibKit

extension LoginViewModel {
    func tdGetAuthorizationState() async -> AuthorizationState? {
        do {
            return try await tdApi.getAuthorizationState()
        } catch {
            logger.log("Error getting authState: \(error)")
            return nil
        }
    }
    
    func tdResendAuthenticationCode() async {
        do {
            _ = try await tdApi.resendAuthenticationCode()
        } catch {
            logger.log("Error resending authCode: \(error)")
        }
    }
    
    func tdSetAuthenticationPhoneNumber(phoneNumber: String) async {
        do {
            _ = try await tdApi.setAuthenticationPhoneNumber(
                phoneNumber: phoneNumber,
                settings: nil
            )
        } catch {
            logger.log("Error checking authPhoneNumber: \(error)")
        }
    }
    
    func tdCheckAuthenticationCode(code: String) async {
        do {
            _ = try await tdApi.checkAuthenticationCode(code: code)
        } catch {
            logger.log("Error checking authCode: \(error)")
        }
    }
    
    func tdCheckAuthenticationPassword(password: String) async {
        do {
            _ = try await tdApi.checkAuthenticationPassword(password: password)
        } catch {
            logger.log("Error checking authPassword: \(error)")
        }
    }
    
    func tdGetCountries() async -> [CountryInfo]? {
        do {
            return try await tdApi.getCountries().countries
        } catch {
            logger.log("Error getting countries: \(error)")
            return nil
        }
    }
    
    func tdGetCountryCode() async -> String? {
        do {
            return try await tdApi.getCountryCode().text
        } catch {
            logger.log("Error getting countryCode: \(error)")
            return nil
        }
    }
}

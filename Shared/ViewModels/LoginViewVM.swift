// LoginViewVM.swift

import SwiftUI
import TDLibKit

class LoginViewVM: ObservableObject {
    private let tdApi: TdApi = .shared
    private let logger = Logger(label: "LoginVM")

    func getAuthorizationState() async throws -> AuthorizationState {
        return try await tdApi.getAuthorizationState()
    }

    func resendAuthCode() async throws -> Ok {
        return try await tdApi.resendAuthenticationCode()
    }

    func checkAuth(phoneNumber: String) async throws -> Ok {
        return try await tdApi.setAuthenticationPhoneNumber(
            phoneNumber: phoneNumber,
            settings: nil
        )
    }

    func checkAuth(code: String) async throws -> Ok {
        return try await tdApi.checkAuthenticationCode(code: code)
    }

    func checkAuth(password: String) async throws -> Ok {
        return try await tdApi.checkAuthenticationPassword(password: password)
    }

    func getCountries() async throws -> [CountryInfo] {
        return try await tdApi.getCountries().countries
    }

    func getCountryCode() async throws -> String {
        return try await tdApi.getCountryCode().text
    }
}

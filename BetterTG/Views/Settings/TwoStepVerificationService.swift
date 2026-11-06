// TwoStepVerificationService.swift

import TDLibKit
import UIKit

// MARK: - TwoStepVerificationConfiguration

/// TwoStepVerificationAccessConfiguration, read from TDLib's passwordState: whether a password is set, its hint, the
/// recovery email, Telegram Passport data, an email that waits for its code and a pending reset.
struct TwoStepVerificationConfiguration: Equatable {
    struct PendingEmail: Equatable {
        let pattern: String
        /// The code's length, when TDLib knows it; the code is checked as soon as it is this long.
        let codeLength: Int?
    }

    var hasPassword: Bool
    var hint: String
    var hasRecoveryEmail: Bool
    var hasPassportData: Bool
    var pendingEmail: PendingEmail?
    /// When a password without a recovery email may be reset, as a Unix time.
    var pendingResetDate: Int?
}

extension TwoStepVerificationConfiguration {
    init(_ state: TDNativePasswordState) {
        self.init(
            hasPassword: state.hasPassword,
            hint: state.passwordHint,
            hasRecoveryEmail: state.hasRecoveryEmailAddress,
            hasPassportData: state.hasPassportData,
            pendingEmail: state.recoveryEmailAddressCodeInfo.map {
                PendingEmail(pattern: $0.emailAddressPattern, codeLength: $0.length > 0 ? $0.length : nil)
            },
            pendingResetDate: state.pendingResetDate > 0 ? state.pendingResetDate : nil,
        )
    }
}

// MARK: - TwoStepVerificationResetResult

/// TDLib's resetPasswordResult, as Telegram's requestTwoStepPasswordReset reports it.
enum TwoStepVerificationResetResult: Equatable {
    case done
    case waitingForReset(date: Int)
    case declined(retryDate: Int)
}

// MARK: - TwoStepVerificationService

/// The requests behind Telegram's two-step verification screens. The app's runs them on the account's client; the
/// probe answers them itself, so the screens can be driven without changing an account's password.
@MainActor protocol TwoStepVerificationService: AnyObject {
    func configuration() async throws -> TwoStepVerificationConfiguration
    /// requestTwoStepVerifiationSettings: checks the password and returns the recovery email.
    func verify(password: String) async throws -> String
    func setPassword(
        old: String,
        new: String,
        hint: String,
        email: String?,
    ) async throws -> TwoStepVerificationConfiguration
    func setRecoveryEmail(password: String, email: String) async throws -> TwoStepVerificationConfiguration
    func checkEmailCode(_ code: String) async throws -> TwoStepVerificationConfiguration
    func resendEmailCode() async throws -> TwoStepVerificationConfiguration
    func cancelEmailVerification() async throws -> TwoStepVerificationConfiguration
    /// requestTwoStepVerificationPasswordRecoveryCode: emails a recovery code and returns the address's pattern.
    func requestRecoveryCode() async throws -> String
    func checkRecoveryCode(_ code: String) async throws
    func recoverPassword(code: String, new: String, hint: String) async throws -> TwoStepVerificationConfiguration
    func resetPassword() async throws -> TwoStepVerificationResetResult
    func cancelPasswordReset() async throws
}

// MARK: - TDLibTwoStepVerificationService

/// TwoStepVerificationService on an account's TDLib client.
@MainActor final class TDLibTwoStepVerificationService: TwoStepVerificationService {
    private let client: TDLibClient

    init(client: TDLibClient) {
        self.client = client
    }

    func configuration() async throws -> TwoStepVerificationConfiguration {
        try await TwoStepVerificationConfiguration(client.send(TDNativeRequests.getPasswordState()))
    }

    func verify(password: String) async throws -> String {
        try await client.send(TDNativeRequests.getRecoveryEmailAddress(password: password)).recoveryEmailAddress
    }

    func setPassword(
        old: String,
        new: String,
        hint: String,
        email: String?,
    ) async throws -> TwoStepVerificationConfiguration {
        try await TwoStepVerificationConfiguration(client.send(TDNativeRequests.setPassword(
            oldPassword: old,
            newPassword: new,
            newHint: hint,
            setRecoveryEmailAddress: email != nil,
            newRecoveryEmailAddress: email ?? "",
        )))
    }

    func setRecoveryEmail(password: String, email: String) async throws -> TwoStepVerificationConfiguration {
        try await TwoStepVerificationConfiguration(client.send(TDNativeRequests.setRecoveryEmailAddress(
            password: password,
            newRecoveryEmailAddress: email,
        )))
    }

    func checkEmailCode(_ code: String) async throws -> TwoStepVerificationConfiguration {
        try await TwoStepVerificationConfiguration(client.send(TDNativeRequests.checkRecoveryEmailAddressCode(
            code: code,
        )))
    }

    func resendEmailCode() async throws -> TwoStepVerificationConfiguration {
        try await TwoStepVerificationConfiguration(client.send(TDNativeRequests.resendRecoveryEmailAddressCode()))
    }

    func cancelEmailVerification() async throws -> TwoStepVerificationConfiguration {
        try await TwoStepVerificationConfiguration(client.send(
            TDNativeRequests.cancelRecoveryEmailAddressVerification(),
        ))
    }

    func requestRecoveryCode() async throws -> String {
        try await client.send(TDNativeRequests.requestPasswordRecovery()).emailAddressPattern
    }

    func checkRecoveryCode(_ code: String) async throws {
        _ = try await client.send(TDNativeRequests.checkPasswordRecoveryCode(recoveryCode: code))
    }

    func recoverPassword(code: String, new: String, hint: String) async throws -> TwoStepVerificationConfiguration {
        try await TwoStepVerificationConfiguration(client.send(TDNativeRequests.recoverPassword(
            recoveryCode: code,
            newPassword: new,
            newHint: hint,
        )))
    }

    func resetPassword() async throws -> TwoStepVerificationResetResult {
        switch try await client.send(TDNativeRequests.resetPassword()) {
        case .resetPasswordResultOk: .done
        case .resetPasswordResultPending(let pending): .waitingForReset(date: pending.pendingResetDate)
        case .resetPasswordResultDeclined(let declined): .declined(retryDate: declined.retryDate)
        }
    }

    func cancelPasswordReset() async throws {
        _ = try await client.send(TDNativeRequests.cancelPasswordReset())
    }
}

// MARK: - TwoStepVerificationErrorText

/// Telegram's texts for the errors of its two-step verification requests.
enum TwoStepVerificationErrorText {
    enum Context {
        case password
        case email
        case code
        case recoveryCode
        case generic
    }

    static func message(for error: Error, context: Context) -> String {
        guard let error = error as? TDLibError else { return L10n.telegram("Login.UnknownError") }
        let message = error.message
        if error.code == 429 || message.hasPrefix("FLOOD_WAIT") || message.hasPrefix("Too Many Requests") {
            return L10n.telegram(context == .password ? "LoginPassword.FloodError" : "TwoStepAuth.FloodError")
        }
        let key: String =
            switch message {
            case "PASSWORD_HASH_INVALID": "LoginPassword.InvalidPasswordError"
            case "EMAIL_INVALID": "TwoStepAuth.EmailInvalid"
            case "CODE_INVALID",
                 "EMAIL_CODE_INVALID",
                 "Invalid recovery code":
                context == .recoveryCode ? "TwoStepAuth.RecoveryCodeInvalid" : "Login.InvalidCodeError"
            case "CODE_EXPIRED",
                 "EMAIL_HASH_EXPIRED",
                 "PASSWORD_RECOVERY_EXPIRED":
                context == .recoveryCode ? "TwoStepAuth.RecoveryCodeInvalid" : "TwoStepAuth.EmailCodeExpired"
            case "PASSWORD_RECOVERY_NA": "TwoStepAuth.RecoveryUnavailable"
            default: "Login.UnknownError"
            }
        return L10n.telegram(key)
    }
}

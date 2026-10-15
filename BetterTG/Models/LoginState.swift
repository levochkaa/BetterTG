// LoginState.swift

import TDLibKit

// MARK: - LoginState

/// A step of Telegram's authorization sequence (`AuthorizationSequenceController`) that BetterTG shows.
enum LoginState: Equatable {
    case phoneNumber
    case code
    case twoFactor
    case emailAddress
    case emailCode
    case registration
    case qrCode
    /// "Forgot password?": the code sent to the recovery email. Shown inside TDLib's password step.
    case passwordRecovery
    /// The new password after a valid recovery code. Shown inside TDLib's password step.
    case newPassword

    /// The step TDLib's state asks for; nil for states without user input.
    init?(_ state: AuthorizationState?) {
        switch state {
        case .authorizationStateWaitPhoneNumber: self = .phoneNumber
        case .authorizationStateWaitCode: self = .code
        case .authorizationStateWaitPassword: self = .twoFactor
        case .authorizationStateWaitEmailAddress: self = .emailAddress
        case .authorizationStateWaitEmailCode: self = .emailCode
        case .authorizationStateWaitRegistration: self = .registration
        case .authorizationStateWaitOtherDeviceConfirmation: self = .qrCode
        default: return nil
        }
    }
}

// MARK: - LoginRequest

/// One TDLib authorization call, frozen with its arguments when the user submits it.
enum LoginRequest: Equatable {
    case phoneNumber(String)
    case code(String)
    case resendCode
    case password(String)
    case passwordRecovery
    case recoveryCode(String)
    case recoverPassword(code: String, password: String, hint: String)
    case emailAddress(String)
    case emailCode(String)
    case registration(firstName: String, lastName: String)
    case qrCode(otherUserIDs: [Int64])
    case resetEmailAddress
}

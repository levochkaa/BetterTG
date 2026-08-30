// LoginState.swift

enum LoginState {
    case phoneNumber, code, twoFactor

    // MARK: Internal

    var title: String {
        switch self {
        case .phoneNumber: L10n.telegram("Login.PhoneTitle")
        case .code: L10n.telegram("Login.Code")
        case .twoFactor: L10n.telegram("LoginPassword.PasswordPlaceholder")
        }
    }
}

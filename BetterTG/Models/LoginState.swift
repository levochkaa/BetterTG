// LoginState.swift

enum LoginState {
    case phoneNumber, code, twoFactor
    
    var title: String {
        switch self {
            case .phoneNumber: "Phone number"
            case .code: "Code"
            case .twoFactor: "2FA"
        }
    }
}

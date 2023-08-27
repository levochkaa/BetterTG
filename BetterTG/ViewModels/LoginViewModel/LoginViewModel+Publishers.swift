// LoginViewModel+Publishers.swift

import TDLibKit

extension LoginViewModel {
    func setPublishers() {
        nc.publisher(for: .waitPassword) { notification in
            guard let waitPassword = notification.object as? AuthorizationStateWaitPassword else { return }
            loginState = .twoFactor
            hint = waitPassword.passwordHint
        }
        
        nc.publisher(for: .waitCode) { _ in
            loginState = .code
        }
        
        nc.mergeMany([.waitPhoneNumber, .closed, .closing, .loggingOut]) { _ in
            loginState = .phoneNumber
        }
    }
}

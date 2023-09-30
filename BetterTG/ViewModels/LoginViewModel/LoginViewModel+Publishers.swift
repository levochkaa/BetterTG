// LoginViewModel+Publishers.swift

import TDLibKit

extension LoginViewModel {
    func setPublishers() {
        nc.publisher(for: .waitPassword) { notification in
            guard let waitPassword = notification.object as? AuthorizationStateWaitPassword else { return }
            withAnimation {
                loginState = .twoFactor
                hint = waitPassword.passwordHint
            }
        }
        
        nc.publisher(for: .waitCode) { _ in
            withAnimation {
                loginState = .code
            }
        }
        
        nc.mergeMany([.waitPhoneNumber, .closed, .closing, .loggingOut]) { _ in
            withAnimation {
                loginState = .phoneNumber
            }
        }
    }
}

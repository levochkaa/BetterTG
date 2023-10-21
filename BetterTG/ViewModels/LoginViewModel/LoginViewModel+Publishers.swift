// LoginViewModel+Publishers.swift

import TDLibKit

extension LoginViewModel {
    func setPublishers() {
        nc.publisher(&cancellables, for: .waitPassword) { [weak self] notification in
            guard let self, let waitPassword = notification.object as? AuthorizationStateWaitPassword else { return }
            withAnimation {
                self.loginState = .twoFactor
                self.hint = waitPassword.passwordHint
            }
        }
        
        nc.publisher(&cancellables, for: .waitCode) { [weak self] _ in
            withAnimation {
                self?.loginState = .code
            }
        }
        
        nc.mergeMany(&cancellables, [.waitPhoneNumber, .closed, .closing, .loggingOut]) { [weak self] _ in
            withAnimation {
                self?.loginState = .phoneNumber
            }
        }
    }
}

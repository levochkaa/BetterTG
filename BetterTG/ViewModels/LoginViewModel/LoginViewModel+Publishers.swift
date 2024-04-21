// LoginViewModel+Publishers.swift

import SwiftUI
import TDLibKit

extension LoginViewModel {
    func setPublishers() {
        nc.publisher(&cancellables, for: .authorizationStateWaitPassword) { [weak self] notification in
            guard let self, let waitPassword = notification.object as? AuthorizationStateWaitPassword else { return }
            withAnimation {
                self.loginState = .twoFactor
                self.hint = waitPassword.passwordHint
            }
        }
        
        nc.publisher(&cancellables, for: .authorizationStateWaitCode) { [weak self] _ in
            withAnimation {
                self?.loginState = .code
            }
        }
        
        nc.mergeMany(&cancellables, [
            .authorizationStateWaitPhoneNumber,
            .authorizationStateClosed,
            .authorizationStateClosing,
            .authorizationStateLoggingOut
        ]) { [weak self] _ in
            withAnimation {
                self?.loginState = .phoneNumber
            }
        }
    }
}

// LoginViewModel+Publishers.swift

import SwiftUI
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
        
        nc.mergeMany([
            nc.publisher(for: .waitPhoneNumber),
            nc.publisher(for: .closed),
            nc.publisher(for: .closing),
            nc.publisher(for: .loggingOut)
        ]) { _ in
            self.loginState = .phoneNumber
        }
    }
}

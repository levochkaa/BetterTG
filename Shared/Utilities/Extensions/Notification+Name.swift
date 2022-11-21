// Notification+Name.swift

import Foundation

extension Notification.Name {
    // updateAuthorizationState.authorizationState
    static let waitTdlibParameters = Notification.Name("waitTdlibParameters")
    static let closed = Notification.Name("closed")
    static let loggingOut = Notification.Name("loggingOut")
    static let closing = Notification.Name("closing")
    static let waitPhoneNumber = Notification.Name("waitPhoneNumber")
    static let waitCode = Notification.Name("waitCode")
    static let waitPassword = Notification.Name("waitPassword")
    static let ready = Notification.Name("ready")
    static let waitEmailAddress = Notification.Name("waitEmailAddress")
    static let waitEmailCode = Notification.Name("waitEmailCode")
    static let waitRegistration = Notification.Name("waitRegistration")
    static let waitOtherDeviceConfirmation = Notification.Name("waitOtherDeviceConfirmation")

    static let file = Notification.Name("file")
    
    static let newMessage = Notification.Name("newMessage")
}

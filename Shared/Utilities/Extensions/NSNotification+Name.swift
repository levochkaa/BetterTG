// NSNotification+Name.swift

import Foundation

extension Notification.Name {
    // updateAuthorizationState.authorizationState
    static let waitTdlibParameters = NSNotification.Name("waitTdlibParameters")
    static let closed = NSNotification.Name("closed")
    static let loggingOut = NSNotification.Name("loggingOut")
    static let closing = NSNotification.Name("closing")
    static let waitPhoneNumber = NSNotification.Name("waitPhoneNumber")
    static let waitCode = NSNotification.Name("waitCode")
    static let waitPassword = NSNotification.Name("waitPassword")
    static let ready = NSNotification.Name("ready")
    static let waitEmailAddress = NSNotification.Name("waitEmailAddress")
    static let waitEmailCode = NSNotification.Name("waitEmailCode")
    static let waitRegistration = NSNotification.Name("waitRegistration")
    static let waitOtherDeviceConfirmation = NSNotification.Name("waitOtherDeviceConfirmation")
}

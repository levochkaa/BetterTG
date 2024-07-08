// NotificationName.swift

import SwiftUI

extension Foundation.Notification.Name {
    static let authorizationStateWaitTdlibParameters = Self("authorizationStateWaitTdlibParameters")
    static let authorizationStateWaitPhoneNumber = Self("authorizationStateWaitPhoneNumber")
    static let authorizationStateWaitEmailAddress = Self("authorizationStateWaitEmailAddress")
    static let authorizationStateWaitEmailCode = Self("authorizationStateWaitEmailCode")
    static let authorizationStateWaitCode = Self("authorizationStateWaitCode")
    static let authorizationStateWaitOtherDeviceConfirmation = Self("authorizationStateWaitOtherDeviceConfirmation")
    static let authorizationStateWaitRegistration = Self("authorizationStateWaitRegistration")
    static let authorizationStateWaitPassword = Self("authorizationStateWaitPassword")
    static let authorizationStateReady = Self("authorizationStateReady")
    static let authorizationStateLoggingOut = Self("authorizationStateLoggingOut")
    static let authorizationStateClosing = Self("authorizationStateClosing")
    static let authorizationStateClosed = Self("authorizationStateClosed")
    
    static let localScrollToLastOnFocus = Self("localScrollToLastOnFocus")
    static let localPasteImages = Self("localPasteImages")
    static let localOnSelectedImagesDrop = Self("localOnSelectedImagesDrop")
}

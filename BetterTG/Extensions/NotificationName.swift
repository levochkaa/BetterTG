// NotificationName.swift

import Foundation

extension Foundation.Notification.Name {
    static let appLanguageChanged = Self("appLanguageChanged")
    static let availableAppLanguagesChanged = Self("availableAppLanguagesChanged")
    static let activeTelegramAccountChanged = Self("activeTelegramAccountChanged")
    static let telegramAccountsChanged = Self("telegramAccountsChanged")
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
    static let authorizationStateWaitPremiumPurchase = Self("authorizationStateWaitPremiumPurchase")
}

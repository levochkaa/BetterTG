// Notification+Name.swift

import Foundation

extension Notification.Name {
    // MARK: updateAuthorizationState.authorizationState
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
    
    // MARK: file
    static let file = Notification.Name("file")
    
    // MARK: message
    static let newMessage = Notification.Name("newMessage")
    
    // MARK: chat
    static let newChat = Notification.Name("newChat")
    static let chatLastMessage = Notification.Name("chatLastMessage")
    static let chatDraftMessage = Notification.Name("chatDraftMessage")
    static let chatIsMarkedAsUnread = Notification.Name("chatIsMarkedAsUnread")
    static let chatFilters = Notification.Name("chatFilters")
    static let chatPhoto = Notification.Name("chatPhoto")
    static let chatTheme = Notification.Name("chatTheme")
    static let chatTitle = Notification.Name("chatTitle")
    
    // MARK: chatAction
    static let uploadingDocument = Notification.Name("uploadingDocument")
    static let choosingContact = Notification.Name("choosingContact")
    
    // MARK: user
    static let user = Notification.Name("user")
}

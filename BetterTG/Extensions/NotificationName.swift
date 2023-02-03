// NotificationName.swift

import Foundation

extension Notification.Name {
    // MARK: updateAuthorizationState.authorizationState
    static let waitTdlibParameters = Self("waitTdlibParameters")
    static let closed = Self("closed")
    static let loggingOut = Self("loggingOut")
    static let closing = Self("closing")
    static let waitPhoneNumber = Self("waitPhoneNumber")
    static let waitCode = Self("waitCode")
    static let waitPassword = Self("waitPassword")
    static let ready = Self("ready")
    static let waitEmailAddress = Self("waitEmailAddress")
    static let waitEmailCode = Self("waitEmailCode")
    static let waitRegistration = Self("waitRegistration")
    static let waitOtherDeviceConfirmation = Self("waitOtherDeviceConfirmation")
    
    // MARK: file
    static let file = Self("file")
    
    // MARK: message
    static let newMessage = Self("newMessage")
    static let deleteMessages = Self("deleteMessages")
    static let messageEdited = Self("messageEdited")
    static let messageSendSucceeded = Self("messageSendSucceeded")
    static let messageSendFailed = Self("messageSendFailed")
    
    // MARK: chat
    static let newChat = Self("newChat")
    static let chatLastMessage = Self("chatLastMessage")
    static let chatDraftMessage = Self("chatDraftMessage")
    static let chatIsMarkedAsUnread = Self("chatIsMarkedAsUnread")
    static let chatFilters = Self("chatFilters")
    static let chatPhoto = Self("chatPhoto")
    static let chatTheme = Self("chatTheme")
    static let chatTitle = Self("chatTitle")
    static let chatPosition = Self("chatPosition")
    
    // MARK: chatAction
    static let chatAction = Self("chatAction")
    static let uploadingDocument = Self("uploadingDocument")
    static let choosingContact = Self("choosingContact")
    static let typing = Self("typing")
    static let recordingVideo = Self("recordingVideo")
    static let uploadingVideo = Self("uploadingVideo")
    static let recordingVoiceNote = Self("recordingVoiceNote")
    static let uploadingVoiceNote = Self("uploadingVoiceNote")
    static let uploadingPhoto = Self("uploadingPhoto")
    static let choosingSticker = Self("choosingSticker")
    static let choosingLocation = Self("choosingLocation")
    static let startPlayingGame = Self("startPlayingGame")
    static let recordingVideoNote = Self("recordingVideoNote")
    static let uploadingVideoNote = Self("uploadingVideoNote")
    static let watchingAnimations = Self("watchingAnimations")
    static let cancel = Self("cancel")
    
    // MARK: user
    static let user = Self("user")
    static let userStatus = Self("userStatus")
    
    // MARK: custom
    static let customIsListeningVoice = Self("customIsListeningVoice")
    static let customRecognizeSpeech = Self("customRecognizeSpeech")
}

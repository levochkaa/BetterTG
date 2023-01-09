// TdApi+Updates.swift

import Foundation
import TDLibKit

extension TdApi {
    static var shared = TdApi(client: TdClientImpl(completionQueue: .global(qos: .userInitiated)))
    
    static let nc: NotificationCenter = .default
    
    func startTdLibUpdateHandler() {
        setPublishers()
        
        client.run { data in
            do {
                let update = try TdApi.shared.decoder.decode(Update.self, from: data)
                self.update(update)
            } catch {
                log("Error TdLibUpdateHandler: \(error)")
            }
        }
    }
    
    func setPublishers() {
        TdApi.nc.publisher(for: .waitTdlibParameters) { _ in
            Task {
                var url = try FileManager.default.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                url.append(path: "td")
                let dir = url.path()
                
                _ = try await self.setTdlibParameters(
                    apiHash: Secret.apiHash,
                    apiId: Secret.apiId,
                    applicationVersion: Utils.info(key: "CFBundleShortVersionString"),
                    databaseDirectory: dir,
                    databaseEncryptionKey: Data(),
                    deviceModel: Utils.modelName,
                    enableStorageOptimizer: true,
                    filesDirectory: dir,
                    ignoreFileNames: false,
                    systemLanguageCode: "en-US",
                    systemVersion: Utils.osVersion,
                    useChatInfoDatabase: true,
                    useFileDatabase: true,
                    useMessageDatabase: true,
                    useSecretChats: true,
                    useTestDc: false
                )
            }
        }
        
        TdApi.nc.publisher(for: .closed) { _ in
            TdApi.shared = TdApi(client: TdClientImpl(completionQueue: .global(qos: .userInitiated)))
            TdApi.shared.startTdLibUpdateHandler()
        }
    }
    
    func update(_ update: Update) {
        // TdApi.logger.log("Update: \(update)")
        switch update {
            case .updateAuthorizationState(let updateAuthorizationState):
                self.updateAuthorizationState(updateAuthorizationState.authorizationState)
            case .updateChatAction(let updateChatAction):
                self.updateChatAction(updateChatAction)
                TdApi.nc.post(name: .chatAction, object: updateChatAction)
            case .updateFile(let updateFile):
                Task { @MainActor in
                    TdApi.nc.post(name: .file, object: updateFile)
                }
            case .updateNewMessage(let updateNewMessage):
                Task { @MainActor in
                    TdApi.nc.post(name: .newMessage, object: updateNewMessage)
                }
            case .updateMessageEdited(let updateMessageEdited):
                Task { @MainActor in
                    TdApi.nc.post(name: .messageEdited, object: updateMessageEdited)
                }
            case .updateChatLastMessage(let updateChatLastMessage):
                TdApi.nc.post(name: .chatLastMessage, object: updateChatLastMessage)
            case .updateChatDraftMessage(let updateChatDraftMessage):
                TdApi.nc.post(name: .chatDraftMessage, object: updateChatDraftMessage)
            case .updateChatIsMarkedAsUnread(let updateChatIsMarkedAsUnread):
                TdApi.nc.post(name: .chatIsMarkedAsUnread, object: updateChatIsMarkedAsUnread)
            case .updateChatFilters(let updateChatFilters):
                TdApi.nc.post(name: .chatFilters, object: updateChatFilters)
            case .updateNewChat(let updateNewChat):
                TdApi.nc.post(name: .newChat, object: updateNewChat)
            case .updateChatPhoto(let updateChatPhoto):
                TdApi.nc.post(name: .chatPhoto, object: updateChatPhoto)
            case .updateChatTheme(let updateChatTheme):
                TdApi.nc.post(name: .chatTheme, object: updateChatTheme)
            case .updateChatTitle(let updateChatTitle):
                TdApi.nc.post(name: .chatTitle, object: updateChatTitle)
            case .updateUser(let updateUser):
                TdApi.nc.post(name: .user, object: updateUser.user)
            case .updateDeleteMessages(let updateDeleteMessages):
                TdApi.nc.post(name: .deleteMessages, object: updateDeleteMessages)
            case .updateMessageSendSucceeded(let updateMessageSendSucceeded):
                TdApi.nc.post(name: .messageSendSucceeded, object: updateMessageSendSucceeded)
            case .updateMessageSendFailed(let updateMessageSendFailed):
                TdApi.nc.post(name: .messageSendFailed, object: updateMessageSendFailed)
            case .updateChatPosition(let updateChatPosition):
                TdApi.nc.post(name: .chatPosition, object: updateChatPosition)
            case .updateUserStatus(let updateUserStatus):
                TdApi.nc.post(name: .userStatus, object: updateUserStatus)
            default:
                break
        }
    }
    
    func updateChatAction(_ updateChatAction: UpdateChatAction) {
        // TdApi.logger.log("ChatAction: \(updateChatAction)")
        switch updateChatAction.action {
            case .chatActionTyping:
                TdApi.nc.post(name: .typing, object: updateChatAction)
            case .chatActionRecordingVideo:
                TdApi.nc.post(name: .recordingVideo, object: updateChatAction)
            case .chatActionUploadingVideo:
                TdApi.nc.post(name: .uploadingVideo, object: updateChatAction)
            case .chatActionChoosingContact:
                TdApi.nc.post(name: .choosingContact, object: updateChatAction)
            case .chatActionUploadingDocument:
                TdApi.nc.post(name: .uploadingDocument, object: updateChatAction)
            case .chatActionRecordingVoiceNote:
                TdApi.nc.post(name: .recordingVoiceNote, object: updateChatAction)
            case .chatActionUploadingVoiceNote:
                TdApi.nc.post(name: .uploadingVoiceNote, object: updateChatAction)
            case .chatActionUploadingPhoto:
                TdApi.nc.post(name: .uploadingPhoto, object: updateChatAction)
            case .chatActionChoosingSticker:
                TdApi.nc.post(name: .choosingSticker, object: updateChatAction)
            case .chatActionChoosingLocation:
                TdApi.nc.post(name: .choosingLocation, object: updateChatAction)
            case .chatActionStartPlayingGame:
                TdApi.nc.post(name: .startPlayingGame, object: updateChatAction)
            case .chatActionRecordingVideoNote:
                TdApi.nc.post(name: .recordingVideoNote, object: updateChatAction)
            case .chatActionUploadingVideoNote:
                TdApi.nc.post(name: .uploadingVideoNote, object: updateChatAction)
            case .chatActionWatchingAnimations:
                TdApi.nc.post(name: .watchingAnimations, object: updateChatAction)
            case .chatActionCancel:
                TdApi.nc.post(name: .cancel, object: updateChatAction)
        }
    }
    
    func updateAuthorizationState(_ authorizationState: AuthorizationState) {
        // TdApi.logger.log("Auth: \(authorizationState)")
        switch authorizationState {
            case .authorizationStateWaitTdlibParameters:
                TdApi.nc.post(name: .waitTdlibParameters, object: nil)
            case .authorizationStateClosing:
                TdApi.nc.post(name: .closing, object: nil)
            case .authorizationStateClosed:
                TdApi.nc.post(name: .closed, object: nil)
            case .authorizationStateLoggingOut:
                TdApi.nc.post(name: .loggingOut, object: nil)
            case .authorizationStateReady:
                TdApi.nc.post(name: .ready, object: nil)
            case .authorizationStateWaitPhoneNumber:
                TdApi.nc.post(name: .waitPhoneNumber, object: nil)
            case .authorizationStateWaitCode(let waitCode):
                TdApi.nc.post(name: .waitCode, object: waitCode)
            case .authorizationStateWaitPassword(let waitPassword):
                TdApi.nc.post(name: .waitPassword, object: waitPassword)
            case .authorizationStateWaitEmailAddress(let waitEmailAddress):
                TdApi.nc.post(name: .waitEmailAddress, object: waitEmailAddress)
            case .authorizationStateWaitEmailCode(let waitEmailCode):
                TdApi.nc.post(name: .waitEmailCode, object: waitEmailCode)
            case .authorizationStateWaitOtherDeviceConfirmation(let waitOtherDeviceConfirmation):
                TdApi.nc.post(name: .waitOtherDeviceConfirmation, object: waitOtherDeviceConfirmation)
            case .authorizationStateWaitRegistration(let waitRegistration):
                TdApi.nc.post(name: .waitRegistration, object: waitRegistration)
        }
    }
}

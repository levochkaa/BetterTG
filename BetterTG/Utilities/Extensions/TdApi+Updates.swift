// TdApi+Updates.swift

import Foundation
import TDLibKit

let tdApi: TdApi = .shared

extension TdApi {
    static var shared = TdApi(client: TdClientImpl(completionQueue: .global(qos: .userInitiated)))
    
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
        nc.publisher(for: .waitTdlibParameters) { _ in
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
        
        nc.publisher(for: .closed) { _ in
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
                nc.post(name: .chatAction, object: updateChatAction)
            case .updateFile(let updateFile):
                Task.main {
                    nc.post(name: .file, object: updateFile)
                }
            case .updateNewMessage(let updateNewMessage):
                Task.main {
                    nc.post(name: .newMessage, object: updateNewMessage)
                }
            case .updateMessageEdited(let updateMessageEdited):
                Task.main {
                    nc.post(name: .messageEdited, object: updateMessageEdited)
                }
            case .updateChatLastMessage(let updateChatLastMessage):
                nc.post(name: .chatLastMessage, object: updateChatLastMessage)
            case .updateChatDraftMessage(let updateChatDraftMessage):
                nc.post(name: .chatDraftMessage, object: updateChatDraftMessage)
            case .updateChatIsMarkedAsUnread(let updateChatIsMarkedAsUnread):
                nc.post(name: .chatIsMarkedAsUnread, object: updateChatIsMarkedAsUnread)
            case .updateChatFilters(let updateChatFilters):
                nc.post(name: .chatFilters, object: updateChatFilters)
            case .updateNewChat(let updateNewChat):
                nc.post(name: .newChat, object: updateNewChat)
            case .updateChatPhoto(let updateChatPhoto):
                nc.post(name: .chatPhoto, object: updateChatPhoto)
            case .updateChatTheme(let updateChatTheme):
                nc.post(name: .chatTheme, object: updateChatTheme)
            case .updateChatTitle(let updateChatTitle):
                nc.post(name: .chatTitle, object: updateChatTitle)
            case .updateUser(let updateUser):
                nc.post(name: .user, object: updateUser.user)
            case .updateDeleteMessages(let updateDeleteMessages):
                nc.post(name: .deleteMessages, object: updateDeleteMessages)
            case .updateMessageSendSucceeded(let updateMessageSendSucceeded):
                nc.post(name: .messageSendSucceeded, object: updateMessageSendSucceeded)
            case .updateMessageSendFailed(let updateMessageSendFailed):
                nc.post(name: .messageSendFailed, object: updateMessageSendFailed)
            case .updateChatPosition(let updateChatPosition):
                nc.post(name: .chatPosition, object: updateChatPosition)
            case .updateUserStatus(let updateUserStatus):
                nc.post(name: .userStatus, object: updateUserStatus)
            default:
                break
        }
    }
    
    func updateChatAction(_ updateChatAction: UpdateChatAction) {
        // TdApi.logger.log("ChatAction: \(updateChatAction)")
        switch updateChatAction.action {
            case .chatActionTyping:
                nc.post(name: .typing, object: updateChatAction)
            case .chatActionRecordingVideo:
                nc.post(name: .recordingVideo, object: updateChatAction)
            case .chatActionUploadingVideo:
                nc.post(name: .uploadingVideo, object: updateChatAction)
            case .chatActionChoosingContact:
                nc.post(name: .choosingContact, object: updateChatAction)
            case .chatActionUploadingDocument:
                nc.post(name: .uploadingDocument, object: updateChatAction)
            case .chatActionRecordingVoiceNote:
                nc.post(name: .recordingVoiceNote, object: updateChatAction)
            case .chatActionUploadingVoiceNote:
                nc.post(name: .uploadingVoiceNote, object: updateChatAction)
            case .chatActionUploadingPhoto:
                nc.post(name: .uploadingPhoto, object: updateChatAction)
            case .chatActionChoosingSticker:
                nc.post(name: .choosingSticker, object: updateChatAction)
            case .chatActionChoosingLocation:
                nc.post(name: .choosingLocation, object: updateChatAction)
            case .chatActionStartPlayingGame:
                nc.post(name: .startPlayingGame, object: updateChatAction)
            case .chatActionRecordingVideoNote:
                nc.post(name: .recordingVideoNote, object: updateChatAction)
            case .chatActionUploadingVideoNote:
                nc.post(name: .uploadingVideoNote, object: updateChatAction)
            case .chatActionWatchingAnimations:
                nc.post(name: .watchingAnimations, object: updateChatAction)
            case .chatActionCancel:
                nc.post(name: .cancel, object: updateChatAction)
        }
    }
    
    func updateAuthorizationState(_ authorizationState: AuthorizationState) {
        // TdApi.logger.log("Auth: \(authorizationState)")
        switch authorizationState {
            case .authorizationStateWaitTdlibParameters:
                nc.post(name: .waitTdlibParameters, object: nil)
            case .authorizationStateClosing:
                nc.post(name: .closing, object: nil)
            case .authorizationStateClosed:
                nc.post(name: .closed, object: nil)
            case .authorizationStateLoggingOut:
                nc.post(name: .loggingOut, object: nil)
            case .authorizationStateReady:
                nc.post(name: .ready, object: nil)
            case .authorizationStateWaitPhoneNumber:
                nc.post(name: .waitPhoneNumber, object: nil)
            case .authorizationStateWaitCode(let waitCode):
                nc.post(name: .waitCode, object: waitCode)
            case .authorizationStateWaitPassword(let waitPassword):
                nc.post(name: .waitPassword, object: waitPassword)
            case .authorizationStateWaitEmailAddress(let waitEmailAddress):
                nc.post(name: .waitEmailAddress, object: waitEmailAddress)
            case .authorizationStateWaitEmailCode(let waitEmailCode):
                nc.post(name: .waitEmailCode, object: waitEmailCode)
            case .authorizationStateWaitOtherDeviceConfirmation(let waitOtherDeviceConfirmation):
                nc.post(name: .waitOtherDeviceConfirmation, object: waitOtherDeviceConfirmation)
            case .authorizationStateWaitRegistration(let waitRegistration):
                nc.post(name: .waitRegistration, object: waitRegistration)
        }
    }
}

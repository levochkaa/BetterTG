// TdApi+Extension.swift

import Foundation
import Combine
import TDLibKit

extension TdApi {
    static var shared = TdApi(client: TdClientImpl(completionQueue: .global(qos: .userInitiated)))

    static let logger = Logger(label: "TdApi")
    static let nc: NotificationCenter = .default

    func startTdLibUpdateHandler() {
        setPublishers()

        client.run { data in
            do {
                let update = try TdApi.shared.decoder.decode(Update.self, from: data)
                self.update(update)
            } catch {
                guard let tdError = error as? TDLibKit.Error else {
                    return
                }
                TdApi.logger.log("TdLibUpdateHandler: \(tdError.code) - \(tdError.message)")
            }
        }
    }

    func setPublishers() {
        TdApi.nc.publisher(for: .waitTdlibParameters) { _ in
            Task {
                var url = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                url.append(path: "td")
                var dir = url.path()
                dir.replace("%20", with: " ")

                TdApi.logger.log("td directory: \(dir)")

                _ = try await self.setTdlibParameters(
                    apiHash: Secret.apiHash,
                    apiId: Secret.apiId,
                    applicationVersion: SystemUtils.info(key: "CFBundleShortVersionString"),
                    databaseDirectory: dir,
                    databaseEncryptionKey: Data(),
                    deviceModel: await SystemUtils.getDeviceModel(),
                    enableStorageOptimizer: true,
                    filesDirectory: dir,
                    ignoreFileNames: false,
                    systemLanguageCode: "en-US",
                    systemVersion: SystemUtils.osVersion,
                    useChatInfoDatabase: true,
                    useFileDatabase: true,
                    useMessageDatabase: true,
                    useSecretChats: true,
                    useTestDc: false
                )
            }
        }

        TdApi.nc.publisher(for: .closed) { _ in
            TdApi.shared = TdApi(client: TdClientImpl(completionQueue: .global()))
            TdApi.shared.startTdLibUpdateHandler()
        }
    }

    func update(_ update: Update) {
//        TdApi.logger.log("Update: \(update)")
        switch update {
            case let .updateAuthorizationState(updateAuthorizationState):
                self.updateAuthorizationState(updateAuthorizationState.authorizationState)
            case let .updateFile(updateFile):
                Task { @MainActor in
                    TdApi.nc.post(name: .file, object: updateFile)
                }
            case let .updateNewMessage(updateNewMessage):
                TdApi.nc.post(name: .newMessage, object: updateNewMessage)
            case let .updateChatLastMessage(updateChatLastMessage):
                TdApi.nc.post(name: .chatLastMessage, object: updateChatLastMessage)
            case let .updateChatDraftMessage(updateChatDraftMessage):
                TdApi.nc.post(name: .chatDraftMessage, object: updateChatDraftMessage)
            case let .updateChatIsMarkedAsUnread(updateChatIsMarkedAsUnread):
                TdApi.nc.post(name: .chatIsMarkedAsUnread, object: updateChatIsMarkedAsUnread)
            case let .updateChatFilters(updateChatFilters):
                TdApi.nc.post(name: .chatFilters, object: updateChatFilters)
            case let .updateNewChat(updateNewChat):
                TdApi.nc.post(name: .newChat, object: updateNewChat)
            case let .updateChatPhoto(updateChatPhoto):
                TdApi.nc.post(name: .chatPhoto, object: updateChatPhoto)
            case let .updateChatTheme(updateChatTheme):
                TdApi.nc.post(name: .chatTheme, object: updateChatTheme)
            case let .updateChatTitle(updateChatTitle):
                TdApi.nc.post(name: .chatTitle, object: updateChatTitle)
            case let .updateUser(updateUser):
                TdApi.nc.post(name: .user, object: updateUser.user)
            case let .updateChatAction(updateChatAction):
                self.updateChatAction(updateChatAction)
            default:
                break
        }
    }

    func updateChatAction(_ updateChatAction: UpdateChatAction) {
        switch updateChatAction.action {
            case .chatActionUploadingDocument:
                TdApi.nc.post(name: .uploadingDocument, object: updateChatAction)
            case .chatActionChoosingContact:
                TdApi.nc.post(name: .choosingContact, object: updateChatAction)
            default:
                break
        }
    }

    func updateAuthorizationState(_ authorizationState: AuthorizationState) {
        TdApi.logger.log("Auth: \(authorizationState)")
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
            case let .authorizationStateWaitCode(waitCode):
                TdApi.nc.post(name: .waitCode, object: waitCode)
            case let .authorizationStateWaitPassword(waitPassword):
                TdApi.nc.post(name: .waitPassword, object: waitPassword)
            case let .authorizationStateWaitEmailAddress(waitEmailAddress):
                TdApi.nc.post(name: .waitEmailAddress, object: waitEmailAddress)
            case let .authorizationStateWaitEmailCode(waitEmailCode):
                TdApi.nc.post(name: .waitEmailCode, object: waitEmailCode)
            case let .authorizationStateWaitOtherDeviceConfirmation(waitOtherDeviceConfirmation):
                TdApi.nc.post(name: .waitOtherDeviceConfirmation, object: waitOtherDeviceConfirmation)
            case let .authorizationStateWaitRegistration(waitRegistration):
                TdApi.nc.post(name: .waitRegistration, object: waitRegistration)
        }
    }
}

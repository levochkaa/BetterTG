// TdApi+Extension.swift

import Foundation
import Combine
import TDLibKit

extension TdApi {
    static var shared = TdApi(client: TdClientImpl(completionQueue: .global(qos: .userInitiated)))
    
    private static let logger = Logger(label: "TdApi")
    private static let nc = NotificationCenter.default
    private static var cancellable = Set<AnyCancellable>()
    
    func startTdLibUpdateHandler() {
        self.setPublishers()
        
        client.run { data in
            do {
                let update = try TdApi.shared.decoder.decode(Update.self, from: data)
                self.update(update)
            } catch {
                guard let tdError = error as? TDLibKit.Error else { return }
                TdApi.logger.log("TdLibUpdateHandler: \(tdError.code) - \(tdError.message)")
            }
        }
    }
    
    func setPublishers() {
        TdApi.nc.publisher(for: .waitTdlibParameters, in: &TdApi.cancellable) { _ in
            Task {
                var url = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true)
                let dir = url.path()
                url.append(path: "td")
                
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
        
        TdApi.nc.publisher(for: .closed, in: &TdApi.cancellable) { _ in
            TdApi.shared = TdApi(client: TdClientImpl(completionQueue: .global()))
            TdApi.shared.startTdLibUpdateHandler()
        }
    }
    
    func update(_ update: Update) {
        switch update {
        case let .updateAuthorizationState(updateAuthorizationState):
            self.updateAuthorizationState(updateAuthorizationState.authorizationState)
        case let .updateFile(updateFile):
            TdApi.nc.post(name: .file, object: updateFile)
        case let .updateNewMessage(updateNewMessage):
            TdApi.nc.post(name: .newMessage, object: updateNewMessage)
        default:
            break
        }
    }
    
    func updateAuthorizationState(_ authorizationState: AuthorizationState) {
        TdApi.logger.log("AuthState: \(authorizationState)")
        
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

// TDLib.swift

import SwiftUI
import TDLibKit
import Combine

var td: TDLibClient { TDLib.shared.td }

final class TDLib: @unchecked Sendable {
    static let shared = TDLib()
    
    fileprivate let td: TDLibClient
    
    private init() {
        td = manager.createClient { data, client in
            do {
                update(try client.decoder.decode(Update.self, from: data))
            } catch {
                log("Error TdLibUpdateHandler: \(error)")
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let manager = TDLibClientManager()
    
    func startTdLibUpdateHandler() {
        // Xcode 15+ is unable to handle so many logs
        try? td.setLogStream(logStream: .logStreamEmpty) { _ in }
        
        nc.publisher(&cancellables, for: .authorizationStateWaitTdlibParameters) { _ in
            Task.background { [weak self] in
                let dir = try FileManager.default.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                ).appending(path: "td").path()
                
                try await self?.td.setTdlibParameters(
                    apiHash: Secret.apiHash,
                    apiId: Secret.apiId,
                    applicationVersion: Utils.applicationVersion,
                    databaseDirectory: dir,
                    databaseEncryptionKey: Data(),
                    deviceModel: Utils.modelName,
                    filesDirectory: dir,
                    systemLanguageCode: "en-US",
                    systemVersion: UIDevice.current.systemVersion,
                    useChatInfoDatabase: true,
                    useFileDatabase: true,
                    useMessageDatabase: true,
                    useSecretChats: true,
                    useTestDc: false
                )
            }
        }
        
        nc.publisher(&cancellables, for: UIApplication.willTerminateNotification) { [weak self] _ in
            self?.manager.closeClients()
        }
    }
    
    func UpdateAuthorizationState(_ updateAuthorizationState: AuthorizationState) {
        switch updateAuthorizationState {
        case .authorizationStateWaitTdlibParameters:
            nc.post(name: .authorizationStateWaitTdlibParameters)
        case .authorizationStateWaitPhoneNumber:
            nc.post(name: .authorizationStateWaitPhoneNumber)
        case .authorizationStateWaitEmailAddress(let authorizationStateWaitEmailAddress):
            nc.post(name: .authorizationStateWaitEmailAddress, object: authorizationStateWaitEmailAddress)
        case .authorizationStateWaitEmailCode(let authorizationStateWaitEmailCode):
            nc.post(name: .authorizationStateWaitEmailCode, object: authorizationStateWaitEmailCode)
        case .authorizationStateWaitCode(let authorizationStateWaitCode):
            nc.post(name: .authorizationStateWaitCode, object: authorizationStateWaitCode)
        case .authorizationStateWaitOtherDeviceConfirmation(let authorizationStateWaitOtherDeviceConfirmation):
            nc.post(
                name: .authorizationStateWaitOtherDeviceConfirmation,
                object: authorizationStateWaitOtherDeviceConfirmation
            )
        case .authorizationStateWaitRegistration(let authorizationStateWaitRegistration):
            nc.post(name: .authorizationStateWaitRegistration, object: authorizationStateWaitRegistration)
        case .authorizationStateWaitPassword(let authorizationStateWaitPassword):
            nc.post(name: .authorizationStateWaitPassword, object: authorizationStateWaitPassword)
        case .authorizationStateReady:
            nc.post(name: .authorizationStateReady)
        case .authorizationStateLoggingOut:
            nc.post(name: .authorizationStateLoggingOut)
        case .authorizationStateClosing:
            nc.post(name: .authorizationStateClosing)
        case .authorizationStateClosed:
            nc.post(name: .authorizationStateClosed)
        }
    }
}

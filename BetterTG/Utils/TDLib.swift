// TDLib.swift

import Combine
import TDLibKit
import UIKit

var td: TDLibClient { TDLib.shared.td }

// MARK: - TDLib

final class TDLib: @unchecked Sendable {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = TDLib()

    func startTdLibUpdateHandler() {
        nc.publisher(&cancellables, for: .authorizationStateWaitTdlibParameters) { [weak self] _ in
            guard let self else { return }
            log("TDLib requested client parameters")
            Task.background {
                do {
                    let state = try await self.configureTDLibParameters()
                    log("TDLib client parameters configured; state=\(state.diagnosticName)")
                    if case .authorizationStateWaitTdlibParameters = state {
                        return
                    }
                    self.UpdateAuthorizationState(state)
                } catch {
                    log("TDLib client parameter configuration failed: \(error.localizedDescription)")
                }
            }
        }

        // Access the lazy client only after the initial authorization-state observer is installed.
        // Otherwise TDLib can emit waitTdlibParameters while TDLib.shared is still initializing.
        // Xcode 15+ is unable to handle so many logs.
        try? td.setLogStream(logStream: .logStreamEmpty) { _ in }

        nc.publisher(&cancellables, for: UIApplication.willTerminateNotification) { [weak self] _ in
            self?.manager.closeClients()
        }
    }

    func UpdateAuthorizationState(_ updateAuthorizationState: AuthorizationState) {
        log("TDLib authorization state received: \(updateAuthorizationState.diagnosticName)")
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
                object: authorizationStateWaitOtherDeviceConfirmation,
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
        case .authorizationStateWaitPremiumPurchase(let authorizationStateWaitPremiumPurchase):
            nc.post(name: .authorizationStateWaitPremiumPurchase, object: authorizationStateWaitPremiumPurchase)
        }
    }

    // MARK: Fileprivate

    fileprivate lazy var td = manager.createClient { data, client in
        do {
            try update(client.decoder.decode(Update.self, from: data))
        } catch {
            log("Error TdLibUpdateHandler: \(error)")
        }
    }

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()
    private let manager = TDLibClientManager()

    private func configureTDLibParameters() async throws -> AuthorizationState {
        let dir = try FileManager.default
            .url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true,
            )
            .appending(path: "td")
            .path()

        try await td.setTdlibParameters(
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
            useTestDc: false,
        )
        return try await td.getAuthorizationState()
    }
}

private extension AuthorizationState {
    var diagnosticName: String {
        switch self {
        case .authorizationStateWaitTdlibParameters:
            "waitTdlibParameters"
        case .authorizationStateWaitPhoneNumber:
            "waitPhoneNumber"
        case .authorizationStateWaitEmailAddress:
            "waitEmailAddress"
        case .authorizationStateWaitEmailCode:
            "waitEmailCode"
        case .authorizationStateWaitCode:
            "waitCode"
        case .authorizationStateWaitOtherDeviceConfirmation:
            "waitOtherDeviceConfirmation"
        case .authorizationStateWaitRegistration:
            "waitRegistration"
        case .authorizationStateWaitPassword:
            "waitPassword"
        case .authorizationStateReady:
            "ready"
        case .authorizationStateLoggingOut:
            "loggingOut"
        case .authorizationStateClosing:
            "closing"
        case .authorizationStateClosed:
            "closed"
        case .authorizationStateWaitPremiumPurchase:
            "waitPremiumPurchase"
        }
    }
}

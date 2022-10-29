// RootViewVM.swift

import SwiftUI
import TDLibKit

class RootViewVM: ObservableObject {
    private let tdApi: TdApi = .shared
    private let logger = Logger(label: "RootVM")

    @Published var loggedIn = true

    init() {
        tdApi.client.run { data in
            do {
                let update = try TdApi.shared.decoder.decode(Update.self, from: data)

                switch update {
                    case .updateAuthorizationState(let updateAuthorizationState):
                        switch updateAuthorizationState.authorizationState {
                            case .authorizationStateClosed,
                                    .authorizationStateReady,
                                    .authorizationStateWaitEncryptionKey,
                                    .authorizationStateWaitTdlibParameters:
                                break // do nothing
                            default:
                                self.loggedIn = false
                        }
                    default:
                        break
                }
            } catch {
                guard let tdError = error as? TDLibKit.Error else { return }
                self.logger.log("Code: \(tdError.code), message: \(tdError.message)", level: .error)
            }
        }
    }
}

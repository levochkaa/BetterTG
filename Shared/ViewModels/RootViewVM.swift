// RootViewVM.swift

import SwiftUI
import TDLibKit
import CollectionConcurrencyKit

class RootViewVM: ObservableObject {
    private let tdApi: TdApi = .shared
    private let logger = Logger(label: "RootVM")

    @Published var loggedIn = true
    @Published var mainChats = [Chat]()

    init() {
        tdApi.client.run { data in
            do {
                let update = try TdApi.shared.decoder.decode(Update.self, from: data)

                switch update {
                    case .updateAuthorizationState(let updateAuthorizationState):
                        switch updateAuthorizationState.authorizationState {
                            case .authorizationStateClosed,
                                    .authorizationStateClosing,
                                    .authorizationStateLoggingOut:
                                break
                            case .authorizationStateReady:
                                Task {
                                    try await self.loadMainChats()
                                }
                            case .authorizationStateWaitEncryptionKey,
                                    .authorizationStateWaitTdlibParameters:
                                break
                            default:
                                DispatchQueue.main.async {
                                    self.loggedIn = false
                                }
                        }
                    default:
                        break
                }
            } catch {
                guard let tdError = error as? TDLibKit.Error else { return }
                self.logger.log("\(tdError.code) - \(tdError.message)", level: .error)
            }
        }
    }

    func loadMainChats() async throws {
        _ = try await tdApi.loadChats(chatList: .chatListMain, limit: 30)
        let chats = try await tdApi.getChats(chatList: .chatListMain, limit: 30)
        mainChats = try await chats.chatIds.asyncMap { id in
            return try await tdApi.getChat(chatId: id)
        }
        logger.log("Loaded chats: \(mainChats)")
    }
}

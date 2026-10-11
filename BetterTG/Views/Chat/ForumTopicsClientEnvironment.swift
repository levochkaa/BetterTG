// ForumTopicsClientEnvironment.swift

import Combine
import Foundation
import TDLibKit

/// Ownership and preparation boundary. The live model keeps its immutable TDLib
/// client; native probes can supply isolated models and gated metadata reads.
@MainActor struct ForumTopicsClientEnvironment {
    struct Metadata {
        let source: TdUpdateSource
        let client: TDLibClient
        let chat: CustomChat
    }

    static var live: Self {
        Self(
            currentSource: { TDLib.shared.activeUpdateSource },
            currentAccount: { RootVM.shared.activeAccountID },
            currentActor: { TDLib.shared.activeAccount?.userID },
            activeChanges: TDLib.shared.activeClientChanges,
            readyChanges: TDLib.shared.readyClientChanges,
            // TDLib publishes identity changes on main. Synchronous sampling
            // preserves intermediate actor departures before a later ABA.
            accountChanges: nc.publisher(for: .telegramAccountsChanged)
                .map { _ in () }
                .eraseToAnyPublisher(),
            metadata: { source, chatID in
                let client = TDLib.shared.activeClient
                guard client.id == source.clientID,
                      let chat = await RootVM.shared.getCustomChatForNavigation(from: chatID, client: client)
                else { return nil }
                return Metadata(source: source, client: client, chat: chat)
            },
            model: { ForumTopicsVM(customChat: $0, location: $1, client: $2, restoration: $3) },
            retryNavigation: { NavigationStorage.shared.retryClientRestoration() },
        )
    }

    let currentSource: () -> TdUpdateSource?
    let currentAccount: () -> UUID?
    let currentActor: () -> Int64?
    let activeChanges: AnyPublisher<TdUpdateSource, Never>
    let readyChanges: AnyPublisher<TdUpdateSource?, Never>
    let accountChanges: AnyPublisher<Void, Never>
    let metadata: (TdUpdateSource, Int64) async -> Metadata?
    let model: (CustomChat, ChatLocation, TDLibClient, ForumTopicsRestorationState?) -> ForumTopicsVM
    let retryNavigation: () -> Void
}

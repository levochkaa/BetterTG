// TDLibNetworkStatus.swift

import Combine
import Foundation
import TDLibKit

extension ConnectionState {
    /// ChatListController's NetworkStatusTitle in place of the list title; nil when online. Telegram leaves the proxy
    /// wording out (`State.ConnectingToProxy` is commented out there).
    var chatListStatus: String? {
        switch self {
        case .connectionStateWaitingForNetwork:
            L10n.telegram("State.WaitingForNetwork")
        case .connectionStateConnecting,
             .connectionStateConnectingToProxy:
            L10n.telegram("State.Connecting")
        case .connectionStateUpdating:
            L10n.telegram("State.Updating")
        case .connectionStateReady:
            nil
        }
    }

    /// ChatTitleView's info text in place of a chat's status; nil when online.
    var chatTitleStatus: String? {
        switch self {
        case .connectionStateWaitingForNetwork:
            L10n.telegram("ChatState.WaitingForNetwork")
        case .connectionStateConnecting,
             .connectionStateConnectingToProxy:
            L10n.telegram("ChatState.Connecting")
        case .connectionStateUpdating:
            L10n.telegram("ChatState.Updating")
        case .connectionStateReady:
            nil
        }
    }
}

extension TDLib {
    /// The chat list's network status title. Leaving online waits 0.3 s, so a reconnect that settles sooner leaves the
    /// title alone (ChatListControllerImpl's delayed `networkState`).
    var chatListNetworkStatus: AnyPublisher<String?, Never> {
        Deferred { [connectionStates] in
            var previous: ConnectionState?
            return connectionStates
                .map { state -> AnyPublisher<ConnectionState, Never> in
                    let leavesReady = previous == .connectionStateReady && state != .connectionStateReady
                    previous = state
                    let value = Just(state)
                    return leavesReady
                        ? value.delay(for: .milliseconds(300), scheduler: DispatchQueue.main).eraseToAnyPublisher()
                        : value.eraseToAnyPublisher()
                }
                .switchToLatest()
        }
        .map(\.chatListStatus)
        .removeDuplicates()
        .eraseToAnyPublisher()
    }
}

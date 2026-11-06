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

// MARK: - ProxyStatusStore

/// ProxySettings as the chat list reads them: whether a proxy is saved and whether one is on. TDLib sends no updates
/// for its proxies, so they are read once the account is ready and again after the proxy screens change them.
@MainActor final class ProxyStatusStore {
    struct State: Equatable {
        var hasProxy = false
        var isEnabled = false
        /// PeerInfoSettingsItems' proxy label: the enabled server's type, or Disabled.
        var enabledTypeTitle: String?
    }

    static let shared = ProxyStatusStore()

    @Published private(set) var state = State()

    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        nc.publisher(&cancellables, for: .authorizationStateReady) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func refresh() {
        refreshTask?.cancel()
        let client = TDLib.shared.activeClient
        refreshTask = Task { [weak self] in
            let proxies = await (try? client.send(TDNativeRequests.getProxies()))?.proxies
            guard let self, !Task.isCancelled, let proxies, TDLib.shared.activeClient.id == client.id else { return }
            let enabled = proxies.first(where: \.isEnabled)
            state = State(
                hasProxy: !proxies.isEmpty,
                isEnabled: enabled != nil,
                enabledTypeTitle: enabled.map { Self.typeTitle($0.proxy) },
            )
        }
    }
}

extension ProxyStatusStore {
    /// PeerInfoSettingsItems' proxy row: MTProto, SOCKS5 or WEB; HTTP, which Telegram doesn't offer, by name.
    static func typeTitle(_ proxy: TDNativeProxy) -> String {
        switch proxy.type {
        case .proxyTypeMtproto: L10n.telegram("SocksProxySetup.ProxyTelegram")
        case .proxyTypeSocks5: L10n.telegram("SocksProxySetup.ProxySocks5")
        case .proxyTypeWeb: L10n.telegram("SocksProxySetup.ProxyWeb")
        case .proxyTypeHttp: "HTTP"
        }
    }
}

@MainActor extension TDLib {
    /// ChatListController's proxyButton: nil without a saved proxy; available while no proxy is on, else connecting
    /// until TDLib is online through it.
    var chatListProxyStatus: AnyPublisher<ChatListProxyStatus?, Never> {
        ProxyStatusStore.shared
            .$state
            .combineLatest(connectionStates)
            .map { proxy, connection -> ChatListProxyStatus? in
                guard proxy.hasProxy else { return nil }
                guard proxy.isEnabled else { return .available }
                return connection == .connectionStateReady ? .connected : .connecting
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

// MARK: - ChatListProxyStatus

/// ChatTitleProxyStatus.
enum ChatListProxyStatus {
    case available
    case connecting
    case connected
}

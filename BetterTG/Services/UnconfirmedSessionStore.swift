// UnconfirmedSessionStore.swift

import Combine
import Foundation
import TDLibKit

// MARK: - UnconfirmedSessionStore

/// NewSessionReview from TDLib's updateUnconfirmedSession: the first login from another device that the account hasn't
/// confirmed yet, with how many wait, kept for each client and published for the active one. Telegram's chat list
/// asks about it in its header (ChatListNotice.reviewLogin). A connected bot's review is left out.
@MainActor final class UnconfirmedSessionStore {
    struct Review: Equatable {
        let accountID: UUID
        let clientID: Int32
        let sessionID: Int64
        let device: String
        let location: String
        let count: Int
    }

    static let shared = UnconfirmedSessionStore()

    /// The active client's review, nil while there is none.
    @Published private(set) var review: Review?

    private var reviews = [String: Review]()
    #if DEBUG
        private var resolvedProbe = false
    #endif
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    private static func key(accountID: UUID, clientID: Int32) -> String {
        "\(accountID.uuidString):\(clientID)"
    }

    func start() {
        guard cancellables.isEmpty else { return }
        nc.scopedPublisher(&cancellables, for: .updateUnconfirmedSession) { [weak self] event in
            self?.receive(event.value, source: event.source)
        }
        nc.publisher(&cancellables, for: .telegramAccountsChanged) { [weak self] _ in
            self?.publish()
        }
    }

    /// Publishes the active client's review again, as the chat list appears for a client that became active.
    func refresh() {
        publish()
    }

    /// The panel goes at once; TDLib's next update confirms it.
    func resolve(_ review: Review) {
        reviews[Self.key(accountID: review.accountID, clientID: review.clientID)] = nil
        #if DEBUG
            resolvedProbe = true
        #endif
        publish()
    }

    private func receive(_ update: TDNativeUpdateUnconfirmedSession, source: TdUpdateSource) {
        let key = Self.key(accountID: source.accountID, clientID: source.clientID)
        reviews[key] =
            if let session = update.session, case .sessionTypeDevice(let device) = session.type {
                Review(
                    accountID: source.accountID,
                    clientID: source.clientID,
                    sessionID: device.sessionId,
                    device: session.deviceModel,
                    location: session.location,
                    count: max(1, update.unconfirmedSessionCount),
                )
            } else {
                nil
            }
        publish()
    }

    private func publish() {
        guard let source = TDLib.shared.activeUpdateSource else {
            if review != nil { review = nil }
            return
        }
        var current = reviews[Self.key(accountID: source.accountID, clientID: source.clientID)]
        #if DEBUG
            // `-ui-probe-session-review` asks about a made-up login, so the panel shows without a new session.
            if current == nil, !resolvedProbe, ProcessInfo.processInfo.arguments.contains("-ui-probe-session-review") {
                current = Review(
                    accountID: source.accountID, clientID: source.clientID, sessionID: 0,
                    device: "Telegram Desktop", location: "Berlin, Germany", count: 2,
                )
            }
        #endif
        if current != review { review = current }
    }
}

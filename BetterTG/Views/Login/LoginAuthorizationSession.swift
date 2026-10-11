// LoginAuthorizationSession.swift

import TDLibKit
import UIKit

@MainActor final class LoginAuthorizationSession {
    struct Client {
        let submit: (LoginState, String) async throws -> Void

        static func live(_ client: TDLibClient) -> Client {
            Client { stage, value in
                _ =
                    switch stage {
                    case .phoneNumber: try await client.setAuthenticationPhoneNumber(phoneNumber: value, settings: nil)
                    case .code: try await client.checkAuthenticationCode(code: value)
                    case .twoFactor: try await client.checkAuthenticationPassword(password: value)
                    }
            }
        }
    }

    struct Token: Equatable {
        let source: TdUpdateSource

        fileprivate let generation: UUID
    }

    let accountID: UUID?
    private(set) var snapshot: TDLibAuthorizationState.Snapshot?
    private(set) var isRevoked = false
    private(set) var isBusy = false
    var onChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let currentSource: () -> TdUpdateSource?
    private let client: (TdUpdateSource) -> Client?
    private var generation = UUID()
    private var requestID: UUID?
    private var pendingValue: String?
    private var requestTask: Task<Void, Never>?

    var stage: LoginState? {
        switch snapshot?.state {
        case .authorizationStateWaitPhoneNumber: .phoneNumber
        case .authorizationStateWaitCode: .code
        case .authorizationStateWaitPassword: .twoFactor
        default: nil
        }
    }

    init(
        accountID: UUID?,
        currentSource: @escaping () -> TdUpdateSource?,
        client: @escaping (TdUpdateSource) -> Client?,
    ) {
        self.accountID = accountID
        self.currentSource = currentSource
        self.client = client
    }

    deinit { requestTask?.cancel() }

    func accept(_ next: TDLibAuthorizationState.Snapshot?) {
        guard !isRevoked else { return }
        if let next {
            guard next.source == currentSource() else { return }
            guard next.source.accountID == accountID else { return revoke() }
        }
        guard next != snapshot else { return }
        cancelRequest()
        generation = UUID()
        snapshot = next
        onChange?(true)
    }

    func revoke() {
        guard !isRevoked else { return }
        isRevoked = true
        cancelRequest()
        snapshot = nil
        generation = UUID()
        onChange?(true)
    }

    func capture() -> Token? {
        guard !isRevoked, let source = snapshot?.source, source == currentSource() else { return nil }
        return Token(source: source, generation: generation)
    }

    func permits(_ token: Token) -> Bool { capture() == token }

    func submit(_ value: String, prefix: String) {
        guard !isBusy, !value.isEmpty, let stage, let token = capture(), let client = client(token.source),
              permits(token) else { return }
        let id = UUID()
        requestID = id
        pendingValue = stage == .phoneNumber ? prefix + value : value
        isBusy = true
        requestTask = Task { [weak self] in
            guard !Task.isCancelled, let value = self?.takeValue(id, token: token) else { return }
            var failure: String?
            do { try await client.submit(stage, value) }
            catch { failure = error.localizedDescription }
            guard !Task.isCancelled else { return }
            self?.finish(id, token: token, failure: failure)
        }
        onChange?(false)
    }

    private func takeValue(_ id: UUID, token: Token) -> String? {
        guard permits(token), requestID == id else { return nil }
        defer { pendingValue = nil }
        return pendingValue
    }

    private func finish(_ id: UUID, token: Token, failure: String?) {
        guard permits(token), requestID == id else { return }
        requestID = nil
        requestTask = nil
        isBusy = false
        onChange?(false)
        if let failure, requestID == nil, permits(token) { onError?(failure) }
    }

    private func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
        requestID = nil
        pendingValue = nil
        isBusy = false
    }
}

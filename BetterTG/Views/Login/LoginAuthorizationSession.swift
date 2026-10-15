// LoginAuthorizationSession.swift

import TDLibKit
import UIKit

// MARK: - LoginAuthorizationSession

@MainActor final class LoginAuthorizationSession {
    struct Client {
        let submit: (LoginRequest) async throws -> Void

        static func live(_ client: TDLibClient) -> Client {
            Client { request in
                _ =
                    switch request {
                    case .phoneNumber(let value):
                        try await client.setAuthenticationPhoneNumber(phoneNumber: value, settings: nil)
                    case .code(let value):
                        try await client.checkAuthenticationCode(code: value)
                    case .password(let value):
                        try await client.checkAuthenticationPassword(password: value)
                    case .emailAddress(let value):
                        try await client.setAuthenticationEmailAddress(emailAddress: value)
                    case .emailCode(let value):
                        try await client.checkAuthenticationEmailCode(
                            code: .emailAddressAuthenticationCode(.init(code: value)),
                        )
                    case .registration(let firstName, let lastName):
                        try await client.registerUser(
                            firstName: firstName,
                            lastName: lastName,
                            disableNotification: false,
                        )
                    case .qrCode(let otherUserIDs):
                        try await client.requestQrCodeAuthentication(otherUserIds: otherUserIDs)
                    case .resetEmailAddress:
                        try await client.resetAuthenticationEmailAddress()
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
    /// When the step's server timer runs out (a pending email reset); nil without one.
    private(set) var stageDeadline: Date?
    var onChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let currentSource: () -> TdUpdateSource?
    private let client: (TdUpdateSource) -> Client?
    private var generation = UUID()
    private var requestID: UUID?
    private var pendingRequest: LoginRequest?
    private var requestTask: Task<Void, Never>?

    var stage: LoginState? { LoginState(snapshot?.state) }

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

    private static func request(
        for stage: LoginState,
        value: String,
        secondary: String,
        prefix: String,
    ) -> LoginRequest? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // A password is taken as typed; other input may not be blank.
        guard !value.isEmpty, !trimmed.isEmpty || stage == .twoFactor else { return nil }
        return switch stage {
        case .phoneNumber: .phoneNumber(prefix + value)
        case .twoFactor: .password(value)
        case .code: .code(trimmed)
        case .emailAddress: .emailAddress(trimmed)
        case .emailCode: .emailCode(trimmed)
        case .registration: .registration(
                firstName: trimmed,
                lastName: secondary.trimmingCharacters(in: .whitespacesAndNewlines),
            )
        case .qrCode: nil
        }
    }

    private static func allows(_ request: LoginRequest, in stage: LoginState) -> Bool {
        switch request {
        // TDLib takes a QR code request from phone entry and from the later steps (requestQrCodeAuthentication).
        case .qrCode: stage == .phoneNumber
        case .resetEmailAddress: stage == .emailCode
        default: false
        }
    }

    private static func deadline(for state: AuthorizationState?) -> Date? {
        guard case .authorizationStateWaitEmailCode(let value) = state,
              case .emailAddressResetStatePending(let pending) = value.emailAddressResetState,
              pending.resetIn > 0 else { return nil }
        return Date(timeIntervalSinceNow: TimeInterval(pending.resetIn))
    }

    func accept(_ next: TDLibAuthorizationState.Snapshot?) {
        guard !isRevoked else { return }
        if let next {
            guard next.source == currentSource() else { return }
            guard next.source.accountID == accountID else { return revoke() }
        }
        guard next != snapshot else { return }
        let previousStage = stage
        // TDLib restates a step with new details (a new QR link, a recovery email pattern, a resent code). The step's
        // request and actions stay valid; only a new step or client retires them.
        let continuesStage = next?.source == snapshot?.source && previousStage != nil
            && LoginState(next?.state) == previousStage
        if !continuesStage {
            cancelRequest()
            generation = UUID()
        }
        snapshot = next
        stageDeadline = Self.deadline(for: next?.state)
        onChange?(!continuesStage || stage != previousStage)
    }

    func revoke() {
        guard !isRevoked else { return }
        isRevoked = true
        cancelRequest()
        snapshot = nil
        stageDeadline = nil
        generation = UUID()
        onChange?(true)
    }

    func capture() -> Token? {
        guard !isRevoked, let source = snapshot?.source, source == currentSource() else { return nil }
        return Token(source: source, generation: generation)
    }

    func permits(_ token: Token) -> Bool { capture() == token }

    /// Seconds left on `stageDeadline`, 0 once it passed or without one.
    func remainingSeconds(at date: Date = Date()) -> Int {
        guard let stageDeadline else { return 0 }
        return max(0, Int(ceil(stageDeadline.timeIntervalSince(date))))
    }

    /// Submits the step's input; `secondary` is the last name when signing up.
    func submit(_ value: String, secondary: String = "", prefix: String) {
        guard let stage,
              let request = Self.request(for: stage, value: value, secondary: secondary, prefix: prefix)
        else { return }
        dispatch(request, stage: stage)
    }

    /// Starts a step action that takes no input.
    func perform(_ request: LoginRequest) {
        guard let stage, Self.allows(request, in: stage) else { return }
        dispatch(request, stage: stage)
    }

    private func dispatch(_ request: LoginRequest, stage: LoginState) {
        guard !isBusy, let token = capture(), let client = client(token.source), permits(token) else { return }
        let id = UUID()
        requestID = id
        pendingRequest = request
        isBusy = true
        requestTask = Task { [weak self] in
            guard !Task.isCancelled, let request = self?.takeRequest(id, token: token) else { return }
            var failure: String?
            do { try await client.submit(request) }
            catch { failure = LoginErrorText.message(for: error, stage: stage) }
            guard !Task.isCancelled else { return }
            self?.finish(id, token: token, failure: failure)
        }
        onChange?(false)
    }

    private func takeRequest(_ id: UUID, token: Token) -> LoginRequest? {
        guard permits(token), requestID == id else { return nil }
        defer { pendingRequest = nil }
        return pendingRequest
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
        pendingRequest = nil
        isBusy = false
    }
}

// MARK: - LoginErrorText

/// Telegram's texts for the authorization errors TDLib reports, as `AuthorizationSequenceController` maps them.
enum LoginErrorText {
    static func message(for error: Error, stage: LoginState) -> String {
        guard let error = error as? TDLibError else { return error.localizedDescription }
        let message = error.message
        if error.code == 429 || message.hasPrefix("FLOOD_WAIT") || message.hasPrefix("Too Many Requests") {
            return L10n.telegram(stage == .twoFactor ? "LoginPassword.FloodError" : "Login.CodeFloodError")
        }
        let key: String? =
            switch message {
            case "PHONE_NUMBER_INVALID": "Login.InvalidPhoneError"
            case "PHONE_NUMBER_BANNED": "Login.PhoneBannedError"
            case "PHONE_NUMBER_FLOOD": "Login.PhoneFloodError"
            case "CODE_INVALID", "EMAIL_CODE_INVALID", "PHONE_CODE_INVALID":
                stage == .emailCode ? "Login.WrongCodeError" : "Login.InvalidCodeError"
            case "CODE_EXPIRED", "EMAIL_CODE_EXPIRED", "PHONE_CODE_EXPIRED": "Login.CodeExpired"
            case "PASSWORD_HASH_INVALID": "LoginPassword.InvalidPasswordError"
            case "FIRSTNAME_INVALID": "Login.InvalidFirstNameError"
            case "LASTNAME_INVALID": "Login.InvalidLastNameError"
            case "EMAIL_INVALID": "Login.InvalidEmailError"
            case "EMAIL_NOT_ALLOWED": "Login.EmailNotAllowedError"
            case "UPDATE_APP_TO_LOGIN": "Login.ErrorAppOutdated"
            // An email reset that is still pending needs Telegram Premium to finish early.
            case "TASK_ALREADY_EXISTS": "Login.Email.PremiumRequiredTitle"
            default: nil
            }
        if let key { return L10n.telegram(key) }
        return message.isEmpty ? L10n.telegram("Login.UnknownError") : message
    }
}

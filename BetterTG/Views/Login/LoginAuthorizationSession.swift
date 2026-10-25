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
                    case .resendCode:
                        try await client.resendAuthenticationCode(reason: .resendCodeReasonUserRequest)
                    case .password(let value):
                        try await client.checkAuthenticationPassword(password: value)
                    case .passwordRecovery:
                        try await client.requestAuthenticationPasswordRecovery()
                    case .recoveryCode(let value):
                        try await client.checkAuthenticationPasswordRecoveryCode(recoveryCode: value)
                    case .recoverPassword(let code, let password, let hint):
                        try await client.recoverAuthenticationPassword(
                            recoveryCode: code,
                            newPassword: password,
                            newHint: hint,
                        )
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

    /// A screen Telegram shows inside one TDLib step: phone entry again from a later step ("Stop" in Telegram's
    /// verification alert), and the recovery code and new password screens of "Forgot password?".
    private enum LocalStage: Equatable {
        case phoneNumber
        case passwordRecovery
        case newPassword(code: String)
    }

    let accountID: UUID?
    private(set) var snapshot: TDLibAuthorizationState.Snapshot?
    private(set) var isRevoked = false
    private(set) var isBusy = false
    /// When the step's server timer runs out (the code resend timeout or a pending email reset); nil without one.
    private(set) var stageDeadline: Date?
    var onChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let currentSource: () -> TdUpdateSource?
    private let client: (TdUpdateSource) -> Client?
    private var generation = UUID()
    private var requestID: UUID?
    private var pendingRequest: LoginRequest?
    private var requestTask: Task<Void, Never>?
    private var localStage: LocalStage?

    /// The screen to show: TDLib's step, or a screen opened inside it.
    var stage: LoginState? {
        guard let tdlibStage else { return nil }
        return switch localStage {
        case .phoneNumber: .phoneNumber
        case .passwordRecovery: .passwordRecovery
        case .newPassword: .newPassword
        case nil: tdlibStage
        }
    }

    /// True on a screen opened inside a TDLib step; going back closes it.
    var hasLocalStage: Bool { localStage != nil }

    /// Telegram's back navigation: a screen opened inside a step closes, and the later steps return to phone entry.
    var canGoBack: Bool { hasLocalStage || offersPhoneNumberChange }

    /// TDLib takes a new phone number in these steps while no request is pending (setAuthenticationPhoneNumber).
    private var offersPhoneNumberChange: Bool {
        guard localStage == nil else { return false }
        return switch tdlibStage {
        case .code,
             .emailAddress,
             .emailCode,
             .registration,
             .twoFactor: true
        default: false
        }
    }

    private var tdlibStage: LoginState? { LoginState(snapshot?.state) }

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

    private static func deadline(for state: AuthorizationState?) -> Date? {
        let seconds: Int? =
            switch state {
            case .authorizationStateWaitCode(let value):
                value.codeInfo.nextType == nil ? nil : value.codeInfo.timeout
            case .authorizationStateWaitEmailCode(let value):
                if case .emailAddressResetStatePending(let pending) = value.emailAddressResetState {
                    pending.resetIn
                } else {
                    nil
                }
            default:
                nil
            }
        guard let seconds, seconds > 0 else { return nil }
        return Date(timeIntervalSinceNow: TimeInterval(seconds))
    }

    func accept(_ next: TDLibAuthorizationState.Snapshot?) {
        guard !isRevoked else { return }
        if let next {
            guard next.source == currentSource() else { return }
            guard next.source.accountID == accountID else { return revoke() }
        }
        guard next != snapshot else { return }
        let previousStage = stage
        let previousTDLibStage = tdlibStage
        // TDLib restates a step with new details (a new QR link, a recovery email pattern, a resent code). The step's
        // request and actions stay valid; only a new step or client retires them.
        let continuesStage = next?.source == snapshot?.source && previousTDLibStage != nil
            && LoginState(next?.state) == previousTDLibStage
        if !continuesStage {
            cancelRequest()
            generation = UUID()
        }
        snapshot = next
        // New details belong to TDLib's own screen, as a new code after a phone number change does.
        localStage = nil
        stageDeadline = Self.deadline(for: next?.state)
        onChange?(!continuesStage || stage != previousStage)
    }

    func revoke() {
        guard !isRevoked else { return }
        isRevoked = true
        cancelRequest()
        snapshot = nil
        localStage = nil
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

    /// Submits the screen's input; `secondary` is the last name when signing up and the hint of a new password.
    func submit(_ value: String, secondary: String = "", prefix: String) {
        guard let stage, let request = request(for: stage, value: value, secondary: secondary, prefix: prefix)
        else { return }
        dispatch(request, stage: stage)
    }

    /// Starts a step action that takes no input.
    func perform(_ request: LoginRequest) {
        guard let stage, allows(request, in: stage) else { return }
        dispatch(request, stage: stage)
    }

    /// Opens phone entry again over a later step; the new number replaces the old one in TDLib.
    func changePhoneNumber() {
        guard offersPhoneNumberChange, !isBusy, capture() != nil else { return }
        localStage = .phoneNumber
        onChange?(true)
    }

    /// Goes back one screen inside the TDLib step.
    func leaveLocalStage() {
        guard let localStage, !isBusy, capture() != nil else { return }
        self.localStage =
            switch localStage {
            case .newPassword: .passwordRecovery
            case .passwordRecovery,
                 .phoneNumber: nil
            }
        onChange?(true)
    }

    private func allows(_ request: LoginRequest, in stage: LoginState) -> Bool {
        switch request {
        // TDLib takes a QR code request from phone entry and from the later steps (requestQrCodeAuthentication).
        case .qrCode:
            return stage == .phoneNumber
        case .resetEmailAddress:
            return stage == .emailCode
        case .passwordRecovery:
            return stage == .twoFactor
        case .resendCode:
            // TDLib resends a code only after the server timeout, when a next code type exists.
            guard stage == .code, case .authorizationStateWaitCode(let value) = snapshot?.state else { return false }
            return value.codeInfo.nextType != nil && remainingSeconds() == 0
        default:
            return false
        }
    }

    private func request(for stage: LoginState, value: String, secondary: String, prefix: String) -> LoginRequest? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPassword = stage == .twoFactor || stage == .newPassword
        // A password is taken as typed; other input may not be blank.
        guard !value.isEmpty, !trimmed.isEmpty || isPassword else { return nil }
        let trimmedSecondary = secondary.trimmingCharacters(in: .whitespacesAndNewlines)
        switch stage {
        // A number typed with its own "+", such as the test server's +99966…, keeps its country code.
        case .phoneNumber: return .phoneNumber(trimmed.hasPrefix("+") ? trimmed : prefix + value)
        case .code: return .code(trimmed)
        case .twoFactor: return .password(value)
        case .passwordRecovery: return .recoveryCode(trimmed)
        case .newPassword:
            guard case .newPassword(let code) = localStage else { return nil }
            return .recoverPassword(code: code, password: value, hint: trimmedSecondary)
        case .emailAddress: return .emailAddress(trimmed)
        case .emailCode: return .emailCode(trimmed)
        case .registration: return .registration(firstName: trimmed, lastName: trimmedSecondary)
        case .qrCode: return nil
        }
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
            do {
                try await client.submit(request)
            } catch {
                failure = LoginErrorText.message(for: error, stage: stage)
            }
            guard !Task.isCancelled else { return }
            self?.finish(id, token: token, request: request, failure: failure)
        }
        onChange?(false)
    }

    private func takeRequest(_ id: UUID, token: Token) -> LoginRequest? {
        guard permits(token), requestID == id else { return nil }
        defer { pendingRequest = nil }
        return pendingRequest
    }

    private func finish(_ id: UUID, token: Token, request: LoginRequest, failure: String?) {
        guard permits(token), requestID == id else { return }
        requestID = nil
        requestTask = nil
        isBusy = false
        let next = failure == nil ? nextLocalStage(after: request) : localStage
        let opensScreen = next != localStage
        localStage = next
        onChange?(opensScreen)
        if let failure, requestID == nil, permits(token) { onError?(failure) }
    }

    /// The screen a successful request leads to inside the step (Telegram's password recovery controllers).
    private func nextLocalStage(after request: LoginRequest) -> LocalStage? {
        switch request {
        case .passwordRecovery where tdlibStage == .twoFactor && localStage == nil:
            .passwordRecovery
        case .recoveryCode(let code) where localStage == .passwordRecovery:
            .newPassword(code: code)
        // An accepted number leaves phone entry even if TDLib restated nothing.
        case .phoneNumber where localStage == .phoneNumber:
            nil
        default:
            localStage
        }
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
            let isPassword = stage == .twoFactor || stage == .passwordRecovery || stage == .newPassword
            return L10n.telegram(isPassword ? "LoginPassword.FloodError" : "Login.CodeFloodError")
        }
        if stage == .passwordRecovery {
            switch message {
            case "CODE_INVALID",
                 "Invalid recovery code",
                 "PASSWORD_RECOVERY_EXPIRED":
                return L10n.telegram("TwoStepAuth.RecoveryCodeInvalid")
            case "PASSWORD_RECOVERY_NA":
                return L10n.telegram("TwoStepAuth.RecoveryUnavailable")
            default:
                break
            }
        }
        let key: String? =
            switch message {
            case "PHONE_NUMBER_INVALID": "Login.InvalidPhoneError"
            case "PHONE_NUMBER_BANNED": "Login.PhoneBannedError"
            case "PHONE_NUMBER_FLOOD": "Login.PhoneFloodError"
            case "CODE_INVALID",
                 "EMAIL_CODE_INVALID",
                 "PHONE_CODE_INVALID":
                stage == .emailCode ? "Login.WrongCodeError" : "Login.InvalidCodeError"
            case "CODE_EXPIRED",
                 "EMAIL_CODE_EXPIRED",
                 "PHONE_CODE_EXPIRED": "Login.CodeExpired"
            case "PASSWORD_HASH_INVALID": "LoginPassword.InvalidPasswordError"
            case "PASSWORD_RECOVERY_NA": "TwoStepAuth.RecoveryUnavailable"
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

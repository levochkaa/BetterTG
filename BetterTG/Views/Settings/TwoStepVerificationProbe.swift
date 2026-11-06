// TwoStepVerificationProbe.swift

#if DEBUG
    import TDLibKit
    import UIKit

    // MARK: - TwoStepVerificationProbe

    /// Opens Two-Step Verification on a made-up account, so its screens can be driven without TDLib and without
    /// changing a real account's password. Launch with `-ui-probe-two-step MODE`:
    /// - `set`: a password ("probe", hint "pet") with a recovery email; a wrong password fails, the right one opens the
    ///   settings, and Change Password, Turn Password Off and the email answer as TDLib would;
    /// - `none`: no password; TwoFactorAuthSplashScreen's intro, whose button creates one with an email waiting for
    ///   code 123456;
    /// - `pending`: a new password whose email waits for code 123456;
    /// - `reset`: a password without a recovery email whose reset is due in three days.
    /// Every request goes to the log and to Documents/two-step-probe.txt.
    @MainActor enum TwoStepVerificationProbe {
        // MARK: - ProbeService

        @MainActor private final class ProbeService: TwoStepVerificationService {
            private static var lines = [String]()

            private var state: TwoStepVerificationConfiguration
            private var password: String?
            private var pendingPassword: String?

            init(mode: String) {
                switch mode {
                case "none":
                    self.state = .init(hasPassword: false, hint: "", hasRecoveryEmail: false, hasPassportData: false)
                case "pending":
                    self.state = .init(
                        hasPassword: false, hint: "", hasRecoveryEmail: false, hasPassportData: false,
                        pendingEmail: .init(pattern: "p***@example.com", codeLength: 6),
                    )
                    self.pendingPassword = "probe"
                case "reset":
                    self.state = .init(
                        hasPassword: true, hint: "pet", hasRecoveryEmail: false, hasPassportData: false,
                        pendingResetDate: Int(Date().timeIntervalSince1970) + 3 * 24 * 60 * 60,
                    )
                    self.password = "probe"
                default:
                    self.state = .init(hasPassword: true, hint: "pet", hasRecoveryEmail: true, hasPassportData: false)
                    self.password = "probe"
                }
            }

            static func record(_ line: String) {
                log(line)
                lines.append(line)
                guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                else { return }
                try? Data(lines.joined(separator: "\n").utf8)
                    .write(to: directory.appendingPathComponent("two-step-probe.txt"), options: .atomic)
            }

            private static func error(_ message: String) -> TDLibError {
                TDLibError(code: 400, message: message)
            }

            func configuration() -> TwoStepVerificationConfiguration {
                Self.record("getPasswordState -> hasPassword=\(state.hasPassword) pending=\(state.pendingEmail != nil)")
                return state
            }

            func verify(password: String) async throws -> String {
                try await Task.sleep(for: .milliseconds(300))
                guard password == self.password else {
                    Self.record("getRecoveryEmailAddress(\(password)) -> PASSWORD_HASH_INVALID")
                    throw Self.error("PASSWORD_HASH_INVALID")
                }
                Self.record("getRecoveryEmailAddress -> ok")
                return state.hasRecoveryEmail ? "probe@example.com" : ""
            }

            func setPassword(
                old: String,
                new: String,
                hint: String,
                email: String?,
            ) async throws -> TwoStepVerificationConfiguration {
                try await Task.sleep(for: .milliseconds(300))
                Self.record("setPassword(old: \(old), new: \(new), hint: \(hint), email: \(email ?? "-"))")
                if let email, !email.contains("@") { throw Self.error("EMAIL_INVALID") }
                if new.isEmpty {
                    password = nil
                    state = .init(hasPassword: false, hint: "", hasRecoveryEmail: false, hasPassportData: false)
                } else if let email {
                    pendingPassword = new
                    state.hint = hint
                    state.pendingEmail = .init(pattern: email, codeLength: 6)
                } else {
                    password = new
                    state.hasPassword = true
                    state.hint = hint
                }
                return state
            }

            func setRecoveryEmail(password _: String, email: String) async throws -> TwoStepVerificationConfiguration {
                try await Task.sleep(for: .milliseconds(300))
                Self.record("setRecoveryEmailAddress(\(email))")
                guard email.contains("@") else { throw Self.error("EMAIL_INVALID") }
                state.pendingEmail = .init(pattern: email, codeLength: 6)
                return state
            }

            func checkEmailCode(_ code: String) async throws -> TwoStepVerificationConfiguration {
                try await Task.sleep(for: .milliseconds(300))
                Self.record("checkRecoveryEmailAddressCode(\(code))")
                guard code == "123456" else { throw Self.error("CODE_INVALID") }
                state.pendingEmail = nil
                state.hasRecoveryEmail = true
                if let pendingPassword {
                    password = pendingPassword
                    state.hasPassword = true
                    self.pendingPassword = nil
                }
                return state
            }

            func resendEmailCode() -> TwoStepVerificationConfiguration {
                Self.record("resendRecoveryEmailAddressCode")
                return state
            }

            func cancelEmailVerification() -> TwoStepVerificationConfiguration {
                Self.record("cancelRecoveryEmailAddressVerification")
                state.pendingEmail = nil
                pendingPassword = nil
                return state
            }

            func requestRecoveryCode() -> String {
                Self.record("requestPasswordRecovery")
                return "p***@example.com"
            }

            func checkRecoveryCode(_ code: String) throws {
                Self.record("checkPasswordRecoveryCode(\(code))")
                guard code == "123456" else { throw Self.error("CODE_INVALID") }
            }

            func recoverPassword(
                code _: String,
                new: String,
                hint: String,
            ) -> TwoStepVerificationConfiguration {
                Self.record("recoverPassword(new: \(new), hint: \(hint))")
                password = new
                state.hint = hint
                return state
            }

            func resetPassword() -> TwoStepVerificationResetResult {
                Self.record("resetPassword")
                let date = Int(Date().timeIntervalSince1970) + 7 * 24 * 60 * 60
                state.pendingResetDate = date
                return .waitingForReset(date: date)
            }

            func cancelPasswordReset() {
                Self.record("cancelPasswordReset")
                state.pendingResetDate = nil
            }
        }

        private static let flag = "-ui-probe-two-step"
        private static var service: ProbeService?

        static func runIfRequested(in window: UIWindow) {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: flag) else { return }
            let mode = arguments[safe: index + 1] ?? "set"
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                let service = ProbeService(mode: mode)
                self.service = service
                let screen = TwoStepVerificationViewController.entry(
                    for: service.configuration(),
                    service: service,
                )
                let navigation = TelegramNavigationController(rootViewController: screen)
                navigation.modalPresentationStyle = .fullScreen
                var presenter = window.rootViewController
                while let presented = presenter?.presentedViewController {
                    presenter = presented
                }
                presenter?.present(navigation, animated: false)
                ProbeService.record("Two-step probe running: \(mode)")
            }
        }
    }
#endif

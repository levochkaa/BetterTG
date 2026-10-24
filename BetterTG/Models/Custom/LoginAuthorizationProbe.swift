// LoginAuthorizationProbe.swift

#if DEBUG
    import Combine
    import TDLibKit
    import UIKit

    @MainActor enum LoginAuthorizationProbe {
        private struct Failure: Swift.Error, CustomStringConvertible { let description: String }
        private final class Requests {
            var calls = [(TdUpdateSource, LoginRequest)]()
            var replies = [CheckedContinuation<Void, Swift.Error>?]()

            func send(_ source: TdUpdateSource, _ request: LoginRequest) async throws {
                calls.append((source, request))
                try await withCheckedThrowingContinuation { replies.append($0) }
            }

            func complete(_ index: Int, failure: Bool = false) {
                guard replies.indices.contains(index), let reply = replies[index] else { return }
                replies[index] = nil
                if failure { reply.resume(throwing: Failure(description: "isolated auth failure")) }
                else { reply.resume() }
            }

            func finishAll() { for index in replies.indices {
                complete(index)
            } }
        }

        static func runDebugProbeIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ui-probe-login-authorization") else { return }
            Task { @MainActor in
                let result: String
                do {
                    try await verify()
                    result = "Login authorization probe passed: accepted-relay/replay/handoff=true; "
                        + "real-Login-credentials/hint/controls=true; frozen-client/stage/duplicate-submit=true; "
                        + "suspended-completion/queued-dispatch/reentrant-revoke/deinit=true; "
                        + "same-account-rebind/foreign-account-terminal=true; generated-scoped-transport=true; "
                        + "input-free-states-denied=true; email/sign-up/qr-stages=true; "
                        + "wrong-number/resend/password-recovery=true; "
                        + "real-auth/account-stores/clipboard=0; server/device-auth=pending"
                } catch {
                    result = "Login authorization probe failed: \(error)"
                }
                log(result)
                if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? Data(result.utf8).write(
                        to: directory.appendingPathComponent("login-authorization-probe.txt"),
                        options: .atomic,
                    )
                }
            }
        }

        private static func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
        }

        private static func drain() async {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }

        private static func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }

        private static func verify() async throws {
            let relay = TDLibAuthorizationState()
            let requests = Requests()
            defer { requests.finishAll() }
            let a1 = TdUpdateSource(accountID: UUID(), clientID: 1)
            let a2 = TdUpdateSource(accountID: a1.accountID, clientID: 2)
            let b = TdUpdateSource(accountID: UUID(), clientID: 3)
            func makeSession() -> LoginAuthorizationSession {
                LoginAuthorizationSession(
                    accountID: a1.accountID,
                    currentSource: { relay.current?.source },
                    client: { source in
                    guard relay.current?.source == source else { return nil }
                    return .init { request in try await requests.send(source, request) }
                },
                )
            }
            let session = makeSession()
            let view = LoginViewController(
                authorization: session,
                updates: relay.publisher,
                hasOtherAccounts: { false },
            )
            view.loadViewIfNeeded()
            guard let input = descendants(view.view).compactMap({ $0 as? UITextField }).first,
                  let button = descendants(view.view)
.compactMap({ $0 as? UIButton })
                  .first(where: { $0.configuration?.title == L10n.telegram("Login.Continue") })
            else {
                throw Failure(description: "real Login controls missing")
            }
            try require(!input.isEnabled && !button.isEnabled, "cold state submitted")
            relay.activate(a1)
            let password = AuthorizationState.authorizationStateWaitPassword(.init(
                passwordHint: "probe hint",
                hasRecoveryEmailAddress: false,
                hasPassportData: false,
                recoveryEmailAddressPattern: "",
            ))
            relay.update(password, source: a1)
            try require(
                input.isSecureTextEntry && input.placeholder == "probe hint" && button.isEnabled,
                "accepted password UI",
            )
            input.text = "isolated-secret"
            relay.update(password, source: a1)
            try require(input.text == "isolated-secret", "duplicate state cleared credentials")
            let oldAction = session.capture()!
            button.sendActions(for: .touchUpInside)
            button.sendActions(for: .touchUpInside)
            await drain()
            try require(
                requests.calls.count == 1 && requests.calls[0].0 == a1
                    && requests.calls[0].1 == .password("isolated-secret"),
                "frozen password dispatch or duplicate",
            )
            relay.invalidate()
            // UITextField normalizes an empty placeholder to nil on this runtime.
            try require(
                (input.text ?? "").isEmpty && (input.placeholder ?? "").isEmpty && !input.isEnabled && !session
                    .permits(oldAction),
                "handoff clearing: text-empty=\((input.text ?? "").isEmpty); hint-nil=\(input.placeholder == nil); "
                    +
                        "hint-empty=\(input.placeholder == ""); input-enabled=\(input.isEnabled); action-valid=\(session.permits(oldAction))",
            )
            relay.update(password, source: a1)
            try require(relay.current == nil, "closed source revived after handoff")
            relay.activate(a2)
            let code = AuthorizationState.authorizationStateWaitCode(.init(codeInfo: .init(
                phoneNumber: "isolated",
                type: .authenticationCodeTypeTelegramMessage(.init(length: 5)),
                nextType: nil,
                timeout: 10,
            )))
            relay.update(code, source: a2)
            input.text = "12345"
            button.sendActions(for: .touchUpInside)
            await drain()
            try require(
                requests.calls.count == 2 && requests.calls[1].0 == a2 && requests.calls[1].1 == .code("12345"),
                "same-account rebind",
            )
            requests.complete(0, failure: true)
            await drain()
            try require(
                session.isBusy && !button.isEnabled && view.presentedViewController == nil,
                "old failure changed replacement UI",
            )
            relay.update(.authorizationStateWaitPhoneNumber, source: a2)
            input.text = "555"
            button.sendActions(for: .touchUpInside)
            await drain()
            try require(
                requests.calls.count == 3 && requests.calls[2].1 == .phoneNumber("7555"),
                "captured phone prefix or stage",
            )
            requests.complete(1, failure: true)
            await drain()
            try require(session.isBusy && view.presentedViewController == nil, "old stage completion applied")
            requests.complete(2)
            await drain()
            try require(button.isEnabled && !session.isBusy, "current completion not delivered")

            input.text = "must-not-dispatch"
            button.sendActions(for: .touchUpInside)
            relay.update(code, source: a2)
            await drain()
            try require(requests.calls.count == 3 && (input.text ?? "").isEmpty, "queued credential crossed stage")
            let staleAction = session.capture()!
            relay.update(password, source: a1)
            try require(session.stage == .code, "old source state accepted")
            relay.activate(b)
            try require(
                view.isRevoked && !button.isEnabled && !session.permits(staleAction),
                "foreign account retained authority",
            )
            relay.activate(a1)
            relay.update(password, source: a1)
            input.text = "old-owner"
            button.sendActions(for: .touchUpInside)
            await drain()
            try require(requests.calls.count == 3 && view.isRevoked, "A-B-A resurrected old owner")

            let replacement = makeSession()
            let replacementView = LoginViewController(
                authorization: replacement,
                updates: relay.publisher,
                hasOtherAccounts: { false },
            )
            replacementView.loadViewIfNeeded()
            try require(replacement.stage == .twoFactor, "new Login missed replay")
            let unsupported: [AuthorizationState] = [
                .authorizationStateWaitTdlibParameters, .authorizationStateReady, .authorizationStateClosing,
                .authorizationStateClosed, .authorizationStateLoggingOut,
                .authorizationStateWaitPremiumPurchase(.init(
                    storeProductId: "",
                    premiumDayCount: 0,
                    supportEmailAddress: "",
                    supportEmailSubject: "",
                )),
            ]
            for state in unsupported {
                relay.update(state, source: a1)
                replacement.submit("denied", prefix: "7")
                try require(replacement.stage == nil && !replacement.isBusy, "input-free state became a step")
            }
            let steps: [(AuthorizationState, LoginState)] = [
                (.authorizationStateWaitEmailAddress(.init(allowAppleId: false, allowGoogleId: false)), .emailAddress),
                (.authorizationStateWaitEmailCode(.init(
                    allowAppleId: false,
                    allowGoogleId: false,
                    codeInfo: .init(emailAddressPattern: "", length: 5),
                    emailAddressResetState: nil,
                )), .emailCode),
                (.authorizationStateWaitOtherDeviceConfirmation(.init(link: "tg://isolated")), .qrCode),
                (.authorizationStateWaitRegistration(.init(termsOfService: .init(
                    text: .init(entities: [], text: ""),
                    minUserAge: 0,
                    showPopup: false,
                ))), .registration),
            ]
            for (state, step) in steps {
                relay.update(state, source: a1)
                try require(replacement.stage == step && !replacement.isBusy, "authorization step \(step) missing")
            }
            await drain()
            try require(requests.calls.count == 3, "input-free RPC dispatched")
            relay.update(password, source: a1)
            replacementView.willMove(toParent: nil)
            try require(replacement.isRevoked, "removed Login retained authority")

            let reentrant = makeSession()
            reentrant.accept(relay.current)
            reentrant.onChange = { [weak reentrant] clear in if !clear { reentrant?.revoke() } }
            reentrant.submit("revoked", prefix: "7")
            var detached: LoginAuthorizationSession? = makeSession()
            let weakDetached = { [weak detached] in detached }
            detached?.accept(relay.current)
            detached?.submit("deallocated", prefix: "7")
            detached = nil
            await drain()
            try require(requests.calls.count == 3 && weakDetached() == nil, "reentrant/deinit dispatch escaped")
            try verifyTransport(source: a1, state: password)
            try await verifyLocalSteps()
        }

        /// Screens opened inside one TDLib step: phone entry over the code step, a resend after the timeout, and the
        /// password recovery chain, which survives TDLib restating the password step before its request returns.
        private static func verifyLocalSteps() async throws {
            let relay = TDLibAuthorizationState()
            let requests = Requests()
            defer { requests.finishAll() }
            let source = TdUpdateSource(accountID: UUID(), clientID: 9)
            let session = LoginAuthorizationSession(
                accountID: source.accountID,
                currentSource: { relay.current?.source },
                client: { candidate in
                    guard relay.current?.source == candidate else { return nil }
                    return .init { request in try await requests.send(candidate, request) }
                },
            )
            let subscription = relay.publisher.sink { session.accept($0) }
            defer { subscription.cancel() }
            relay.activate(source)
            relay.update(.authorizationStateWaitCode(.init(codeInfo: .init(
                phoneNumber: "isolated",
                type: .authenticationCodeTypeSms(.init(length: 5)),
                nextType: .authenticationCodeTypeCall(.init(length: 5)),
                timeout: 0,
            ))), source: source)
            session.changePhoneNumber()
            try require(session.stage == .phoneNumber && session.hasLocalStage, "wrong number kept the code step")
            session.leaveLocalStage()
            try require(session.stage == .code, "back from phone entry lost the code step")
            session.perform(.resendCode)
            await drain()
            try require(requests.calls.last?.1 == .resendCode, "resend not dispatched after the timeout")
            requests.complete(0)
            await drain()

            func password(pattern: String) -> AuthorizationState {
                .authorizationStateWaitPassword(.init(
                    passwordHint: "",
                    hasRecoveryEmailAddress: true,
                    hasPassportData: false,
                    recoveryEmailAddressPattern: pattern,
                ))
            }
            relay.update(password(pattern: ""), source: source)
            session.perform(.passwordRecovery)
            await drain()
            relay.update(password(pattern: "isolated@pattern"), source: source)
            try require(session.isBusy, "restated step cancelled its request")
            requests.complete(1)
            await drain()
            try require(session.stage == .passwordRecovery, "recovery code screen missing")
            session.submit("123456", prefix: "")
            await drain()
            try require(requests.calls.last?.1 == .recoveryCode("123456"), "recovery code not checked")
            requests.complete(2)
            await drain()
            try require(session.stage == .newPassword, "new password screen missing")
            session.submit("new-secret", secondary: "hint", prefix: "")
            await drain()
            try require(
                requests.calls.last?.1 == .recoverPassword(code: "123456", password: "new-secret", hint: "hint"),
                "new password lost its recovery code",
            )
        }

        private static func verifyTransport(source: TdUpdateSource, state: AuthorizationState) throws {
            let center = NotificationCenter()
            var count = 0
            var observed: TdScopedUpdate<UpdateAuthorizationState>?
            let subscription = center.publisher(for: .updateAuthorizationState).sink {
                count += 1
                observed = TdScopedUpdate(notification: $0)
            }
            defer { subscription.cancel() }
            update(
                .updateAuthorizationState(.init(authorizationState: state)),
                source: source,
                notificationCenter: center,
            )
            try require(
                count == 1 && observed?.source == source && observed?.value.authorizationState == state,
                "generated auth bypassed injected scoped center",
            )
            update(.updateAuthorizationState(.init(authorizationState: state)), notificationCenter: center)
            try require(count == 2 && observed == nil, "unscoped auth gained authority")
        }
    }
#endif

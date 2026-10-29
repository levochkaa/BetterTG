// LoginChromeProbe.swift

#if DEBUG
import TDLibKit
import UIKit

/// The real login view with an isolated auth relay/client. No credential or account-store writes.
/// The fixture replaces the Accounts tap with a local callback before showing the controller.
@MainActor enum LoginChromeProbe {
    private final class Controller: UIViewController {
        private let relay = TDLibAuthorizationState()
        private let source = TdUpdateSource(accountID: UUID(), clientID: -1)
        private var hasOtherAccounts = true
        private var login: LoginViewController!
        private let status = UILabel()
        private let controls = UIStackView()

        private var formStage: String? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-login-probe-form"),
                  index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            let session = LoginAuthorizationSession(
                accountID: source.accountID,
                currentSource: { [weak self] in self?.relay.current?.source },
                client: { _ in .init { _ in } },
            )
            login = LoginViewController(
                authorization: session,
                updates: relay.publisher,
                hasOtherAccounts: { [weak self] in self?.hasOtherAccounts == true },
                serverSwitch: .init(
                    usesTestServer: { ProcessInfo.processInfo.arguments.contains("-login-probe-test-server") },
                    select: { _ in },
                ),
            )
            addChild(login)
            view.addSubview(login.view)
            login.didMove(toParent: self)
            func descendants(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(descendants) }
            let accounts = descendants(login.view).compactMap { $0 as? UIButton }.first {
                ($0.title(for: .normal) ?? $0.configuration?.title) == L10n.betterTG("Accounts.Section")
            }
            precondition(accounts != nil, "Fixture must intercept Accounts before display")
            accounts?.removeTarget(nil, action: nil, for: .allEvents)
            accounts?.addAction(
                UIAction { [weak self] _ in self?.status.text = "Accounts: local callback" },
                for: .touchUpInside,
            )
            controls.axis = .vertical
            controls.spacing = 4
            for actions: [(String, () -> Void)] in [
                [
                    ("Phone", { [weak self] in self?.show(.authorizationStateWaitPhoneNumber) }),
                    ("Code", { [weak self] in self?.showCode() }),
                    ("Password", { [weak self] in
                        self?.show(.authorizationStateWaitPassword(.init(
                            passwordHint: "Fixture hint",
                            hasRecoveryEmailAddress: false,
                            hasPassportData: false,
                            recoveryEmailAddressPattern: "",
                        )))
                    }),
                ],
                [
                    ("Other accounts", { [weak self] in
                        guard let self else { return }
                        hasOtherAccounts.toggle()
                        if let state = relay.current?.state { show(state) }
                    }),
                    ("Appearance", { [weak self] in
                        guard let self else { return }
                        overrideUserInterfaceStyle = traitCollection.userInterfaceStyle == .dark ? .light : .dark
                    }),
                    ("Inspect", { [weak self] in self?.inspect() }),
                ],
            ] {
                let row = UIStackView()
                row.axis = .horizontal
                row.distribution = .fillEqually
                for (title, action) in actions {
                    let button = UIButton(type: .system)
                    button.setTitle(title, for: .normal)
                    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
                    row.addArrangedSubview(button)
                }
                controls.addArrangedSubview(row)
            }
            view.addSubview(controls)
            status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            status.numberOfLines = 0
            view.addSubview(status)
            controls.isHidden = formStage != nil
            status.isHidden = formStage != nil
            if ProcessInfo.processInfo.arguments.contains("-login-probe-large-text") {
                traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            }
            switch formStage {
            case "phone": show(.authorizationStateWaitPhoneNumber)
            case "password":
                show(.authorizationStateWaitPassword(.init(
                    passwordHint: "Fixture hint",
                    hasRecoveryEmailAddress: false,
                    hasPassportData: false,
                    recoveryEmailAddressPattern: "",
                )))
            case "registration":
                show(.authorizationStateWaitRegistration(.init(termsOfService: .init(
                    text: .init(entities: [], text: "Fixture terms"),
                    minUserAge: 0,
                    showPopup: false,
                ))))
            case "qr": show(.authorizationStateWaitOtherDeviceConfirmation(.init(link: "tg://isolated")))
            default: showCode()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard formStage != nil, formStage != "qr" else { return }
            func descendants(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(descendants) }
            descendants(login.view).compactMap { $0 as? UITextField }.first?.becomeFirstResponder()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            login.view.frame = view.bounds
            controls.frame = CGRect(x: 16, y: view.safeAreaInsets.top + 70, width: view.bounds.width - 32, height: 66)
            status.frame = CGRect(x: 16, y: view.safeAreaInsets.top + 143, width: view.bounds.width - 32, height: 40)
        }

        private func show(_ state: AuthorizationState) {
            relay.activate(source)
            relay.update(state, source: source)
        }

        private func showCode() {
            show(.authorizationStateWaitCode(.init(codeInfo: .init(
                phoneNumber: "+1 202 555 0100",
                type: .authenticationCodeTypeTelegramMessage(.init(length: 5)),
                nextType: nil,
                timeout: 0,
            ))))
        }

        private func inspect() {
            login.view.endEditing(true)
            login.view.layoutIfNeeded()
            func descendants(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(descendants) }
            let glass = descendants(login.view)
.compactMap { $0 as? UIVisualEffectView }
                .filter { $0.effect is UIGlassEffect && !$0.isHidden && $0.window != nil }
            let buttons = descendants(login.view).compactMap { $0 as? UIButton }.filter { button in
                let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: login.view)
                return !button.isHidden && point.y < login.view.safeAreaInsets.top + 60
                    && login.view.hitTest(point, with: nil)?.isDescendant(of: button) == true
            }
            let inside = buttons.allSatisfy { button in
                glass
                    .contains {
                    button.isDescendant(of: $0.contentView) && ($0.effect as? UIGlassEffect)?.isInteractive == true
                    }
            }
            status.text = "bar buttons: \(buttons.count); live interactive glass: \(inside)\nheights: \(buttons.map { Int($0.bounds.height) }); requests: local only"
            log("Login chrome fixture: \(status.text ?? "")")
        }
    }

    static func runIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.arguments.contains("-ui-probe-login-chrome") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let controller = Controller()
            controller.modalPresentationStyle = .fullScreen
            window.rootViewController?.present(controller, animated: false)
        }
    }
}
#endif

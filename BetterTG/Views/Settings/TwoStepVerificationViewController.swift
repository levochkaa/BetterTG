// TwoStepVerificationViewController.swift

import UIKit

// MARK: - TwoStepVerificationViewController

/// TwoStepVerificationUnlockSettingsController. With a password it asks for it, under the hint, the help and Forgot
/// Password, or a pending reset's time and Cancel Reset; once the password checks out it manages it: Change Password,
/// Turn Password Off and the recovery email, with the email still waiting for its code. Without one it offers to set
/// it, or takes the code of the email a new password waits for, or aborts that setup. Telegram 13 opens the intro of
/// TwoFactorAuthSplashScreen instead for an account with neither; BetterTG has no splash and shows the Set Additional
/// Password row this screen keeps for that case.
final class TwoStepVerificationViewController: SettingsListViewController {
    // MARK: Internal

    /// TwoStepVerificationUnlockSettingsControllerData.
    enum Data: Equatable {
        /// The password's state, nil while it loads.
        case access(TwoStepVerificationConfiguration?)
        case manage(
            password: String,
            emailSet: Bool,
            pendingEmail: TwoStepVerificationConfiguration.PendingEmail?,
            hasPassportData: Bool,
        )
    }

    private(set) var data: Data

    // MARK: Private

    private let service: TwoStepVerificationService
    private var passwordText = ""
    private var emailCode = ""
    private var isChecking = false
    private var didFocus = false

    private var currentEmailSet: Bool {
        if case .manage(_, let emailSet, _, _) = data { return emailSet }
        return false
    }

    init(configuration: TwoStepVerificationConfiguration? = nil, service: TwoStepVerificationService? = nil) {
        self.data = .access(configuration)
        self.service = service ?? TDLibTwoStepVerificationService(client: TDLib.shared.activeClient)
        super.init()
    }

    init(data: Data, service: TwoStepVerificationService) {
        self.data = data
        self.service = service
        super.init()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateChrome()
        if case .access(nil) = data { loadConfiguration() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        focusFieldIfNeeded()
    }

    override func makeSections() -> [SettingsSection] {
        switch data {
        case .access(nil):
            return []
        case .access(let configuration?):
            if configuration.hasPassword { return passwordEntrySections(configuration) }
            if let pending = configuration.pendingEmail { return pendingEmailSections(pending) }
            return [SettingsSection(
                footer: L10n.telegram("TwoStepAuth.SetPasswordHelp"),
                rows: [SettingsRow(
                    title: L10n.telegram("TwoStepAuth.SetPassword"),
                    style: .action(destructive: false),
                ) {
                    [weak self] in self?.openSetup(.createPassword)
                }],
            )]
        case .manage(let password, let emailSet, let pendingEmail, let hasPassportData):
            var sections = [SettingsSection(
                footer: pendingEmail == nil ? L10n.telegram("TwoStepAuth.GenericHelp") : nil,
                rows: [
                    SettingsRow(
                        title: L10n.telegram("TwoStepAuth.ChangePassword"),
                        style: .action(destructive: false),
                    ) {
                        [weak self] in
                        self?.openSetup(.updatePassword(
                            current: password,
                            hasRecoveryEmail: emailSet,
                            hasPassportData: hasPassportData,
                        ))
                    },
                    SettingsRow(
                        title: L10n.telegram("TwoStepAuth.RemovePassword"),
                        style: .action(destructive: false),
                    ) {
                        [weak self] in self?.confirmDisable()
                    },
                    SettingsRow(
                        title: L10n.telegram(emailSet ? "TwoStepAuth.ChangeEmail" : "TwoStepAuth.SetupEmail"),
                        style: .action(destructive: false),
                    ) { [weak self] in
                        self?.openSetup(.addEmail(
                            hadRecoveryEmail: emailSet,
                            hasPassportData: hasPassportData,
                            password: password,
                        ))
                    },
                ],
            )]
            if let pendingEmail {
                sections.append(SettingsSection(
                    header: L10n.telegram("TwoStepAuth.EmailSent"),
                    rows: [SettingsRow(
                        title: L10n.telegram("TwoStepAuth.EnterEmailCode"),
                        style: .action(destructive: false),
                    ) {
                        [weak self] in
                        self?.openSetup(.confirmEmail(
                            password: password,
                            hasPassportData: hasPassportData,
                            pattern: pendingEmail.pattern,
                            codeLength: pendingEmail.codeLength,
                        ))
                    }],
                ))
            }
            return sections
        }
    }

    /// PrivacyAndSecurityController's openTwoStepVerification: TwoFactorAuthSplashScreen's intro for an account with
    /// no password and no email waiting for its code, this screen otherwise. The intro's button sets a password, and
    /// the settings then take the intro's place.
    static func entry(
        for configuration: TwoStepVerificationConfiguration?,
        service: TwoStepVerificationService,
    ) -> UIViewController {
        guard let configuration, !configuration.hasPassword, configuration.pendingEmail == nil else {
            return TwoStepVerificationViewController(configuration: configuration, service: service)
        }
        let intro = TwoStepVerificationIntroViewController()
        intro.onAction = { [weak intro] in
            guard let intro else { return }
            let setup = TwoStepVerificationSetupViewController(initial: .createPassword, service: service)
            setup.onUpdate = { [weak intro] outcome, _ in
                guard let intro, let navigation = intro.navigationController else { return }
                let data: Data
                switch outcome {
                case .noPassword:
                    return
                case .awaitingEmailConfirmation(_, let pattern, let codeLength):
                    var pending = configuration
                    pending.pendingEmail = .init(pattern: pattern, codeLength: codeLength)
                    data = .access(pending)
                case .passwordSet(let password?, let hasRecoveryEmail, let hasPassportData):
                    data = .manage(
                        password: password, emailSet: hasRecoveryEmail, pendingEmail: nil,
                        hasPassportData: hasPassportData,
                    )
                case .passwordSet(nil, _, _):
                    data = .access(nil)
                }
                let settings = TwoStepVerificationViewController(data: data, service: service)
                navigation.setViewControllers(
                    navigation.viewControllers.map { $0 === intro ? settings : $0 },
                    animated: false,
                )
                if case .manage = data {
                    TelegramUndoToast.show(
                        text: L10n.telegram("TwoStepAuth.EnabledSuccess").replacing("\n", with: " "),
                        in: navigation.view,
                        bottomInset: 12,
                        undo: nil,
                    )
                }
            }
            intro.present(TelegramNavigationController(rootViewController: setup), animated: true)
        }
        return intro
    }

    /// The password field, and under it the hint, then Forgot Password, or what a pending reset allows.
    private func passwordEntrySections(_ configuration: TwoStepVerificationConfiguration) -> [SettingsSection] {
        var text = ""
        if !configuration.hint.isEmpty {
            text += L10n.telegram("TwoStepAuth.EnterPasswordHint", configuration.hint.replacing("[", with: "("))
        }
        var links = [String: () -> Void]()
        if let resetDate = configuration.pendingResetDate {
            text += "\n\n"
            let remaining = resetDate - Int(Date().timeIntervalSince1970)
            if remaining <= 0 {
                text += "[" + L10n.telegram("TwoStepAuth.ResetAction") + "](reset)"
                links["reset"] = { [weak self] in self?.resetPassword() }
            } else {
                text += L10n.telegram(
                    "TwoStepAuth.ResetPendingText",
                    SettingsFormatting.timeInterval(seconds: remaining),
                )
                text += "\n[" + L10n.telegram("TwoStepAuth.CancelResetTitle") + "](declineReset)"
                links["declineReset"] = { [weak self] in self?.confirmDeclineReset() }
            }
        } else {
            text += "\n\n" + L10n.telegram("TwoStepAuth.EnterPasswordHelp")
            text += "\n\n[" + L10n.telegram("TwoStepAuth.EnterPasswordForgot") + "](forgot)"
            links["forgot"] = { [weak self] in self?.openForgotPassword() }
        }
        let input = SettingsTextInput(
            text: passwordText,
            placeholder: "",
            prefix: L10n.telegram("TwoStepAuth.EnterPasswordPassword"),
            autocapitalization: .none,
            autocorrection: false,
            isSecure: true,
            textContentType: .password,
            returnKeyType: .done,
            onChange: { [weak self] in self?.passwordText = $0 },
            onReturn: { [weak self] in self?.checkPassword() },
        )
        return [SettingsSection(
            footer: text.trimmingCharacters(in: .whitespacesAndNewlines),
            rows: [SettingsRow(title: "", style: .input(input))],
            footerLinks: links,
        )]
    }

    /// A new password whose email waits for its code: the code's field and Abort Two-Step Verification Setup.
    private func pendingEmailSections(_ pending: TwoStepVerificationConfiguration.PendingEmail) -> [SettingsSection] {
        let input = SettingsTextInput(
            text: emailCode,
            placeholder: L10n.telegram("TwoStepAuth.RecoveryCode"),
            autocapitalization: .none,
            autocorrection: false,
            keyboardType: .numberPad,
            textContentType: .oneTimeCode,
            onChange: { [weak self] value in self?.updateEmailCode(value, codeLength: pending.codeLength) },
        )
        return [SettingsSection(
            header: L10n.telegram("TwoStepAuth.SetupPendingEmail", pending.pattern),
            footer: "[" + L10n.telegram("TwoStepAuth.ConfirmationAbort") + "]()",
            rows: [SettingsRow(title: "", style: .input(input))],
            footerLinks: ["default": { [weak self] in self?.abortPendingSetup() }],
        )]
    }

    /// The title and the bar's Next, bold, or a spinner while a request runs or the state loads.
    private func updateChrome() {
        title =
            switch data {
            case .access:
                L10n.telegram("TwoStepAuth.Title")
            case .manage:
                L10n.telegram("PrivacySettings.TwoStepAuth")
            }
        let showsNext: Bool =
            switch data {
            case .access(let configuration?):
                configuration.hasPassword || configuration.pendingEmail != nil
            default:
                false
            }
        navigationItem.rightBarButtonItem = rightBarItem(showsNext: showsNext)
    }

    private func rightBarItem(showsNext: Bool) -> UIBarButtonItem? {
        if isChecking || data == .access(nil) {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            return UIBarButtonItem(customView: indicator)
        }
        guard showsNext else { return nil }
        return UIBarButtonItem(
            title: L10n.telegram("Common.Next"),
            style: .prominent,
            target: self,
            action: #selector(nextPressed),
        )
    }

    private func setData(_ data: Data) {
        self.data = data
        passwordText = ""
        emailCode = ""
        didFocus = false
        updateChrome()
        reload()
        focusFieldIfNeeded()
    }

    private func setChecking(_ checking: Bool) {
        isChecking = checking
        updateChrome()
    }

    /// Telegram focuses the password or code field as the screen shows.
    private func focusFieldIfNeeded() {
        guard !didFocus, view.window != nil, case .access(let configuration?) = data,
              configuration.hasPassword || configuration.pendingEmail != nil
        else { return }
        didFocus = true
        focusInput(at: IndexPath(row: 0, section: 0))
    }

    private func loadConfiguration() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let configuration = try await service.configuration()
                setData(.access(configuration))
            } catch {
                presentAlert(title: nil, message: TwoStepVerificationErrorText.message(for: error, context: .generic))
            }
        }
    }

    @objc private func nextPressed() {
        guard case .access(let configuration?) = data else { return }
        if configuration.hasPassword {
            checkPassword()
        } else if configuration.pendingEmail != nil {
            checkEmailCode()
        }
    }

    /// checkPassword: requestTwoStepVerifiationSettings with the password, then the settings it unlocks.
    private func checkPassword() {
        let password = passwordText
        guard !password.isEmpty, !isChecking, case .access(let configuration?) = data else { return }
        setChecking(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                let email = try await service.verify(password: password)
                let fresh = try await service.configuration()
                setChecking(false)
                view.endEditing(true)
                setData(.manage(
                    password: password,
                    emailSet: !email.isEmpty || fresh.hasRecoveryEmail,
                    pendingEmail: fresh.pendingEmail,
                    hasPassportData: configuration.hasPassportData || fresh.hasPassportData,
                ))
            } catch {
                setChecking(false)
                presentAlert(title: nil, message: TwoStepVerificationErrorText.message(for: error, context: .password))
            }
        }
    }

    /// updateEmailCode: a code of the expected length is checked at once.
    private func updateEmailCode(_ value: String, codeLength: Int?) {
        let previous = emailCode
        emailCode = value
        if let codeLength, previous.count != codeLength, value.count == codeLength { checkEmailCode() }
    }

    /// checkEmailConfirmation: the code confirms the email, and the new password is set.
    private func checkEmailCode() {
        let code = emailCode
        guard !code.isEmpty, !isChecking else { return }
        setChecking(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                let configuration = try await service.checkEmailCode(code)
                setChecking(false)
                setData(.access(configuration))
            } catch {
                setChecking(false)
                emailCode = ""
                reload()
                presentAlert(title: nil, message: TwoStepVerificationErrorText.message(for: error, context: .code))
            }
        }
    }

    /// openResetPendingEmail: the password that waits for its email is dropped.
    private func abortPendingSetup() {
        guard !isChecking else { return }
        setChecking(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                let configuration = try await service.cancelEmailVerification()
                setChecking(false)
                setData(.access(configuration))
            } catch {
                setChecking(false)
            }
        }
    }

    /// openForgotPassword: a code emailed to the recovery address, or without one the reset Telegram offers.
    private func openForgotPassword() {
        guard case .access(let configuration?) = data, !isChecking else { return }
        if configuration.hasRecoveryEmail {
            setChecking(true)
            Task { [weak self] in
                guard let self else { return }
                do {
                    let pattern = try await service.requestRecoveryCode()
                    setChecking(false)
                    openSetup(.recoverPassword(emailPattern: pattern))
                } catch {
                    setChecking(false)
                    presentAlert(title: nil, message: L10n.telegram("Login.UnknownError"))
                }
            }
        } else if let resetDate = configuration.pendingResetDate {
            if resetDate <= Int(Date().timeIntervalSince1970) { resetPassword() }
        } else {
            confirm(
                title: L10n.telegram("TwoStepAuth.RecoveryUnavailableResetTitle"),
                message: L10n.telegram("TwoStepAuth.RecoveryUnavailableResetText"),
                actionTitle: L10n.telegram("TwoStepAuth.RecoveryUnavailableResetAction"),
                isDestructive: false,
            ) { [weak self] in self?.resetPassword() }
        }
    }

    /// requestTwoStepPasswordReset: done resets at once; otherwise the screen shows when it can, or why not yet.
    private func resetPassword() {
        Task { [weak self] in
            guard let self else { return }
            do {
                switch try await service.resetPassword() {
                case .done:
                    navigationController?.popViewController(animated: true)
                case .waitingForReset:
                    try await setData(.access(service.configuration()))
                case .declined(let retryDate):
                    let remaining = retryDate - Int(Date().timeIntervalSince1970)
                    presentAlert(
                        title: nil,
                        message: remaining > 0
                            ? L10n.telegram(
                                "TwoFactorSetup.ResetFloodWait",
                                SettingsFormatting.timeInterval(seconds: remaining),
                            )
                            : L10n.telegram("TwoStepAuth.FloodError"),
                    )
                }
            } catch {
                presentAlert(title: nil, message: TwoStepVerificationErrorText.message(for: error, context: .generic))
            }
        }
    }

    /// declinePasswordReset: Cancel Reset, asked first, as a further reset takes another seven days.
    private func confirmDeclineReset() {
        let alert = UIAlertController(
            title: L10n.telegram("TwoStepAuth.CancelResetTitle"),
            message: L10n.telegram("TwoStepAuth.CancelResetText"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.No"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Yes"), style: .default) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                try? await service.cancelPasswordReset()
                if let configuration = try? await service.configuration() { setData(.access(configuration)) }
            }
        })
        present(alert, animated: true)
    }

    /// openDisablePassword: asked first, with Telegram Passport's warning when there is data in it.
    private func confirmDisable() {
        guard case .manage(let password, _, _, let hasPassportData) = data, !isChecking else { return }
        let message = L10n.telegram(hasPassportData
            ? "TwoStepAuth.PasswordRemovePassportConfirmation"
            : "TwoStepAuth.PasswordRemoveConfirmation")
        confirm(message: message, actionTitle: L10n.telegram("TwoStepAuth.Disable")) { [weak self] in
            guard let self else { return }
            setChecking(true)
            Task { [weak self] in
                guard let self else { return }
                do {
                    _ = try await service.setPassword(old: password, new: "", hint: "", email: nil)
                    setChecking(false)
                    showSuccess(L10n.telegram("TwoStepAuth.DisableSuccess"))
                    navigationController?.popViewController(animated: true)
                } catch {
                    setChecking(false)
                    presentAlert(
                        title: nil,
                        message: TwoStepVerificationErrorText.message(for: error, context: .generic),
                    )
                }
            }
        }
    }

    /// SetupTwoStepVerificationController as a sheet; its outcomes move this screen on as Telegram's stateUpdated does.
    private func openSetup(_ initial: TwoStepVerificationSetupViewController.Initial) {
        let setup = TwoStepVerificationSetupViewController(initial: initial, service: service)
        setup.onUpdate = { [weak self] outcome, _ in self?.apply(outcome, from: initial) }
        present(TelegramNavigationController(rootViewController: setup), animated: true)
    }

    private func apply(
        _ outcome: TwoStepVerificationSetupViewController.Outcome,
        from initial: TwoStepVerificationSetupViewController.Initial,
    ) {
        switch outcome {
        case .noPassword:
            setData(.access(TwoStepVerificationConfiguration(
                hasPassword: false, hint: "", hasRecoveryEmail: false, hasPassportData: false,
            )))
        case .awaitingEmailConfirmation(let password, let pattern, let codeLength):
            let pending = TwoStepVerificationConfiguration.PendingEmail(pattern: pattern, codeLength: codeLength)
            switch initial {
            case .createPassword:
                setData(.access(TwoStepVerificationConfiguration(
                    hasPassword: false, hint: "", hasRecoveryEmail: false, hasPassportData: false,
                    pendingEmail: pending,
                )))
            case .addEmail(let hadRecoveryEmail, let hasPassportData, _):
                setData(.manage(
                    password: password,
                    emailSet: hadRecoveryEmail,
                    pendingEmail: pending,
                    hasPassportData: hasPassportData,
                ))
            case .confirmEmail(_, let hasPassportData, _, _):
                setData(.manage(
                    password: password,
                    emailSet: currentEmailSet,
                    pendingEmail: pending,
                    hasPassportData: hasPassportData,
                ))
            case .updatePassword(_, let hasRecoveryEmail, let hasPassportData):
                setData(.manage(
                    password: password,
                    emailSet: hasRecoveryEmail,
                    pendingEmail: pending,
                    hasPassportData: hasPassportData,
                ))
            case .recoverPassword:
                loadAfterChange()
            }
        case .passwordSet(let password, let hasRecoveryEmail, let hasPassportData):
            let success: String? =
                switch initial {
                case .createPassword: L10n.telegram("TwoStepAuth.EnabledSuccess")
                case .updatePassword: L10n.telegram("TwoStepAuth.PasswordChangeSuccess")
                case .addEmail(let hadRecoveryEmail, _, _):
                    L10n.telegram(hadRecoveryEmail ? "TwoStepAuth.EmailChangeSuccess" : "TwoStepAuth.EmailAddSuccess")
                case .confirmEmail:
                    L10n.telegram(currentEmailSet ? "TwoStepAuth.EmailChangeSuccess" : "TwoStepAuth.EmailAddSuccess")
                case .recoverPassword: nil
                }
            if let password {
                setData(.manage(
                    password: password,
                    emailSet: hasRecoveryEmail,
                    pendingEmail: nil,
                    hasPassportData: hasPassportData,
                ))
            } else {
                loadAfterChange()
            }
            if let success { showSuccess(success) }
        }
    }

    private func loadAfterChange() {
        setData(.access(nil))
        loadConfiguration()
    }

    /// OverlayStatusController's `.genericSuccess`, as BetterTG's toast.
    private func showSuccess(_ text: String) {
        let host = navigationController?.view ?? view!
        TelegramUndoToast.show(text: text.replacing("\n", with: " "), in: host, bottomInset: 12, undo: nil)
    }
}

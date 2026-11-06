// TwoStepVerificationSetupViewController.swift

import TDLibKit
import UIKit

// MARK: - TwoStepVerificationSetupViewController

/// SetupTwoStepVerificationController (PasswordSetupUI): one field at a time under a light 30 pt title and a 16 pt
/// description, with Cancel and Next in the bar. Creating a password asks for it twice, then for an optional hint and
/// an optional recovery email, which is confirmed with the code sent to it; changing it skips the email; adding an
/// email asks for it and its code. BetterTG also recovers a forgotten password here: the code TDLib emails, then the
/// new password and its hint, which Telegram does in TwoFactorDataInputScreen's recovery mode.
final class TwoStepVerificationSetupViewController: UIViewController, UITextFieldDelegate {
    // MARK: Internal

    enum Initial {
        case createPassword
        case updatePassword(current: String, hasRecoveryEmail: Bool, hasPassportData: Bool)
        case addEmail(hadRecoveryEmail: Bool, hasPassportData: Bool, password: String)
        case confirmEmail(password: String?, hasPassportData: Bool, pattern: String, codeLength: Int?)
        case recoverPassword(emailPattern: String)
    }

    /// SetupTwoStepVerificationStateUpdate.
    enum Outcome: Equatable {
        case noPassword
        case awaitingEmailConfirmation(password: String, pattern: String, codeLength: Int?)
        case passwordSet(password: String?, hasRecoveryEmail: Bool, hasPassportData: Bool)
    }

    // MARK: Private

    private enum PasswordMode {
        case create
        case update(current: String, hasRecoveryEmail: Bool, hasPassportData: Bool)
        case recover(code: String)
    }

    private enum EmailMode {
        case create(password: String, hint: String)
        case add(hadRecoveryEmail: Bool, hasPassportData: Bool, password: String)
    }

    private enum ConfirmMode {
        case create(password: String, hint: String, email: String)
        case add(password: String, hadRecoveryEmail: Bool, hasPassportData: Bool, email: String)
        case confirm(password: String?, hasPassportData: Bool, pattern: String)
    }

    private enum Step {
        case enterPassword(PasswordMode)
        case confirmPassword(PasswordMode, password: String)
        case enterHint(PasswordMode, password: String)
        case enterEmail(EmailMode)
        case confirmEmail(ConfirmMode, pattern: String, codeLength: Int?)
        case recoveryCode(emailPattern: String)
    }

    /// The outcome and whether the form is done and goes away.
    var onUpdate: ((Outcome, Bool) -> Void)?

    private let service: TwoStepVerificationService
    private var step: Step
    private var isBusy = false
    private let contentView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textField = UITextField()
    private let separator = UIView()
    private let leftActionButton = UIButton(type: .system)
    private let rightActionButton = UIButton(type: .system)
    private var leftAction: (() -> Void)?
    private var rightAction: (() -> Void)?
    private var keyboardHeight = CGFloat.zero

    init(initial: Initial, service: TwoStepVerificationService) {
        self.service = service
        self.step =
            switch initial {
            case .createPassword:
                .enterPassword(.create)
            case .updatePassword(let current, let hasRecoveryEmail, let hasPassportData):
                .enterPassword(.update(
                    current: current,
                    hasRecoveryEmail: hasRecoveryEmail,
                    hasPassportData: hasPassportData,
                ))
            case .addEmail(let hadRecoveryEmail, let hasPassportData, let password):
                .enterEmail(.add(
                    hadRecoveryEmail: hadRecoveryEmail,
                    hasPassportData: hasPassportData,
                    password: password,
                ))
            case .confirmEmail(let password, let hasPassportData, let pattern, let codeLength):
                .confirmEmail(
                    .confirm(password: password, hasPassportData: hasPassportData, pattern: pattern),
                    pattern: pattern,
                    codeLength: codeLength,
                )
            case .recoverPassword(let emailPattern):
                .recoveryCode(emailPattern: emailPattern)
            }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.telegram("Common.Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelPressed),
        )
        titleLabel.font = .systemFont(ofSize: 30, weight: .light)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        subtitleLabel.font = .systemFont(ofSize: 16)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        textField.font = .systemFont(ofSize: 22)
        textField.delegate = self
        textField.returnKeyType = .next
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        separator.backgroundColor = .separator
        for button in [leftActionButton, rightActionButton] {
            button.titleLabel?.font = .systemFont(ofSize: 16)
            button.addTarget(self, action: #selector(actionPressed(_:)), for: .touchUpInside)
        }
        for subview in [titleLabel, subtitleLabel, textField, separator, leftActionButton, rightActionButton] {
            contentView.addSubview(subview)
        }
        view.addSubview(contentView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
        )
        apply(step, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textField.becomeFirstResponder()
    }

    /// SetupTwoStepVerificationContentNode.updateLayout: the texts centred 20 pt in, the 44 pt field at most 300 pt
    /// wide and 37 pt in, with a hairline under it, the block centred in what the keyboard leaves and at most 215 pt
    /// tall, and the actions 16 pt from the sides in a 56 pt row above the keyboard.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        contentView.frame = view.bounds
        let size = view.bounds.size
        let bandMinX = view.safeAreaInsets.left
        let bandWidth = size.width - view.safeAreaInsets.left - view.safeAreaInsets.right
        let top = view.safeAreaInsets.top
        let bottom = max(keyboardHeight, view.safeAreaInsets.bottom)
        let textWidth = bandWidth - 40
        let titleSize = titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        let subtitleSize = subtitleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        let spacing: CGFloat = 12
        let inputHeight: CGFloat = 44
        let inputWidth = min(300, bandWidth - 74)
        let minimumHeight = titleSize.height + spacing + subtitleSize.height + inputHeight
        let contentHeight = min(215, max(size.height - top - bottom - 40, minimumHeight))
        let origin = max(56, top + floor((size.height - top - bottom - contentHeight) / 2))
        titleLabel.frame = CGRect(
            x: bandMinX + floor((bandWidth - titleSize.width) / 2),
            y: origin,
            width: titleSize.width,
            height: titleSize.height,
        )
        subtitleLabel.frame = CGRect(
            x: bandMinX + floor((bandWidth - subtitleSize.width) / 2),
            y: titleLabel.frame.maxY + spacing,
            width: subtitleSize.width,
            height: subtitleSize.height,
        )
        let pixel = 1 / max(1, traitCollection.displayScale)
        textField.frame = CGRect(
            x: bandMinX + floor((bandWidth - inputWidth) / 2),
            y: origin + contentHeight - inputHeight,
            width: inputWidth,
            height: inputHeight,
        )
        separator.frame = CGRect(
            x: textField.frame.minX,
            y: textField.frame.maxY - pixel,
            width: inputWidth,
            height: pixel,
        )
        let buttonsHeight: CGFloat = 56
        for (button, isLeft) in [(leftActionButton, true), (rightActionButton, false)] {
            let buttonSize = button.sizeThatFits(CGSize(width: bandWidth - 40, height: .greatestFiniteMagnitude))
            button.frame = CGRect(
                x: isLeft ? bandMinX + 16 : bandMinX + bandWidth - 16 - buttonSize.width,
                y: size.height - bottom - buttonsHeight + floor((buttonsHeight - buttonSize.height) / 2),
                width: buttonSize.width,
                height: buttonSize.height,
            )
        }
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        nextPressed()
        return false
    }

    /// SetupTwoStepVerificationContentNode's texts, field and actions for a step, cross-faded on a change.
    private func apply(_ step: Step, animated: Bool) {
        self.step = step
        leftAction = nil
        rightAction = nil
        let title: String
        let subtitle: String
        let placeholder: String
        var isSecure = false
        var keyboardType = UIKeyboardType.default
        var contentType: UITextContentType?
        switch step {
        case .enterPassword(let mode):
            switch mode {
            case .create,
                 .recover:
                title = L10n.telegram("TwoStepAuth.SetupPasswordTitle")
                subtitle = L10n.telegram("TwoStepAuth.SetupPasswordDescription")
            case .update:
                title = L10n.telegram("TwoStepAuth.ChangePassword")
                subtitle = L10n.telegram("TwoStepAuth.ChangePasswordDescription")
            }
            placeholder = L10n.telegram("LoginPassword.PasswordPlaceholder")
            isSecure = true
            contentType = .newPassword
        case .confirmPassword:
            title = L10n.telegram("TwoStepAuth.ReEnterPasswordTitle")
            subtitle = L10n.telegram("TwoStepAuth.ReEnterPasswordDescription")
            placeholder = L10n.telegram("LoginPassword.PasswordPlaceholder")
            isSecure = true
            contentType = .newPassword
        case .enterHint:
            title = L10n.telegram("TwoStepAuth.AddHintTitle")
            subtitle = L10n.telegram("TwoStepAuth.AddHintDescription")
            placeholder = L10n.telegram("TwoStepAuth.HintPlaceholder")
        case .enterEmail(let mode):
            title = L10n.telegram("TwoStepAuth.RecoveryEmailTitle")
            if case .add(true, _, _) = mode {
                subtitle = L10n.telegram("TwoStepAuth.RecoveryEmailChangeDescription")
            } else {
                subtitle = L10n.telegram("TwoStepAuth.RecoveryEmailAddDescription")
            }
            placeholder = L10n.telegram("TwoStepAuth.EmailPlaceholder")
            keyboardType = .emailAddress
            contentType = .emailAddress
        case .confirmEmail(let mode, let pattern, _):
            title = L10n.telegram("TwoStepAuth.RecoveryEmailTitle")
            let shown: String =
                switch mode {
                case .add(_, _, _, let email),
                     .create(_, _, let email): email
                case .confirm: pattern
                }
            subtitle = L10n.telegram("TwoStepAuth.ConfirmEmailDescription", shown)
            placeholder = L10n.telegram("TwoStepAuth.ConfirmEmailCodePlaceholder")
            isSecure = true
            keyboardType = .asciiCapableNumberPad
            contentType = .oneTimeCode
            switch mode {
            case .create(let password, let hint, _):
                leftAction = { [weak self] in self?.changePendingEmail(password: password, hint: hint) }
            case .add(let password, let hadRecoveryEmail, let hasPassportData, _):
                leftAction = { [weak self] in
                    self?.apply(
                        .enterEmail(.add(
                            hadRecoveryEmail: hadRecoveryEmail,
                            hasPassportData: hasPassportData,
                            password: password,
                        )),
                        animated: true,
                    )
                }
            case .confirm:
                break
            }
            rightAction = { [weak self] in self?.resendCode() }
        case .recoveryCode:
            title = L10n.telegram("TwoStepAuth.RecoveryTitle")
            subtitle = L10n.telegram("TwoStepAuth.RecoveryCodeHelp")
            placeholder = L10n.telegram("TwoStepAuth.RecoveryCode")
            keyboardType = .asciiCapableNumberPad
            contentType = .oneTimeCode
        }
        let update = { [self] in
            titleLabel.text = title
            subtitleLabel.text = subtitle
            textField.text = ""
            textField.isSecureTextEntry = isSecure
            textField.keyboardType = keyboardType
            textField.textContentType = contentType
            textField.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [
                .font: UIFont.systemFont(ofSize: 22),
                .foregroundColor: UIColor.placeholderText,
            ])
            textField.reloadInputViews()
            leftActionButton.setTitle(L10n.telegram("TwoStepAuth.ChangeEmail"), for: .normal)
            leftActionButton.isHidden = leftAction == nil
            rightActionButton.setTitle(L10n.telegram("TwoStepAuth.ConfirmEmailResendCode"), for: .normal)
            rightActionButton.isHidden = rightAction == nil
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
        if animated, !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(
                with: contentView,
                duration: 0.25,
                options: [.transitionCrossDissolve],
                animations: update,
            )
        } else {
            update()
        }
        updateNextButton()
    }

    /// SetupTwoStepVerificationNextAction: Next, or Skip for an empty hint or email when creating, disabled while the
    /// field it needs is empty, and a spinner while a request runs.
    private func updateNextButton() {
        guard !isBusy else {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
            leftActionButton.isEnabled = false
            rightActionButton.isEnabled = false
            return
        }
        leftActionButton.isEnabled = true
        rightActionButton.isEnabled = true
        let text = textField.text ?? ""
        let title: String
        let isEnabled: Bool
        switch step {
        case .enterHint:
            title = L10n.telegram(text.isEmpty ? "TwoStepAuth.EmailSkip" : "Common.Next")
            isEnabled = true
        case .enterEmail(.create):
            title = L10n.telegram(text.isEmpty ? "TwoStepAuth.EmailSkip" : "Common.Next")
            isEnabled = true
        default:
            title = L10n.telegram("Common.Next")
            isEnabled = !text.isEmpty
        }
        let item = UIBarButtonItem(title: title, style: .prominent, target: self, action: #selector(nextPressed))
        item.isEnabled = isEnabled
        navigationItem.rightBarButtonItem = item
    }

    @objc private func textChanged() {
        updateNextButton()
        // The code is checked as soon as it has the length TDLib named.
        if case .confirmEmail(_, _, let codeLength?) = step, (textField.text ?? "").count == codeLength {
            nextPressed()
        }
    }

    @objc private func cancelPressed() {
        dismiss(animated: true)
    }

    @objc private func actionPressed(_ sender: UIButton) {
        guard !isBusy else { return }
        (sender === leftActionButton ? leftAction : rightAction)?()
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let local = view.convert(frame, from: nil)
        keyboardHeight = max(0, view.bounds.maxY - local.minY)
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    // MARK: Steps

    @objc private func nextPressed() {
        guard !isBusy else { return }
        let text = textField.text ?? ""
        switch step {
        case .enterPassword(let mode):
            guard !text.isEmpty else { return }
            apply(.confirmPassword(mode, password: text), animated: true)
        case .confirmPassword(let mode, let password):
            guard !text.isEmpty else { return }
            guard text == password else {
                presentAlert(L10n.telegram("TwoStepAuth.SetupPasswordConfirmFailed"))
                return
            }
            apply(.enterHint(mode, password: password), animated: true)
        case .enterHint(let mode, let password):
            switch mode {
            case .create:
                apply(.enterEmail(.create(password: password, hint: text)), animated: true)
            case .update(let current, let hasRecoveryEmail, let hasPassportData):
                run(context: .generic) { [self] in
                    let state = try await service.setPassword(old: current, new: password, hint: text, email: nil)
                    if let pending = state.pendingEmail {
                        finish(
                            .awaitingEmailConfirmation(
                                password: password,
                                pattern: pending.pattern,
                                codeLength: pending.codeLength,
                            ),
                            dismisses: true,
                        )
                    } else {
                        finish(
                            .passwordSet(
                                password: password,
                                hasRecoveryEmail: hasRecoveryEmail,
                                hasPassportData: hasPassportData,
                            ),
                            dismisses: true,
                        )
                    }
                }
            case .recover(let code):
                run(context: .recoveryCode) { [self] in
                    let state = try await service.recoverPassword(code: code, new: password, hint: text)
                    finish(
                        .passwordSet(
                            password: password,
                            hasRecoveryEmail: state.hasRecoveryEmail,
                            hasPassportData: state.hasPassportData,
                        ),
                        dismisses: true,
                    )
                }
            }
        case .enterEmail(let mode):
            switch mode {
            case .create(let password, let hint):
                let create = { [self] in
                    run(context: .email, onError: { [weak self] error in
                        if (error as? TDLibError)?.message == "EMAIL_INVALID" {
                            self?.apply(.enterEmail(.create(password: password, hint: hint)), animated: false)
                        }
                    }) { [self] in
                        let state = try await service.setPassword(
                            old: "",
                            new: password,
                            hint: hint,
                            email: text.isEmpty ? nil : text,
                        )
                        if let pending = state.pendingEmail {
                            apply(
                                .confirmEmail(
                                    .create(password: password, hint: hint, email: text),
                                    pattern: pending.pattern,
                                    codeLength: pending.codeLength,
                                ),
                                animated: true,
                            )
                            onUpdate?(
                                .awaitingEmailConfirmation(
                                    password: password,
                                    pattern: pending.pattern,
                                    codeLength: pending.codeLength,
                                ),
                                false,
                            )
                        } else {
                            finish(
                                .passwordSet(password: password, hasRecoveryEmail: false, hasPassportData: false),
                                dismisses: true,
                            )
                        }
                    }
                }
                if text.isEmpty {
                    // Skipping the email asks once more, as Telegram's EmailSkipAlert does.
                    let alert = UIAlertController(
                        title: nil,
                        message: L10n.telegram("TwoStepAuth.EmailSkipAlert"),
                        preferredStyle: .alert,
                    )
                    alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
                    alert.addAction(UIAlertAction(title: L10n.telegram("TwoStepAuth.EmailSkip"), style: .destructive) {
                        _ in create()
                    })
                    present(alert, animated: true)
                } else {
                    create()
                }
            case .add(let hadRecoveryEmail, let hasPassportData, let password):
                guard !text.isEmpty else { return }
                run(context: .email) { [self] in
                    let state = try await service.setRecoveryEmail(password: password, email: text)
                    if let pending = state.pendingEmail {
                        apply(
                            .confirmEmail(
                                .add(
                                    password: password,
                                    hadRecoveryEmail: hadRecoveryEmail,
                                    hasPassportData: hasPassportData,
                                    email: text,
                                ),
                                pattern: pending.pattern,
                                codeLength: pending.codeLength,
                            ),
                            animated: true,
                        )
                        onUpdate?(
                            .awaitingEmailConfirmation(
                                password: password,
                                pattern: pending.pattern,
                                codeLength: pending.codeLength,
                            ),
                            false,
                        )
                    } else {
                        finish(
                            .passwordSet(password: password, hasRecoveryEmail: true, hasPassportData: hasPassportData),
                            dismisses: true,
                        )
                    }
                }
            }
        case .confirmEmail(let mode, _, _):
            guard !text.isEmpty else { return }
            run(context: .code) { [self] in
                _ = try await service.checkEmailCode(text)
                switch mode {
                case .create(let password, _, _):
                    finish(
                        .passwordSet(password: password, hasRecoveryEmail: true, hasPassportData: false),
                        dismisses: true,
                    )
                case .add(let password, _, let hasPassportData, let email):
                    finish(
                        .passwordSet(
                            password: password,
                            hasRecoveryEmail: !email.isEmpty,
                            hasPassportData: hasPassportData,
                        ),
                        dismisses: true,
                    )
                case .confirm(let password, let hasPassportData, _):
                    finish(
                        .passwordSet(password: password, hasRecoveryEmail: true, hasPassportData: hasPassportData),
                        dismisses: true,
                    )
                }
            }
        case .recoveryCode:
            guard !text.isEmpty else { return }
            run(context: .recoveryCode) { [self] in
                try await service.checkRecoveryCode(text)
                apply(.enterPassword(.recover(code: text)), animated: true)
            }
        }
    }

    /// Change E-Mail while a new password waits for its email: the password goes, and the email is asked again.
    private func changePendingEmail(password: String, hint: String) {
        run(context: .generic) { [self] in
            _ = try await service.cancelEmailVerification()
            apply(.enterEmail(.create(password: password, hint: hint)), animated: true)
            onUpdate?(.noPassword, false)
        }
    }

    /// resendTwoStepRecoveryEmail.
    private func resendCode() {
        run(context: .code) { [self] in
            _ = try await service.resendEmailCode()
        }
    }

    private func finish(_ outcome: Outcome, dismisses: Bool) {
        view.endEditing(true)
        onUpdate?(outcome, dismisses)
        if dismisses { dismiss(animated: true) }
    }

    /// Runs a request with the spinner in the bar; a failure shows Telegram's text for it and keeps the step.
    private func run(
        context: TwoStepVerificationErrorText.Context,
        onError: ((Error) -> Void)? = nil,
        _ request: @escaping @MainActor () async throws -> Void,
    ) {
        guard !isBusy else { return }
        isBusy = true
        updateNextButton()
        Task { [weak self] in
            do {
                try await request()
                guard let self else { return }
                isBusy = false
                updateNextButton()
            } catch {
                guard let self else { return }
                isBusy = false
                updateNextButton()
                onError?(error)
                presentAlert(TwoStepVerificationErrorText.message(for: error, context: context))
            }
        }
    }

    private func presentAlert(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }
}

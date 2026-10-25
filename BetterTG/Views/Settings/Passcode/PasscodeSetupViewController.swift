// PasscodeSetupViewController.swift

import UIKit

// MARK: - PasscodeSetupViewController

/// PasscodeSetupController: a new passcode entered twice (with Passcode Options for a 6-digit, 4-digit or
/// alphanumeric code on the first step), a changed one the same way, or the current one entered to open the settings
/// or turn the passcode off. Digits fill PasscodeInputFieldNode's dots from the number pad; a password goes in a
/// field with Next. Mismatched entries start over with "Passcodes don't match. Please try again."
final class PasscodeSetupViewController: UIViewController, UITextFieldDelegate {
    enum Mode {
        case create
        case change
        /// The current passcode authorizes something; the closure runs once it is right.
        case verify(() -> Void)
    }

    private let mode: Mode
    private var onFinish: (() -> Void)?
    private var kind: AppPasscode.Kind
    private var firstEntry: String?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let dotsView = PasscodeDotsView()
    private let textField = UITextField()
    private let fieldBackground = UIView()
    private let optionsButton = UIButton(type: .system)
    private var subtitleBelowDots: NSLayoutConstraint?
    private var subtitleBelowField: NSLayoutConstraint?

    private var isVerifying: Bool {
        if case .verify = mode {
            true
        } else {
            false
        }
    }

    init(mode: Mode, onFinish: (() -> Void)? = nil) {
        self.mode = mode
        self.onFinish = onFinish
        self.kind =
            if case .verify = mode {
                AppPasscode.shared.kind
            } else {
                .sixDigits
            }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("PasscodeSettings.Title")
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground

        titleLabel.font = .systemFont(ofSize: 17)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        subtitleLabel.font = .systemFont(ofSize: 16)
        subtitleLabel.textColor = .label
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        dotsView.color = .label

        fieldBackground.backgroundColor = .secondarySystemGroupedBackground
        fieldBackground.layer.cornerRadius = 12
        fieldBackground.layer.cornerCurve = .continuous
        textField.font = .systemFont(ofSize: 17)
        textField.isSecureTextEntry = true
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.delegate = self
        textField.addAction(UIAction { [weak self] _ in self?.textChanged() }, for: .editingChanged)

        optionsButton.setTitle(L10n.telegram("PasscodeSettings.PasscodeOptions"), for: .normal)
        optionsButton.titleLabel?.font = .systemFont(ofSize: 17)
        optionsButton.addAction(UIAction { [weak self] _ in self?.presentKindMenu() }, for: .touchUpInside)

        for subview in [titleLabel, subtitleLabel, dotsView, fieldBackground, textField, optionsButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        // The field sits in the middle of the room the keyboard leaves, Passcode Options 9 pt above the keyboard.
        let content = UILayoutGuide()
        view.addLayoutGuide(content)
        subtitleBelowDots = subtitleLabel.topAnchor.constraint(equalTo: dotsView.bottomAnchor, constant: 20)
        subtitleBelowField = subtitleLabel.topAnchor.constraint(equalTo: fieldBackground.bottomAnchor, constant: 20)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            dotsView.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -10),
            dotsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dotsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dotsView.heightAnchor.constraint(equalToConstant: 13),
            fieldBackground.centerYAnchor.constraint(equalTo: dotsView.centerYAnchor),
            fieldBackground.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            fieldBackground.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            fieldBackground.heightAnchor.constraint(equalToConstant: 52),
            textField.leadingAnchor.constraint(equalTo: fieldBackground.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: fieldBackground.trailingAnchor, constant: -16),
            textField.centerYAnchor.constraint(equalTo: fieldBackground.centerYAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: fieldBackground.topAnchor, constant: -16),
            titleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            optionsButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -9),
            optionsButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            optionsButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        applyKind()
        resetToFirstStep(subtitle: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textField.becomeFirstResponder()
    }

    // MARK: UITextFieldDelegate

    func textField(_: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let digits = kind.digitCount else { return true }
        let current = textField.text ?? ""
        guard let swiftRange = Range(range, in: current) else { return false }
        let updated = current.replacingCharacters(in: swiftRange, with: string)
        return updated.count <= digits && updated.allSatisfy(\.isNumber)
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        submit()
        return false
    }

    // MARK: Private

    private func applyKind() {
        let digits = kind.digitCount
        dotsView.count = digits ?? 0
        dotsView.isHidden = digits == nil
        fieldBackground.isHidden = digits != nil
        textField.alpha = digits == nil ? 1 : 0
        textField.keyboardType = digits == nil ? .default : .numberPad
        textField.returnKeyType = .next
        navigationItem.rightBarButtonItem = digits == nil
            ? UIBarButtonItem(
                title: L10n.telegram("Common.Next"),
                style: .prominent,
                target: self,
                action: #selector(nextTapped),
            )
            : nil
        textField.reloadInputViews()
        subtitleBelowDots?.isActive = digits != nil
        subtitleBelowField?.isActive = digits == nil
    }

    private func resetToFirstStep(subtitle: String?) {
        firstEntry = nil
        textField.text = ""
        dotsView.filled = 0
        titleLabel.text =
            switch mode {
            case .create: L10n.telegram("EnterPasscode.EnterNewPasscodeNew")
            case .change: L10n.telegram("EnterPasscode.EnterNewPasscodeChange")
            case .verify: L10n.telegram("EnterPasscode.EnterPasscode")
            }
        subtitleLabel.text = subtitle
        optionsButton.isHidden = isVerifying
    }

    private func textChanged() {
        let text = textField.text ?? ""
        dotsView.filled = text.count
        guard let digits = kind.digitCount, text.count == digits else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.submit() }
    }

    @objc private func nextTapped() {
        submit()
    }

    private func submit() {
        let entry = textField.text ?? ""
        guard !entry.isEmpty else { return }
        if case .verify(let completion) = mode {
            guard AppPasscode.shared.blockedUntil == nil else {
                subtitleLabel.text = L10n.telegram("PasscodeSettings.TryAgainIn1Minute")
                return
            }
            if AppPasscode.shared.verify(entry) {
                AppPasscode.shared.resetFailedAttempts()
                completion()
            } else {
                AppPasscode.shared.recordFailedAttempt()
                textField.text = ""
                dotsView.filled = 0
                shake()
                subtitleLabel.text = AppPasscode.shared.blockedUntil != nil
                    ? L10n.telegram("PasscodeSettings.TryAgainIn1Minute")
                    : L10n.telegramPlural("PasscodeSettings.FailedAttempts", count: AppPasscode.shared.failedAttempts)
            }
            return
        }
        guard let first = firstEntry else {
            firstEntry = entry
            textField.text = ""
            dotsView.filled = 0
            titleLabel.text = L10n.telegram("EnterPasscode.RepeatNewPasscode")
            subtitleLabel.text = nil
            optionsButton.isHidden = true
            return
        }
        guard first == entry else {
            shake()
            resetToFirstStep(subtitle: L10n.telegram("PasscodeSettings.DoNotMatch"))
            return
        }
        AppPasscode.shared.setPasscode(entry, kind: kind)
        textField.resignFirstResponder()
        onFinish?()
    }

    /// selectPasscodeMode: 6-digit, 4-digit or alphanumeric, the current one checked.
    private func presentKindMenu() {
        let options: [(AppPasscode.Kind, String)] = [
            (.sixDigits, L10n.telegram("PasscodeSettings.6DigitCode")),
            (.fourDigits, L10n.telegram("PasscodeSettings.4DigitCode")),
            (.alphanumeric, L10n.telegram("PasscodeSettings.AlphanumericCode")),
        ]
        let actions = options.map { kind, title in
            TelegramContextMenuAction(
                title: title,
                image: kind == self.kind ? UIImage(systemName: "checkmark") : nil,
            ) { [weak self] in
                guard let self, self.kind != kind else { return }
                self.kind = kind
                applyKind()
                resetToFirstStep(subtitle: nil)
            }
        }
        presentTelegramContextMenu(sourceView: optionsButton, actions: actions, presentationStyle: .menuOnly)
    }

    private func shake() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -14, 14, -10, 10, -5, 5, 0]
        animation.duration = 0.4
        (kind.digitCount == nil ? fieldBackground.layer : dotsView.layer).add(animation, forKey: "shake")
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

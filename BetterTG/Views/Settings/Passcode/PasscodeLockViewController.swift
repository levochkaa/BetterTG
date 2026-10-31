// PasscodeLockViewController.swift

import LocalAuthentication
import UIKit

// MARK: - PasscodeLockViewController

/// PasscodeEntryController over the locked app: the lock icon, "Enter your Telegram Passcode", the dots (or a
/// field for a password), and PasscodeEntryKeyboardNode's round digit keys with their letters, Delete, and Face ID
/// under them, which is also asked for as the screen appears. A wrong passcode shakes the dots and counts the failed
/// attempts; every fifth blocks entry for a minute. Telegram's iPhone layout: the title 162 pt down, the dots at
/// 206 pt, 75 pt keys from 294 pt, 103 pt and 91 pt apart.
final class PasscodeLockViewController: UIViewController, UITextFieldDelegate {
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    private let onUnlock: () -> Void
    private let passcode = AppPasscode.shared

    private let gradient = CAGradientLayer()
    private let lockIcon = UIImageView(image: UIImage(
        systemName: "lock.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .regular),
    ))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let dotsView = PasscodeDotsView()
    private let textField = UITextField()
    private var keys = [PasscodeKeyButton]()
    private let deleteButton = UIButton(type: .system)
    private let biometricButton = UIButton(type: .system)
    private var entered = ""
    private var blockTimer: Timer?
    private var didAskBiometrics = false

    private var digitCount: Int? {
        passcode.kind.digitCount
    }

    // MARK: Private

    private var canUseBiometrics: Bool {
        passcode.usesBiometrics && LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    init(onUnlock: @escaping () -> Void) {
        self.onUnlock = onUnlock
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        blockTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer.addSublayer(gradient)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.updateBackground() }

        lockIcon.tintColor = .white
        lockIcon.contentMode = .center
        titleLabel.text = L10n.telegram("EnterPasscode.EnterPasscode")
        titleLabel.font = .systemFont(ofSize: 20)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .white
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        dotsView.count = digitCount ?? 0
        dotsView.isHidden = digitCount == nil

        textField.isSecureTextEntry = true
        textField.textColor = .white
        textField.tintColor = .white
        textField.font = .systemFont(ofSize: 17)
        textField.keyboardAppearance = .dark
        textField.returnKeyType = .done
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.delegate = self
        textField.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        textField.layer.borderWidth = 1
        textField.layer.cornerRadius = 10
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 13, height: 1))
        textField.leftViewMode = .always
        textField.isHidden = digitCount != nil

        deleteButton.setTitle(L10n.telegram("Common.Delete"), for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 17)
        deleteButton.tintColor = .white
        deleteButton.alpha = 0
        deleteButton.addAction(UIAction { [weak self] _ in self?.deleteLast() }, for: .touchUpInside)

        let symbol = passcode.biometryType == .touchID ? "touchid" : "faceid"
        biometricButton.setImage(UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .regular),
        ), for: .normal)
        biometricButton.tintColor = .white
        biometricButton.accessibilityLabel = L10n.telegram("EnterPasscode.TouchId")
        biometricButton.isHidden = !canUseBiometrics
        biometricButton.addAction(UIAction { [weak self] _ in self?.askBiometrics() }, for: .touchUpInside)

        for subview in [lockIcon, titleLabel, subtitleLabel, dotsView, textField, deleteButton, biometricButton] {
            view.addSubview(subview)
        }
        if digitCount != nil {
            let letters = ["", "", "ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ"]
            keys = (0...9).map { digit in
                let key = PasscodeKeyButton(title: "\(digit)", subtitle: letters[digit])
                key.addAction(UIAction { [weak self] _ in self?.append("\(digit)") }, for: .touchDown)
                view.addSubview(key)
                return key
            }
        }
        updateBackground()
        updateBlockedState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if digitCount == nil { textField.becomeFirstResponder() }
        if !didAskBiometrics {
            didAskBiometrics = true
            askBiometrics()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient.frame = view.bounds
        // The band beside iPhone Duo's strip.
        let left = view.safeAreaInsets.left
        let width = view.bounds.width - left - view.safeAreaInsets.right
        let safeTop = view.safeAreaInsets.top
        lockIcon.frame = CGRect(x: left + (width - 35) / 2 + 6, y: safeTop + 15, width: 35, height: 37)
        let compact = view.bounds.height < 800
        let titleY: CGFloat = compact ? 100 : 162
        let fieldY: CGFloat = compact ? 144 : 206
        let keyboardTop: CGFloat = compact ? 221 : 294
        titleLabel.frame = CGRect(x: left + 16, y: titleY, width: width - 32, height: 26)
        dotsView.frame = CGRect(x: left, y: fieldY, width: width, height: 13)
        textField.frame = CGRect(x: left + 50, y: fieldY - 8, width: width - 100, height: 38)
        let subtitleTop = digitCount == nil ? textField.frame.maxY + 16 : dotsView.frame.maxY + 8
        subtitleLabel.frame = CGRect(x: left + 16, y: subtitleTop, width: width - 32, height: 40)
        // PasscodeKeyboardLayout for the iPhone X class: 75 pt keys in a 281 pt wide block.
        let size: CGFloat = 75
        let originX = left + (width - 281) / 2
        let columns: [CGFloat] = [0, 103, 206]
        let rows: [CGFloat] = [0, 91, 182, 273]
        for (index, key) in keys.enumerated() {
            let (row, column) = index == 0 ? (3, 1) : ((index - 1) / 3, (index - 1) % 3)
            key.frame = CGRect(x: originX + columns[column], y: keyboardTop + rows[row], width: size, height: size)
        }
        let deleteSize = deleteButton.sizeThatFits(view.bounds.size)
        deleteButton.frame = CGRect(
            x: originX + columns[2] + (size - deleteSize.width) / 2,
            y: keyboardTop + rows[3] + (size - deleteSize.height) / 2,
            width: deleteSize.width,
            height: deleteSize.height,
        )
        let keyboardBottom = digitCount == nil ? subtitleLabel.frame.maxY : keyboardTop + rows[3] + size
        biometricButton.frame = CGRect(x: left + (width - 44) / 2, y: keyboardBottom + 30, width: 44, height: 44)
    }

    // MARK: UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        check(textField.text ?? "")
        return false
    }

    /// PasscodeBackground: black in the dark theme, Telegram's blue gradient in the day one.
    private func updateBackground() {
        let dark = traitCollection.userInterfaceStyle == .dark
        gradient.colors = dark
            ? [UIColor.black.cgColor, UIColor.black.cgColor]
            : [UIColor(rgb: 0x46739E).cgColor, UIColor(rgb: 0x2A5982).cgColor]
        for key in keys {
            key.updateBackground(dark: dark)
        }
    }

    private func append(_ digit: String) {
        guard let digitCount, passcode.blockedUntil == nil, entered.count < digitCount else { return }
        entered += digit
        dotsView.filled = entered.count
        updateDeleteButton()
        guard entered.count == digitCount else { return }
        let attempt = entered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.check(attempt) }
    }

    private func deleteLast() {
        guard !entered.isEmpty else { return }
        entered.removeLast()
        dotsView.filled = entered.count
        updateDeleteButton()
    }

    private func updateDeleteButton() {
        UIView.animate(withDuration: 0.2) { self.deleteButton.alpha = self.entered.isEmpty ? 0 : 1 }
    }

    private func check(_ attempt: String) {
        guard passcode.blockedUntil == nil else { return }
        if passcode.verify(attempt) {
            passcode.resetFailedAttempts()
            textField.resignFirstResponder()
            onUnlock()
            return
        }
        passcode.recordFailedAttempt()
        entered = ""
        textField.text = ""
        dotsView.filled = 0
        updateDeleteButton()
        shake()
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        updateBlockedState()
    }

    /// The failed attempts under the dots, or "Try again in 1 minute" while entry is blocked.
    private func updateBlockedState() {
        blockTimer?.invalidate()
        if let until = passcode.blockedUntil {
            subtitleLabel.text = L10n.telegram("PasscodeSettings.TryAgainIn1Minute")
            keys.forEach { $0.isEnabled = false }
            textField.isEnabled = false
            blockTimer = Timer
                .scheduledTimer(withTimeInterval: until.timeIntervalSinceNow, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateBlockedState() }
                }
            return
        }
        keys.forEach { $0.isEnabled = true }
        textField.isEnabled = true
        let attempts = passcode.failedAttempts
        subtitleLabel.text = attempts > 0
            ? L10n.telegramPlural("PasscodeSettings.FailedAttempts", count: attempts)
            : nil
    }

    private func shake() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -14, 14, -10, 10, -5, 5, 0]
        animation.duration = 0.4
        (digitCount == nil ? textField.layer : dotsView.layer).add(animation, forKey: "shake")
    }

    private func askBiometrics() {
        guard canUseBiometrics, passcode.blockedUntil == nil else { return }
        let context = LAContext()
        context.localizedFallbackTitle = ""
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: L10n.telegram("EnterPasscode.TouchId"),
        ) { [weak self] success, _ in
            guard success else { return }
            DispatchQueue.main.async {
                self?.passcode.resetFailedAttempts()
                self?.onUnlock()
            }
        }
    }
}

// MARK: - PasscodeDotsView

/// PasscodeInputFieldNode's dots: 13 pt circles 24 pt apart, outlined until a digit fills them.
final class PasscodeDotsView: UIView {
    var count = 4 {
        didSet { rebuild() }
    }

    var filled = 0 {
        didSet { update() }
    }

    var color = UIColor.white {
        didSet { update() }
    }

    private var dots = [CAShapeLayer]()

    override func layoutSubviews() {
        super.layoutSubviews()
        let diameter: CGFloat = 13
        let spacing: CGFloat = 24
        let total = CGFloat(count) * diameter + CGFloat(max(0, count - 1)) * spacing
        var x = (bounds.width - total) / 2
        for dot in dots {
            dot.frame = CGRect(x: x, y: 0, width: diameter, height: diameter)
            dot.path = UIBezierPath(ovalIn: CGRect(x: 0.5, y: 0.5, width: diameter - 1, height: diameter - 1)).cgPath
            x += diameter + spacing
        }
    }

    private func rebuild() {
        dots.forEach { $0.removeFromSuperlayer() }
        dots = (0..<count).map { _ in
            let dot = CAShapeLayer()
            dot.lineWidth = 1
            layer.addSublayer(dot)
            return dot
        }
        update()
        setNeedsLayout()
    }

    private func update() {
        for (index, dot) in dots.enumerated() {
            dot.strokeColor = color.cgColor
            dot.fillColor = index < filled ? color.cgColor : UIColor.clear.cgColor
        }
    }
}

// MARK: - PasscodeKeyButton

/// PasscodeEntryButtonNode: a 75 pt circle on glass with the digit in 36 pt and its letters in 10 pt bold.
final class PasscodeKeyButton: UIControl {
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: isHighlighted ? 0.05 : 0.25) {
                self.backgroundView.alpha = self.isHighlighted ? 0.55 : 1
            }
        }
    }

    private let backgroundView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        backgroundView.isUserInteractionEnabled = false
        backgroundView.clipsToBounds = true
        addSubview(backgroundView)
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 36)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 10, weight: .bold)
        subtitleLabel.textColor = .white
        subtitleLabel.textAlignment = .center
        for label in [titleLabel, subtitleLabel] {
            label.isUserInteractionEnabled = false
            addSubview(label)
        }
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .keyboardKey
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
        backgroundView.layer.cornerRadius = bounds.width / 2
        let hasLetters = !(subtitleLabel.text ?? "").isEmpty
        titleLabel.frame = CGRect(x: 0, y: hasLetters ? 10 : 17, width: bounds.width, height: 42)
        subtitleLabel.frame = CGRect(x: 0, y: 48, width: bounds.width, height: 13)
    }

    /// The dark theme draws keys on Telegram's 0x1c1c1d; the day one leaves them clear glass.
    func updateBackground(dark: Bool) {
        backgroundView.backgroundColor = dark ? UIColor(rgb: 0x1C1C1D).withAlphaComponent(0.6) : .clear
    }
}

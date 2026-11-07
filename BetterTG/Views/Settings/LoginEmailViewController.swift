// LoginEmailViewController.swift

import Lottie
import TDLibKit
import UIKit

// MARK: - LoginEmailViewController

/// loginEmailSetupController: AuthorizationSequenceEmailEntryController's IntroMail animation, Add Email (Enter New
/// Email when one is set) in 28 pt bold, LoginEmail.Description in 16 pt, the email field and Continue; then
/// AuthorizationSequenceCodeEntryController's Check Your Email with the code TDLib sent (setLoginEmailAddress,
/// checkLoginEmailAddressCode). The screen pops with "Email added" once the code is right.
final class LoginEmailViewController: UIViewController, UITextFieldDelegate {
    private enum Stage {
        case email
        case code(TDNativeEmailAddressAuthenticationCodeInfo)
    }

    var onCompleted: (() -> Void)?

    private let client: TDLibClient
    private let isChange: Bool
    private var stage = Stage.email
    private let animationView = LottieAnimationView(configuration: LottieConfiguration(
        renderingEngine: .automatic, decodingStrategy: .legacyCodable,
    ))
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let field = UITextField()
    private let separator = UIView()
    private let button = UIButton(configuration: .prominentGlass())
    private var isWorking = false

    init(client: TDLibClient, isChange: Bool) {
        self.client = client
        self.isChange = isChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        animationView.loopMode = .playOnce
        animationView.contentMode = .scaleAspectFit
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        textLabel.font = .systemFont(ofSize: 16)
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        field.font = .systemFont(ofSize: 20)
        field.textAlignment = .center
        field.delegate = self
        field.addAction(UIAction { [weak self] _ in self?.fieldChanged() }, for: .editingChanged)
        separator.backgroundColor = .separator
        button.addAction(UIAction { [weak self] _ in self?.proceed() }, for: .touchUpInside)
        for subview in [animationView, titleLabel, textLabel, field, separator, button] {
            view.addSubview(subview)
        }
        // Continue stands over the keyboard.
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            button.heightAnchor.constraint(equalToConstant: 50),
            button.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
        ])
        if let path = Bundle.main.path(forResource: "IntroMail", ofType: "tgs") {
            Task { [weak self] in
                guard let animation = await TGSAnimationRepository.animation(at: path), let self else { return }
                animationView.animation = animation
                if view.window != nil { animationView.play() }
            }
        }
        updateStage()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if animationView.animation != nil, !animationView.isAnimationPlaying, animationView.currentProgress == 0 {
            animationView.play()
        }
        field.becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let side: CGFloat = 32
        var y = view.safeAreaInsets.top + 24
        let showsAnimation =
            if case .email = stage {
                true
            } else {
                false
            }
        animationView.isHidden = !showsAnimation
        if showsAnimation {
            animationView.frame = CGRect(x: floor((width - 120) / 2), y: y, width: 120, height: 120)
            y += 120 + 18
        }
        let textWidth = width - side * 2
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        titleLabel.frame = CGRect(x: side, y: y, width: textWidth, height: titleHeight)
        y += titleHeight + 12
        let textHeight = textLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        textLabel.frame = CGRect(x: side, y: y, width: textWidth, height: textHeight)
        y += textHeight + 30
        field.frame = CGRect(x: side, y: y, width: textWidth, height: 44)
        separator.frame = CGRect(
            x: side,
            y: field.frame.maxY,
            width: textWidth,
            height: 1 / traitCollection.displayScale,
        )
    }

    func textFieldShouldReturn(_: UITextField) -> Bool {
        proceed()
        return false
    }

    private func updateStage() {
        switch stage {
        case .email:
            title = nil
            titleLabel.text = L10n.telegram(isChange ? "Login.EnterNewEmailTitle" : "LoginEmail.Title")
            textLabel.text = L10n.telegram("LoginEmail.Description")
            field.placeholder = L10n.telegram("Login.AddEmailPlaceholder")
            field.keyboardType = .emailAddress
            field.textContentType = .emailAddress
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        case .code(let info):
            titleLabel.text = L10n.telegram("Login.EnterCodeEmailTitle")
            textLabel.text = L10n.telegram("Login.EnterCodeEmailText", info.emailAddressPattern)
            field.text = ""
            field.placeholder = String(repeating: "–", count: max(info.length, 1))
            field.keyboardType = .numberPad
            field.textContentType = .oneTimeCode
        }
        field.reloadInputViews()
        var configuration = button.configuration ?? .prominentGlass()
        configuration.title = L10n.telegram("Login.Continue")
        configuration.showsActivityIndicator = isWorking
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        button.configuration = configuration
        fieldChanged()
        view.setNeedsLayout()
    }

    private func fieldChanged() {
        let text = field.text ?? ""
        switch stage {
        case .email:
            button.isEnabled = !isWorking && !text.isEmpty
        case .code(let info):
            button.isEnabled = !isWorking && !text.isEmpty
            // The code goes in by itself once it is complete, as the code entry does.
            if info.length > 0, text.count == info.length, !isWorking { proceed() }
        }
    }

    private func proceed() {
        let text = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isWorking, !text.isEmpty else { return }
        isWorking = true
        updateStage()
        let client = client
        let stage = stage
        Task { [weak self] in
            do {
                switch stage {
                case .email:
                    let info = try await client.send(TDNativeRequests.setLoginEmailAddress(newLoginEmailAddress: text))
                    guard let self else { return }
                    isWorking = false
                    self.stage = .code(info)
                    updateStage()
                case .code:
                    _ = try await client.send(TDNativeRequests.checkLoginEmailAddressCode(
                        code: .emailAddressAuthenticationCode(.init(code: text)),
                    ))
                    guard let self else { return }
                    finish()
                }
            } catch {
                guard let self else { return }
                isWorking = false
                updateStage()
                presentError(error)
            }
        }
    }

    /// The setup's errors as Telegram words them.
    private func presentError(_ error: Error) {
        let message = (error as? TDLibError)?.message ?? ""
        let key =
            if message.contains("EMAIL_INVALID") {
                "Login.InvalidEmailError"
            } else if message.contains("EMAIL_NOT_ALLOWED") {
                "Login.EmailNotAllowedError"
            } else if message.contains("CODE_INVALID") {
                "Login.InvalidCodeError"
            } else if message.contains("CODE_EXPIRED") {
                "Login.CodeExpired"
            } else {
                "Login.InvalidEmailAddressError"
            }
        let alert = UIAlertController(title: nil, message: L10n.telegram(key), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }

    private func finish() {
        let host = navigationController?.viewControllers.dropLast().last
        onCompleted?()
        navigationController?.popViewController(animated: true)
        guard let host else { return }
        TelegramUndoToast.show(
            title: L10n.telegram("LoginEmail.Success.Title"),
            text: L10n.telegram("LoginEmail.Success.Text"),
            in: host.view,
            bottomInset: 12,
            undo: nil,
        )
    }
}

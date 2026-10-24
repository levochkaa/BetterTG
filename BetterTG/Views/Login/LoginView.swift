// LoginView.swift

import Combine
import CoreImage.CIFilterBuiltins
import TDLibKit
import UIKit

final class LoginViewController: UIViewController {
    // MARK: Private

    private static let qrCodeContext = CIContext()

    private let authorization: LoginAuthorizationSession
    private let authorizationUpdates: AnyPublisher<TDLibAuthorizationState.Snapshot?, Never>
    private let hasOtherAccounts: () -> Bool
    private let otherAccountUserIDs: () -> [Int64]
    private let restartSignIn: (() throws -> Void)?
    private var selectedCountry = PhoneNumberInfo(
        country: "RU",
        phoneNumberPrefix: "7",
        name: Locale(identifier: AppLocalization.shared.selectedLanguagePackID).localizedString(forRegionCode: "RU")
            ?? "Russia",
    )
    private var cancellables = Set<AnyCancellable>()
    private var renderedQRCodeLink: String?
    private var stageTimer: Timer?
    private var optionAction: LoginStageContent.Action?
    private var secondaryOptionAction: LoginStageContent.Action?

    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let qrCodeContainer = UIView()
    private let qrCodeView = UIImageView()
    private let countryButton = UIButton(type: .system)
    private let prefixLabel = UILabel()
    private let inputRow = UIStackView()
    private let inputField = UITextField()
    private let secondaryRow = UIStackView()
    private let secondaryField = UITextField()
    private let continueButton = UIButton(type: .system)
    private let optionButton = UIButton(type: .system)
    private let secondaryOptionButton = UIButton(type: .system)
    private let noteLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private let accountsButton = UIButton(type: .system)

    // MARK: Internal

    var isRevoked: Bool { authorization.isRevoked }

    convenience init(accountID: UUID?) {
        let authorization = LoginAuthorizationSession(
            accountID: accountID,
            currentSource: { TDLib.shared.activeAuthorizationSource },
            client: { TDLib.shared.authorizationClient(for: $0).map(LoginAuthorizationSession.Client.live) },
        )
        self.init(
            authorization: authorization, updates: TDLib.shared.authorizationUpdates,
            hasOtherAccounts: { TDLib.shared.accounts.contains { $0.id != accountID } },
            otherAccountUserIDs: { TDLib.shared.accounts.filter { $0.id != accountID }.compactMap(\.userID) },
            restartSignIn: accountID
                .map { accountID in { try TDLib.shared.restartActiveSignIn(accountID: accountID) } },
        )
    }

    init(
        authorization: LoginAuthorizationSession,
        updates: AnyPublisher<TDLibAuthorizationState.Snapshot?, Never>,
        hasOtherAccounts: @escaping () -> Bool,
        otherAccountUserIDs: @escaping () -> [Int64] = { [] },
        restartSignIn: (() throws -> Void)? = nil,
    ) {
        self.authorization = authorization
        self.authorizationUpdates = updates
        self.hasOtherAccounts = hasOtherAccounts
        self.otherAccountUserIDs = otherAccountUserIDs
        self.restartSignIn = restartSignIn
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { stageTimer?.invalidate() }

    override func willMove(toParent parent: UIViewController?) {
        if parent == nil {
            authorization.revoke()
            stageTimer?.invalidate()
            stageTimer = nil
        }
        super.willMove(toParent: parent)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureViews()
        configureConstraints()
        configurePublishers()
    }

    private static func qrCodeImage(for link: String, side: CGFloat, scale: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        // Whole-pixel modules keep the code sharp.
        let factor = max(1, floor(side * scale / output.extent.width))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        guard let image = qrCodeContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }

    private static func styleField(_ field: UITextField) {
        field.backgroundColor = .secondarySystemBackground
        field.textColor = .label
        field.tintColor = .systemBlue
        field.layer.cornerRadius = 10
        field.clearButtonMode = .whileEditing
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private static func styleRow(_ row: UIStackView) {
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.backgroundColor = .secondarySystemBackground
        row.layer.cornerRadius = 10
        row.layoutMargins = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 8)
        row.isLayoutMarginsRelativeArrangement = true
    }

    /// Sets the field's traits only when they change, so a timer render leaves the keyboard alone.
    private static func apply(
        _ content: LoginStageContent,
        to field: UITextField,
        placeholder: String,
        contentType: UITextContentType?,
    ) {
        if field.placeholder != placeholder { field.placeholder = placeholder }
        if field.keyboardType != content.keyboardType { field.keyboardType = content.keyboardType }
        if field.textContentType != contentType { field.textContentType = contentType }
        if field.autocapitalizationType != content.autocapitalization {
            field.autocapitalizationType = content.autocapitalization
        }
    }

    /// A text option; one without an action reads as a countdown.
    private static func apply(_ option: LoginStageContent.Option?, to button: UIButton, enabled: Bool) {
        button.isHidden = option == nil
        button.configuration?.title = option?.title
        button.configuration?.baseForegroundColor = option?.action == nil ? .secondaryLabel : nil
        button.isEnabled = enabled && option?.action != nil
    }

    private func configureViews() {
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill
        view.addSubview(contentStack)

        var accountsConfiguration = UIButton.Configuration.plain()
        accountsConfiguration.title = L10n.betterTG("Accounts.Section")
        accountsConfiguration.image = UIImage(systemName: "person.2.fill")
        accountsConfiguration.imagePadding = 6
        accountsButton.configuration = accountsConfiguration
        accountsButton.translatesAutoresizingMaskIntoConstraints = false
        accountsButton.addTarget(self, action: #selector(showAccounts), for: .touchUpInside)
        view.addSubview(accountsButton)

        var backConfiguration = UIButton.Configuration.plain()
        backConfiguration.image = UIImage(systemName: "chevron.backward")
        backConfiguration.title = L10n.telegram("Common.Back")
        backConfiguration.imagePadding = 4
        backButton.configuration = backConfiguration
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(backPressed), for: .touchUpInside)
        view.addSubview(backButton)

        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        descriptionLabel.numberOfLines = 0

        // The code stays dark on white in both appearances so any camera reads it.
        qrCodeContainer.backgroundColor = .white
        qrCodeContainer.layer.cornerRadius = 16
        qrCodeView.translatesAutoresizingMaskIntoConstraints = false
        qrCodeView.contentMode = .scaleAspectFit
        qrCodeView.layer.magnificationFilter = .nearest
        qrCodeView.isAccessibilityElement = true
        qrCodeView.accessibilityTraits = .image
        qrCodeContainer.addSubview(qrCodeView)
        NSLayoutConstraint.activate([
            qrCodeView.widthAnchor.constraint(equalToConstant: 220),
            qrCodeView.heightAnchor.constraint(equalToConstant: 220),
            qrCodeView.topAnchor.constraint(equalTo: qrCodeContainer.topAnchor, constant: 16),
            qrCodeView.bottomAnchor.constraint(equalTo: qrCodeContainer.bottomAnchor, constant: -16),
            qrCodeView.centerXAnchor.constraint(equalTo: qrCodeContainer.centerXAnchor),
        ])

        var countryConfiguration = UIButton.Configuration.plain()
        countryConfiguration.titleAlignment = .leading
        countryConfiguration.image = UIImage(systemName: "chevron.down")
        countryConfiguration.imagePlacement = .trailing
        countryConfiguration.imagePadding = 8
        countryButton.configuration = countryConfiguration
        countryButton.contentHorizontalAlignment = .fill
        countryButton.addTarget(self, action: #selector(selectCountry), for: .touchUpInside)

        prefixLabel.textColor = .label
        prefixLabel.font = .preferredFont(forTextStyle: .body)
        prefixLabel.setContentHuggingPriority(.required, for: .horizontal)
        prefixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        Self.styleField(inputField)
        Self.styleRow(inputRow)
        inputRow.addArrangedSubview(prefixLabel)
        inputRow.addArrangedSubview(inputField)

        Self.styleField(secondaryField)
        Self.styleRow(secondaryRow)
        secondaryRow.addArrangedSubview(secondaryField)

        var continueConfiguration = UIButton.Configuration.filled()
        continueConfiguration.title = L10n.telegram("Login.Continue")
        continueConfiguration.cornerStyle = .medium
        continueButton.configuration = continueConfiguration
        continueButton.addTarget(self, action: #selector(continueLogin), for: .touchUpInside)
        continueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        var optionConfiguration = UIButton.Configuration.plain()
        optionConfiguration.titleAlignment = .center
        optionConfiguration.titleLineBreakMode = .byWordWrapping
        optionButton.configuration = optionConfiguration
        optionButton.addTarget(self, action: #selector(optionPressed), for: .touchUpInside)
        secondaryOptionButton.configuration = optionConfiguration
        secondaryOptionButton.addTarget(self, action: #selector(secondaryOptionPressed), for: .touchUpInside)

        noteLabel.numberOfLines = 0
        noteLabel.textAlignment = .center
        noteLabel.textColor = .secondaryLabel
        noteLabel.font = .preferredFont(forTextStyle: .subheadline)
        noteLabel.adjustsFontForContentSizeCategory = true

        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(descriptionLabel)
        contentStack.addArrangedSubview(qrCodeContainer)
        contentStack.addArrangedSubview(countryButton)
        contentStack.addArrangedSubview(inputRow)
        contentStack.addArrangedSubview(secondaryRow)
        contentStack.addArrangedSubview(continueButton)
        contentStack.addArrangedSubview(noteLabel)
        contentStack.addArrangedSubview(optionButton)
        contentStack.addArrangedSubview(secondaryOptionButton)
        render()
    }

    private func configureConstraints() {
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            contentStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            accountsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            accountsButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            backButton.centerYAnchor.constraint(equalTo: accountsButton.centerYAnchor),
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 4),
        ])
    }

    private func configurePublishers() {
        authorization.onChange = { [weak self] clearCredentials in
            guard let self else { return }
            if clearCredentials {
                inputField.text = nil
                inputField.placeholder = nil
                secondaryField.text = nil
                // All presented sheets/callbacks belong to the old auth stage.
                presentedViewController?.dismiss(animated: false)
            }
            render()
            if clearCredentials, let stage = authorization.stage, stage != .qrCode, view.window != nil {
                inputField.becomeFirstResponder()
                inputField.reloadInputViews()
            }
        }
        authorization.onError = { [weak self] message in self?.showError(message) }
        // TDLib publishes synchronously on main; an extra queued hop could
        // replay an older same-client state after the current snapshot.
        authorizationUpdates
            .sink { [weak self] state in self?.authorization.accept(state) }
            .store(in: &cancellables)

        nc.publisher(for: .telegramAccountsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
    }

    private func render() {
        let stage = authorization.stage
        let current = authorization.capture() != nil
        let content = LoginStageContent.make(
            stage: stage,
            state: authorization.snapshot?.state,
            remaining: authorization.remainingSeconds(),
        )
        let enabled = current && stage != nil && !authorization.isBusy

        titleLabel.text = content.title
        descriptionLabel.attributedText = content.text.map {
            LoginStageContent.attributed($0, font: .preferredFont(forTextStyle: .body), color: .secondaryLabel)
        }
        descriptionLabel.textAlignment = stage == .qrCode ? .natural : .center
        descriptionLabel.isHidden = content.text == nil

        if case .authorizationStateWaitOtherDeviceConfirmation(let value) = authorization.snapshot?.state {
            updateQRCode(link: value.link)
        } else {
            updateQRCode(link: nil)
        }
        qrCodeView.accessibilityLabel = content.title
        qrCodeContainer.isHidden = qrCodeView.image == nil

        countryButton.isHidden = stage != .phoneNumber
        countryButton.configuration?.title = selectedCountry.name
        prefixLabel.isHidden = stage != .phoneNumber
        prefixLabel.text = "+\(selectedCountry.phoneNumberPrefix)"
        inputRow.isHidden = !content.acceptsInput
        Self.apply(content, to: inputField, placeholder: content.placeholder, contentType: content.contentType)
        inputField.isSecureTextEntry = content.isSecure
        secondaryRow.isHidden = content.secondaryPlaceholder == nil
        Self.apply(
            content,
            to: secondaryField,
            placeholder: content.secondaryPlaceholder ?? "",
            contentType: content.secondaryContentType,
        )
        inputField.isEnabled = enabled && content.acceptsInput
        secondaryField.isEnabled = inputField.isEnabled
        continueButton.isHidden = !content.acceptsInput
        continueButton.isEnabled = inputField.isEnabled
        countryButton.isEnabled = inputField.isEnabled

        optionAction = content.option?.action
        Self.apply(content.option, to: optionButton, enabled: enabled)
        secondaryOptionAction = content.secondaryOption?.action
        Self.apply(content.secondaryOption, to: secondaryOptionButton, enabled: enabled)
        noteLabel.text = content.note
        noteLabel.isHidden = content.note == nil

        backButton.isHidden = !authorization.canGoBack
        backButton.isEnabled = enabled
        accountsButton.isEnabled = current
        accountsButton.isHidden = !hasOtherAccounts()
        if !current || stage == nil || !content.acceptsInput {
            inputField.resignFirstResponder()
            secondaryField.resignFirstResponder()
        }
        updateStageTimer()
    }

    private func updateQRCode(link: String?) {
        guard link != renderedQRCodeLink else { return }
        renderedQRCodeLink = link
        qrCodeView.image = link.flatMap {
            Self.qrCodeImage(for: $0, side: 220, scale: max(1, traitCollection.displayScale))
        }
    }

    /// Renders every second while the step's server timer runs.
    private func updateStageTimer() {
        let isRunning = authorization.stageDeadline.map { $0 > Date() } == true
        if isRunning, stageTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.render()
            }
            stageTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else if !isRunning {
            stageTimer?.invalidate()
            stageTimer = nil
        }
    }

    @objc private func showAccounts() {
        guard let token = authorization.capture() else { return }
        let otherAccounts = TDLib.shared.sortedAccounts.filter { $0.id != authorization.accountID }
        guard !otherAccounts.isEmpty else { return }

        let alert = UIAlertController(
            title: L10n.betterTG("Accounts.Section"),
            message: nil,
            preferredStyle: .actionSheet,
        )
        for account in otherAccounts {
            alert.addAction(UIAlertAction(title: account.localizedTitle, style: .default) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, authorization.permits(token) else { return }
                    do {
                        try TDLib.shared.switchToAccount(account.id)
                    } catch {
                        if authorization.permits(token) { showError(error.localizedDescription) }
                    }
                }
            })
        }
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = accountsButton
            popover.sourceRect = accountsButton.bounds
        }
        present(alert, animated: true)
    }

    @objc private func selectCountry() {
        guard let token = authorization.capture(),
              let client = TDLib.shared.authorizationClient(for: token.source) else { return }
        let countries = SelectCountryViewController(
            selectedCountry: selectedCountry, client: client,
            contextIsCurrent: { [weak self] in self?.authorization.permits(token) == true },
        ) { [weak self] country in
            guard let self, authorization.permits(token) else { return }
            selectedCountry = country
            render()
        }
        present(TelegramNavigationController(rootViewController: countries), animated: true)
    }

    @objc private func continueLogin() {
        // Telegram asks to accept blocking terms of service before signing up.
        if authorization.stage == .registration,
           case .authorizationStateWaitRegistration(let value) = authorization.snapshot?.state,
           value.termsOfService.showPopup,
           !(inputField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let token = authorization.capture()
        {
            presentTermsOfService(value.termsOfService, token: token, asksToAgree: true)
            return
        }
        submitInput()
    }

    private func submitInput() {
        authorization.submit(
            inputField.text ?? "",
            secondary: secondaryField.text ?? "",
            prefix: selectedCountry.phoneNumberPrefix,
        )
    }

    @objc private func optionPressed() {
        handle(optionAction)
    }

    @objc private func secondaryOptionPressed() {
        handle(secondaryOptionAction)
    }

    private func handle(_ action: LoginStageContent.Action?) {
        guard let action, let token = authorization.capture() else { return }
        switch action {
        case .requestQRCode:
            authorization.perform(.qrCode(otherUserIDs: otherAccountUserIDs()))
        case .resendCode:
            authorization.perform(.resendCode)
        case .openURL(let url):
            UIApplication.shared.open(url)
        case .forgotPassword:
            forgotPassword()
        case .resetEmail:
            confirmEmailReset(token: token)
        case .showTermsOfService:
            guard case .authorizationStateWaitRegistration(let value) = authorization.snapshot?.state else { return }
            presentTermsOfService(value.termsOfService, token: token, asksToAgree: false)
        case .usePhoneNumber:
            guard authorization.stage == .qrCode, let restartSignIn else { return }
            do {
                try restartSignIn()
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    /// Telegram's back button: a screen opened inside a step closes; a later step asks to stop its verification
    /// first and then returns to phone entry (`AuthorizationSequenceCodeEntryController`, sign-up and email).
    @objc private func backPressed() {
        guard let token = authorization.capture() else { return }
        if authorization.hasLocalStage {
            authorization.leaveLocalStage()
            return
        }
        let keys: (text: String, proceed: String, stop: String)? =
            switch authorization.stage {
            case .code:
                (
                    text: "Login.CancelPhoneVerification",
                    proceed: "Login.CancelPhoneVerificationContinue",
                    stop: "Login.CancelPhoneVerificationStop",
                )
            case .emailAddress,
                 .emailCode:
                (
                    text: "Login.CancelEmailVerification",
                    proceed: "Login.CancelEmailVerificationContinue",
                    stop: "Login.CancelEmailVerificationStop",
                )
            case .registration:
                (
                    text: "Login.CancelSignUpConfirmation",
                    proceed: "Login.CancelPhoneVerificationContinue",
                    stop: "Login.CancelPhoneVerificationStop",
                )
            default:
                nil
            }
        guard let keys else {
            authorization.changePhoneNumber()
            return
        }
        let alert = UIAlertController(title: nil, message: L10n.telegram(keys.text), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram(keys.proceed), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram(keys.stop), style: .default) { [weak self] _ in
            guard let self, authorization.permits(token) else { return }
            authorization.changePhoneNumber()
        })
        present(alert, animated: true)
    }

    /// Telegram's "Forgot password?": a recovery email gets a code; without one only Telegram's explanation remains.
    private func forgotPassword() {
        guard case .authorizationStateWaitPassword(let value) = authorization.snapshot?.state else { return }
        guard value.hasRecoveryEmailAddress else {
            let alert = UIAlertController(
                title: nil,
                message: L10n.telegram("TwoStepAuth.RecoveryUnavailable"),
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
            present(alert, animated: true)
            return
        }
        authorization.perform(.passwordRecovery)
    }

    /// Telegram's "Can't access this email?": a reset that needs waiting is confirmed first (`resetEmail`).
    private func confirmEmailReset(token: LoginAuthorizationSession.Token) {
        guard case .authorizationStateWaitEmailCode(let value) = authorization.snapshot?.state else { return }
        guard case .emailAddressResetStateAvailable(let available) = value.emailAddressResetState,
              available.waitPeriod > 0
        else {
            authorization.perform(.resetEmailAddress)
            return
        }
        let alert = UIAlertController(
            title: L10n.telegram("Login.Email.ResetTitle"),
            message: LoginStageContent.plain(
                "Login.Email.ResetText",
                value.codeInfo.emailAddressPattern,
                LoginStageContent.intervalText(seconds: available.waitPeriod),
            ),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.telegram("Login.Email.Reset"), style: .default) { [weak self] _ in
            guard let self, authorization.permits(token) else { return }
            authorization.perform(.resetEmailAddress)
        })
        present(alert, animated: true)
    }

    /// Telegram's terms of service alert; when signing up it asks to agree (`AuthorizationSequenceController`).
    private func presentTermsOfService(
        _ terms: TDNativeTermsOfService,
        token: LoginAuthorizationSession.Token,
        asksToAgree: Bool,
    ) {
        let alert = UIAlertController(
            title: L10n.telegram("Login.TermsOfServiceHeader"),
            message: terms.text.text,
            preferredStyle: .alert,
        )
        if asksToAgree {
            let decline = L10n.telegram("Login.TermsOfServiceDecline")
            alert.addAction(UIAlertAction(title: decline, style: .cancel) { [weak self] _ in
                guard let self, authorization.permits(token) else { return }
                presentTermsDecline(terms, token: token)
            })
            let agree = L10n.telegram("Login.TermsOfServiceAgree")
            alert.addAction(UIAlertAction(title: agree, style: .default) { [weak self] _ in
                guard let self, authorization.permits(token) else { return }
                submitInput()
            })
        } else {
            alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        }
        present(alert, animated: true)
    }

    private func presentTermsDecline(_ terms: TDNativeTermsOfService, token: LoginAuthorizationSession.Token) {
        let alert = UIAlertController(
            title: L10n.telegram("Login.TermsOfServiceDecline"),
            message: L10n.telegram("Login.TermsOfServiceSignupDecline"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { [weak self] _ in
            guard let self, authorization.permits(token) else { return }
            presentTermsOfService(terms, token: token, asksToAgree: true)
        })
        // Telegram ends the sign-up when its terms are declined.
        let decline = L10n.telegram("Login.TermsOfServiceDecline")
        alert.addAction(UIAlertAction(title: decline, style: .destructive) { [weak self] _ in
            guard let self, authorization.permits(token) else { return }
            authorization.changePhoneNumber()
        })
        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: L10n.betterTG("Login.ErrorTitle"),
            message: message,
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }
}

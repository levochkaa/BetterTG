// LoginView.swift

import Combine
import TDLibKitDynamic
import UIKit

final class LoginViewController: UIViewController {
    // MARK: Private

    private let authorization: LoginAuthorizationSession
    private let authorizationUpdates: AnyPublisher<TDLibAuthorizationState.Snapshot?, Never>
    private let hasOtherAccounts: () -> Bool
    private var selectedCountry = PhoneNumberInfo(country: "RU", phoneNumberPrefix: "7", name: "Russian Federation")
    private var cancellables = Set<AnyCancellable>()

    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let countryButton = UIButton(type: .system)
    private let prefixLabel = UILabel()
    private let inputField = UITextField()
    private let continueButton = UIButton(type: .system)
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
        )
    }

    init(
        authorization: LoginAuthorizationSession,
        updates: AnyPublisher<TDLibAuthorizationState.Snapshot?, Never>,
        hasOtherAccounts: @escaping () -> Bool,
    ) {
        self.authorization = authorization
        self.authorizationUpdates = updates
        self.hasOtherAccounts = hasOtherAccounts
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func willMove(toParent parent: UIViewController?) {
        if parent == nil { authorization.revoke() }
        super.willMove(toParent: parent)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureViews()
        configureConstraints()
        configurePublishers()
    }

    private func configureViews() {
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill
        view.addSubview(contentStack)

        var accountsConfiguration = UIButton.Configuration.plain()
        accountsConfiguration.title = "Accounts"
        accountsConfiguration.image = UIImage(systemName: "person.2.fill")
        accountsConfiguration.imagePadding = 6
        accountsButton.configuration = accountsConfiguration
        accountsButton.translatesAutoresizingMaskIntoConstraints = false
        accountsButton.addTarget(self, action: #selector(showAccounts), for: .touchUpInside)
        view.addSubview(accountsButton)

        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label

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

        inputField.backgroundColor = .secondarySystemBackground
        inputField.textColor = .label
        inputField.tintColor = .systemBlue
        inputField.layer.cornerRadius = 10
        inputField.clearButtonMode = .whileEditing
        inputField.font = .preferredFont(forTextStyle: .body)
        inputField.adjustsFontForContentSizeCategory = true
        inputField.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        inputField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let inputRow = UIStackView(arrangedSubviews: [prefixLabel, inputField])
        inputRow.axis = .horizontal
        inputRow.alignment = .center
        inputRow.spacing = 8
        inputRow.backgroundColor = .secondarySystemBackground
        inputRow.layer.cornerRadius = 10
        inputRow.layoutMargins = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 8)
        inputRow.isLayoutMarginsRelativeArrangement = true

        var continueConfiguration = UIButton.Configuration.filled()
        continueConfiguration.title = "Continue"
        continueConfiguration.cornerStyle = .medium
        continueButton.configuration = continueConfiguration
        continueButton.addTarget(self, action: #selector(continueLogin), for: .touchUpInside)
        continueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(countryButton)
        contentStack.addArrangedSubview(inputRow)
        contentStack.addArrangedSubview(continueButton)
        render()
    }

    private func configureConstraints() {
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            contentStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            accountsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            accountsButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
        ])
    }

    private func configurePublishers() {
        authorization.onChange = { [weak self] clearCredentials in
            guard let self else { return }
            if clearCredentials {
                inputField.text = nil
                inputField.placeholder = nil
                // All presented sheets/callbacks belong to the old auth stage.
                presentedViewController?.dismiss(animated: false)
            }
            render()
            if clearCredentials, authorization.stage != nil, view.window != nil {
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
        let loginState = authorization.stage
        let current = authorization.capture() != nil
        titleLabel.text = loginState?.title ?? "Waiting for authorization"
        countryButton.isHidden = loginState != .phoneNumber
        countryButton.configuration?.title = selectedCountry.name
        prefixLabel.isHidden = loginState != .phoneNumber
        prefixLabel.text = "+\(selectedCountry.phoneNumberPrefix)"
        inputField.isSecureTextEntry = loginState == .twoFactor
        inputField.keyboardType = loginState == .twoFactor ? .default : .numberPad
        inputField.textContentType = loginState == .twoFactor ? .password : .oneTimeCode
        inputField.placeholder =
            switch loginState {
            case .phoneNumber: "Phone Number"
            case .code: "Code"
            case .twoFactor:
                if case .authorizationStateWaitPassword(let state) = authorization.snapshot?.state,
                   !state.passwordHint.isEmpty
                {
                    state.passwordHint
                } else {
                    "2FA"
                }
            case nil: ""
            }
        inputField.isEnabled = current && loginState != nil && !authorization.isBusy
        continueButton.isEnabled = inputField.isEnabled
        countryButton.isEnabled = inputField.isEnabled
        accountsButton.isEnabled = current
        accountsButton.isHidden = !hasOtherAccounts()
        if !current || loginState == nil { inputField.resignFirstResponder() }
    }

    @objc private func showAccounts() {
        guard let token = authorization.capture() else { return }
        let otherAccounts = TDLib.shared.sortedAccounts.filter { $0.id != authorization.accountID }
        guard !otherAccounts.isEmpty else { return }

        let alert = UIAlertController(title: "Accounts", message: nil, preferredStyle: .actionSheet)
        for account in otherAccounts {
            alert.addAction(UIAlertAction(title: account.title, style: .default) { [weak self] _ in
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
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
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
        present(ClassicNavigation.controller(rootViewController: countries), animated: true)
    }

    @objc private func continueLogin() {
        authorization.submit(inputField.text ?? "", prefix: selectedCountry.phoneNumberPrefix)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// LoginView.swift

import Combine
import TDLibKitDynamic
import UIKit

final class LoginViewController: UIViewController {
    // MARK: Private

    private var loginState = LoginState.phoneNumber
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureViews()
        configureConstraints()
        configurePublishers()
        refreshAuthorizationState()
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
        nc.publisher(for: .authorizationStateWaitPassword)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let waitPassword = notification.object as? AuthorizationStateWaitPassword else { return }
                self?.setTwoFactorState(waitPassword)
            }
            .store(in: &cancellables)

        nc.publisher(for: .authorizationStateWaitCode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setState(.code) }
            .store(in: &cancellables)

        nc.mergeMany([
            .authorizationStateWaitPhoneNumber,
            .authorizationStateClosed,
            .authorizationStateClosing,
            .authorizationStateLoggingOut,
        ])
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.setState(.phoneNumber) }
        .store(in: &cancellables)

        nc.publisher(for: .telegramAccountsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
    }

    private func refreshAuthorizationState() {
        Task { [weak self] in
            let state = try? await td.getAuthorizationState()
            await MainActor.run {
                guard let self else { return }
                switch state {
                case .authorizationStateWaitPassword(let waitPassword):
                    self.setTwoFactorState(waitPassword)
                case .authorizationStateWaitCode:
                    self.setState(.code)
                case .authorizationStateClosed, .authorizationStateClosing, .authorizationStateLoggingOut:
                    self.showError("There was an error with Authorization State. Please restart the app.")
                case .authorizationStateWaitPremiumPurchase:
                    self.showError("Login requires Telegram Premium. Please upgrade in the Telegram app.")
                default:
                    break
                }
            }
        }
    }

    private func setState(_ state: LoginState) {
        loginState = state
        inputField.text = nil
        render()
        inputField.becomeFirstResponder()
        inputField.reloadInputViews()
    }

    private func setTwoFactorState(_ waitPassword: AuthorizationStateWaitPassword) {
        inputField.placeholder = waitPassword.passwordHint.isEmpty ? "2FA" : waitPassword.passwordHint
        setState(.twoFactor)
    }

    private func render() {
        titleLabel.text = loginState.title
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
            case .twoFactor: inputField.placeholder ?? "2FA"
            }
        accountsButton.isHidden = TDLib.shared.accounts.allSatisfy { $0.id == TDLib.shared.activeAccountID }
    }

    @objc private func showAccounts() {
        let otherAccounts = TDLib.shared.sortedAccounts.filter { $0.id != TDLib.shared.activeAccountID }
        guard !otherAccounts.isEmpty else { return }

        let alert = UIAlertController(title: "Accounts", message: nil, preferredStyle: .actionSheet)
        for account in otherAccounts {
            alert.addAction(UIAlertAction(title: account.title, style: .default) { [weak self] _ in
                Task { @MainActor in
                    do {
                        try TDLib.shared.switchToAccount(account.id)
                    } catch {
                        self?.showError(error.localizedDescription)
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
        let countries = SelectCountryViewController(selectedCountry: selectedCountry) { [weak self] country in
            self?.selectedCountry = country
            self?.render()
        }
        present(UINavigationController(rootViewController: countries), animated: true)
    }

    @objc private func continueLogin() {
        let value = inputField.text ?? ""
        continueButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            let state = try? await td.getAuthorizationState()
            switch state {
            case .authorizationStateWaitPassword:
                _ = try? await td.checkAuthenticationPassword(password: value)
            case .authorizationStateWaitCode:
                _ = try? await td.checkAuthenticationCode(code: value)
            case .authorizationStateWaitPhoneNumber:
                _ = try? await td.setAuthenticationPhoneNumber(
                    phoneNumber: "\(selectedCountry.phoneNumberPrefix)\(value)",
                    settings: nil,
                )
            default:
                break
            }
            await MainActor.run { self.continueButton.isEnabled = true }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

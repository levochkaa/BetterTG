// DeleteAccountDataViewController.swift

import Lottie
import TDLibKit
import UIKit

// MARK: - DeleteAccountDataViewController

/// Telegram's DeleteAccountDataController: the steps before deleting the account. Each shows InviteLinkHeaderItem's
/// animation, title and text, with DeleteAccountFooterItem's Come Back Later and Continue under them: what the account
/// loses (itself and the people it talks to most), the public groups and channels it created, the message history,
/// then its phone number and, with two-step verification, its password. Continue replaces the step with the next one;
/// after the last, Telegram's alert deletes the account (deleteAccount) and TDLib's logout removes it.
final class DeleteAccountDataViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
UITextFieldDelegate {
    enum Step {
        case cloud
        case groups([SettingsPeer])
        case messages
        case phone
        case password

        var animationName: String {
            switch self {
            case .cloud: "DeleteAccountCloud"
            case .groups: "DeleteAccountGroups"
            case .messages: "DeleteAccountMessages"
            case .phone: "DeleteAccountPhone"
            case .password: "DeleteAccountPassword"
            }
        }

        var title: String {
            switch self {
            case .cloud: L10n.telegram("DeleteAccount.CloudStorageTitle")
            case .groups: L10n.telegram("DeleteAccount.GroupsAndChannelsTitle")
            case .messages: L10n.telegram("DeleteAccount.MessageHistoryTitle")
            case .phone: L10n.telegram("DeleteAccount.EnterPhoneNumber")
            case .password: L10n.telegram("DeleteAccount.EnterPassword")
            }
        }

        var text: String {
            switch self {
            case .cloud: L10n.telegram("DeleteAccount.CloudStorageText")
            case .groups: L10n.telegram("DeleteAccount.GroupsAndChannelsText")
            case .messages: L10n.telegram("DeleteAccount.MessageHistoryText")
            case .password,
                 .phone: ""
            }
        }

        /// The steps that type: their animation gives way to the keyboard on a portrait screen.
        var hidesAnimationInPortrait: Bool {
            switch self {
            case .password,
                 .phone: true
            case .cloud,
                 .groups,
                 .messages: false
            }
        }
    }

    private let step: Step
    private let hasPassword: Bool
    private let accountID = TDLib.shared.activeAccountID
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerView = DeleteAccountHeaderView()
    private let footerPanel = DeleteAccountFooterPanel()
    private var peers = [SettingsPeer]()
    /// The cloud step loads the public chats the account created, which decide whether the groups step comes next.
    private var createdPublicChats: Task<[SettingsPeer], Never>?
    private var isLoading = false {
        didSet { updateActivity() }
    }

    /// DeleteAccountDataController's `secondaryActionDisabled`: Continue works once until its step fails.
    private var isProceeding = false
    private var countries = [PhoneNumberInfo]()
    private var country: PhoneNumberInfo?
    private let codeField = UITextField()
    private let numberField = UITextField()
    private let passwordField = UITextField()

    private var client: TDLibClient {
        TDLib.shared.activeClient
    }

    private var contextIsCurrent: Bool {
        accountID != nil && TDLib.shared.activeAccountID == accountID
    }

    init(step: Step, hasPassword: Bool) {
        self.step = step
        self.hasPassword = hasPassword
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { createdPublicChats?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.telegram("DeleteAccount.DeleteMyAccountTitle")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        navigationItem.hidesBackButton = true

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive
        tableView.register(DeleteAccountPeersCell.self, forCellReuseIdentifier: DeleteAccountPeersCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        view.addSubview(tableView)

        headerView.configure(step: step)
        tableView.tableHeaderView = headerView

        footerPanel.translatesAutoresizingMaskIntoConstraints = false
        switch step {
        case .password,
             .phone: footerPanel.configure(title: nil)
        case .cloud,
             .groups,
             .messages: footerPanel.configure(title: L10n.telegram("DeleteAccount.ComeBackLater"))
        }
        footerPanel.onPrimary = { [weak self] in self?.dismiss(animated: true) }
        footerPanel.onSecondary = { [weak self] in self?.proceed() }
        view.addSubview(footerPanel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerPanel.contentBottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        configureFields()
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let isLandscape = view.bounds.width > view.bounds.height && view.bounds.width > 320
        headerView.update(animationSide: isLandscape ? 140 : step.hidesAnimationInPortrait ? 0 : 124)
        let size = headerView.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        let headerSize = CGSize(width: tableView.bounds.width, height: size.height)
        if headerView.frame.size != headerSize {
            headerView.frame.size = headerSize
            tableView.tableHeaderView = headerView
        }
        let bottomInset = footerPanel.frame.height - view.safeAreaInsets.bottom
        if tableView.contentInset.bottom != bottomInset {
            tableView.contentInset.bottom = bottomInset
            tableView.verticalScrollIndicatorInsets.bottom = bottomInset
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        headerView.play()
        // The typing steps start with their field focused, as `didAppear` activates the input.
        switch step {
        case .phone:
            codeField.becomeFirstResponder()
        case .password:
            passwordField.becomeFirstResponder()
        case .cloud,
             .groups,
             .messages:
            break
        }
    }

    // MARK: Table

    func numberOfSections(in _: UITableView) -> Int {
        1
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        switch step {
        case .cloud,
             .groups: peers.isEmpty ? 0 : 1
        case .messages: 0
        case .phone: 2
        case .password: 1
        }
    }

    func tableView(_: UITableView, titleForFooterInSection _: Int) -> String? {
        if case .groups = step, !peers.isEmpty { return L10n.telegram("DeleteAccount.GroupsAndChannelsInfo") }
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch step {
        case .cloud,
             .groups:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: DeleteAccountPeersCell.reuseIdentifier,
                for: indexPath,
            )
            (cell as? DeleteAccountPeersCell)?.configure(peers: peers, client: client, accountID: accountID)
            return cell
        case .phone where indexPath.row == 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var configuration = UIListContentConfiguration.cell()
            configuration.text = country?.name ?? L10n.telegram("Login.CountryCode")
            cell.contentConfiguration = configuration
            cell.accessoryType = .disclosureIndicator
            cell.backgroundColor = .secondarySystemGroupedBackground
            return cell
        case .messages,
             .password,
             .phone:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            cell.contentConfiguration = nil
            cell.accessoryType = .none
            cell.selectionStyle = .none
            cell.backgroundColor = .secondarySystemGroupedBackground
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            if case .password = step {
                embed([passwordField], in: cell)
            } else {
                embed([codeField, numberField], in: cell)
            }
            return cell
        }
    }

    func tableView(_: UITableView, heightForRowAt _: IndexPath) -> CGFloat {
        switch step {
        case .cloud,
             .groups: DeleteAccountPeersCell.height
        case .messages,
             .password,
             .phone: 44
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if case .phone = step, indexPath.row == 0 { selectCountry() }
    }

    // MARK: Fields

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String,
    ) -> Bool {
        guard textField === codeField else { return true }
        // The code keeps its "+" and at most four digits, as PhoneInputNode's country code field.
        let current = (textField.text ?? "") as NSString
        let digits = current.replacingCharacters(in: range, with: string).filter(\.isNumber)
        textField.text = "+" + digits.prefix(4)
        updateCountry()
        if digits.count >= 4 { numberField.becomeFirstResponder() }
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === codeField {
            numberField.becomeFirstResponder()
        } else {
            proceed()
        }
        return false
    }

    private func configureFields() {
        codeField.text = "+"
        codeField.keyboardType = .phonePad
        codeField.textContentType = .telephoneNumber
        codeField.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        codeField.delegate = self
        numberField.placeholder = L10n.telegram("Login.PhonePlaceholder")
        numberField.keyboardType = .phonePad
        numberField.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        numberField.delegate = self
        passwordField.placeholder = L10n.telegram("LoginPassword.PasswordPlaceholder")
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .done
        passwordField.delegate = self
    }

    /// DeleteAccountPhoneItem's row: the code in 67 pt from 11 pt, a separator, then the number; one field otherwise.
    private func embed(_ fields: [UITextField], in cell: UITableViewCell) {
        for field in fields {
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(field)
            NSLayoutConstraint.activate([
                field.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
            ])
        }
        if fields.count == 2 {
            let separator = UIView()
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.backgroundColor = .separator
            cell.contentView.addSubview(separator)
            NSLayoutConstraint.activate([
                fields[0].leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                fields[0].widthAnchor.constraint(equalToConstant: 67),
                separator.leadingAnchor.constraint(equalTo: fields[0].trailingAnchor, constant: 4),
                separator.widthAnchor.constraint(equalToConstant: 1 / max(1, traitCollection.displayScale)),
                separator.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                separator.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                fields[1].leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 10),
                fields[1].trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            ])
        } else if let field = fields.first {
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                field.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            ])
        }
    }

    private func selectCountry() {
        let picker = SelectCountryViewController(
            selectedCountry: country ?? PhoneNumberInfo(country: "", phoneNumberPrefix: "", name: ""),
            client: client,
            contextIsCurrent: { [weak self] in self?.contextIsCurrent == true },
        ) { [weak self] selected in
            guard let self else { return }
            country = selected
            codeField.text = "+" + selected.phoneNumberPrefix
            tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none)
            numberField.becomeFirstResponder()
        }
        view.endEditing(true)
        present(TelegramNavigationController(rootViewController: picker), animated: true)
    }

    /// The country whose calling code is typed, as DeleteAccountPhoneItem names it on its button.
    private func updateCountry() {
        let code = (codeField.text ?? "").filter(\.isNumber)
        let match = code.isEmpty ? nil : countries.first { $0.phoneNumberPrefix == code }
        guard match != country else { return }
        country = match
        tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none)
    }

    // MARK: Loading

    private func load() {
        guard contextIsCurrent else { return }
        let client = client
        switch step {
        case .cloud:
            // The account itself, then up to nine of the people it talks to most (recentPeers).
            Task { [weak self] in
                var loaded = [SettingsPeer]()
                if let me = try? await client.getMe() {
                    loaded.append(SettingsPeer(
                        id: me.id,
                        title: L10n.telegram("DeleteAccount.SavedMessages"),
                        file: nil,
                        minithumbnail: nil,
                        placeholder: me.telegramAvatarPlaceholder,
                    ))
                }
                if let top = try? await client.getTopChats(category: .topChatCategoryUsers, limit: 9) {
                    for chatID in top.chatIds {
                        if let peer = await SettingsPeer.chat(chatID, client: client) { loaded.append(peer) }
                    }
                }
                guard let self, contextIsCurrent else { return }
                peers = loaded
                tableView.reloadData()
            }
            createdPublicChats = Task {
                guard let chats = try? await client.send(TDNativeRequests.getCreatedPublicChats(
                    type: .publicChatTypeHasUsername,
                )) else { return [] }
                var loaded = [SettingsPeer]()
                for chatID in chats.chatIds {
                    if let peer = await SettingsPeer.chat(chatID, client: client) { loaded.append(peer) }
                }
                return loaded
            }
        case .groups(let preloaded):
            peers = preloaded.shuffled()
        case .phone:
            Task { [weak self] in
                guard let result = try? await client.getCountries().countries else { return }
                let mapped = result.compactMap { country -> PhoneNumberInfo? in
                    country.callingCodes.first.map {
                        PhoneNumberInfo(country: country.countryCode, phoneNumberPrefix: $0, name: country.name)
                    }
                }
                guard let self, contextIsCurrent else { return }
                countries = mapped
                updateCountry()
            }
        case .messages,
             .password:
            break
        }
    }

    private func updateActivity() {
        if isLoading {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    // MARK: Proceeding

    private func proceed() {
        guard !isProceeding, contextIsCurrent else { return }
        isProceeding = true
        switch step {
        case .cloud:
            let task = createdPublicChats
            Task { [weak self] in
                let chats = await task?.value ?? []
                guard let self, contextIsCurrent else { return }
                replace(with: chats.isEmpty ? .messages : .groups(chats))
            }
        case .groups:
            replace(with: .messages)
        case .messages:
            replace(with: .phone)
        case .phone:
            verifyPhone()
        case .password:
            verifyPassword()
        }
    }

    /// The next step takes this one's place in the modal, as `replaceTopControllerImpl` does.
    private func replace(with next: Step) {
        navigationController?.setViewControllers(
            [DeleteAccountDataViewController(step: next, hasPassword: hasPassword)],
            animated: true,
        )
    }

    /// The typed number must be the account's, with the leading zeros of a national number allowed.
    private func verifyPhone() {
        var code = "+" + (codeField.text ?? "").filter(\.isNumber)
        var number = (numberField.text ?? "").filter(\.isNumber)
        // Test numbers under +93 9998 are typed with their own code.
        if code == "+93", number.hasPrefix("9998") {
            code = "+"
        }
        guard (code + number).count > 4 else {
            isProceeding = false
            return
        }
        let client = client
        Task { [weak self] in
            guard let me = try? await client.getMe(), let self, contextIsCurrent else {
                self?.isProceeding = false
                return
            }
            let phone = "+" + me.phoneNumber.filter(\.isNumber)
            var matches = phone == code + number
            while !matches, number.hasPrefix("0") {
                number.removeFirst()
                matches = phone == code + number
            }
            guard matches else {
                isProceeding = false
                presentAlert(L10n.telegram("DeleteAccount.InvalidPhoneNumberError"))
                return
            }
            hasPassword ? replace(with: .password) : confirm(password: nil)
        }
    }

    /// requestTwoStepVerifiationSettings: TDLib's getRecoveryEmailAddress checks the password.
    private func verifyPassword() {
        let password = passwordField.text ?? ""
        guard !password.isEmpty else {
            isProceeding = false
            return
        }
        isLoading = true
        let client = client
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.getRecoveryEmailAddress(password: password))
                guard let self, contextIsCurrent else { return }
                isLoading = false
                confirm(password: password)
            } catch {
                guard let self else { return }
                isLoading = false
                isProceeding = false
                let message = (error as? TDLibError)?.message ?? ""
                let key =
                    if (error as? TDLibError)?.code == 429 || message.hasPrefix("FLOOD_WAIT") {
                        "LoginPassword.FloodError"
                    } else if message == "PASSWORD_HASH_INVALID" {
                        "DeleteAccount.InvalidPasswordError"
                    } else {
                        "Login.UnknownError"
                    }
                presentAlert(L10n.telegram(key))
            }
        }
    }

    /// Telegram's last alert; Delete My Account calls deleteAccount with reason "Manual".
    private func confirm(password: String?) {
        let alert = UIAlertController(
            title: L10n.telegram("DeleteAccount.ConfirmationAlertTitle"),
            message: L10n.telegram("DeleteAccount.ConfirmationAlertText"),
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(
            title: L10n.telegram("DeleteAccount.ConfirmationAlertDelete"),
            style: .destructive,
        ) { [weak self] _ in self?.deleteAccount(password: password) })
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.Cancel"), style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func deleteAccount(password: String?) {
        guard contextIsCurrent else { return }
        #if DEBUG
        // Debug builds, which every test runs, have no deleteAccount request at all, so testing the flow can't delete
        // an account. Release builds for TestFlight and the App Store delete it.
        isProceeding = false
        presentAlert("Debug build: the account was not deleted. Release builds delete it here.")
        #else
        isLoading = true
        let client = client
        Task { [weak self] in
            do {
                _ = try await client.send(TDNativeRequests.deleteAccount(reason: "Manual", password: password ?? ""))
                // TDLib logs the account out next, and BetterTG removes it as after a remote logout.
                let window = self?.view.window
                self?.dismiss(animated: true) {
                    if let window {
                        TelegramUndoToast.show(
                            text: L10n.telegram("DeleteAccount.Success"),
                            in: window,
                            bottomInset: 12,
                            undo: nil,
                        )
                    }
                }
            } catch {
                guard let self else { return }
                isLoading = false
                isProceeding = false
                presentAlert(L10n.telegram("Login.UnknownError"))
            }
        }
        #endif
    }

    private func presentAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.telegram("Common.OK"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - DeleteAccountHeaderView

/// InviteLinkHeaderItem: the animation played once, 124 pt (140 pt in landscape) and 10 pt above the item, the 17 pt
/// semibold title 8 pt under it less 4, and the 14 pt text 5 pt under the title, both centered 24 pt from the sides.
private final class DeleteAccountHeaderView: UIView {
    private let animationView = LottieAnimationView(configuration: LottieConfiguration(
        renderingEngine: .automatic,
        decodingStrategy: .legacyCodable,
    ))
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private var animationSide: NSLayoutConstraint?
    private var titleTop: NSLayoutConstraint?
    private var animationName = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.loopMode = .playOnce
        animationView.contentMode = .scaleAspectFit
        addSubview(animationView)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        addSubview(titleLabel)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.font = .systemFont(ofSize: 14)
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        addSubview(textLabel)
        let side = animationView.widthAnchor.constraint(equalToConstant: 124)
        let titleTop = titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 128)
        self.animationSide = side
        self.titleTop = titleTop
        NSLayoutConstraint.activate([
            side,
            animationView.heightAnchor.constraint(equalTo: animationView.widthAnchor),
            animationView.topAnchor.constraint(equalTo: topAnchor, constant: -10),
            animationView.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleTop,
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            textLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(step: DeleteAccountDataViewController.Step) {
        titleLabel.text = step.title
        textLabel.text = step.text
        animationName = step.animationName
        guard let path = Bundle.main.path(forResource: animationName, ofType: "tgs") else { return }
        Task { [weak self] in
            guard let animation = await TGSAnimationRepository.animation(at: path), let self else { return }
            animationView.animation = animation
            if window != nil { animationView.play() }
        }
    }

    func update(animationSide side: CGFloat) {
        animationView.isHidden = side == 0
        animationSide?.constant = side
        titleTop?.constant = side - 4 + 8
    }

    func play() {
        guard animationView.animation != nil, !animationView.isAnimationPlaying else { return }
        animationView.play()
    }
}

// MARK: - DeleteAccountFooterPanel

/// DeleteAccountFooterItem: over the bar's background with a hairline, the 52 pt capsule button 16 pt from the sides
/// and 9 pt from the top, then Continue in the 17 pt accent 23 pt under it and 23 pt above the bottom (16 pt on a
/// 320 pt screen). Without a title the button goes away, as it does over the keyboard.
private final class DeleteAccountFooterPanel: UIView {
    var onPrimary: (() -> Void)?
    var onSecondary: (() -> Void)?

    /// Pin this to the keyboard's top: the buttons ride above it, the background reaches the screen's bottom.
    let contentBottomAnchorView = UIView()

    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let separator = UIView()
    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)
    private let stack = UIStackView()
    private var separatorHeight: NSLayoutConstraint?
    private var bottomSpacing: NSLayoutConstraint?

    var contentBottomAnchor: NSLayoutYAxisAnchor {
        contentBottomAnchorView.bottomAnchor
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        var primary = UIButton.Configuration.filled()
        primary.cornerStyle = .capsule
        primary.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 17, weight: .semibold)
            return attributes
        }
        primaryButton.configuration = primary
        primaryButton.addAction(UIAction { [weak self] _ in self?.onPrimary?() }, for: .primaryActionTriggered)
        primaryButton.heightAnchor.constraint(equalToConstant: 52).isActive = true

        secondaryButton.setTitle(L10n.telegram("DeleteAccount.Continue"), for: .normal)
        secondaryButton.titleLabel?.font = .systemFont(ofSize: 17)
        secondaryButton.addAction(UIAction { [weak self] _ in self?.onSecondary?() }, for: .primaryActionTriggered)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.addArrangedSubview(primaryButton)
        stack.addArrangedSubview(secondaryButton)
        addSubview(stack)
        contentBottomAnchorView.translatesAutoresizingMaskIntoConstraints = false
        contentBottomAnchorView.isUserInteractionEnabled = false
        addSubview(contentBottomAnchorView)

        stack.spacing = 23
        let separatorHeight = separator.heightAnchor.constraint(equalToConstant: 1)
        let bottomSpacing = contentBottomAnchorView.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 23)
        self.separatorHeight = separatorHeight
        self.bottomSpacing = bottomSpacing
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorHeight,
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bottomSpacing,
            contentBottomAnchorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentBottomAnchorView.heightAnchor.constraint(equalToConstant: 0),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        // 23 pt around Continue, 16 pt on a 320 pt screen.
        let inset: CGFloat = bounds.width > 320 ? 23 : 16
        if stack.spacing != inset { stack.spacing = inset }
        if bottomSpacing?.constant != inset { bottomSpacing?.constant = inset }
        let hairline = 1 / max(1, traitCollection.displayScale)
        if separatorHeight?.constant != hairline { separatorHeight?.constant = hairline }
        super.layoutSubviews()
    }

    func configure(title: String?) {
        primaryButton.configuration?.title = title
        primaryButton.isHidden = title == nil
    }
}

// MARK: - DeleteAccountPeersCell

/// DeleteAccountPeersItem: a 109 pt card with HorizontalPeerItem's compact strip of 60 pt avatars over their names.
private final class DeleteAccountPeersCell: UITableViewCell, UICollectionViewDataSource {
    static let reuseIdentifier = "DeleteAccountPeersCell"
    static let height = CGFloat(109)

    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 80, height: 92)
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    private var peers = [SettingsPeer]()
    private var client: TDLibClient?
    private var accountID: UUID?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.register(
            DeleteAccountPeerCell.self,
            forCellWithReuseIdentifier: DeleteAccountPeerCell.reuseIdentifier,
        )
        contentView.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: 92),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(peers: [SettingsPeer], client: TDLibClient, accountID: UUID?) {
        self.peers = peers
        self.client = client
        self.accountID = accountID
        collectionView.reloadData()
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        peers.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath,
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: DeleteAccountPeerCell.reuseIdentifier,
            for: indexPath,
        )
        if let client, let cell = cell as? DeleteAccountPeerCell {
            cell.configure(peer: peers[indexPath.item], client: client, accountID: accountID)
        }
        return cell
    }
}

// MARK: - DeleteAccountPeerCell

/// SelectablePeerNode in compact mode: the avatar 4 pt from the top, the 11 pt name 4 pt under it.
private final class DeleteAccountPeerCell: UICollectionViewCell {
    static let reuseIdentifier = "DeleteAccountPeerCell"

    private let avatarView = ProfileAvatarView()
    private let nameLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.showsContextMenu = false
        avatarView.isUserInteractionEnabled = false
        contentView.addSubview(avatarView)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        contentView.addSubview(nameLabel)
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            avatarView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 60),
            avatarView.heightAnchor.constraint(equalToConstant: 60),
            nameLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
        ])
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(peer: SettingsPeer, client: TDLibClient, accountID: UUID?) {
        avatarView.configure(
            file: peer.file,
            minithumbnail: peer.minithumbnail,
            placeholder: peer.placeholder,
            accountID: accountID,
            client: client,
        )
        nameLabel.text = peer.title
    }
}
